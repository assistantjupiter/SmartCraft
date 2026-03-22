-- AltsFrame.lua
-- Alts tab content builder for MainFrame.
-- Shows all known characters with their professions and
-- highlights which alts hold items on the current shopping list.

SmartCraft.AltsUI = {}
local AU = SmartCraft.AltsUI

-- Class colors (standard WoW)
local CLASS_COLOR = {
    WARRIOR  = "C79C6E", PALADIN  = "F58CBA", HUNTER   = "ABD473",
    ROGUE    = "FFF569", PRIEST   = "FFFFFF", SHAMAN   = "0070DE",
    MAGE     = "69CCF0", WARLOCK  = "9482C9", DRUID    = "FF7D0A",
    DEATHKNIGHT = "C41F3B",
}

function AU:GetLines()
    local lines = {}
    local CDB   = SmartCraft.CharacterDB

    local chars = CDB:GetCharacterList()
    if #chars == 0 then
        table.insert(lines, {
            text = "  No character data yet.",
            r=0.5, g=0.5, b=0.5,
        })
        table.insert(lines, {
            text = "  Data saves automatically when you log in",
            r=0.5, g=0.5, b=0.5,
        })
        table.insert(lines, {
            text = "  on each character and open a profession.",
            r=0.5, g=0.5, b=0.5,
        })
        return lines
    end

    -- Build a needed-items map from shopping list
    local needed = {}
    for _, entry in ipairs(SmartCraft.ShoppingList.list or {}) do
        if entry.toBuy > 0 then
            needed[entry.itemID] = { name=entry.itemName, need=entry.toBuy }
        end
    end

    local myKey = CDB:CurrentKey()

    for _, char in ipairs(chars) do
        local isMe = (char.key == myKey)

        -- Character header
        local hex   = CLASS_COLOR[char.class] or "aaaaaa"
        local tag   = isMe and " |cff00ff96(you)|r" or ""
        local hdr   = string.format("|cff%s%s|r  Lv%d%s",
            hex, char.name, char.level, tag)
        table.insert(lines, { text=hdr, isHeader=true, hex=hex })

        -- Last seen
        table.insert(lines, {
            text = string.format("  Last seen: %s", char.lastSeen),
            r=0.5, g=0.5, b=0.5,
        })

        -- Professions
        if #char.professions > 0 then
            local profStrs = {}
            for _, p in ipairs(char.professions) do
                table.insert(profStrs, string.format("%s %d/%d", p.name, p.rank, p.maxRank))
            end
            table.insert(lines, {
                text = "  " .. table.concat(profStrs, "  |cff555555·|r  "),
                r=0.8, g=0.8, b=0.5,
            })
        end

        -- Shopping list items this char has
        local charItems = CDB:GetCharItems(char.key)
        local contributions = {}
        for itemID, need in pairs(needed) do
            local have = charItems[itemID] or 0
            if have > 0 then
                local useful = math.min(have, need.need)
                table.insert(contributions, {
                    name    = need.name,
                    have    = have,
                    useful  = useful,
                    itemID  = itemID,
                })
            end
        end

        if #contributions > 0 then
            table.sort(contributions, function(a, b) return a.useful > b.useful end)
            table.insert(lines, { text="  Has items you need:", r=0.4, g=1, b=0.6 })
            for _, c in ipairs(contributions) do
                local txt = string.format(
                    "    |cffffd700%s|r — has %d  (need %d)",
                    c.name, c.have, needed[c.itemID].need
                )
                table.insert(lines, { text=txt, r=0.85, g=0.85, b=0.85 })
            end
        end

        table.insert(lines, { text=" ", r=1,g=1,b=1 })
    end

    return lines
end
