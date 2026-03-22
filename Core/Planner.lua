-- Planner.lua
-- Target Skill Planner: given a target skill level, compute the
-- most mat-efficient path from current skill to target.
--
-- Strategy:
--   1. Walk skill levels from current → target-1
--   2. At each level, pick the recipe that gives a skill-up AND
--      costs the fewest total reagents (greedy heuristic)
--   3. Accumulate required mats
--   4. Subtract what player already owns (bags + bank)
--   5. Output: craft plan steps + final shopping list
--
-- Limitations (TBC API):
--   - Exact recipe unlock thresholds aren't exposed; we use our
--     EstimateSkillReq approximation.
--   - Yields > 1 per craft are respected (numMade field).
--
-- Result stored in SmartCraft.Planner.plan and SmartCraft.Planner.buyList

SmartCraft.Planner = {}
local PL = SmartCraft.Planner

PL.targetSkill = 0
PL.plan        = {}   -- [{ recipe, craftsNeeded, matsUsed }]
PL.buyList     = {}   -- [{ itemID, itemName, need, have, toBuy }]

-- ----------------------------------------------------------------
-- Build a plan to reach targetSkill from current skill
-- ----------------------------------------------------------------
function PL:BuildPlan(targetSkill)
    self.targetSkill = targetSkill
    self.plan        = {}
    self.buyList     = {}

    local current = SmartCraft.Recipes.skillLevel
    local max     = SmartCraft.Recipes.maxSkill
    targetSkill   = math.min(targetSkill, max)

    if targetSkill <= current then
        self.errorMsg = "Target skill must be higher than current skill."
        return
    end
    self.errorMsg = nil

    -- Simulate skill progression
    local simSkill = current
    -- Track total mats needed across the whole plan
    local matTotals = {}   -- itemID → total count

    -- Build a merged recipe pool: known recipes + trainer recipes in range
    self.recipePool = self:BuildRecipePool(current, targetSkill)

    while simSkill < targetSkill do
        -- Find best recipe available at simSkill
        local best = self:BestRecipeAt(simSkill)
        if not best then
            -- No craftable recipe found — can't continue
            self.errorMsg = string.format("No recipe available at skill %d. Plan incomplete.", simSkill)
            break
        end

        -- How many crafts to reach next meaningful recipe or target?
        -- Each craft gives ~1 skill-up when orange/yellow. Green is ~50% chance.
        local skillUpsNeeded = targetSkill - simSkill
        local craftsMult = 1
        if best.difficulty == "EASY" then
            craftsMult = 2   -- ~50% chance, so craft ~2x per skill-up
        end
        local craftsForThis = math.ceil(skillUpsNeeded * craftsMult)

        -- Don't over-plan: stop when next recipe bracket would change
        -- (i.e., only plan until this recipe would turn grey)
        local greyAt = self:GreyAt(best, simSkill)
        local skillUpsHere = greyAt - simSkill
        if skillUpsHere <= 0 then skillUpsHere = 1 end
        local craftsHere = math.ceil(skillUpsHere * craftsMult)
        craftsHere = math.min(craftsHere, craftsForThis)

        -- Trainer-only recipe: note it and advance skill by 1 (placeholder)
        if best.isTrainerOnly then
            table.insert(self.plan, {
                recipe        = best,
                craftsNeeded  = 0,
                matsUsed      = {},
                fromSkill     = simSkill,
                toSkill       = simSkill,
                isTrainerStep = true,
            })
            simSkill = simSkill + 1
        else
            -- Accumulate mats
            local matsUsed = {}
            for id, perCraft in pairs(best.reagents) do
                local total = perCraft * craftsHere
                matsUsed[id] = total
                matTotals[id] = (matTotals[id] or 0) + total
            end

            table.insert(self.plan, {
                recipe       = best,
                craftsNeeded = craftsHere,
                matsUsed     = matsUsed,
                fromSkill    = simSkill,
                toSkill      = math.min(simSkill + skillUpsHere, targetSkill),
            })
            simSkill = simSkill + skillUpsHere
        end
    end

    -- Build buy list: matTotals minus what player owns
    local owned = SmartCraft.Inventory:GetAllItems()
    for id, needed in pairs(matTotals) do
        local have = owned[id] or 0
        local toBuy = math.max(0, needed - have)
        table.insert(self.buyList, {
            itemID   = id,
            itemName = SmartCraft.ItemCache:Get(id),
            need     = needed,
            have     = have,
            toBuy    = toBuy,
        })
    end
    table.sort(self.buyList, function(a, b) return a.toBuy > b.toBuy end)

    -- Collapse consecutive same-recipe steps into single entries
    self.plan = self:CollapsePlan(self.plan)
end

-- Merge consecutive steps with the same recipe name into one
function PL:CollapsePlan(plan)
    local collapsed = {}
    for _, step in ipairs(plan) do
        local last = collapsed[#collapsed]
        if last
            and not step.isTrainerStep
            and not (last.isTrainerStep)
            and last.recipe.name == step.recipe.name
        then
            -- Merge into previous entry
            last.craftsNeeded = last.craftsNeeded + step.craftsNeeded
            last.toSkill      = step.toSkill
            for id, count in pairs(step.matsUsed or {}) do
                last.matsUsed[id] = (last.matsUsed[id] or 0) + count
            end
        else
            -- Clone step so we don't mutate the original
            local s = {}
            for k, v in pairs(step) do s[k] = v end
            s.matsUsed = {}
            for id, count in pairs(step.matsUsed or {}) do
                s.matsUsed[id] = count
            end
            table.insert(collapsed, s)
        end
    end
    return collapsed
end

-- ----------------------------------------------------------------
-- Build merged recipe pool: known recipes + trainer recipes
-- Trainer entries get synthetic recipe objects with skillReq set
-- to their actual trainer-stated required skill level.
-- ----------------------------------------------------------------
function PL:BuildRecipePool(fromSkill, toSkill)
    local pool = {}

    -- Known recipes (already scanned)
    for _, recipe in ipairs(SmartCraft.Recipes.list) do
        if recipe.difficulty ~= "TRIVIAL" then
            table.insert(pool, recipe)
        end
    end

    -- Trainer recipes in the target range
    local TDB = SmartCraft.TrainerDB
    if TDB and #TDB.recipes > 0 then
        for _, tr in ipairs(TDB:GetRecipesInRange(fromSkill, toSkill)) do
            -- Check it's not already in known recipes
            local known = false
            for _, r in ipairs(SmartCraft.Recipes.list) do
                if r.name == tr.name then known = true break end
            end
            if not known then
                -- Synthetic recipe entry — no reagent data yet (not learned)
                -- Mark as trainer-only so Planner can note "learn from trainer first"
                table.insert(pool, {
                    name       = tr.name,
                    skillReq   = tr.reqSkill,
                    difficulty = "OPTIMAL",   -- assume orange when first learned
                    reagents   = {},           -- unknown until learned
                    numMade    = 1,
                    isTrainerOnly = true,
                    trainerCost   = tr.moneyCost,
                })
            end
        end
    end

    return pool
end

-- Find the most efficient recipe for a given skill level from the pool
-- Priority: OPTIMAL > MEDIUM > EASY; tiebreak = fewest total reagent quantity
-- Trainer-only recipes (no reagent data) are noted but skipped for mat planning
function PL:BestRecipeAt(simSkill)
    local best, bestScore = nil, nil
    local priority = { OPTIMAL=1, MEDIUM=2, EASY=3 }
    local pool = self.recipePool or SmartCraft.Recipes.list

    for _, recipe in ipairs(pool) do
        if not recipe.isTrainerOnly then
            -- Estimate difficulty at simSkill based on skillReq delta
            local delta = simSkill - recipe.skillReq
            local diff
            if     delta < 10  then diff = "OPTIMAL"
            elseif delta < 25  then diff = "MEDIUM"
            elseif delta < 50  then diff = "EASY"
            else                    diff = "TRIVIAL"
            end

            if diff ~= "TRIVIAL" then
                local greyAt = recipe.skillReq + 50
                if simSkill >= recipe.skillReq and simSkill < greyAt then
                    local p = priority[diff] or 99
                    local cost = self:TotalReagents(recipe)
                    local score = p * 1000 + cost
                    if not best or score < bestScore then
                        best, bestScore = recipe, score
                    end
                end
            end
        end
    end

    -- If no known recipe found, check if a trainer recipe unlocks soon
    if not best then
        local pool2 = self.recipePool or {}
        for _, recipe in ipairs(pool2) do
            if recipe.isTrainerOnly and recipe.skillReq <= simSkill + 5 then
                -- Suggest learning from trainer
                if not best or recipe.skillReq < best.skillReq then
                    best = recipe
                end
            end
        end
    end

    return best
end

-- Estimate skill at which a recipe turns grey
function PL:GreyAt(recipe, currentSkill)
    -- Orange recipes grey out ~+15 levels after they become yellow
    -- Approximation: grey when current > skillReq + 45
    return recipe.skillReq + 45
end

-- Sum of all reagent counts for one craft
function PL:TotalReagents(recipe)
    local n = 0
    for _, count in pairs(recipe.reagents) do n = n + count end
    return n
end

-- ----------------------------------------------------------------
-- Line builders for UI
-- ----------------------------------------------------------------
function PL:GetPlanLines()
    local lines = {}

    if self.errorMsg then
        table.insert(lines, { text = "|cffff4444"..self.errorMsg.."|r", r=1, g=0.3, b=0.3 })
    end

    if #self.plan == 0 then
        if not self.errorMsg then
            table.insert(lines, { text="  Set a target skill level below.", r=0.6, g=0.6, b=0.6 })
        end
        return lines
    end

    local C = SmartCraft.Constants.DIFF_COLOR

    for _, step in ipairs(self.plan) do
        if step.isTrainerStep then
            local cost = step.recipe.trainerCost or 0
            local costStr = cost > 0 and string.format(" (%dg %ds %dc)",
                math.floor(cost/10000),
                math.floor((cost%10000)/100),
                cost%100) or ""
            table.insert(lines, {
                text = string.format("  sk.%d  [LEARN] %s%s", step.fromSkill, step.recipe.name, costStr),
                r=0.5, g=0.8, b=1,
            })
        else
            local c = C[step.recipe.difficulty] or C.TRIVIAL
            local text = string.format(
                "  %s  |cffaaaaaa x%d|r  |cff888888(%d to %d)|r",
                step.recipe.name, step.craftsNeeded,
                step.fromSkill, step.toSkill
            )
            table.insert(lines, { text=text, r=c.r, g=c.g, b=c.b })
        end
    end

    return lines
end

function PL:GetBuyLines()
    local lines = {}

    if #self.buyList == 0 then
        if #self.plan > 0 then
            table.insert(lines, { text="  You already have all the mats for this route!", r=0.4, g=1, b=0.6 })
        end
        return lines
    end

    table.insert(lines, { text="-- Mats to Buy --", r=1, g=0.8, b=0.2 })
    for _, e in ipairs(self.buyList) do
        if e.toBuy > 0 then
            local text = string.format(
                "  Buy %dx |cffffd700%s|r  (need %d, have %d)",
                e.toBuy, e.itemName, e.need, e.have
            )
            table.insert(lines, { text=text, r=0.9, g=0.9, b=0.9 })
        else
            local text = string.format("  [done] %s (%d / %d)", e.itemName, e.have, e.need)
            table.insert(lines, { text=text, r=0.4, g=0.9, b=0.4 })
        end
    end

    return lines
end

function PL:PrintToChat()
    if #self.plan == 0 then
        print("|cff00ff96SmartCraft Planner:|r No plan built yet.")
        return
    end
    print(string.format("|cff00ff96SmartCraft Planner:|r Route to skill %d:", self.targetSkill))
    for _, step in ipairs(self.plan) do
        print(string.format("  %d to %d: %dx %s", step.fromSkill, step.toSkill, step.craftsNeeded, step.recipe.name))
    end
    if #self.buyList > 0 then
        print("|cff00ff96Shopping:|r")
        for _, e in ipairs(self.buyList) do
            if e.toBuy > 0 then
                print(string.format("  |cffffd700%dx|r %s", e.toBuy, e.itemName))
            end
        end
    end
end
