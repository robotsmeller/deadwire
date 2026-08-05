-- Deadwire LootDistribution: Add bells to loot tables
-- Server: runs via OnPreDistributionMerge (fires once at game start)

require "Deadwire/Config"

local function getSpawnChance()
    local rate = DeadwireConfig.getSandbox("BellSpawnRate", 3)
    -- enum: 1=Rare, 2=Moderate, 3=Common, 4=Abundant
    local chances = { [1] = 2, [2] = 6, [3] = 12, [4] = 20 }
    return chances[rate] or 12
end

local function preDistributionMerge()
    if not isServer() then return end
    if not DeadwireConfig.getSandbox("EnableMod", true) then return end

    local chance = getSpawnChance()

    -- Bell loot: general utility/farm locations
    -- Names verified against vanilla ProceduralDistributions.lua on 42.20
    local bellDists = {
        "FarmerTools",
        "BarnTools",
        "ToolStoreTools",
        "GardenStoreTools",
        "SchoolLockers",
        "OfficeDeskHome",
        "ChurchStorageMisc",
    }

    local bellCount = 0
    for _, distName in ipairs(bellDists) do
        if ProceduralDistributions.list[distName] then
            table.insert(ProceduralDistributions.list[distName].items, "Base.Bell")
            table.insert(ProceduralDistributions.list[distName].items, chance)
            bellCount = bellCount + 1
        end
    end

    -- Issue #12: ReinforcedTripLineKit in metalworking locations
    -- Names verified against vanilla ProceduralDistributions.lua on 42.20
    local kitDists = {
        "MetalShopTools",
        "MetalWorkerTools",
        "WeldingWorkshopMetal",
        "GarageMetalwork",
    }

    local kitCount = 0
    for _, distName in ipairs(kitDists) do
        if ProceduralDistributions.list[distName] then
            table.insert(ProceduralDistributions.list[distName].items, "Base.Deadwire_ReinforcedTripLineKit")
            table.insert(ProceduralDistributions.list[distName].items, chance)
            kitCount = kitCount + 1
        end
    end

    DeadwireConfig.log("LootDistribution: bells→" .. bellCount .. " tables, kits→" .. kitCount .. " tables (chance=" .. chance .. ")")
end

Events.OnPreDistributionMerge.Add(preDistributionMerge)
DeadwireConfig.log("LootDistribution initialized (server)")
