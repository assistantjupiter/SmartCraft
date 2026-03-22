-- Suggestion.lua
-- Formats Reservation output into display-ready line tables.

SmartCraft.Suggestion = {}
local S = SmartCraft.Suggestion

local C = {
    OPTIMAL = { r=1.00, g=0.50, b=0.25 },
    MEDIUM  = { r=1.00, g=1.00, b=0.00 },
    EASY    = { r=0.25, g=0.75, b=0.25 },
    TRIVIAL = { r=0.55, g=0.55, b=0.55 },
}

function S:GetSuggestionLines()
    local lines = {}
    local sug = SmartCraft.Reservation.suggestions
    if not sug or #sug == 0 then
        table.insert(lines, { text="  No crafts available with current mats.", r=0.6, g=0.6, b=0.6 })
        return lines
    end
    for _, s in ipairs(sug) do
        local col = C[s.recipe.difficulty] or C.TRIVIAL
        table.insert(lines, {
            text      = string.format("  [%dx] %s", s.maxCrafts, s.recipe.name),
            r = col.r, g = col.g, b = col.b,
            recipeIdx = s.recipe.index,   -- exposed for click-to-craft
            maxCrafts = s.maxCrafts,
        })
    end
    return lines
end

function S:GetReservedLines()
    local lines = {}
    local res = SmartCraft.Reservation.reserved
    local any = false
    for _ in pairs(res) do any = true break end
    if not any then return lines end

    table.insert(lines, { text="── Reserved Mats ──", r=0.5, g=0.7, b=1 })
    for id, count in pairs(res) do
        local name = SmartCraft.ItemCache:Get(id)
        table.insert(lines, {
            text = string.format("  %dx %s  |cff888888(held back)|r", count, name),
            r=0.7, g=0.85, b=1,
        })
    end
    return lines
end
