-- MainFrame.lua
-- Fully native WoW frame — vanilla Classic / Anniversary compatible.
-- Avoids all Dragonflight/TBC-only frame templates.
-- Uses SetBackdrop + manual title/close for maximum compatibility.

SmartCraft.UI = {}
local UI = SmartCraft.UI

local UC = SmartCraft.Constants.UI
local W, H = UC.W, UC.H

local frame, scrollFrame, scrollChild
local skillLine, bankLine
local tabs      = {}
local activeTab = "crafts"

local fsPool  = {}
local btnPool = {}

local plannerTargetBox, plannerGoBtn

-- Standard vanilla backdrop
local BACKDROP = {
    bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile     = true,
    tileSize = 32,
    edgeSize = 32,
    insets   = { left=11, right=12, top=12, bottom=11 },
}

-- ----------------------------------------------------------------
-- Build the static frame skeleton (called once)
-- ----------------------------------------------------------------
function UI:Init()
    if frame then return end

    -- ── Main window ─────────────────────────────────────────────
    frame = CreateFrame("Frame", "SmartCraftMainFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    frame:SetSize(W, H)
    frame:SetPoint("CENTER")
    -- SetBackdrop requires BackdropTemplateMixin in Anniversary/Shadowlands+
    if frame.SetBackdrop then
        frame:SetBackdrop(BACKDROP)
        frame:SetBackdropColor(0, 0, 0, 1)
    else
        -- Fallback: plain dark background texture
        local bg = frame:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(frame)
        bg:SetColorTexture(0.05, 0.05, 0.05, 0.95)
    end
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop",  frame.StopMovingOrSizing)
    frame:SetToplevel(true)
    frame:SetFrameStrata("HIGH")
    frame:Hide()

    -- ── Title bar ───────────────────────────────────────────────
    local titleBg = frame:CreateTexture(nil, "OVERLAY")
    titleBg:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
    titleBg:SetWidth(300)
    titleBg:SetHeight(64)
    titleBg:SetPoint("TOP", frame, "TOP", 0, 12)

    local titleText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleText:SetPoint("TOP", frame, "TOP", 0, -2)
    titleText:SetText("|cff00ff96⚒|r SmartCraft")

    -- ── Close button ─────────────────────────────────────────────
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 2, 2)
    closeBtn:SetScript("OnClick", function() frame:Hide() end)

    -- ── Status row ───────────────────────────────────────────────
    skillLine = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    skillLine:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -20)
    skillLine:SetText("")

    bankLine = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    bankLine:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -28, -20)
    bankLine:SetJustifyH("RIGHT")
    bankLine:SetText("")

    -- ── Tab buttons ──────────────────────────────────────────────
    local tabDefs = {
        { key="crafts",   label="Crafts"   },
        { key="shopping", label="Shopping" },
        { key="planner",  label="Planner"  },
    }
    local tx = 14
    for _, def in ipairs(tabDefs) do
        local btn = CreateFrame("Button", "SCTab_"..def.key, frame, "UIPanelButtonTemplate")
        btn:SetSize(86, UC.TAB_H)
        btn:SetPoint("TOPLEFT", frame, "TOPLEFT", tx, -UC.HEADER_H)
        btn:SetText(def.label)
        local key = def.key
        btn:SetScript("OnClick", function() UI:SwitchTab(key) end)
        tabs[def.key] = btn
        tx = tx + 90
    end

    -- ── Scroll area ──────────────────────────────────────────────
    local scrollTop = UC.HEADER_H + UC.TAB_H + 6
    scrollFrame = CreateFrame("ScrollFrame", "SmartCraftScroll", frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT",     frame, "TOPLEFT",     14,          -scrollTop)
    scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -UC.SCROLL_R, UC.FOOTER_H)

    scrollChild = CreateFrame("Frame", "SmartCraftScrollChild", scrollFrame)
    scrollChild:SetWidth(W - 14 - UC.SCROLL_R - 4)
    scrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(scrollChild)

    -- ── Footer ───────────────────────────────────────────────────
    local refreshBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    refreshBtn:SetSize(68, 20)
    refreshBtn:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 14, 14)
    refreshBtn:SetText("Refresh")
    refreshBtn:SetScript("OnClick", function()
        SmartCraft:RunAnalysis()
        UI:Refresh()
    end)

    local bankToggle = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    bankToggle:SetSize(100, 20)
    bankToggle:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 88, 14)
    bankToggle:SetText("Toggle Bank")
    bankToggle:SetScript("OnClick", function()
        if SmartCraftDB then
            SmartCraftDB.includeBank = not SmartCraftDB.includeBank
        end
        SmartCraft:RunAnalysis()
        UI:Refresh()
    end)

    local printBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    printBtn:SetSize(70, 20)
    printBtn:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 14)
    printBtn:SetText("Print")
    printBtn:SetScript("OnClick", function()
        if activeTab == "shopping" then
            SmartCraft.ShoppingList:PrintToChat()
        elseif activeTab == "planner" then
            SmartCraft.Planner:PrintToChat()
        end
    end)

    -- ── Planner controls ─────────────────────────────────────────
    plannerGoBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    plannerGoBtn:SetSize(52, 22)
    plannerGoBtn:SetPoint("TOPRIGHT", scrollFrame, "TOPRIGHT", 0, 26)
    plannerGoBtn:SetText("Plan")
    plannerGoBtn:SetScript("OnClick", function()
        local val = tonumber(plannerTargetBox:GetText())
        if val then
            SmartCraft.Planner:BuildPlan(val)
            UI:RebuildContent()
        else
            print("|cff00ff96SmartCraft:|r Enter a numeric target skill.")
        end
    end)
    plannerGoBtn:Hide()

    plannerTargetBox = CreateFrame("EditBox", "SCPlannerTarget", frame, "InputBoxTemplate")
    plannerTargetBox:SetSize(60, 20)
    plannerTargetBox:SetPoint("RIGHT", plannerGoBtn, "LEFT", -4, 0)
    plannerTargetBox:SetAutoFocus(false)
    plannerTargetBox:SetNumeric(true)
    plannerTargetBox:SetMaxLetters(3)
    plannerTargetBox:SetScript("OnEnterPressed", function()
        plannerGoBtn:Click()
    end)
    plannerTargetBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    plannerTargetBox:Hide()

    self.frame       = frame
    self.scrollChild = scrollChild
    self.scrollFrame = scrollFrame
end

-- ----------------------------------------------------------------
-- Tab switching
-- ----------------------------------------------------------------
function UI:SwitchTab(key)
    activeTab = key
    for k, btn in pairs(tabs) do
        btn:SetAlpha(k == key and 1.0 or 0.5)
    end
    local isPlanner = (key == "planner")
    if plannerTargetBox then plannerTargetBox:SetShown(isPlanner) end
    if plannerGoBtn     then plannerGoBtn:SetShown(isPlanner)     end
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
    end
    bankLine:SetText(SmartCraft.Inventory:BankCacheStatus())
end

-- ----------------------------------------------------------------
-- Rebuild scrollable content
-- ----------------------------------------------------------------
function UI:RebuildContent()
    for _, fs  in ipairs(fsPool)  do fs:SetText("") ; fs:Hide() end
    for _, btn in ipairs(btnPool) do btn:Hide() end

    local lines = {}
    if     activeTab == "crafts"   then lines = self:BuildCraftLines()
    elseif activeTab == "shopping" then lines = self:BuildShoppingLines()
    elseif activeTab == "planner"  then lines = self:BuildPlannerLines()
    end

    local LH   = UC.LINE_H
    local yOff = -4

    for i, line in ipairs(lines) do
        local fs = fsPool[i]
        if not fs then
            fs = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            fs:SetJustifyH("LEFT")
            fsPool[i] = fs
        end
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 4, yOff)
        local lineWidth = scrollChild:GetWidth() - (line.hasCraftBtn and 64 or 4)
        fs:SetWidth(lineWidth)
        fs:SetText(line.text or "")
        fs:SetTextColor(line.r or 1, line.g or 1, line.b or 1)
        fs:Show()

        if line.hasCraftBtn and line.recipeIdx then
            local bi  = line.btnPoolIdx
            local btn = btnPool[bi]
            if not btn then
                btn = CreateFrame("Button", "SCCraftBtn"..bi, scrollChild, "UIPanelButtonTemplate")
                btn:SetSize(56, LH + 2)
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

    scrollChild:SetHeight(math.max(math.abs(yOff) + 4, 1))
    scrollFrame:SetVerticalScroll(0)
end

-- ----------------------------------------------------------------
-- Click-to-craft (vanilla-safe ticker)
-- ----------------------------------------------------------------
function UI:DoCraft(recipeIdx, times)
    if not recipeIdx then return end
    TradeSkillFrame_SetSelection(recipeIdx)
    DoTradeSkill(recipeIdx, times)
    local ticker = CreateFrame("Frame")
    local elapsed = 0
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

    table.insert(lines, { text="── Safe to Craft ──", r=0.4, g=1, b=0.6 })

    local sug = SmartCraft.Reservation.suggestions
    if not sug or #sug == 0 then
        table.insert(lines, { text="  No crafts available with current mats.", r=0.6, g=0.6, b=0.6 })
    else
        for _, s in ipairs(sug) do
            local c = SmartCraft.Constants.DIFF_COLOR[s.recipe.difficulty]
            btnIdx = btnIdx + 1
            table.insert(lines, {
                text        = string.format("  [%dx] %s", s.maxCrafts, s.recipe.name),
                r=c.r, g=c.g, b=c.b,
                hasCraftBtn = true,
                recipeIdx   = s.recipe.index,
                maxCrafts   = s.maxCrafts,
                btnPoolIdx  = btnIdx,
            })
        end
    end

    table.insert(lines, { text=" ", r=1, g=1, b=1 })

    for _, l in ipairs(SmartCraft.Suggestion:GetReservedLines()) do
        table.insert(lines, l)
    end
    return lines
end

function UI:BuildShoppingLines()
    local lines = {}
    for _, l in ipairs(SmartCraft.ShoppingList:GetLines()) do
        table.insert(lines, l)
    end
    local gaps = SmartCraft.Reservation.gaps
    if gaps and #gaps > 0 then
        table.insert(lines, { text=" ", r=1,g=1,b=1 })
        table.insert(lines, { text="── Breakdown by Recipe ──", r=0.7,g=0.7,b=1 })
        for _, gap in ipairs(gaps) do
            table.insert(lines, { text="  "..gap.recipe.name..":", r=1, g=0.85, b=0.3 })
            for id, count in pairs(gap.short) do
                local name = SmartCraft.ItemCache:Get(id)
                table.insert(lines, {
                    text = string.format("    need %dx %s", count, name),
                    r=0.9, g=0.5, b=0.5,
                })
            end
        end
    end
    table.insert(lines, { text=" ", r=1,g=1,b=1 })
    table.insert(lines, { text="|cff888888Press Print to output list to chat|r", r=0.6,g=0.6,b=0.6 })
    return lines
end

function UI:BuildPlannerLines()
    local lines = {}
    local PL = SmartCraft.Planner
    if PL.targetSkill == 0 and #PL.plan == 0 then
        table.insert(lines, { text="Enter a target skill and press Plan.", r=0.6,g=0.6,b=0.6 })
        table.insert(lines, { text=" ", r=1,g=1,b=1 })
        table.insert(lines, {
            text = string.format("|cffaaaaaa Current: %d / %d|r",
                SmartCraft.Recipes.skillLevel, SmartCraft.Recipes.maxSkill),
            r=0.7, g=0.7, b=0.7,
        })
        return lines
    end
    table.insert(lines, {
        text = string.format("── Route to Skill %d ──", PL.targetSkill),
        r=0.4, g=1, b=0.6,
    })
    for _, l in ipairs(PL:GetPlanLines())  do table.insert(lines, l) end
    table.insert(lines, { text=" ", r=1,g=1,b=1 })
    for _, l in ipairs(PL:GetBuyLines())   do table.insert(lines, l) end
    table.insert(lines, { text=" ", r=1,g=1,b=1 })
    table.insert(lines, { text="|cff888888Press Print to output plan to chat|r", r=0.6,g=0.6,b=0.6 })
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
