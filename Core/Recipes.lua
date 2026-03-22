-- Recipes.lua
-- Reads profession window via legacy TBC Classic API.
-- Populates SmartCraft.Recipes.list (sorted high→low skillReq).

SmartCraft.Recipes = {}
local R = SmartCraft.Recipes

R.list       = {}
R.skillName  = ""
R.skillLevel = 0
R.maxSkill   = 0

-- GetTradeSkillLine() in vanilla Classic 1.x only returns the skill name.
-- Skill level must be fetched via GetProfessions() + GetProfessionInfo().
function R:FetchSkillLevel(skillName)
    if not GetProfessions then return 0, 0 end
    -- GetProfessions() returns up to 6 slot indices (prof1, prof2, archaeology, fishing, cooking, firstaid)
    local slots = { GetProfessions() }
    for _, slot in ipairs(slots) do
        if slot then
            local name, _, rank, maxRank = GetProfessionInfo(slot)
            if name and name:lower() == (skillName or ""):lower() then
                return rank or 0, maxRank or 0
            end
        end
    end
    -- Fallback: try to find any partial match
    for _, slot in ipairs(slots) do
        if slot then
            local name, _, rank, maxRank = GetProfessionInfo(slot)
            if name and skillName and name:find(skillName) then
                return rank or 0, maxRank or 0
            end
        end
    end
    return 0, 0
end

function R:Scan()
    self.list = {}

    local skillName = GetTradeSkillLine()
    self.skillName = skillName or "Unknown"

    -- Fetch real skill level via GetProfessions/GetProfessionInfo
    local skillLevel, maxSkill = self:FetchSkillLevel(skillName)
    self.skillLevel = skillLevel
    self.maxSkill   = maxSkill

    local num = GetNumTradeSkills()
    if not num or num == 0 then return end

    -- Collect all reagent IDs for prefetch
    local allReagentIDs = {}

    for i = 1, num do
        local name, skillType = GetTradeSkillInfo(i)

        if name and skillType and skillType ~= "header" then
            local minMade = GetTradeSkillNumMade(i) or 1
            local numR    = GetTradeSkillNumReagents(i) or 0
            local reagents = {}

            for r = 1, numR do
                local _, _, reagentCount = GetTradeSkillReagentInfo(i, r)
                local link = GetTradeSkillReagentItemLink(i, r)
                local itemID = SmartCraft.Inventory:LinkToID(link)
                if itemID and reagentCount and reagentCount > 0 then
                    reagents[itemID] = (reagents[itemID] or 0) + reagentCount
                    allReagentIDs[itemID] = true
                end
            end

            local difficulty = self:NormalizeDifficulty(skillType)
            local skillReq   = self:EstimateSkillReq(difficulty, self.skillLevel)

            table.insert(self.list, {
                index      = i,
                name       = name,
                skillReq   = skillReq,
                difficulty = difficulty,
                numMade    = minMade,
                reagents   = reagents,
                reserved   = false,
            })
        end
    end

    -- Sort high → low so reservation phase works correctly
    table.sort(self.list, function(a, b)
        return a.skillReq > b.skillReq
    end)

    -- Kick off background name fetch for all reagents
    local ids = {}
    for id in pairs(allReagentIDs) do table.insert(ids, id) end
    SmartCraft.ItemCache:Prefetch(ids)
end

function R:NormalizeDifficulty(t)
    t = string.lower(t or "")
    if     t == "optimal" then return "OPTIMAL"
    elseif t == "medium"  then return "MEDIUM"
    elseif t == "easy"    then return "EASY"
    else                       return "TRIVIAL"
    end
end

-- Approximate skill requirement based on difficulty bracket.
-- TBC color thresholds (rough): orange ≈ current+5, yellow ≈ current-10,
-- green ≈ current-30, grey ≈ current-60
function R:EstimateSkillReq(difficulty, current)
    if     difficulty == "OPTIMAL" then return current + 5
    elseif difficulty == "MEDIUM"  then return current - 10
    elseif difficulty == "EASY"    then return current - 30
    else                                return current - 60
    end
end

-- Return recipes filtered by difficulty (for planner)
function R:GetByDifficulty(difficulties)
    local out = {}
    for _, recipe in ipairs(self.list) do
        for _, d in ipairs(difficulties) do
            if recipe.difficulty == d then
                table.insert(out, recipe)
                break
            end
        end
    end
    return out
end
