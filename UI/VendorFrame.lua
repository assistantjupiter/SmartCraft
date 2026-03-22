-- VendorFrame.lua
-- Auto-detects when a vendor sells items on the SmartCraft shopping list.
-- Shows a compact popup alongside the merchant window with [Buy X] buttons.
--
-- WoW Anniversary API used:
--   MERCHANT_SHOW / MERCHANT_CLOSED events
--   GetMerchantNumItems()
--   GetMerchantItemInfo(i) → name, texture, price, quantity, numAvailable, isUsable, extendedCost
--   GetMerchantItemLink(i) → item link (for itemID)
--   BuyMerchantItem(i, quantity)

SmartCraft.VendorFrame = {}
local VF = SmartCraft.VendorFrame

local frame, titleText, scrollFrame, scrollChild
local fsPool  = {}
local btnPool = {}

local W, H = 260, 320
local LH    = 18

-- items this vendor sells that we need: [{ merchantIdx, itemID, name, need, have, toBuy }]
VF.matches = {}

-- ----------------------------------------------------------------
-- Called on MERCHANT_SHOW
-- ----------------------------------------------------------------
function VF:OnMerchantShow()
    -- Re-run analysis to get fresh shopping list
    SmartCraft:RunAnalysis()
    self:ScanVendor()
    if #self.matches > 0 then
        self:Show()
    end
end

-- ----------------------------------------------------------------
-- Scan vendor inventory against shopping list
-- ----------------------------------------------------------------
function VF:ScanVendor()
    self.matches = {}

    local shopList = SmartCraft.ShoppingList.list
    if not shopList or #shopList == 0 then return end

    -- Build a quick lookup: itemID → shopping entry
    local needed = {}
    for _, entry in ipairs(shopList) do
        if entry.toBuy > 0 then
            needed[entry.itemID] = entry
        end
    end

    local numItems = GetMerchantNumItems()
    if not numItems then return end

    for i = 1, numItems do
        local link = GetMerchantItemLink(i)
        if link then
            local itemID = SmartCraft.Inventory:LinkToID(link)
            if itemID and needed[itemID] then
                local entry = needed[itemID]
                local name, _, price, _, numAvailable = GetMerchantItemInfo(i)
                table.insert(self.matches, {
                    merchantIdx  = i,
                    itemID       = itemID,
                    name         = name or entry.itemName,
                    need         = entry.need or entry.toBuy,
                    have         = entry.have,
                    toBuy        = entry.toBuy,
                    price        = price or 0,
                    numAvailable = numAvailable,   -- -1 = unlimited
                })
            end
        end
    end
end

-- ----------------------------------------------------------------
-- Build the frame (once)
-- ----------------------------------------------------------------
function VF:Init()
    if frame then return end

    local tmpl = BackdropTemplateMixin and "BackdropTemplate" or nil
    frame = CreateFrame("Frame", "SmartCraftVendorFrame", UIParent, tmpl)
    frame:SetSize(W, H)
    frame:SetPoint("TOPLEFT", MerchantFrame, "TOPRIGHT", 6, 0)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop",  frame.StopMovingOrSizing)
    frame:SetToplevel(true)
    frame:SetFrameStrata("HIGH")
    frame:Hide()

    if frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile=true, tileSize=32, edgeSize=26,
            insets = { left=9, right=9, top=9, bottom=9 },
        })
        frame:SetBackdropColor(0.05, 0.05, 0.08, 1)
        frame:SetBackdropBorderColor(0.4, 0.4, 0.5, 1)
    else
        local bg = frame:CreateTexture(nil, "BACKGROUND")
        bg:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Background")
        bg:SetAllPoints(frame)
    end

    -- Header bar
    local headerBg = frame:CreateTexture(nil, "ARTWORK")
    headerBg:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Background-Dark")
    headerBg:SetPoint("TOPLEFT",  frame, "TOPLEFT",  9,  -9)
    headerBg:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -9, -9)
    headerBg:SetHeight(30)

    titleText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleText:SetPoint("TOP", frame, "TOP", 0, -16)
    titleText:SetText("SmartCraft — Buy from Vendor")
    titleText:SetTextColor(1, 0.82, 0)

    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetSize(26, 26)
    closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 2, 2)
    closeBtn:SetScript("OnClick", function() frame:Hide() end)

    -- Divider
    local div = frame:CreateTexture(nil, "OVERLAY")
    div:SetColorTexture(0.25, 0.25, 0.35, 1)
    div:SetPoint("TOPLEFT",  frame, "TOPLEFT",  9, -39)
    div:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -9, -39)
    div:SetHeight(1)

    -- Scroll area
    scrollFrame = CreateFrame("ScrollFrame", "SCVendorScroll", frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT",     frame, "TOPLEFT",     12,  -42)
    scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -26, 40)

    scrollChild = CreateFrame("Frame", "SCVendorScrollChild", scrollFrame)
    scrollChild:SetWidth(W - 12 - 26 - 4)
    scrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(scrollChild)

    -- Footer: Buy All button
    local buyAllBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    buyAllBtn:SetSize(100, 22)
    buyAllBtn:SetPoint("BOTTOM", frame, "BOTTOM", 0, 12)
    buyAllBtn:SetText("Buy All Listed")
    buyAllBtn:SetScript("OnClick", function()
        VF:BuyAll()
    end)

    -- Footer hint
    local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 12, 14)
    hint:SetText("|cffaaaaaaruns on vendor open|r")

    self.frame       = frame
    self.scrollChild = scrollChild
    self.scrollFrame = scrollFrame
end

-- ----------------------------------------------------------------
-- Render the match list
-- ----------------------------------------------------------------
function VF:Rebuild()
    for _, fs  in pairs(fsPool)  do fs:SetText("") ; fs:Hide() end
    for _, btn in ipairs(btnPool) do btn:Hide() end

    local yOff   = -4
    local btnIdx = 0

    if #self.matches == 0 then
        local fs = fsPool[1]
        if not fs then
            fs = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            fs:SetJustifyH("LEFT")
            fsPool[1] = fs
        end
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 4, yOff)
        fs:SetWidth(scrollChild:GetWidth() - 8)
        fs:SetText("No shopping list items sold here.")
        fs:SetTextColor(0.5, 0.5, 0.5)
        fs:Show()
        scrollChild:SetHeight(40)
        return
    end

    for i, match in ipairs(self.matches) do
        -- Item name + need/have
        local fs = fsPool[i]
        if not fs then
            fs = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            fs:SetJustifyH("LEFT")
            fsPool[i] = fs
        end
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 4, yOff)
        fs:SetWidth(scrollChild:GetWidth() - 72)

        -- Format price
        local priceStr = ""
        if match.price and match.price > 0 then
            local gold   = math.floor(match.price / 10000)
            local silver = math.floor((match.price % 10000) / 100)
            local copper = match.price % 100
            if gold > 0 then
                priceStr = string.format(" |cffffd700%dg|r", gold)
            elseif silver > 0 then
                priceStr = string.format(" |cffaaaaaa%ds|r", silver)
            else
                priceStr = string.format(" |cffb87333%dc|r", copper)
            end
            priceStr = priceStr .. " ea"
        end

        fs:SetText(string.format(
            "|cffffd700%s|r\n  Need %d  Have %d%s",
            match.name, match.toBuy, match.have, priceStr
        ))
        fs:SetTextColor(0.9, 0.9, 0.9)
        fs:Show()

        -- Buy button
        btnIdx = btnIdx + 1
        local btn = btnPool[btnIdx]
        if not btn then
            btn = CreateFrame("Button", "SCVendorBuy"..btnIdx, scrollChild, "UIPanelButtonTemplate")
            btn:SetSize(60, 22)
            btnPool[btnIdx] = btn
        end
        btn:ClearAllPoints()
        btn:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", -4, yOff - 4)
        local midx, qty = match.merchantIdx, match.toBuy
        btn:SetScript("OnClick", function()
            VF:BuyItem(midx, qty)
        end)
        btn:SetText(string.format("Buy %d", match.toBuy))
        btn:Show()

        yOff = yOff - (LH * 2 + 8)
    end

    scrollChild:SetHeight(math.max(math.abs(yOff) + 4, 1))
    scrollFrame:SetVerticalScroll(0)
end

-- ----------------------------------------------------------------
-- Buy a single item
-- ----------------------------------------------------------------
function VF:BuyItem(merchantIdx, qty)
    -- BuyMerchantItem(index, quantity)
    local ok, err = pcall(BuyMerchantItem, merchantIdx, qty)
    if not ok then
        SmartCraft.ErrorLog:Add("VendorFrame:BuyItem", err)
        return
    end
    -- Re-scan after purchase
    local elapsed = 0
    local ticker = CreateFrame("Frame")
    ticker:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        if elapsed >= 0.3 then
            self:SetScript("OnUpdate", nil)
            SmartCraft:RunAnalysis()
            VF:ScanVendor()
            VF:Rebuild()
        end
    end)
end

-- ----------------------------------------------------------------
-- Buy all matched items
-- ----------------------------------------------------------------
function VF:BuyAll()
    for _, match in ipairs(self.matches) do
        local ok, err = pcall(BuyMerchantItem, match.merchantIdx, match.toBuy)
        if not ok then
            SmartCraft.ErrorLog:Add("VendorFrame:BuyAll", err)
        end
    end
    -- Re-scan after a short delay
    local elapsed = 0
    local ticker = CreateFrame("Frame")
    ticker:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        if elapsed >= 0.5 then
            self:SetScript("OnUpdate", nil)
            SmartCraft:RunAnalysis()
            VF:ScanVendor()
            VF:Rebuild()
        end
    end)
end

-- ----------------------------------------------------------------
-- Show / Hide
-- ----------------------------------------------------------------
function VF:Show()
    self:Init()
    self:Rebuild()
    frame:Show()
end

function VF:Hide()
    if frame then frame:Hide() end
end
