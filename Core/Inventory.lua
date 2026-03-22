-- Inventory.lua
-- Scans bags and caches bank contents.
-- TBC Classic 2.5.5: GetContainerItemInfo, GetContainerNumSlots

SmartCraft.Inventory = {}
local Inv = SmartCraft.Inventory

Inv.bagItems = {}

-- Bag IDs: 0=backpack, 1-4=bag slots
local PLAYER_BAGS = { 0, 1, 2, 3, 4 }
-- Bank: -1=main bank, 5-11=bank bag slots
local BANK_BAGS   = { -1, 5, 6, 7, 8, 9, 10, 11 }

function Inv:ScanBags()
    self.bagItems = self:ScanContainers(PLAYER_BAGS)
end

function Inv:ScanBank()
    local bankItems = self:ScanContainers(BANK_BAGS)
    if not SmartCraftDB then SmartCraftDB = {} end
    SmartCraftDB.bankCache = {}
    for id, count in pairs(bankItems) do
        SmartCraftDB.bankCache[id] = count
    end
    local n = self:CountKeys(bankItems)
    print(string.format("|cff00ff96SmartCraft:|r Bank cache updated — %d item type%s.", n, n == 1 and "" or "s"))
end

function Inv:GetCount(itemID)
    local count = self.bagItems[itemID] or 0
    if SmartCraftDB and SmartCraftDB.includeBank then
        count = count + ((SmartCraftDB.bankCache or {})[itemID] or 0)
    end
    return count
end

function Inv:GetAllItems()
    local combined = {}
    for id, count in pairs(self.bagItems) do
        combined[id] = (combined[id] or 0) + count
    end
    if SmartCraftDB and SmartCraftDB.includeBank then
        for id, count in pairs(SmartCraftDB.bankCache or {}) do
            combined[id] = (combined[id] or 0) + count
        end
    end
    return combined
end

function Inv:ScanContainers(list)
    local items = {}
    for _, bag in ipairs(list) do
        local slots = GetContainerNumSlots(bag)
        if slots and slots > 0 then
            for slot = 1, slots do
                -- Vanilla/Anniversary GetContainerItemInfo returns:
                -- texture, count, locked, quality, readable, lootable, link
                -- (same order as TBC but we use GetContainerItemLink for safety)
                local link = GetContainerItemLink(bag, slot)
                if link then
                    local id = self:LinkToID(link)
                    if id then
                        local _, count = GetContainerItemInfo(bag, slot)
                        items[id] = (items[id] or 0) + (count or 1)
                    end
                end
            end
        end
    end
    return items
end

function Inv:LinkToID(link)
    if not link then return nil end
    local id = link:match("item:(%d+)")
    return id and tonumber(id) or nil
end

function Inv:CountKeys(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

function Inv:BankCacheStatus()
    local cache = SmartCraftDB and SmartCraftDB.bankCache or {}
    local n = self:CountKeys(cache)
    if n == 0 then
        return "|cffff9900Bank: not scanned — visit bank to cache|r"
    end
    local state = (SmartCraftDB and SmartCraftDB.includeBank) and "|cff00ff96ON|r" or "|cffff4444OFF|r"
    return string.format("|cffaaaaaa Bank %s (%d types)|r", state, n)
end
