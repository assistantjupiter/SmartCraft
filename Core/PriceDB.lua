-- PriceDB.lua
-- Multi-source price lookup for items.
--
-- Sources (in priority order):
--   1. AH — TSM API (if TSM is loaded)
--   2. AH — Auctionator API (if Auctionator is loaded)
--   3. Vendor sell price — GetItemInfo field 11 (what vendors pay YOU)
--   4. Build cost — sum of reagent vendor prices × qty (for craftable items)
--   5. Disenchant — static quality/ilvl estimate table
--
-- Note: "AH buy price" (what you pay) is not exposed by WoW natively.
-- TSM and Auctionator each provide their own market value estimates.
-- We query both and prefer TSM if available.

SmartCraft.PriceDB = {}
local PDB = SmartCraft.PriceDB

-- ----------------------------------------------------------------
-- AH price — TSM integration
-- TSM_API.GetCustomPriceValue(priceSource, itemString) → copper or nil
-- ----------------------------------------------------------------
function PDB:GetTSMPrice(itemID)
    if not TSM_API then return nil end
    local itemString = "i:" .. itemID
    -- Try several TSM price sources in preference order
    local sources = { "DBRegionMarketAvg", "DBMarket", "DBMinBuyout", "Crafting" }
    for _, src in ipairs(sources) do
        local ok, val = pcall(TSM_API.GetCustomPriceValue, src, itemString)
        if ok and val and val > 0 then
            return val
        end
    end
    return nil
end

-- ----------------------------------------------------------------
-- AH price — Auctionator integration
-- Auctionator.API.v1.GetAuctionPriceByItemID(addonName, itemID) → copper or nil
-- ----------------------------------------------------------------
function PDB:GetAuctionatorPrice(itemID)
    if not Auctionator or not Auctionator.API then return nil end
    local v1 = Auctionator.API.v1
    if not v1 or not v1.GetAuctionPriceByItemID then return nil end
    local ok, val = pcall(v1.GetAuctionPriceByItemID, "SmartCraft", itemID)
    if ok and val and val > 0 then return val end
    return nil
end

-- ----------------------------------------------------------------
-- Vendor sell price (what a vendor pays YOU for this item)
-- GetItemInfo returns: name,link,quality,ilvl,reqLvl,type,subtype,
--                      stackCount,equipLoc,texture,vendorPrice
-- ----------------------------------------------------------------
function PDB:GetVendorSellPrice(itemID)
    local _, _, _, _, _, _, _, _, _, _, vendorPrice = GetItemInfo(itemID)
    if vendorPrice and vendorPrice > 0 then return vendorPrice end
    return nil
end

-- ----------------------------------------------------------------
-- Build cost — sum of (reagent vendorPrice × qty)
-- Useful for knowing the raw mat cost when farming vs buying.
-- recipeEntry = { reagents = {itemID → count} }
-- ----------------------------------------------------------------
function PDB:GetBuildCost(recipeEntry)
    if not recipeEntry or not recipeEntry.reagents then return nil end
    local total = 0
    local allKnown = true
    for itemID, count in pairs(recipeEntry.reagents) do
        local p = self:GetVendorSellPrice(itemID)
        -- vendor sell is what YOU get; vendor buy is typically 4× that
        -- (WoW's rule of thumb: buy ≈ 4× sell for crafting mats)
        -- This is an estimate only.
        if p then
            total = total + (p * 4 * count)
        else
            allKnown = false
        end
    end
    if total == 0 then return nil end
    return total, allKnown
end

-- ----------------------------------------------------------------
-- Disenchant value estimate
-- WoW Classic DE values by item quality and item level (static table).
-- Values in copper — rough averages, not exact.
-- ----------------------------------------------------------------
local DE_TABLE = {
    -- [quality] = { [ilvl_min] = { dust, shards, essences, essenceChance } }
    -- Quality 2 = Uncommon (green), 3 = Rare (blue), 4 = Epic (purple)
    -- We just return an estimated gold value for simplicity.
    [2] = {  -- Uncommon (green) → Strange Dust / Lesser Magic Essence
        { minIlvl=0,   maxIlvl=15,  value=2*100   },  -- ~2s
        { minIlvl=16,  maxIlvl=20,  value=5*100   },  -- ~5s
        { minIlvl=21,  maxIlvl=25,  value=8*100   },
        { minIlvl=26,  maxIlvl=30,  value=12*100  },
        { minIlvl=31,  maxIlvl=35,  value=18*100  },
        { minIlvl=36,  maxIlvl=40,  value=25*100  },
        { minIlvl=41,  maxIlvl=45,  value=35*100  },
        { minIlvl=46,  maxIlvl=50,  value=50*100  },
        { minIlvl=51,  maxIlvl=55,  value=70*100  },
        { minIlvl=56,  maxIlvl=60,  value=100*100 },
    },
    [3] = {  -- Rare (blue) → Soul Dust / Greater Essences / Small Radiant Shard
        { minIlvl=0,   maxIlvl=25,  value=40*100  },
        { minIlvl=26,  maxIlvl=35,  value=80*100  },
        { minIlvl=36,  maxIlvl=45,  value=150*100 },
        { minIlvl=46,  maxIlvl=55,  value=250*100 },
        { minIlvl=56,  maxIlvl=60,  value=400*100 },
    },
    [4] = {  -- Epic (purple) → Large Radiant Shard / Nexus Crystal
        { minIlvl=0,   maxIlvl=55,  value=800*100  },
        { minIlvl=56,  maxIlvl=60,  value=2000*100 },
    },
}

function PDB:GetDisenchantValue(itemID)
    local _, _, quality, ilvl = GetItemInfo(itemID)
    if not quality or not ilvl then return nil end
    if quality < 2 or quality > 4 then return nil end  -- only green/blue/epic

    local tiers = DE_TABLE[quality]
    if not tiers then return nil end

    for _, tier in ipairs(tiers) do
        if ilvl >= tier.minIlvl and ilvl <= tier.maxIlvl then
            return tier.value
        end
    end
    return nil
end

-- ----------------------------------------------------------------
-- Master lookup: returns a table of all available prices for an item
-- {
--   ah      = copper or nil,   ahSource = "TSM" or "Auctionator"
--   vendor  = copper or nil,   (sell price — what vendor pays you)
--   de      = copper or nil,   (estimated disenchant value)
--   build   = copper or nil,   (estimated raw mat cost)
-- }
-- ----------------------------------------------------------------
function PDB:Get(itemID, recipeEntry)
    local result = {}

    -- AH
    local ah = self:GetTSMPrice(itemID)
    if ah then
        result.ah       = ah
        result.ahSource = "TSM"
    else
        ah = self:GetAuctionatorPrice(itemID)
        if ah then
            result.ah       = ah
            result.ahSource = "Auctionator"
        end
    end

    -- Vendor sell
    result.vendor = self:GetVendorSellPrice(itemID)

    -- DE
    result.de = self:GetDisenchantValue(itemID)

    -- Build cost (only if recipe provided)
    if recipeEntry then
        result.build = self:GetBuildCost(recipeEntry)
    end

    return result
end

-- ----------------------------------------------------------------
-- Format a price row for display
-- Returns a string like: "AH: 2g 50s  Vendor: 30s  DE: 1g"
-- ----------------------------------------------------------------
function PDB:FormatPrices(prices, short)
    if not prices then return "" end
    local parts = {}

    local function fmt(copper)
        if not copper then return nil end
        local g = math.floor(copper / 10000)
        local s = math.floor((copper % 10000) / 100)
        local c = copper % 100
        local out = {}
        if g > 0 then table.insert(out, string.format("|cffffd700%dg|r", g)) end
        if s > 0 then table.insert(out, string.format("|cffaaaaaa%ds|r", s)) end
        if c > 0 or #out == 0 then table.insert(out, string.format("|cffb87333%dc|r", c)) end
        return table.concat(out, " ")
    end

    if prices.ah then
        local src = short and "AH" or (prices.ahSource or "AH")
        table.insert(parts, src .. ": " .. (fmt(prices.ah) or "?"))
    end
    if prices.vendor then
        table.insert(parts, "Sell: " .. (fmt(prices.vendor) or "?"))
    end
    if prices.de then
        table.insert(parts, "DE~: " .. (fmt(prices.de) or "?"))
    end
    if prices.build then
        table.insert(parts, "Build~: " .. (fmt(prices.build) or "?"))
    end

    if #parts == 0 then return "|cff888888No price data|r" end
    return table.concat(parts, "  ")
end
