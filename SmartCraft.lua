-- SmartCraft.lua
-- Entry point — TBC Classic 2.5.5 (Interface 20502)
-- Fully native, no external dependencies.

SmartCraft = SmartCraft or {}
SmartCraft.version = "0.4.1"

SmartCraft.defaults = {
    includeBank = true,
    bankCache   = {},
}

local eventFrame = CreateFrame("Frame", "SmartCraftEventFrame", UIParent)
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("TRADE_SKILL_SHOW")
eventFrame:RegisterEvent("TRADE_SKILL_CLOSE")
eventFrame:RegisterEvent("TRADE_SKILL_UPDATE")
eventFrame:RegisterEvent("BANKFRAME_OPENED")
eventFrame:RegisterEvent("BANKFRAME_CLOSED")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if     event == "ADDON_LOADED"     then SmartCraft:OnAddonLoaded(...)
    elseif event == "TRADE_SKILL_SHOW"   then SmartCraft:OnTradeSkillShow()
    elseif event == "TRADE_SKILL_CLOSE"  then SmartCraft:OnTradeSkillClose()
    elseif event == "TRADE_SKILL_UPDATE" then SmartCraft:OnTradeSkillUpdate()
    elseif event == "BANKFRAME_OPENED"   then SmartCraft:OnBankOpened()
    end
end)

function SmartCraft:OnAddonLoaded(name)
    if name ~= "SmartCraft" then return end

    -- Initialise / migrate SavedVariables
    if not SmartCraftDB then SmartCraftDB = {} end
    for k, v in pairs(self.defaults) do
        if SmartCraftDB[k] == nil then SmartCraftDB[k] = v end
    end

    -- Init minimap button
    SmartCraft.MinimapButton:Init()

    print("|cff00ff96SmartCraft|r v" .. self.version .. " loaded.")
    print("  |cffaaaaaa/sc|r          open panel      |cffaaaaaa/sc bank|r    toggle bank")
    print("  |cffaaaaaa/sc shop|r     shopping list    |cffaaaaaa/sc plan|r    open planner")
    print("  |cffaaaaaa/sc errors|r   show error log   |cffaaaaaa/sc clearerrors|r  wipe log")

    SLASH_SMARTCRAFT1 = "/smartcraft"
    SLASH_SMARTCRAFT2 = "/sc"
    SlashCmdList["SMARTCRAFT"] = function(msg)
        local ok, err = pcall(function()
            local cmd = string.lower(string.match(msg or "", "^%s*(%S*)"))
            if cmd == "bank" then
                SmartCraftDB.includeBank = not SmartCraftDB.includeBank
                local s = SmartCraftDB.includeBank and "|cff00ff00ON|r" or "|cffff4444OFF|r"
                print("|cff00ff96SmartCraft:|r Bank scanning " .. s)
                if TradeSkillFrame and TradeSkillFrame:IsShown() then
                    SmartCraft:RunAnalysis()
                    SmartCraft.UI:Refresh()
                end
            elseif cmd == "shop" then
                SmartCraft.UI:ShowTab("shopping")
            elseif cmd == "plan" then
                SmartCraft.UI:ShowTab("planner")
            elseif cmd == "errors" then
                SmartCraft.ErrorLog:Print()
            elseif cmd == "clearerrors" then
                SmartCraft.ErrorLog:Clear()
            else
                SmartCraft:ToggleUI()
            end
        end)
        if not ok then
            SmartCraft.ErrorLog:Add("SlashCmd", err)
        end
    end
end

function SmartCraft:OnTradeSkillShow()
    -- Delay slightly: WoW populates trade skill data a frame after TRADE_SKILL_SHOW
    local elapsed = 0
    local ticker = CreateFrame("Frame")
    ticker:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        if elapsed >= 0.2 then
            self:SetScript("OnUpdate", nil)
            SmartCraft:RunAnalysis()
            SmartCraft.UI:Show()
        end
    end)
end

function SmartCraft:OnTradeSkillClose()
    self.UI:Hide()
end

function SmartCraft:OnTradeSkillUpdate()
    self:RunAnalysis()
    self.UI:Refresh()
end

function SmartCraft:OnBankOpened()
    self.Inventory:ScanBank()
    if TradeSkillFrame and TradeSkillFrame:IsShown() then
        self:RunAnalysis()
        self.UI:Refresh()
    end
end

function SmartCraft:RunAnalysis()
    local EL = self.ErrorLog
    EL:Wrap("Inventory:ScanBags",  function() self.Inventory:ScanBags() end)
    EL:Wrap("Recipes:Scan",        function() self.Recipes:Scan() end)
    EL:Wrap("Reservation:Run",     function() self.Reservation:Run() end)
    EL:Wrap("ShoppingList:Build",  function() self.ShoppingList:Build() end)
    if self.Planner.targetSkill and self.Planner.targetSkill > 0 then
        EL:Wrap("Planner:BuildPlan", function()
            self.Planner:BuildPlan(self.Planner.targetSkill)
        end)
    end
end

function SmartCraft:ToggleUI()
    local ok, err = pcall(function()
        if self.UI:IsShown() then
            self.UI:Hide()
        else
            self:RunAnalysis()
            self.UI:Show()
        end
    end)
    if not ok then
        self.ErrorLog:Add("ToggleUI", err)
    end
end
