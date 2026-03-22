-- AuctionFrame.lua
-- Auto-opens next to the Auction House window when AUCTION_HOUSE_SHOW fires.
-- Shows the SmartCraft shopping list with AH prices (TSM/Auctionator if available).
-- Includes a [Search] button per item that opens TSM/Auctionator search if loaded,
-- or falls back to typing the item name into the AH search box.

SmartCraft.AuctionFrame = {}
local AF = SmartCraft.AuctionFrame

local frame, scrollFrame, scrollChild, totalLine
local fsPool  = {}
local btnPool = {}

local W, H = 280, 400

-- ----------------------------------------------------------------
-- Called on AUCTION_HOUSE_SHOW
-- ----------------------------------------------------------------
function AF:OnAuctionShow()
    SmartCraft:RunAnalysis()
    self:Show()
    self:StartBagWatch()
end

-- ----------------------------------------------------------------
-- Called on AUCTION_HOUSE_CLOSED
-- ----------------------------------------------------------------
function AF:OnAuctionClosed()
    self:StopBagWatch()
    self:Hide()
end

-- ----------------------------------------------------------------
-- BAG_UPDATE watcher — re-scans when items land in bags
-- Debounced: waits 0.5s after last update to avoid rapid rebuilds
-- ----------------------------------------------------------------
AF._bagWatcher   = nil
AF._bagDebounce  = nil
AF._bagDebounceT = 0

function AF:StartBagWatch()
    if self._bagWatcher then return end  -- already watching

    local watcher = CreateFrame("Frame")
    watcher:RegisterEvent("BAG_UPDATE")
    watcher:SetScript("OnEvent", function(self, event)
        -- Start/reset debounce timer
        AF._bagDebounceT = 0
        if not AF._bagDebounce then
            AF._bagDebounce = CreateFrame("Frame")
            AF._bagDebounce:SetScript("OnUpdate", function(_, dt)
                AF._bagDebounceT = AF._bagDebounceT + dt
                if AF._bagDebounceT >= 0.5 then
                    AF._bagDebounce:SetScript("OnUpdate", nil)
                    AF._bagDebounce = nil
                    -- Re-scan bags and rebuild shopping list
                    SmartCraft.Inventory:ScanBags()
                    SmartCraft.Reservation:Run()
                    SmartCraft.ShoppingList:Build()
                    AF:Rebuild()
                end
            end)
        end
    end)
    self._bagWatcher = watcher
end

function AF:StopBagWatch()
    if self._bagWatcher then
        self._bagWatcher:UnregisterAllEvents()
        self._bagWatcher:SetScript("OnEvent", nil)
        self._bagWatcher = nil
    end
    if self._bagDebounce then
        self._bagDebounce:SetScript("OnUpdate", nil)
        self._bagDebounce = nil
    end
end

-- ----------------------------------------------------------------
-- Build frame (once)
-- ----------------------------------------------------------------
function AF:Init()
    if frame then return end

    local tmpl = BackdropTemplateMixin and "BackdropTemplate" or nil
    frame = CreateFrame("Frame", "SmartCraftAuctionFrame", UIParent, tmpl)
    frame:SetSize(W, H)
    -- Position to the right of the AH frame
    frame:SetPoint("TOPLEFT", AuctionFrame or UIParent, "TOPRIGHT", 6, 0)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop",  frame.StopMovingOrSizing)
    frame:SetToplevel(true)
    frame:SetFrameStrata("HIGH")
    frame:Hide()

    -- Background
    if frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile=true, tileSize=8, edgeSize=26,
            insets = { left=9, right=9, top=9, bottom=9 },
        })
        frame:SetBackdropColor(0, 0, 0, 0.95)
        frame:SetBackdropBorderColor(0.35, 0.35, 0.45, 1)
    else
        local bg = frame:CreateTexture(nil, "BACKGROUND")
        bg:SetColorTexture(0, 0, 0, 0.95)
        bg:SetAllPoints(frame)
    end

    -- Header
    local headerBg = frame:CreateTexture(nil, "ARTWORK")
    headerBg:SetColorTexture(0, 0, 0, 1)
    headerBg:SetPoint("TOPLEFT",  frame, "TOPLEFT",  9,  -9)
    headerBg:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -9, -9)
    headerBg:SetHeight(30)

    local titleText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleText:SetPoint("TOP", frame, "TOP", 0, -16)
    titleText:SetText("SmartCraft — AH List")
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
    scrollFrame = CreateFrame("ScrollFrame", "SCAuctionScroll", frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT",     frame, "TOPLEFT",     12,  -42)
    scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -26, 50)

    scrollChild = CreateFrame("Frame", "SCAuctionScrollChild", scrollFrame)
    scrollChild:SetWidth(W - 12 - 26 - 4)
    scrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(scrollChild)

    -- Footer divider
    local footDiv = frame:CreateTexture(nil, "OVERLAY")
    footDiv:SetColorTexture(0.25, 0.25, 0.35, 1)
    footDiv:SetPoint("BOTTOMLEFT",  frame, "BOTTOMLEFT",   9, 48)
    footDiv:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -9, 48)
    footDiv:SetHeight(1)

    -- Total cost line
    totalLine = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    totalLine:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 14, 28)
    totalLine:SetText("")
    totalLine:SetTextColor(1, 0.82, 0)

    -- Refresh button
    local refreshBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    refreshBtn:SetSize(70, 20)
    refreshBtn:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 14)
    refreshBtn:SetText("Refresh")
    refreshBtn:SetScript("OnClick", function()
        SmartCraft:RunAnalysis()
        AF:Rebuild()
    end)

    self.frame       = frame
    self.scrollChild = scrollChild
    self.scrollFrame = scrollFrame
end

-- ----------------------------------------------------------------
-- Rebuild content
-- ----------------------------------------------------------------
function AF:Rebuild()
    for _, fs  in pairs(fsPool)  do fs:SetText("") ; fs:Hide() end
    for _, btn in ipairs(btnPool) do btn:Hide() end
    if totalLine then totalLine:SetText("") end

    local shopList = SmartCraft.ShoppingList.list
    local yOff     = -4
    local LH       = 16
    local btnIdx   = 0
    local grandTotal = 0
    local grandKnown = true

    if not shopList or #shopList == 0 then
        local fs = fsPool[1]
        if not fs then
            fs = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            fs:SetJustifyH("LEFT")
            fsPool[1] = fs
        end
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 4, yOff)
        fs:SetWidth(scrollChild:GetWidth() - 8)
        fs:SetText("Shopping list is empty.")
        fs:SetTextColor(0.5, 0.5, 0.5)
        fs:Show()
        scrollChild:SetHeight(40)
        return
    end

    for i, entry in ipairs(shopList) do
        -- Item name + need/have
        local fsKey = "item"..i
        local fs = fsPool[fsKey]
        if not fs then
            fs = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            fs:SetJustifyH("LEFT")
            fsPool[fsKey] = fs
        end
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 4, yOff)
        fs:SetWidth(scrollChild:GetWidth() - 72)

        -- AH price per unit
        local prices   = SmartCraft.PriceDB:Get(entry.itemID)
        local unitPrice = prices.ah
        local priceStr = ""
        if unitPrice and unitPrice > 0 then
            local total = unitPrice * entry.toBuy
            grandTotal  = grandTotal + total
            priceStr    = "  " .. SmartCraft.VendorFrame:FormatMoney(total)
        else
            grandKnown = false
            priceStr   = "  |cff888888No AH data|r"
        end

        fs:SetText(string.format(
            "|cffffd700%s|r\n  Buy %d (have %d)%s",
            entry.itemName, entry.toBuy, entry.have, priceStr
        ))
        fs:SetTextColor(0.9, 0.9, 0.9)
        fs:Show()

        -- Search button
        btnIdx = btnIdx + 1
        local btn = btnPool[btnIdx]
        if not btn then
            btn = CreateFrame("Button", "SCAHSearchBtn"..btnIdx, scrollChild, "UIPanelButtonTemplate")
            btn:SetSize(58, 20)
            btnPool[btnIdx] = btn
        end
        btn:ClearAllPoints()
        btn:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", -4, yOff - 4)
        local itemName = entry.itemName
        local itemID   = entry.itemID
        btn:SetScript("OnClick", function()
            AF:SearchItem(itemName, itemID)
        end)
        btn:SetText("Search")
        btn:Show()

        yOff = yOff - (LH * 2 + 8)
    end

    scrollChild:SetHeight(math.max(math.abs(yOff) + 4, 1))
    scrollFrame:SetVerticalScroll(0)

    -- Total footer
    if totalLine then
        if grandTotal > 0 then
            local prefix = grandKnown and "Est. Total: " or "Est. Total~: "
            totalLine:SetText(prefix .. SmartCraft.VendorFrame:FormatMoney(grandTotal))
        else
            totalLine:SetText("|cff888888No AH prices available|r")
        end
    end
end

-- ----------------------------------------------------------------
-- Search for an item in TSM / Auctionator / fallback
-- ----------------------------------------------------------------
function AF:SearchItem(itemName, itemID)
    -- TSM4 search
    if TSM_API and TSM_API.OpenAuctionSearch then
        TSM_API.OpenAuctionSearch("i:" .. itemID)
        return
    end
    -- Auctionator search
    if Auctionator and Auctionator.API and Auctionator.API.v1 then
        local v1 = Auctionator.API.v1
        if v1.OpenAH then
            v1.OpenAH("SmartCraft", itemName)
            return
        end
    end
    -- Fallback: type into the native AH search box
    if AuctionFrameBrowse and BrowseName then
        BrowseName:SetText(itemName)
        AuctionFrameTab1:Click()   -- switch to Browse tab
        BrowseSearchButton:Click()
    else
        print("|cff00ff96SmartCraft:|r Search for: |cffffd700" .. itemName .. "|r")
    end
end

-- ----------------------------------------------------------------
-- Show / Hide
-- ----------------------------------------------------------------
function AF:Show()
    self:Init()
    self:Rebuild()
    frame:Show()
end

function AF:Hide()
    if frame then frame:Hide() end
end
