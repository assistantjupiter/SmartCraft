-- MainFrame.lua
-- Polished WoW-style UI — Anniversary / vanilla Classic compatible.
-- Uses standard WoW dialog artwork for a native look.
-- No emoji (they render as boxes in WoW's font engine).

SmartCraft.UI = {}
local UI = SmartCraft.UI

local UC = SmartCraft.Constants.UI
local W, H = UC.W, UC.H

local frame, scrollFrame, scrollChild
local skillLine, bankLine
local tabs      = {}
local activeTab = "crafts"

local fsPool    = {}
local btnPool   = {}
local stratBtns = {}
local plannerTargetBox, plannerGoBtn

-- ----------------------------------------------------------------
-- Helpers
-- ----------------------------------------------------------------
local function MakeTexture(parent, layer, file, w, h, x, y, anchor)
    local t = parent:CreateTexture(nil, layer or "ARTWORK")
    if file  then t:SetTexture(file) end
    if w and h then t:SetSize(w, h) end
    if anchor then t:SetPoint(anchor, parent, anchor, x or 0, y or 0) end
    return t
end

-- Solid coloured rectangle (used for tab highlight, dividers, etc.)
local function MakeColorBox(parent, layer, r, g, b, a, w, h, point, relPoint, ox, oy)
    local t = parent:CreateTexture(nil, layer or "OVERLAY")
    t:SetColorTexture(r, g, b, a or 1)
    if w and h then t:SetSize(w, h) end
    if point then t:SetPoint(point, parent, relPoint or point, ox or 0, oy or 0) end
    return t
end

-- ----------------------------------------------------------------
-- Build frame (once)
-- ----------------------------------------------------------------
function UI:Init()
    if frame then return end

    -- ── Outer frame ─────────────────────────────────────────────
    -- Use BackdropTemplate if available (Anniversary); fallback to manual bg
    local tmpl = BackdropTemplateMixin and "BackdropTemplate" or nil
    frame = CreateFrame("Frame", "SmartCraftMainFrame", UIParent, tmpl)
    frame:SetSize(W, H)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop",  frame.StopMovingOrSizing)
    frame:SetToplevel(true)
    frame:SetFrameStrata("HIGH")
    frame:Hide()

    -- Background — solid near-black panel
    if frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8X8",   -- solid colour fill
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile     = true, tileSize = 8, edgeSize = 26,
            insets   = { left=9, right=9, top=9, bottom=9 },
        })
        frame:SetBackdropColor(0, 0, 0, 0.95)            -- near-black 95%
        frame:SetBackdropBorderColor(0.35, 0.35, 0.45, 1)
    else
        -- Hard fallback: solid colour texture
        local bg = frame:CreateTexture(nil, "BACKGROUND")
        bg:SetColorTexture(0, 0, 0, 0.95)
        bg:SetAllPoints(frame)
        local edge = frame:CreateTexture(nil, "BORDER")
        edge:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Border")
        edge:SetAllPoints(frame)
    end

    -- ── Header bar ──────────────────────────────────────────────
    local headerBg = frame:CreateTexture(nil, "ARTWORK")
    headerBg:SetColorTexture(0, 0, 0, 1)   -- pure black header bar
    headerBg:SetPoint("TOPLEFT",  frame, "TOPLEFT",  9,  -9)
    headerBg:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -9, -9)
    headerBg:SetHeight(36)

    -- Bottom edge of header
    local headerLine = frame:CreateTexture(nil, "OVERLAY")
    headerLine:SetTexture("Interface\\Tooltips\\UI-Tooltip-Border")
    headerLine:SetColorTexture(0.3, 0.3, 0.4, 0.8)
    headerLine:SetPoint("TOPLEFT",  frame, "TOPLEFT",  9, -45)
    headerLine:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -9, -45)
    headerLine:SetHeight(1)

    -- Title text
    local titleText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("TOP", frame, "TOP", 0, -16)
    titleText:SetText("SmartCraft")
    titleText:SetTextColor(1, 0.82, 0)

    -- ── Close button ─────────────────────────────────────────────
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetSize(26, 26)
    closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 2, 2)
    closeBtn:SetScript("OnClick", function() frame:Hide() end)

    -- ── Skill / bank status ───────────────────────────────────────
    skillLine = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    skillLine:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -34)
    skillLine:SetText("|cffaaaaaa-- open a profession window --|r")

    bankLine = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    bankLine:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -32, -34)
    bankLine:SetJustifyH("RIGHT")
    bankLine:SetText("")

    -- ── Tab bar ───────────────────────────────────────────────────
    local tabBarBg = frame:CreateTexture(nil, "ARTWORK")
    tabBarBg:SetColorTexture(0.04, 0.04, 0.06, 1)   -- very dark tab bar
    tabBarBg:SetPoint("TOPLEFT",  frame, "TOPLEFT",  9,  -46)
    tabBarBg:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -9, -46)
    tabBarBg:SetHeight(UC.TAB_H + 2)

    local tabDefs = {
        { key="crafts",   label="Crafts"   },
        { key="shopping", label="Shopping" },
        { key="planner",  label="Planner"  },
        { key="optimize", label="Optimize" },
        { key="help",     label="Guide"    },
    }
    local tx = 14
    for _, def in ipairs(tabDefs) do
        local tbtn = CreateFrame("Button", "SCTab_"..def.key, frame)
        tbtn:SetSize(68, UC.TAB_H)
        tbtn:SetPoint("TOPLEFT", frame, "TOPLEFT", tx, -(UC.HEADER_H + 2))

        -- tab background
        local tabBg = tbtn:CreateTexture(nil, "BACKGROUND")
        tabBg:SetAllPoints(tbtn)
        tabBg:SetColorTexture(0.15, 0.15, 0.2, 0.9)
        tbtn.bg = tabBg

        -- active highlight bar (bottom)
        local tabLine = tbtn:CreateTexture(nil, "OVERLAY")
        tabLine:SetColorTexture(1, 0.75, 0, 1)
        tabLine:SetPoint("BOTTOMLEFT",  tbtn, "BOTTOMLEFT",  0, 0)
        tabLine:SetPoint("BOTTOMRIGHT", tbtn, "BOTTOMRIGHT", 0, 0)
        tabLine:SetHeight(2)
        tabLine:Hide()
        tbtn.activeLine = tabLine

        local tabLabel = tbtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        tabLabel:SetAllPoints(tbtn)
        tabLabel:SetJustifyH("CENTER")
        tabLabel:SetText(def.label)
        tabLabel:SetTextColor(0.8, 0.8, 0.8)
        tbtn.label = tabLabel

        local key = def.key
        tbtn:SetScript("OnClick", function() UI:SwitchTab(key) end)
        tbtn:SetScript("OnEnter", function(self)
            if activeTab ~= key then
                self.label:SetTextColor(1, 1, 1)
            end
        end)
        tbtn:SetScript("OnLeave", function(self)
            if activeTab ~= key then
                self.label:SetTextColor(0.8, 0.8, 0.8)
            end
        end)

        tabs[def.key] = tbtn
        tx = tx + 72
    end

    -- ── Divider below tabs ────────────────────────────────────────
    local divider = frame:CreateTexture(nil, "OVERLAY")
    divider:SetColorTexture(0.25, 0.25, 0.35, 1)
    divider:SetPoint("TOPLEFT",  frame, "TOPLEFT",  9,  -(UC.HEADER_H + UC.TAB_H + 4))
    divider:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -9, -(UC.HEADER_H + UC.TAB_H + 4))
    divider:SetHeight(1)

    -- ── Scroll area ───────────────────────────────────────────────
    local scrollTop = UC.HEADER_H + UC.TAB_H + 6
    scrollFrame = CreateFrame("ScrollFrame", "SmartCraftScroll", frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT",     frame, "TOPLEFT",     14,          -scrollTop)
    scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -UC.SCROLL_R, UC.FOOTER_H)

    scrollChild = CreateFrame("Frame", "SmartCraftScrollChild", scrollFrame)
    scrollChild:SetWidth(W - 14 - UC.SCROLL_R - 4)
    scrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(scrollChild)

    -- ── Footer divider ────────────────────────────────────────────
    local footerLine = frame:CreateTexture(nil, "OVERLAY")
    footerLine:SetColorTexture(0.25, 0.25, 0.35, 1)
    footerLine:SetPoint("BOTTOMLEFT",  frame, "BOTTOMLEFT",   9, UC.FOOTER_H - 1)
    footerLine:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -9, UC.FOOTER_H - 1)
    footerLine:SetHeight(1)

    -- ── Footer buttons ────────────────────────────────────────────
    local function MakeFooterBtn(label, xLeft, onClick)
        local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        b:SetSize(80, 22)
        b:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", xLeft, 8)
        b:SetText(label)
        b:SetScript("OnClick", onClick)
        return b
    end

    MakeFooterBtn("Refresh", 14, function()
        SmartCraft:RunAnalysis()
        UI:Refresh()
    end)

    MakeFooterBtn("Bank: ON", 100, function()
        if SmartCraftDB then
            SmartCraftDB.includeBank = not SmartCraftDB.includeBank
        end
        SmartCraft:RunAnalysis()
        UI:Refresh()
    end)

    local printBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    printBtn:SetSize(70, 22)
    printBtn:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 8)
    printBtn:SetText("Print")
    printBtn:SetScript("OnClick", function()
        if activeTab == "shopping" then
            SmartCraft.ShoppingList:PrintToChat()
        elseif activeTab == "planner" then
            SmartCraft.Planner:PrintToChat()
        else
            print("|cff00ff96SmartCraft:|r Open Shopping or Planner tab to print.")
        end
    end)

    -- Planner input widgets are created lazily inside BuildPlannerLines
    -- so they sit inside the scroll area, not floating above the tabs.

    self.frame       = frame
    self.scrollChild = scrollChild
    self.scrollFrame = scrollFrame

    -- Activate default tab
    UI:SwitchTab("crafts")
end

-- ----------------------------------------------------------------
-- Tab switching
-- ----------------------------------------------------------------
function UI:SwitchTab(key)
    activeTab = key
    for k, tbtn in pairs(tabs) do
        local active = (k == key)
        tbtn.activeLine:SetShown(active)
        if active then
            tbtn.bg:SetColorTexture(0.2, 0.2, 0.3, 1)
            tbtn.label:SetTextColor(1, 0.82, 0)
        else
            tbtn.bg:SetColorTexture(0.1, 0.1, 0.15, 0.9)
            tbtn.label:SetTextColor(0.7, 0.7, 0.7)
        end
    end
    self:RebuildContent()
end

-- ----------------------------------------------------------------
-- Public refresh
-- ----------------------------------------------------------------
function UI:Refresh()
    self:Init()
    self:UpdateHeader()
    self:RebuildContent()
end

function UI:UpdateHeader()
    local R = SmartCraft.Recipes
    if R.skillName and R.skillName ~= "" then
        skillLine:SetText(string.format(
            "|cffffd700%s|r  |cffaaaaaa%d / %d|r",
            R.skillName, R.skillLevel, R.maxSkill
        ))
    else
        skillLine:SetText("|cffaaaaaa-- open a profession window --|r")
    end
    local statusParts = { SmartCraft.Inventory:BankCacheStatus() }
    local trainerStatus = SmartCraft.TrainerDB and SmartCraft.TrainerDB:StatusLine()
    if trainerStatus then table.insert(statusParts, trainerStatus) end
    bankLine:SetText(table.concat(statusParts, "  "))
end

-- ----------------------------------------------------------------
-- Rebuild content
-- ----------------------------------------------------------------
function UI:RebuildContent()
    -- pairs covers both numeric and string-keyed entries (e.g. "planner_lbl", "hdr1")
    for _, fs  in pairs(fsPool)  do fs:SetText("") ; fs:Hide() end
    for _, btn in ipairs(btnPool) do btn:Hide() end
    -- Always hide planner widgets; they re-show themselves if on planner tab
    if plannerGoBtn     then plannerGoBtn:Hide() end
    if plannerTargetBox then plannerTargetBox:Hide() end
    -- Always hide strategy buttons; re-shown by optimize tab
    for _, b in ipairs(stratBtns) do b:Hide() end

    local lines = {}
    if     activeTab == "crafts"   then lines = self:BuildCraftLines()
    elseif activeTab == "shopping" then lines = self:BuildShoppingLines()
    elseif activeTab == "planner"  then lines = self:BuildPlannerLines()
    elseif activeTab == "optimize" then lines = self:BuildOptimizeLines()
    elseif activeTab == "help"     then lines = self:BuildHelpLines()
    end

    local LH   = UC.LINE_H
    local yOff = -6

    for i, line in ipairs(lines) do

        -- ── Strategy selector row (Optimize tab) ────────────────
        if line.isStrategyRow then
            yOff = self:RenderStrategyRow(yOff)

        -- ── Planner inline input row ─────────────────────────────
        elseif line.isPlannerInput then
            -- Create once, reuse after
            if not plannerTargetBox then
                plannerTargetBox = CreateFrame("EditBox", "SCPlannerTarget", scrollChild, "InputBoxTemplate")
                plannerTargetBox:SetSize(80, 22)
                plannerTargetBox:SetAutoFocus(false)
                plannerTargetBox:SetNumeric(true)
                plannerTargetBox:SetMaxLetters(3)
                plannerTargetBox:SetScript("OnEnterPressed", function()
                    if plannerGoBtn then plannerGoBtn:Click() end
                end)
                plannerTargetBox:SetScript("OnEscapePressed", function(self)
                    self:ClearFocus()
                end)
            end
            if not plannerGoBtn then
                plannerGoBtn = CreateFrame("Button", "SCPlannerGoBtn", scrollChild, "UIPanelButtonTemplate")
                plannerGoBtn:SetSize(60, 22)
                plannerGoBtn:SetText("Plan")
                plannerGoBtn:SetScript("OnClick", function()
                    local val = tonumber(plannerTargetBox:GetText())
                    if val then
                        SmartCraft.Planner:BuildPlan(val)
                        UI:RebuildContent()
                    else
                        print("|cff00ff96SmartCraft:|r Enter a numeric target skill (e.g. 300).")
                    end
                end)
            end

            -- Position label
            local lbl = fsPool["planner_lbl"]
            if not lbl then
                lbl = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                lbl:SetJustifyH("LEFT")
                fsPool["planner_lbl"] = lbl
            end
            lbl:ClearAllPoints()
            lbl:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 6, yOff)
            lbl:SetText("Target skill:")
            lbl:SetTextColor(0.8, 0.8, 0.8)
            lbl:Show()

            plannerTargetBox:ClearAllPoints()
            plannerTargetBox:SetPoint("LEFT", lbl, "RIGHT", 10, 0)
            plannerTargetBox:Show()

            plannerGoBtn:ClearAllPoints()
            plannerGoBtn:SetPoint("LEFT", plannerTargetBox, "RIGHT", 6, 0)
            plannerGoBtn:Show()

            yOff = yOff - (UC.LINE_H + 8)

        -- ── Section header style
        elseif line.isHeader then
            -- Coloured background bar for section headers
            local hdr = fsPool["hdr"..i]
            if not hdr then
                hdr = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                hdr:SetJustifyH("LEFT")
                fsPool["hdr"..i] = hdr
            end
            hdr:ClearAllPoints()
            hdr:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 6, yOff)
            hdr:SetWidth(scrollChild:GetWidth() - 10)
            hdr:SetText("|cff" .. (line.hex or "aaaaff") .. line.text .. "|r")
            hdr:SetTextColor(1, 1, 1)
            hdr:Show()
            fsPool[i] = hdr   -- also index by number for cleanup
            yOff = yOff - (LH + 2)
        else
            local fs = fsPool[i]
            if not fs then
                fs = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                fs:SetJustifyH("LEFT")
                fsPool[i] = fs
            end
            fs:ClearAllPoints()
            fs:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 6, yOff)
            local lineW = scrollChild:GetWidth() - (line.hasCraftBtn and 68 or 8)
            fs:SetWidth(lineW)
            fs:SetText(line.text or "")
            fs:SetTextColor(line.r or 1, line.g or 1, line.b or 1)
            fs:Show()

            if line.hasCraftBtn and line.recipeIdx then
                local bi  = line.btnPoolIdx
                local btn = btnPool[bi]
                if not btn then
                    btn = CreateFrame("Button", "SCCraftBtn"..bi, scrollChild, "UIPanelButtonTemplate")
                    btn:SetSize(60, LH + 2)
                    btnPool[bi] = btn
                end
                btn:ClearAllPoints()
                btn:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", -4, yOff)
                local idx, times = line.recipeIdx, line.maxCrafts
                btn:SetScript("OnClick", function() UI:DoCraft(idx, times) end)
                btn:SetText("Craft")
                btn:Show()
            end

            yOff = yOff - LH
        end
    end

    scrollChild:SetHeight(math.max(math.abs(yOff) + 6, 1))
    scrollFrame:SetVerticalScroll(0)
end

-- ----------------------------------------------------------------
-- Click-to-craft (vanilla-safe ticker)
-- ----------------------------------------------------------------
function UI:DoCraft(recipeIdx, times)
    if not recipeIdx then return end
    TradeSkillFrame_SetSelection(recipeIdx)
    DoTradeSkill(recipeIdx, times)
    local elapsed = 0
    local ticker  = CreateFrame("Frame")
    ticker:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        if elapsed >= 0.4 then
            self:SetScript("OnUpdate", nil)
            SmartCraft:RunAnalysis()
            UI:Refresh()
        end
    end)
end

-- ----------------------------------------------------------------
-- Content builders
-- ----------------------------------------------------------------
function UI:BuildCraftLines()
    local lines  = {}
    local btnIdx = 0

    table.insert(lines, { text="Safe to Craft", isHeader=true, hex="66ff99" })

    local sug = SmartCraft.Reservation.suggestions
    if not sug or #sug == 0 then
        table.insert(lines, { text="  No crafts available with current mats.", r=0.5, g=0.5, b=0.5 })
    else
        for _, s in ipairs(sug) do
            local c = SmartCraft.Constants.DIFF_COLOR[s.recipe.difficulty]
            btnIdx = btnIdx + 1
            table.insert(lines, {
                text        = string.format("  [%dx]  %s", s.maxCrafts, s.recipe.name),
                r=c.r, g=c.g, b=c.b,
                hasCraftBtn = true,
                recipeIdx   = s.recipe.index,
                maxCrafts   = s.maxCrafts,
                btnPoolIdx  = btnIdx,
            })
            -- Build cost sub-line
            local buildCost = SmartCraft.PriceDB:GetBuildCost(s.recipe)
            if buildCost then
                table.insert(lines, {
                    text = "    Build cost~: " .. SmartCraft.PriceDB:FormatPrices({ build = buildCost }, true),
                    r=0.55, g=0.55, b=0.65,
                })
            end
        end
    end

    local resLines = SmartCraft.Suggestion:GetReservedLines()
    if #resLines > 0 then
        table.insert(lines, { text=" ", r=1, g=1, b=1 })
        table.insert(lines, { text="Reserved Mats", isHeader=true, hex="88bbff" })
        for _, l in ipairs(resLines) do
            if not l.text:find("Reserved Mats") then
                table.insert(lines, l)
            end
        end
    end

    return lines
end

function UI:BuildShoppingLines()
    local lines = {}

    table.insert(lines, { text="Shopping List", isHeader=true, hex="ffd700" })

    local shopList = SmartCraft.ShoppingList.list
    if not shopList or #shopList == 0 then
        table.insert(lines, { text="  Nothing to buy!", r=0.4, g=1, b=0.6 })
    else
        for _, entry in ipairs(shopList) do
            table.insert(lines, {
                text = string.format("  Buy %dx |cffffd700%s|r  (have %d)",
                    entry.toBuy, entry.itemName, entry.have),
                r=0.9, g=0.9, b=0.9,
            })
            -- Price sub-line
            local prices = SmartCraft.PriceDB:Get(entry.itemID)
            local priceStr = SmartCraft.PriceDB:FormatPrices(prices, true)
            if priceStr ~= "" then
                table.insert(lines, {
                    text = "    " .. priceStr,
                    r=0.55, g=0.55, b=0.65,
                })
            end
        end
    end

    local gaps = SmartCraft.Reservation.gaps
    if gaps and #gaps > 0 then
        table.insert(lines, { text=" ", r=1,g=1,b=1 })
        table.insert(lines, { text="Breakdown by Recipe", isHeader=true, hex="aaaaff" })
        for _, gap in ipairs(gaps) do
            table.insert(lines, { text="  "..gap.recipe.name..":", r=1, g=0.85, b=0.3 })
            for id, count in pairs(gap.short) do
                local name = SmartCraft.ItemCache:Get(id)
                table.insert(lines, {
                    text = string.format("    need %dx %s", count, name),
                    r=0.85, g=0.45, b=0.45,
                })
            end
        end
    end

    table.insert(lines, { text=" ", r=1,g=1,b=1 })
    table.insert(lines, { text="  Press Print to output list to chat.", r=0.5, g=0.5, b=0.5 })
    return lines
end

function UI:BuildPlannerLines()
    local lines = {}
    local PL = SmartCraft.Planner

    table.insert(lines, { text="Skill Route Planner", isHeader=true, hex="66ff99" })

    -- Inline input row (rendered as a widget line, not FontString)
    table.insert(lines, { isPlannerInput = true })

    table.insert(lines, {
        text = string.format("  Current skill:  %d / %d",
            SmartCraft.Recipes.skillLevel, SmartCraft.Recipes.maxSkill),
        r=0.7, g=0.7, b=0.7,
    })

    if PL.errorMsg then
        table.insert(lines, { text="  "..PL.errorMsg, r=1, g=0.3, b=0.3 })
    end

    if #PL.plan > 0 then
        table.insert(lines, { text=" ", r=1,g=1,b=1 })
        for _, l in ipairs(PL:GetPlanLines()) do table.insert(lines, l) end
        table.insert(lines, { text=" ", r=1,g=1,b=1 })
        table.insert(lines, { text="Mats to Buy", isHeader=true, hex="ffd700" })
        for _, l in ipairs(PL:GetBuyLines()) do table.insert(lines, l) end
        table.insert(lines, { text=" ", r=1,g=1,b=1 })
        table.insert(lines, { text="  Press Print to output plan to chat.", r=0.5,g=0.5,b=0.5 })
    end

    return lines
end

function UI:BuildOptimizeLines()
    local lines = {}
    local OPT   = SmartCraft.Optimizer

    -- Strategy selector buttons rendered as a special widget row
    table.insert(lines, { isStrategyRow = true })

    local headers = {
        cheapest = "Cheapest Skill-Ups",
        ah       = "Best AH Profit",
        de       = "Best DE Profit",
        deprofit = "DE Profit Only (break-even+)",
    }
    table.insert(lines, {
        text = headers[OPT.strategy] or "Optimize",
        isHeader = true, hex = "ffd700",
    })

    local desc = {
        cheapest = "  Ranked by lowest build cost per skill-up.",
        ah       = "  Ranked by AH sell - build cost. Needs TSM/Auctionator.",
        de       = "  Ranked by Disenchant value - build cost.",
        deprofit = "  Only recipes where DE value covers build cost.",
    }
    table.insert(lines, { text = desc[OPT.strategy] or "", r=0.5, g=0.5, b=0.65 })
    table.insert(lines, { text = " ", r=1,g=1,b=1 })

    for _, l in ipairs(OPT:GetLines()) do
        table.insert(lines, l)
    end

    return lines
end

function UI:RenderStrategyRow(yOff)
    local strategies = {
        { key="cheapest",  label="Cheapest"  },
        { key="ah",        label="AH Profit" },
        { key="de",        label="DE Profit" },
        { key="deprofit",  label="DE>=Cost"  },
    }
    local bw, bh, bx = 82, 20, 4
    for i, def in ipairs(strategies) do
        local btn = stratBtns[i]
        if not btn then
            btn = CreateFrame("Button", "SCStratBtn"..i, scrollChild, "UIPanelButtonTemplate")
            btn:SetSize(bw, bh)
            stratBtns[i] = btn
        end
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", bx, yOff)
        btn:SetText(def.label)
        local key = def.key
        btn:SetScript("OnClick", function()
            SmartCraft.Optimizer:Run(key)
            UI:RebuildContent()
        end)
        btn:SetAlpha(SmartCraft.Optimizer.strategy == def.key and 1.0 or 0.55)
        btn:Show()
        bx = bx + bw + 2
    end
    return yOff - (bh + 8)
end

function UI:BuildHelpLines()
    local W = 0.85
    local lines = {}

    local function H1(text, hex)
        table.insert(lines, { text=text, isHeader=true, hex=hex or "ffd700" })
    end
    local function P(text, r, g, b)
        table.insert(lines, { text=text, r=r or W, g=g or W, b=b or W })
    end
    local function Gap()
        table.insert(lines, { text=" ", r=1, g=1, b=1 })
    end

    H1("What is SmartCraft?")
    P("SmartCraft helps you level professions faster")
    P("by figuring out the smartest crafting order")
    P("based on what's already in your bags and bank.")
    Gap()

    H1("The Problem It Solves", "ff9966")
    P("Crafting the easiest recipe first can waste")
    P("materials you need for higher-skill recipes.")
    P("SmartCraft prevents that.")
    Gap()

    H1("How It Works — 3 Phases", "66ff99")
    P("|cffffd700Phase 1 — Reserve|r", 1,1,1)
    P("  Scans from your MAX skill recipe down")
    P("  to your current skill.  Locks in enough")
    P("  materials for each orange/yellow recipe")
    P("  before anything is crafted.")
    Gap()
    P("|cffffd700Phase 2 — Suggest|r", 1,1,1)
    P("  Uses only what's LEFT OVER after")
    P("  reservation.  These are your safe crafts")
    P("  — you won't break any future recipe.")
    Gap()
    P("|cffffd700Phase 3 — Shop|r", 1,1,1)
    P("  Finds every recipe you ALMOST have")
    P("  enough mats for, and tells you exactly")
    P("  what to buy to unlock more skill-ups.")
    Gap()

    H1("The Tabs", "88bbff")
    P("|cffffd700Crafts|r  — Safe recipes to craft now.")
    P("  Color = skill-up chance:")
    P("  |cffff8040Orange|r = guaranteed  |cffffd700Yellow|r = likely")
    P("  |cff40c040Green|r  = possible    |cff888888Gray|r   = none")
    P("  Click [Craft] to craft directly.")
    Gap()
    P("|cffffd700Shopping|r  — What to buy at the AH")
    P("  to unlock more skill-up recipes.")
    P("  Press Print to paste the list to chat.")
    Gap()
    P("|cffffd700Planner|r  — Enter a target skill level.")
    P("  Gets a full route: which recipes to")
    P("  craft and exactly how many mats to buy.")
    Gap()

    H1("Bank Scanning", "aaaaff")
    P("SmartCraft caches your bank contents")
    P("when you visit the bank.  It uses them")
    P("automatically so you never have to carry")
    P("everything to the trainer first.")
    P("Right-click the minimap icon to toggle")
    P("bank on or off.  Status shown top-right.")
    Gap()

    H1("Commands", "cccccc")
    P("  /sc              open/close panel")
    P("  /sc bank         toggle bank scanning")
    P("  /sc shop         jump to Shopping tab")
    P("  /sc plan         jump to Planner tab")
    P("  /sc errors       show error log")
    Gap()

    return lines
end

-- ----------------------------------------------------------------
-- Public show / hide
-- ----------------------------------------------------------------
function UI:Show()
    self:Init()
    self:SwitchTab(activeTab)
    self:UpdateHeader()
    frame:Show()
end

function UI:Hide()
    if frame then frame:Hide() end
end

function UI:IsShown()
    return frame and frame:IsShown()
end

function UI:ShowTab(key)
    self:Show()
    self:SwitchTab(key)
end
