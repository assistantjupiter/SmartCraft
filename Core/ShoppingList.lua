-- ShoppingList.lua
-- Aggregates mat shortfalls across all gap recipes.
-- Produces a "buy X of Y" list, sorted by quantity needed.

SmartCraft.ShoppingList = {}
local SL = SmartCraft.ShoppingList

SL.list = {}

function SL:Build()
    self.list = {}
    local gaps = SmartCraft.Reservation.gaps
    if not gaps or #gaps == 0 then return end

    local totals = {}
    for _, gap in ipairs(gaps) do
        for id, short in pairs(gap.short) do
            totals[id] = (totals[id] or 0) + short
        end
    end

    for id, toBuy in pairs(totals) do
        table.insert(self.list, {
            itemID   = id,
            itemName = SmartCraft.ItemCache:Get(id),
            have     = SmartCraft.Inventory:GetCount(id),
            toBuy    = toBuy,
        })
    end

    table.sort(self.list, function(a, b) return a.toBuy > b.toBuy end)
end

function SL:GetLines()
    local lines = {}
    if #self.list == 0 then
        table.insert(lines, { text = "  Nothing to buy — you have all the mats!", r=0.4, g=1, b=0.6 })
        return lines
    end
    table.insert(lines, { text = "── Shopping List ──", r=1, g=0.8, b=0.2 })
    for _, e in ipairs(self.list) do
        local text = string.format("  Buy %dx |cffffd700%s|r  (have %d)", e.toBuy, e.itemName, e.have)
        table.insert(lines, { text=text, r=0.9, g=0.9, b=0.9 })
    end
    return lines
end

function SL:PrintToChat()
    if #self.list == 0 then
        print("|cff00ff96SmartCraft:|r Nothing to buy.")
        return
    end
    print("|cff00ff96SmartCraft Shopping List:|r")
    for _, e in ipairs(self.list) do
        print(string.format("  |cffffd700%dx|r %s", e.toBuy, e.itemName))
    end
end
