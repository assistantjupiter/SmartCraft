-- MinimapButton.lua
-- Circular minimap button that orbits the minimap edge.
-- Position (angle in degrees) is saved to SmartCraftDB.minimapAngle.
-- Left-click: toggle main panel
-- Right-click: toggle bank on/off
-- Drag: reposition around the minimap

SmartCraft.MinimapButton = {}
local MB = SmartCraft.MinimapButton

local BUTTON_SIZE = 32
local MINIMAP_RADIUS = 80   -- distance from minimap center to button center

-- ----------------------------------------------------------------
-- Place the button at a given angle (degrees, 0 = right, CCW)
-- ----------------------------------------------------------------
local function UpdatePosition(btn, angle)
    local rad = math.rad(angle)
    local x   = math.cos(rad) * MINIMAP_RADIUS
    local y   = math.sin(rad) * MINIMAP_RADIUS
    btn:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

-- ----------------------------------------------------------------
-- Build and register the button (called once on load)
-- ----------------------------------------------------------------
function MB:Init()
    if self.btn then return end

    -- Ensure DB angle exists
    if not SmartCraftDB then SmartCraftDB = {} end
    if SmartCraftDB.minimapAngle == nil then
        SmartCraftDB.minimapAngle = 220   -- default bottom-left of minimap
    end

    -- ── Button frame ─────────────────────────────────────────────
    local btn = CreateFrame("Button", "SmartCraftMinimapBtn", Minimap)
    btn:SetSize(BUTTON_SIZE, BUTTON_SIZE)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(8)

    -- Circular mask / background
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-ZoneButton-Background")
    bg:SetAllPoints(btn)

    -- Icon — profession anvil texture
    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\Icons\\Trade_BlackSmithing")
    icon:SetSize(BUTTON_SIZE - 6, BUTTON_SIZE - 6)
    icon:SetPoint("CENTER", btn, "CENTER", 0, 0)

    -- Circular overlay border
    local overlay = btn:CreateTexture(nil, "OVERLAY")
    overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    overlay:SetSize(BUTTON_SIZE + 12, BUTTON_SIZE + 12)
    overlay:SetPoint("CENTER", btn, "CENTER", 0, 0)

    -- Hover highlight
    local hilite = btn:CreateTexture(nil, "HIGHLIGHT")
    hilite:SetTexture("Interface\\Minimap\\UI-Minimap-ZoneButton-Highlight")
    hilite:SetSize(BUTTON_SIZE + 12, BUTTON_SIZE + 12)
    hilite:SetPoint("CENTER", btn, "CENTER", 0, 0)
    hilite:SetBlendMode("ADD")

    btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoneButton-Highlight")

    -- ── Tooltip ───────────────────────────────────────────────────
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("SmartCraft", 1, 0.82, 0)
        GameTooltip:AddLine("Left-click: toggle panel", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Right-click: toggle bank scan", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Drag: move button", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- ── Clicks ────────────────────────────────────────────────────
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:SetScript("OnClick", function(self, mouseBtn)
        if mouseBtn == "RightButton" then
            -- Toggle bank
            if SmartCraftDB then
                SmartCraftDB.includeBank = not SmartCraftDB.includeBank
            end
            local s = (SmartCraftDB and SmartCraftDB.includeBank)
                and "|cff00ff00ON|r" or "|cffff4444OFF|r"
            print("|cff00ff96SmartCraft:|r Bank scanning " .. s)
            if TradeSkillFrame and TradeSkillFrame:IsShown() then
                SmartCraft:RunAnalysis()
                SmartCraft.UI:Refresh()
            end
        else
            SmartCraft:ToggleUI()
        end
    end)

    -- ── Drag to reposition ────────────────────────────────────────
    btn:SetMovable(true)
    btn:RegisterForDrag("LeftButton")

    btn:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function(self)
            local mx, my = Minimap:GetCenter()
            local px, py = GetCursorPosition()
            local scale  = Minimap:GetEffectiveScale()
            px = px / scale
            py = py / scale
            local angle = math.deg(math.atan2(py - my, px - mx))
            SmartCraftDB.minimapAngle = angle
            UpdatePosition(self, angle)
        end)
    end)

    btn:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    -- ── Initial position ──────────────────────────────────────────
    UpdatePosition(btn, SmartCraftDB.minimapAngle)

    self.btn = btn
end
