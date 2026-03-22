-- SmartCraft.lua
-- Entry point — TBC Classic 2.5.5 (Interface 20502)
-- Fully native, no external dependencies.

SmartCraft = SmartCraft or {}
SmartCraft.version = "0.3.1"

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

    print("|cff00ff96SmartCraft|r v" .. self.version .. " loaded.")
    print("  |cffaaaaaa/sc|r          open panel      |cffaaaaaa/sc bank|r  toggle bank")
    print("  |cffaaaaaa/sc shop|r     shopping list    |cffaaaaaa/sc plan|r  open planner")

    SLASH_SMARTCRAFT1 = "/smartcraft"
    SLASH_SMARTCRAFT2 = "/sc"
    SlashCmdList["SMARTCRAFT"] = function(msg)
        local cmd = string.lower(string.match(msg or "", "^%s*(%S*)"))
        if cmd == "bank" then
            SmartCraftDB.includeBank = not SmartCraftDB.includeBank
            local s = SmartCraftDB.includeBank and "|cff00ff00ON|r" or "|cffff4444OFF|r"
            print("|cff00ff96SmartCraft:|r Bank scanning " .. s)
            if TradeSkillFrame and TradeSkillFrame:IsShown() then
                self:RunAnalysis() ; self.UI:Refresh()
            end
        elseif cmd == "shop" then
            if not TradeSkillFrame or not TradeSkillFrame:IsShown() then
                print("|cff00ff96SmartCraft:|r Open your profession window first.")
            else
                self.UI:ShowTab("shopping")
            end
        elseif cmd == "plan" then
            if not TradeSkillFrame or not TradeSkillFrame:IsShown() then
                print("|cff00ff96SmartCraft:|r Open your profession window first.")
            else
                self.UI:ShowTab("planner")
            end
        else
            self:ToggleUI()
        end
    end
end

function SmartCraft:OnTradeSkillShow()
    self:RunAnalysis()
    self.UI:Show()
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
    self.Inventory:ScanBags()
    self.Recipes:Scan()
    self.Reservation:Run()
    self.ShoppingList:Build()
    -- Planner re-runs only if a target was already set
    if self.Planner.targetSkill and self.Planner.targetSkill > 0 then
        self.Planner:BuildPlan(self.Planner.targetSkill)
    end
end

function SmartCraft:ToggleUI()
    if self.UI:IsShown() then
        self.UI:Hide()
    else
        if not TradeSkillFrame or not TradeSkillFrame:IsShown() then
            print("|cff00ff96SmartCraft:|r Open your profession window first.")
            return
        end
        self:RunAnalysis()
        self.UI:Show()
    end
end
