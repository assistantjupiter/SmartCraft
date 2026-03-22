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

-- Anniversary (1.15.x) uses C_Container.* API.
-- Fall back to legacy globals if C_Container doesn't exist (older clients).
local function ContainerNumSlots(bag)
    if C_Container and C_Container.GetContainerNumSlots then
        return C_Container.GetContainerNumSlots(bag)
    end
    return GetContainerNumSlots(bag)
end

local function ContainerItemLink(bag, slot)
    if C_Container and C_Container.GetContainerItemLink then
        return C_Container.GetContainerItemLink(bag, slot)
    end
    return GetContainerItemLink and GetContainerItemLink(bag, slot)
end

local function ContainerItemCount(bag, slot)
    if C_Container and C_Container.GetContainerItemInfo then
        local info = C_Container.GetContainerItemInfo(bag, slot)
        return info and info.stackCount or 1
    end
    local _, count = GetContainerItemInfo(bag, slot)
    return count or 1
end

function Inv:ScanContainers(list)
    local items = {}
    for _, bag in ipairs(list) do
        local slots = ContainerNumSlots(bag)
        if slots and slots > 0 then
            for slot = 1, slots do
                local link = ContainerItemLink(bag, slot)
                if link then
                    local id = self:LinkToID(link)
                    if id then
                        local count = ContainerItemCount(bag, slot)
                        items[id] = (items[id] or 0) + count
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
        return "|cffff9900Bank: visit to scan|r"
    end
    if SmartCraftDB and SmartCraftDB.includeBank then
        return string.format("|cff00ff96Bank: ON (%d)|r", n)
    else
        return string.format("|cffff4444Bank: OFF (%d)|r", n)
    end
end
