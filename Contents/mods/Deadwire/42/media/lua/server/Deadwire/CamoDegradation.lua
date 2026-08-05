-- Deadwire CamoDegradation: Server-side rain-based camouflage durability loss
-- Server: EveryTenMinutes — checks rain strength and degrades all camouflaged wires.
--
-- Trigger-based degradation (each wire trigger) is handled in
-- ServerCommands.lua WireTriggered handler — not here.
--
-- Degradation model:
--   - Rain intensity 0.0-0.8: degrade = floor(baseRate * rainIntensity)
--   - Rain intensity 0.8+:    degrade = floor(baseRate * stormMult)
--   - When durability hits 0: camo removed, WireCamouflaged broadcast to all clients
--
-- The old implementation called Climate.GetInstance():getRainStrength(). No part
-- of that exists in 42.20: there is no `Climate` global, and no getRainStrength
-- on anything. Both guards failed silently and the function always returned 0, so
-- camouflage never degraded from weather at all. Verified against 42.20 (Issue #18).
--
-- The real API is getClimateManager():getRainIntensity(), returning a float.
-- Range is 0.0-1.0: ClimateManager's sibling intensity getters are used that way
-- throughout vanilla (forageSystem rounds getPrecipitationIntensity() to one
-- decimal and multiplies chances by it; Bobber.lua tests getFogIntensity() >= 0.4),
-- which is what STORM_THRESHOLD below assumes.
-- getPrecipitationIntensity() is the near-equivalent that also counts snow.

require "Deadwire/Config"
require "Deadwire/WireNetwork"

-----------------------------------------------------------
-- Get current rain intensity (0.0 = dry, 1.0 = heaviest)
-----------------------------------------------------------

local function getRainIntensity()
    local climate = getClimateManager()
    if not climate then return 0 end
    return climate:getRainIntensity() or 0
end

-----------------------------------------------------------
-- EveryTenMinutes: apply rain degradation to all camo wires
-----------------------------------------------------------

local function onEveryTenMinutes()
    if not DeadwireConfig.getSandbox("EnableCamouflage", true) then return end

    local rainIntensity = getRainIntensity()
    if rainIntensity <= 0 then return end

    local baseRate    = DeadwireConfig.getSandbox("CamoRainDegradeRate",  5)
    local stormMult   = DeadwireConfig.getSandbox("CamoStormMultiplier",  2.0)
    local STORM_THRESHOLD = 0.8

    local effective
    if rainIntensity >= STORM_THRESHOLD then
        effective = math.floor(baseRate * stormMult)
    else
        effective = math.floor(baseRate * rainIntensity)
    end

    if effective <= 0 then return end

    -- Collect expired tiles separately — avoids modifying table mid-iteration
    local toRemove = {}
    local camoTiles = DeadwireNetwork.getCamoTiles()

    for key, wire in pairs(camoTiles) do
        local newDur = (wire.camoDurability or 0) - effective
        if newDur <= 0 then
            table.insert(toRemove, { x = wire.x, y = wire.y, z = wire.z })
        else
            wire.camoDurability = newDur
        end
    end

    for _, pos in ipairs(toRemove) do
        DeadwireNetwork.setCamouflaged(pos.x, pos.y, pos.z, false, 0)
        sendServerCommand(DeadwireConfig.MODULE, "WireCamouflaged", {
            x          = pos.x,
            y          = pos.y,
            z          = pos.z,
            camouflaged = false,
            durability  = 0,
        })
        DeadwireConfig.debugLog("CamoDegradation: rain expired camo at "
            .. pos.x .. "," .. pos.y .. "," .. pos.z)
    end

    if #toRemove > 0 then
        DeadwireConfig.log("CamoDegradation: " .. #toRemove
            .. " wire(s) lost camouflage from rain (intensity=" .. rainIntensity .. ")")
    end
end

Events.EveryTenMinutes.Add(onEveryTenMinutes)
DeadwireConfig.log("CamoDegradation initialized (server)")
