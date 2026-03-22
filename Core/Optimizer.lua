-- Optimizer.lua
-- Scores every recipe by 4 strategies and ranks them.
--
-- STRATEGIES
--   cheapest  → lowest build cost per expected skill-up
--   ah        → highest (AH sell price − build cost) per craft
--   de        → highest (Disenchant value − build cost) per craft
--   deprofit  → same as de but ONLY shows recipes where DE − build ≥ 0
--                (you actually make money or break even by crafting + DEing)
--
-- SKILL-UP PROBABILITY weights (approximate):
--   OPTIMAL (orange)  = 1.00 skill-up per craft
--   MEDIUM  (yellow)  = 0.50
--   EASY    (green)   = 0.25
--   TRIVIAL (grey)    = 0.0  (excluded)
--
-- BUILD COST SOURCE PRIORITY:
--   1. Sum of AH prices for reagents (if TSM/Auctionator available)
--   2. Sum of vendor sell × 4 heuristic
--   3. nil (can't score)

SmartCraft.Optimizer = {}
local OPT = SmartCraft.Optimizer

OPT.strategy = "cheapest"   -- default
OPT.results  = {}           -- sorted scored entries

local SKILLUP_WEIGHT = {
    OPTIMAL = 1.00,
    MEDIUM  = 0.50,
    EASY    = 0.25,
    TRIVIAL = 0.00,
}

-- ----------------------------------------------------------------
-- Run scoring for the current strategy
-- ----------------------------------------------------------------
function OPT:Run(strategy)
    self.strategy = strategy or self.strategy
    self.results  = {}

    local recipes = SmartCraft.Recipes.list
    if not recipes or #recipes == 0 then return end

    for _, recipe in ipairs(recipes) do
        local weight = SKILLUP_WEIGHT[recipe.difficulty] or 0
        if weight > 0 then
            local entry = self:ScoreRecipe(recipe, weight)
            if entry then
                table.insert(self.results, entry)
            end
        end
    end

    self:Sort()
end

-- ----------------------------------------------------------------
-- Score a single recipe
-- ----------------------------------------------------------------
function OPT:ScoreRecipe(recipe, weight)
    -- Build cost: prefer AH reagent prices, fall back to vendor heuristic
    local buildCost = self:GetReagentCost(recipe)
    if not buildCost then return nil end

    -- Output item prices (need the item link from the recipe index)
    local outputLink = GetTradeSkillItemLink and GetTradeSkillItemLink(recipe.index)
    local outputID   = outputLink and SmartCraft.Inventory:LinkToID(outputLink)

    local ahValue, deValue
    if outputID then
        local prices = SmartCraft.PriceDB:Get(outputID)
        ahValue = prices.ah
        deValue = prices.de
    end

    -- Adjust for num items made (yield > 1 multiplies output value)
    local yield = recipe.numMade or 1
    if ahValue then ahValue = ahValue * yield end
    if deValue then deValue = deValue * yield end

    local netAH = ahValue and (ahValue - buildCost) or nil
    local netDE = deValue and (deValue - buildCost) or nil

    -- Cost per expected skill-up
    local costPerSku = buildCost / weight

    return {
        recipe      = recipe,
        buildCost   = buildCost,
        ahValue     = ahValue,
        deValue     = deValue,
        netAH       = netAH,
        netDE       = netDE,
        costPerSku  = costPerSku,
        weight      = weight,
        yield       = yield,
    }
end

-- ----------------------------------------------------------------
-- Sort results according to current strategy
-- ----------------------------------------------------------------
function OPT:Sort()
    local s = self.strategy

    if s == "cheapest" then
        table.sort(self.results, function(a, b)
            return a.costPerSku < b.costPerSku
        end)

    elseif s == "ah" then
        -- Filter to entries with AH data, sort by netAH desc
        local filtered = {}
        for _, e in ipairs(self.results) do
            if e.netAH then table.insert(filtered, e) end
        end
        table.sort(filtered, function(a, b) return a.netAH > b.netAH end)
        self.results = filtered

    elseif s == "de" then
        local filtered = {}
        for _, e in ipairs(self.results) do
            if e.netDE then table.insert(filtered, e) end
        end
        table.sort(filtered, function(a, b) return a.netDE > b.netDE end)
        self.results = filtered

    elseif s == "deprofit" then
        -- Only recipes where DE value ≥ build cost (profit or break even)
        local filtered = {}
        for _, e in ipairs(self.results) do
            if e.netDE and e.netDE >= 0 then
                table.insert(filtered, e)
            end
        end
        table.sort(filtered, function(a, b) return a.netDE > b.netDE end)
        self.results = filtered
    end
end

-- ----------------------------------------------------------------
-- Get total reagent cost (AH price preferred, else vendor heuristic)
-- ----------------------------------------------------------------
function OPT:GetReagentCost(recipe)
    local total = 0
    for itemID, count in pairs(recipe.reagents) do
        local prices = SmartCraft.PriceDB:Get(itemID)
        local price
        if prices.ah then
            price = prices.ah               -- actual AH price per unit
        elseif prices.vendor then
            price = prices.vendor * 4       -- vendor sell × 4 heuristic
        end
        if not price then return nil end    -- can't score without any price
        total = total + price * count
    end
    return total > 0 and total or nil
end

-- ----------------------------------------------------------------
-- Line builder for UI
-- ----------------------------------------------------------------
function OPT:GetLines()
    local lines = {}
    local PDB   = SmartCraft.PriceDB

    if #self.results == 0 then
        local msg = {
            cheapest = "No build cost data available. Open a vendor or install TSM/Auctionator.",
            ah       = "No AH data. Install TSM or Auctionator and scan the AH.",
            de       = "No DE value data (need item quality/ilvl from GetItemInfo).",
            deprofit = "No recipes found where Disenchant value covers build cost.",
        }
        table.insert(lines, {
            text = "  " .. (msg[self.strategy] or "No results."),
            r=0.5, g=0.5, b=0.5,
        })
        return lines
    end

    local function fmt(copper)
        if not copper then return "|cff888888n/a|r" end
        local neg = copper < 0
        copper = math.abs(copper)
        local g = math.floor(copper / 10000)
        local s = math.floor((copper % 10000) / 100)
        local c = copper % 100
        local parts = {}
        if g > 0 then table.insert(parts, string.format("%dg", g)) end
        if s > 0 then table.insert(parts, string.format("%ds", s)) end
        if c > 0 or #parts == 0 then table.insert(parts, string.format("%dc", c)) end
        local str = table.concat(parts, " ")
        if neg then
            return "|cffff4444-" .. str .. "|r"
        else
            return "|cff" .. (copper > 0 and "44ff88" or "aaaaaa") .. str .. "|r"
        end
    end

    for rank, e in ipairs(self.results) do
        if rank > 20 then break end  -- cap at 20 results

        local c    = SmartCraft.Constants.DIFF_COLOR[e.recipe.difficulty]
        local diff = e.recipe.difficulty:sub(1,3)  -- OPT/MED/EAS

        -- Main recipe line
        table.insert(lines, {
            text = string.format("  #%d  [%s]  %s", rank, diff, e.recipe.name),
            r=c.r, g=c.g, b=c.b,
        })

        -- Score sub-line varies by strategy
        local sub
        if self.strategy == "cheapest" then
            sub = string.format(
                "    Build: %s  |cffaaaaaa(%s/sku)|r",
                fmt(e.buildCost), fmt(e.costPerSku)
            )
        elseif self.strategy == "ah" then
            sub = string.format(
                "    Build: %s  AH: %s  |cffffd700Net: %s|r",
                fmt(e.buildCost), fmt(e.ahValue), fmt(e.netAH)
            )
        elseif self.strategy == "de" or self.strategy == "deprofit" then
            sub = string.format(
                "    Build: %s  DE~: %s  |cffffd700Net: %s|r",
                fmt(e.buildCost), fmt(e.deValue), fmt(e.netDE)
            )
        end

        if sub then
            table.insert(lines, { text=sub, r=0.6, g=0.6, b=0.7 })
        end
    end

    return lines
end
