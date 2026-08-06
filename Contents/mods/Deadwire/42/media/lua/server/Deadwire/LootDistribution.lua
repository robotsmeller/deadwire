-- Deadwire LootDistribution: Add bells and kits to loot tables
-- Authoritative side (SP + dedicated server), via OnPreDistributionMerge,
-- which fires once per load before distributions merge.

require "Deadwire/Config"

local function getSpawnChance()
    local rate = DeadwireConfig.getSandbox("BellSpawnRate", 3)
    -- enum: 1=Rare, 2=Moderate, 3=Common, 4=Abundant
    local chances = { [1] = 2, [2] = 6, [3] = 12, [4] = 20 }
    return chances[rate] or 12
end

-- Append `item` at `chance` to each named distribution, returning how many
-- took it.
--
-- A missing name is logged loudly rather than skipped in silence. Every bug
-- this file has had was a name that resolved to nil and produced an absent
-- feature with a clean log; a warning here is what makes the next one visible
-- the first time the world generates.
local function addToDistributions(distNames, item, chance)
    local count = 0
    for _, distName in ipairs(distNames) do
        local dist = ProceduralDistributions.list[distName]
        if dist and dist.items then
            table.insert(dist.items, item)
            table.insert(dist.items, chance)
            count = count + 1
        else
            DeadwireConfig.log("LootDistribution: WARNING no distribution '"
                .. distName .. "' -- " .. item .. " will not spawn there")
        end
    end
    return count
end

local function preDistributionMerge()
    -- Authoritative side only. `isServer()` is true ONLY on a dedicated server:
    -- in single-player isServer() and isClient() are BOTH false, so guarding on
    -- `not isServer()` returned immediately and no Deadwire loot has ever been
    -- injected in SP. Guard on isClient() instead -- false in SP and on the
    -- dedicated server, true only on a real MP client. Same idiom as
    -- TriggerHandlers.lua:47.
    if isClient() then return end
    if not DeadwireConfig.getSandbox("EnableMod", true) then return end

    local chance = getSpawnChance()

    -- Bell loot: general utility/farm locations.
    -- ChurchStorageMisc used to be in this list and does not exist -- 42.20 has
    -- no church distribution at all. It was added as a "verified" replacement
    -- for the equally nonexistent ChurchMisc and silently spawned nothing.
    -- Every name below is checked by scripts/verify_names.py against the
    -- installed game; run that rather than adding a name by eye.
    local bellDists = {
        "FarmerTools",
        "BarnTools",
        "ToolStoreTools",
        "GardenStoreTools",
        "SchoolLockers",
        "OfficeDeskHome",
        "JanitorMisc",
    }

    -- Issue #12: ReinforcedTripLineKit in metalworking locations
    local kitDists = {
        "MetalShopTools",
        "MetalWorkerTools",
        "WeldingWorkshopMetal",
        "GarageMetalwork",
    }

    local bellCount = addToDistributions(bellDists, "Base.Bell", chance)
    local kitCount  = addToDistributions(kitDists,
        "Base.Deadwire_ReinforcedTripLineKit", chance)

    DeadwireConfig.log("LootDistribution: bells→" .. bellCount .. " tables, kits→" .. kitCount .. " tables (chance=" .. chance .. ")")
end

Events.OnPreDistributionMerge.Add(preDistributionMerge)
DeadwireConfig.log("LootDistribution initialized (server)")
