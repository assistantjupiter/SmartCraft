-- TrainerDB.lua
-- Scans the profession trainer window when it opens and caches all
-- learnable recipes with their required skill level.
-- The Planner merges these "future recipes" into its route so it can
-- plan paths through recipes you haven't learned yet.
--
-- WoW Classic trainer API:
--   GetNumTrainerServices()
--   GetTrainerServiceInfo(i) → name, type, isExpanded, isAvailable
--   GetTrainerServiceSkillReq(i) → skillName, reqRank
--   GetTrainerServiceCost(i) → moneyCost, talentCost, profCost
--   IsTrainerServiceAvailable(i) → bool
--
-- "type" values include: "spell", "ability", "passive", "recipe" etc.
-- We capture all services associated with the open trade skill's profession.

SmartCraft.TrainerDB = {}
local TDB = SmartCraft.TrainerDB

-- List of cached trainer recipes (persists until next trainer open)
-- Each entry: { name, reqSkill, moneyCost, isKnown }
TDB.recipes = {}
TDB.profession = ""

-- ----------------------------------------------------------------
-- Called on TRAINER_SHOW — scan and cache trainer services
-- ----------------------------------------------------------------
function TDB:Scan()
    self.recipes   = {}
    self.profession = SmartCraft.Recipes.skillName or ""

    local num = GetNumTrainerServices and GetNumTrainerServices() or 0
    if num == 0 then return end

    for i = 1, num do
        local name, trainerType, _, isAvailable = GetTrainerServiceInfo(i)
        if name and trainerType ~= "header" then
            -- GetTrainerServiceSkillReq: returns skillName, reqRank
            local skillName, reqRank = GetTrainerServiceSkillReq(i)
            -- GetTrainerServiceCost: returns moneyCost, talentCost, professionCost
            local moneyCost = GetTrainerServiceCost and GetTrainerServiceCost(i) or 0

            table.insert(self.recipes, {
                name       = name,
                reqSkill   = reqRank or 0,
                moneyCost  = moneyCost or 0,
                isAvailable = isAvailable,
            })
        end
    end

    -- Sort by required skill ascending
    table.sort(self.recipes, function(a, b)
        return a.reqSkill < b.reqSkill
    end)

    local n = #self.recipes
    if n > 0 then
        print(string.format(
            "|cff00ff96SmartCraft:|r Trainer scanned — %d recipe%s cached for Planner.",
            n, n == 1 and "" or "s"
        ))
    end
end

-- ----------------------------------------------------------------
-- Get all trainer recipes that unlock between fromSkill and toSkill
-- Returns list of { name, reqSkill, moneyCost }
-- ----------------------------------------------------------------
function TDB:GetRecipesInRange(fromSkill, toSkill)
    local out = {}
    for _, r in ipairs(self.recipes) do
        if r.reqSkill >= fromSkill and r.reqSkill <= toSkill then
            table.insert(out, r)
        end
    end
    return out
end

-- ----------------------------------------------------------------
-- Status line for UI header
-- ----------------------------------------------------------------
function TDB:StatusLine()
    local n = #self.recipes
    if n == 0 then return nil end
    return string.format("|cff88aaff Trainer: %d recipes|r", n)
end
