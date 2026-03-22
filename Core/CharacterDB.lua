-- CharacterDB.lua
-- Per-character data store (account-wide SavedVariables).
-- Saves bags, bank, mail, and professions for every character that
-- has run SmartCraft. Stored in SmartCraftDB.characters[key].
--
-- Key format: "CharacterName-RealmName"
--
-- Data saved per character:
--   items     = { [itemID] = count }   bags + bank + mail combined
--   bagItems  = { [itemID] = count }
--   bankItems = { [itemID] = count }
--   mailItems = { [itemID] = count }
--   professions = { { name, rank, maxRank } }
--   lastSeen  = timestamp string
--   class     = "MAGE" etc
--   level     = 60

SmartCraft.CharacterDB = {}
local CDB = SmartCraft.CharacterDB

-- ----------------------------------------------------------------
-- Get the key for the current logged-in character
-- ----------------------------------------------------------------
function CDB:CurrentKey()
    local name  = UnitName("player") or "Unknown"
    local realm = GetRealmName and GetRealmName() or "Unknown"
    return name .. "-" .. realm
end

-- ----------------------------------------------------------------
-- Save current character's data into SmartCraftDB.characters
-- Called automatically by RunAnalysis
-- ----------------------------------------------------------------
function CDB:SaveCurrent()
    if not SmartCraftDB then SmartCraftDB = {} end
    if not SmartCraftDB.characters then SmartCraftDB.characters = {} end

    local key  = self:CurrentKey()
    local Inv  = SmartCraft.Inventory

    -- Snapshot current inventory sources
    local bags  = {}
    local bank  = SmartCraftDB.bankCache or {}
    local mail  = Inv.mailItems or {}

    for id, count in pairs(Inv.bagItems or {}) do
        bags[id] = count
    end

    -- Combined
    local combined = {}
    for id, count in pairs(bags)  do combined[id] = (combined[id] or 0) + count end
    for id, count in pairs(bank)  do combined[id] = (combined[id] or 0) + count end
    for id, count in pairs(mail)  do combined[id] = (combined[id] or 0) + count end

    -- Professions
    local professions = {}
    local numLines = GetNumSkillLines and GetNumSkillLines() or 0
    for i = 1, numLines do
        local name, isHeader, _, rank, _, _, maxRank = GetSkillLineInfo(i)
        if not isHeader and name and rank and rank > 0 then
            -- Only primary/secondary professions (heuristic: maxRank >= 75)
            if maxRank and maxRank >= 75 then
                table.insert(professions, { name=name, rank=rank, maxRank=maxRank })
            end
        end
    end

    -- Character info
    local _, class  = UnitClass("player")
    local level     = UnitLevel("player") or 0

    SmartCraftDB.characters[key] = {
        name        = UnitName("player"),
        realm       = GetRealmName and GetRealmName() or "",
        class       = class or "UNKNOWN",
        level       = level,
        lastSeen    = date("%Y-%m-%d %H:%M"),
        items       = combined,
        bagItems    = bags,
        bankItems   = bank,
        mailItems   = mail,
        professions = professions,
    }
end

-- ----------------------------------------------------------------
-- Get all items across ALL characters (merged pool)
-- Optionally exclude the current character (if you want alts-only)
-- ----------------------------------------------------------------
function CDB:GetAllCharItems(excludeCurrent)
    local merged = {}
    local chars  = SmartCraftDB and SmartCraftDB.characters or {}
    local myKey  = self:CurrentKey()

    for key, data in pairs(chars) do
        if not (excludeCurrent and key == myKey) then
            for id, count in pairs(data.items or {}) do
                merged[id] = (merged[id] or 0) + count
            end
        end
    end
    return merged
end

-- ----------------------------------------------------------------
-- Get items from a specific character key
-- ----------------------------------------------------------------
function CDB:GetCharItems(key)
    local chars = SmartCraftDB and SmartCraftDB.characters or {}
    return (chars[key] and chars[key].items) or {}
end

-- ----------------------------------------------------------------
-- Get list of all stored characters (sorted by name)
-- Returns list of { key, name, realm, class, level, lastSeen, professions }
-- ----------------------------------------------------------------
function CDB:GetCharacterList()
    local list  = {}
    local chars = SmartCraftDB and SmartCraftDB.characters or {}
    for key, data in pairs(chars) do
        table.insert(list, {
            key        = key,
            name       = data.name or key,
            realm      = data.realm or "",
            class      = data.class or "",
            level      = data.level or 0,
            lastSeen   = data.lastSeen or "",
            professions = data.professions or {},
        })
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

-- ----------------------------------------------------------------
-- Check which alts have a specific item and how many
-- Returns list of { charName, count } sorted by count desc
-- ----------------------------------------------------------------
function CDB:WhoHas(itemID)
    local result = {}
    local chars  = SmartCraftDB and SmartCraftDB.characters or {}
    for _, data in pairs(chars) do
        local count = (data.items or {})[itemID] or 0
        if count > 0 then
            table.insert(result, { charName=data.name or "?", count=count })
        end
    end
    table.sort(result, function(a, b) return a.count > b.count end)
    return result
end
