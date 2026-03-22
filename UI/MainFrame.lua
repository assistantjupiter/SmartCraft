-- MainFrame.lua
-- Fully native WoW frame — TBC Classic 2.5.5 (Interface 20502)
-- No external library dependencies.
--
-- Tabs: [Crafts] [Shopping] [Planner]
--
-- Crafts tab:   colored suggestion rows, each with a [Craft] button
-- Shopping tab: buy list + per-recipe breakdown
-- Planner tab:  target skill input, craft route, mats-to-buy list

SmartCraft.UI = {}
local UI = SmartCraft.UI

local UC = SmartCraft.Constants.UI  -- W, H, TAB_H, HEADER_H, FOOTER_H, LINE_H, SCROLL_R

local frame, scrollFrame, scrollChild
local skillLine, bankLine
local tabs    = {}
local activeTab = "crafts"

-- Font string pool: WoW can't destroy FontStrings, so we reuse them
local fsPool    = {}
local btnPool   = {}   -- craft buttons pool

-- Planner widgets (created once)
local plannerTargetBox, plannerGoBtn, plannerPrintBtn

-- ----------------------------------------------------------------
-- Build the static frame skeleton (called once)
-- ----------------------------------------------------------------
function UI:Init()
    if frame then return end

    local W, H = UC.W, UC.H

    -- ── Main window ─────────────────────────────────────────────
    frame = CreateFrame("Frame", "SmartCraftMainFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(W, H)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop",  frame.StopMovingOrSizing)
    frame:SetToplevel(true)
    frame:Hide()
    frame.TitleText:SetText("|cff00ff96⚒|r SmartCraft")

    -- ── Status row ──────────────────────────────────────────────
    skillLine = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    skillLine:SetPoint("TOPLEFT",  frame, "TOPLEFT",  12, -30)
    skillLine:SetText("")

    bankLine = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    bankLine:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -28, -30)
    bankLine:SetJustifyH("RIGHT")
    bankLine:SetText("")

    -- ── Tab buttons ─────────────────────────────────────────────
    local tabDefs = {
        { key="crafts",   label="Crafts"   },
        { key="shopping", label="Shopping" },
        { key="planner",  label="Planner"  },
    }
    local tx = 10
    for _, def in ipairs(tabDefs) do
        local btn = CreateFrame("Button", "SCTab_"..def.key, frame, "UIPanelButtonTemplate")
        btn:SetSize(88, UC.TAB_H)
        btn:SetPoint("TOPLEFT", frame, "TOPLEFT", tx, -UC.HEADER_H)
        btn:SetText(def.label)
        local key = def.key
        btn:SetScript("OnClick", function() UI:SwitchTab(key) end)
        tabs[def.key] = btn
        tx = tx + 92
    end

    -- ── Scroll area ─────────────────────────────────────────────
    local scrollTop = UC.HEADER_H + UC.TAB_H + 4
    scrollFrame = CreateFrame("ScrollFrame", "SmartCraftScroll", frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT",     frame, "TOPLEFT",     10,         -scrollTop)
    scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -UC.SCROLL_R, UC.FOOTER_H)

    scrollChild = CreateFrame("Frame", "SmartCraftScrollChild", scrollFrame)
    scrollChild:SetWidth(W - 10 - UC.SCROLL_R - 4)
    scrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(scrollChild)

    -- ── Footer ───────────────────────────────────────────────────
    local refreshBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    refreshBtn:SetSize(68, 20)
    refreshBtn:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 10, 6)
    refreshBtn:SetText("Refresh")
    refreshBtn:SetScript("OnClick", function()
        SmartCraft:RunAnalysis()
        UI:Refresh()
    end)

    local bankToggle = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    bankToggle:SetSize(100, 20)
    bankToggle:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 84, 6)
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
    printBtn:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -28, 6)
    printBtn:SetText("Print")
    printBtn:SetScript("OnClick", function()
        if activeTab == "shopping" then
            SmartCraft.ShoppingList:PrintToChat()
        elseif activeTab == "planner" then
            SmartCraft.Planner:PrintToChat()
        end
    end)

    -- ── Planner controls (hidden by default) ────────────────────
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
    plannerTargetBox:SetSize(60, 22)
    plannerTargetBox:SetPoint("RIGHT", plannerGoBtn, "LEFT", -4, 0)
    plannerTargetBox:SetAutoFocus(false)
    plannerTargetBox:SetNumeric(true)
    plannerTargetBox:SetMaxLetters(3)
    local placeholder = plannerTargetBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    placeholder:SetPoint("LEFT", plannerTargetBox, "LEFT", 4, 0)
    placeholder:SetText("Target")
    plannerTargetBox:SetScript("OnTextChanged", function(self)
        placeholder:SetShown(self:GetText() == "")
    end)
    plannerTargetBox:SetScript("OnEnterPressed", function()
        plannerGoBtn:Click()
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
    -- Show/hide planner controls
    local isPlanner = (key == "planner")
    plannerTargetBox:SetShown(isPlanner)
    plannerGoBtn:SetShown(isPlanner)
    self:RebuildContent()
end

-- ----------------------------------------------------------------
-- Public refresh (call after analysis runs)
-- ----------------------------------------------------------------
function UI:Refresh()
    self:Init()
    self:UpdateHeader()
    self:RebuildContent()
end

function UI:UpdateHeader()
    local R = SmartCraft.Recipes
    if R.skillName ~= "" then
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
    -- Hide all pooled widgets
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
            fs:SetWidth(scrollChild:GetWidth() - (line.hasCraftBtn and 60 or 4))
            fsPool[i] = fs
        end
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 4, yOff)
        fs:SetText(line.text or "")
        fs:SetTextColor(line.r or 1, line.g or 1, line.b or 1)
        fs:SetWidth(scrollChild:GetWidth() - (line.hasCraftBtn and 64 or 4))
        fs:Show()

        -- Click-to-craft button
        if line.hasCraftBtn and line.recipeIdx then
            local bi = line.btnPoolIdx
            local btn = btnPool[bi]
            if not btn then
                btn = CreateFrame("Button", "SCCraftBtn"..bi, scrollChild, "UIPanelButtonTemplate")
                btn:SetSize(56, LH + 1)
                btnPool[bi] = btn
            end
            btn:ClearAllPoints()
            btn:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", -4, yOff)
            local idx, times = line.recipeIdx, line.maxCrafts
            btn:SetScript("OnClick", function()
                UI:DoCraft(idx, times)
            end)
            btn:SetText("Craft")
            btn:Show()
        end

        yOff = yOff - LH
    end

    scrollChild:SetHeight(math.max(math.abs(yOff) + 4, 1))
    scrollFrame:SetVerticalScroll(0)
end

-- ----------------------------------------------------------------
-- Click-to-craft
-- ----------------------------------------------------------------
function UI:DoCraft(recipeIdx, times)
    if not recipeIdx then return end
    -- DoTradeSkill(index, minTime, maxTime, repeatTimes) in TBC
    -- Simple version: open the trade skill entry and craft
    TradeSkillFrame_SetSelection(recipeIdx)   -- select in the blizzard list
    DoTradeSkill(recipeIdx, times)
    -- Small delay then re-run analysis
    C_Timer and C_Timer.After and C_Timer.After(0.3, function()
        SmartCraft:RunAnalysis()
        UI:Refresh()
    end)
end

-- ----------------------------------------------------------------
-- Content builders
-- ----------------------------------------------------------------
function UI:BuildCraftLines()
    local lines = {}
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
                r           = c.r, g=c.g, b=c.b,
                hasCraftBtn = true,
                recipeIdx   = s.recipe.index,
                maxCrafts   = s.maxCrafts,
                btnPoolIdx  = btnIdx,
            })
        end
    end

    table.insert(lines, { text=" ", r=1,g=1,b=1 })

    local resLines = SmartCraft.Suggestion:GetReservedLines()
    for _, l in ipairs(resLines) do table.insert(lines, l) end

    return lines
end

function UI:BuildShoppingLines()
    local lines = {}
    for _, l in ipairs(SmartCraft.ShoppingList:GetLines()) do
        table.insert(lines, l)
    end

    local gaps = SmartCraft.Reservation.gaps
    if gaps and #gaps > 0 then
        table.insert(lines, { text=" ",                          r=1,g=1,b=1 })
        table.insert(lines, { text="── Breakdown by Recipe ──",  r=0.7,g=0.7,b=1 })
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

    if self.targetSkill == 0 and #PL.plan == 0 then
        table.insert(lines, { text="Enter a target skill level and press Plan.", r=0.6,g=0.6,b=0.6 })
        table.insert(lines, { text=" ", r=1,g=1,b=1 })
        table.insert(lines, {
            text = string.format(
                "|cffaaaaaa Current: %d / %d|r",
                SmartCraft.Recipes.skillLevel,
                SmartCraft.Recipes.maxSkill
            ),
            r=0.7, g=0.7, b=0.7,
        })
        return lines
    end

    -- Route
    table.insert(lines, {
        text = string.format("── Route to Skill %d ──", PL.targetSkill),
        r=0.4, g=1, b=0.6,
    })
    for _, l in ipairs(PL:GetPlanLines()) do table.insert(lines, l) end

    table.insert(lines, { text=" ", r=1,g=1,b=1 })

    -- Buy list
    for _, l in ipairs(PL:GetBuyLines()) do table.insert(lines, l) end

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
