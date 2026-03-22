-- Inventory.lua
-- Scans bags, bank, and mailbox attachments.
-- WoW Anniversary (vanilla Classic 1.15.x): C_Container.* API

SmartCraft.Inventory = {}
local Inv = SmartCraft.Inventory

Inv.bagItems  = {}
Inv.mailItems = {}   -- items pending in mailbox (in-memory only, not persisted)

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

-- ----------------------------------------------------------------
-- Scan mailbox attachments (only works while mailbox is open).
-- Uses GetInboxNumItems / GetInboxItem / GetInboxItemLink.
-- Mail attachments that haven't been taken yet are counted as
-- "incoming" and added to the combined pool.
-- ----------------------------------------------------------------
function Inv:ScanMail()
    self.mailItems = {}
    local numMail = GetInboxNumItems and GetInboxNumItems() or 0
    if numMail == 0 then return end

    for i = 1, numMail do
        -- Each mail can have up to ATTACHMENTS_MAX_SEND attachments
        for slot = 1, ATTACHMENTS_MAX_SEND or 16 do
            local link = GetInboxItemLink and GetInboxItemLink(i, slot)
            if link then
                local id = self:LinkToID(link)
                if id then
                    -- GetInboxItem returns: name,itemID,texture,count,quality,canUse
                    local _, _, _, count = GetInboxItem(i, slot)
                    self.mailItems[id] = (self.mailItems[id] or 0) + (count or 1)
                end
            end
        end
    end

    local n = self:CountKeys(self.mailItems)
    print(string.format("|cff00ff96SmartCraft:|r Mailbox scanned — %d item type%s in mail.", n, n==1 and "" or "s"))
end

function Inv:ClearMail()
    self.mailItems = {}
end

function Inv:MailCacheStatus()
    local n = self:CountKeys(self.mailItems)
    if n == 0 then return nil end
    return string.format("|cffddaa00Mail: %d types|r", n)
end

function Inv:GetCount(itemID)
    local count = self.bagItems[itemID] or 0
    if SmartCraftDB and SmartCraftDB.includeBank then
        count = count + ((SmartCraftDB.bankCache or {})[itemID] or 0)
    end
    count = count + (self.mailItems[itemID] or 0)
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
    -- Include mail items
    for id, count in pairs(self.mailItems) do
        combined[id] = (combined[id] or 0) + count
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
    local parts = {}

    if n == 0 then
        table.insert(parts, "|cffff9900Bank: visit to scan|r")
    elseif SmartCraftDB and SmartCraftDB.includeBank then
        table.insert(parts, string.format("|cff00ff96Bank: ON (%d)|r", n))
    else
        table.insert(parts, string.format("|cffff4444Bank: OFF (%d)|r", n))
    end

    local mailN = self:CountKeys(self.mailItems)
    if mailN > 0 then
        table.insert(parts, string.format("|cffddaa00Mail: %d|r", mailN))
    end

    return table.concat(parts, "  ")
end
