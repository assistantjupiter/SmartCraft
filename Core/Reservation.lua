-- Reservation.lua
-- 3-phase SmartCraft algorithm.

SmartCraft.Reservation = {}
local Res = SmartCraft.Reservation

Res.reserved    = {}
Res.suggestions = {}
Res.gaps        = {}

function Res:Run()
    self.reserved    = {}
    self.suggestions = {}
    self.gaps        = {}

    for _, r in ipairs(SmartCraft.Recipes.list) do r.reserved = false end

    -- Working pool: bags + (cached bank if enabled)
    local pool = {}
    for id, count in pairs(SmartCraft.Inventory:GetAllItems()) do
        pool[id] = count
    end

    local recipes = SmartCraft.Recipes.list   -- HIGH → LOW

    -- ── PHASE 1: RESERVE ────────────────────────────────────────
    for _, recipe in ipairs(recipes) do
        if recipe.difficulty == "OPTIMAL" or recipe.difficulty == "MEDIUM" then
            if self:CanCraft(recipe.reagents, pool) then
                for id, needed in pairs(recipe.reagents) do
                    pool[id] = (pool[id] or 0) - needed
                    self.reserved[id] = (self.reserved[id] or 0) + needed
                end
                recipe.reserved = true
            end
        end
    end

    -- ── PHASE 2: SUGGEST ────────────────────────────────────────
    local bySkillAsc = {}
    for i = #recipes, 1, -1 do table.insert(bySkillAsc, recipes[i]) end

    for _, recipe in ipairs(bySkillAsc) do
        if recipe.difficulty ~= "TRIVIAL" then
            local max = self:MaxCrafts(recipe.reagents, pool)
            if max > 0 then
                table.insert(self.suggestions, { recipe = recipe, maxCrafts = max })
                for id, needed in pairs(recipe.reagents) do
                    pool[id] = (pool[id] or 0) - needed * max
                end
            end
        end
    end

    -- ── PHASE 3: GAPS ───────────────────────────────────────────
    local fullPool = SmartCraft.Inventory:GetAllItems()
    for _, recipe in ipairs(recipes) do
        if (recipe.difficulty == "OPTIMAL" or recipe.difficulty == "MEDIUM") and not recipe.reserved then
            local short, any = {}, false
            for id, needed in pairs(recipe.reagents) do
                local have = fullPool[id] or 0
                if have < needed then
                    short[id] = needed - have
                    any = true
                end
            end
            if any then
                table.insert(self.gaps, { recipe = recipe, short = short })
            end
        end
    end
end

function Res:CanCraft(reagents, pool)
    for id, needed in pairs(reagents) do
        if (pool[id] or 0) < needed then return false end
    end
    return true
end

function Res:MaxCrafts(reagents, pool)
    local max = math.huge
    for id, needed in pairs(reagents) do
        local p = math.floor((pool[id] or 0) / needed)
        if p < max then max = p end
    end
    return max == math.huge and 0 or max
end
