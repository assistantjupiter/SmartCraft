-- ItemCache.lua
-- Resolves item names from itemIDs.
-- GetItemInfo() in TBC may return nil if the client hasn't cached the item yet.
-- This module queues unknown IDs, sends tooltip queries to force server fetch,
-- and retries after GET_ITEM_INFO_RECEIVED fires.
--
-- Usage:
--   SmartCraft.ItemCache:Get(itemID)   → name string or "Item #<id>"
--   SmartCraft.ItemCache:Prefetch(ids) → queue a list of IDs for background fetch

SmartCraft.ItemCache = {}
local IC = SmartCraft.ItemCache

IC.names   = {}   -- itemID → name (permanent in-memory cache)
IC.pending = {}   -- itemID → true (queued for fetch)

-- Hidden tooltip used to force client to request item data from server
local tooltip

local function GetTooltip()
    if not tooltip then
        tooltip = CreateFrame("GameTooltip", "SmartCraftItemTooltip", UIParent, "GameTooltipTemplate")
        tooltip:SetOwner(UIParent, "ANCHOR_NONE")
    end
    return tooltip
end

-- Register for GET_ITEM_INFO_RECEIVED to know when data arrives
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
eventFrame:SetScript("OnEvent", function(self, event, itemID, success)
    if event == "GET_ITEM_INFO_RECEIVED" then
        itemID = tonumber(itemID)
        if itemID and IC.pending[itemID] then
            IC.pending[itemID] = nil
            local name = GetItemInfo(itemID)
            if name then
                IC.names[itemID] = name
            end
            -- Notify UI to re-render if it's open
            if SmartCraft.UI and SmartCraft.UI:IsShown() then
                SmartCraft.UI:RebuildContent()
            end
        end
    end
end)

-- Get item name; returns "Item #<id>" if not yet cached
function IC:Get(itemID)
    if self.names[itemID] then
        return self.names[itemID]
    end
    local name = GetItemInfo(itemID)
    if name then
        self.names[itemID] = name
        return name
    end
    -- Not cached — queue a fetch
    self:FetchOne(itemID)
    return "Item #" .. itemID
end

-- Queue a single item fetch via hidden tooltip
function IC:FetchOne(itemID)
    if self.pending[itemID] then return end
    self.pending[itemID] = true
    -- Tooltip SetHyperlink forces the client to request data from the server
    local ok, err = pcall(function()
        local tip = GetTooltip()
        tip:SetHyperlink("item:" .. itemID)
    end)
    if not ok then
        -- Tooltip method failed; try the direct API
        GetItemInfo(itemID)
    end
end

-- Prefetch a list of item IDs (call after recipe scan)
function IC:Prefetch(ids)
    for _, itemID in ipairs(ids) do
        if not self.names[itemID] and not GetItemInfo(itemID) then
            self:FetchOne(itemID)
        else
            -- Already know the name — cache it now
            local name = GetItemInfo(itemID)
            if name then self.names[itemID] = name end
        end
    end
end
