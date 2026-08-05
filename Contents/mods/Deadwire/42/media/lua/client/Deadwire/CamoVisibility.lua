-- Deadwire CamoVisibility: Per-client alpha control for camouflaged wires
-- Client: checks the local player's scavenging level and updates IsoThumpable alpha.
--
-- Runs on OnTick with a 60-tick throttle (~1s at 60fps).
-- Visual-only: server state is unchanged. Each client sees wires at a
-- different alpha based on their own skill level + distance.
--
-- The skill is PlantScavenging (shown in-game as "Foraging"). Perks.Foraging
-- is NOT a real enum member: reading it yields nil, getPerkLevel(nil) returns
-- 0, and every player is permanently at level 0, so camouflaged wires were
-- invisible to absolutely everyone. Verified against 42.20 (Issue #17).
--
-- Detection scaling (all thresholds configurable via SandboxVars):
--   level 0-2  → alpha 0.0  (invisible — trips it blind)
--   level 3-4  → alpha 0.15 (faint shimmer, close range only)
--   level 5-6  → alpha 0.4  (semi-visible, moderate range)
--   level 7+   → alpha 0.8  (clear + orange outline)

require "Deadwire/Config"
require "Deadwire/WireNetwork"

local TICK_INTERVAL = 60   -- update once per second at 60fps
local tickCounter   = 0

-----------------------------------------------------------
-- Compute alpha + outline flag for a single wire
-----------------------------------------------------------

local function getVisibility(skillLevel, dist, isOwner, adminBypass)
    -- Owner always sees their own wires (configurable)
    if isOwner and DeadwireConfig.getSandbox("CamoVisibleToOwner", true) then
        return 1.0, false
    end

    -- Admins bypass camo entirely (configurable)
    if adminBypass and DeadwireConfig.getSandbox("AdminBypassCamo", true) then
        return 1.0, false
    end

    -- Skill-based visibility (thresholds + detection ranges)
    local fullLevel = DeadwireConfig.getSandbox("CamoDetectLevelFull", 7)
    local midLevel  = DeadwireConfig.getSandbox("CamoDetectLevelMid",  5)
    local lowLevel  = DeadwireConfig.getSandbox("CamoDetectLevelLow",  3)
    local fullRange = DeadwireConfig.getSandbox("CamoDetectRangeFull", 15)
    local midRange  = DeadwireConfig.getSandbox("CamoDetectRangeMid",   8)
    local lowRange  = DeadwireConfig.getSandbox("CamoDetectRangeLow",   3)

    if skillLevel >= fullLevel and dist <= fullRange then
        return 0.8, true   -- clear + orange outline
    end
    if skillLevel >= midLevel and dist <= midRange then
        return 0.4, false  -- semi-visible
    end
    if skillLevel >= lowLevel and dist <= lowRange then
        return 0.15, false -- faint shimmer
    end
    return 0.0, false      -- invisible
end

-----------------------------------------------------------
-- OnTick: throttled alpha update for all camouflaged tiles
-----------------------------------------------------------

local function onTick()
    tickCounter = tickCounter + 1
    if tickCounter < TICK_INTERVAL then return end
    tickCounter = 0

    if not DeadwireConfig.getSandbox("EnableCamouflage", true) then return end

    local player = getPlayer()
    if not player then return end

    local username   = player:getUsername() or ""
    local skillLevel = player:getPerkLevel(Perks.PlantScavenging)
    local adminBypass = isAdmin() or false

    local px = math.floor(player:getX())
    local py = math.floor(player:getY())
    local pz = math.floor(player:getZ())

    local MAX_RANGE = 20   -- skip tiles further than this (Chebyshev distance)

    local camoTiles = DeadwireNetwork.getCamoTiles()
    for key, wire in pairs(camoTiles) do
        if wire.z == pz then
            local dx = math.abs(wire.x - px)
            local dy = math.abs(wire.y - py)
            if dx <= MAX_RANGE and dy <= MAX_RANGE then
                local obj = wire.isoObject
                if obj then
                    local dist     = math.sqrt(dx * dx + dy * dy)
                    local isOwner  = (wire.ownerId == username)
                    local alpha, outline = getVisibility(
                        skillLevel, dist, isOwner, adminBypass)

                    obj:setAlphaAndTarget(alpha)
                    if outline then
                        obj:setOutlineHighlight(true)
                        obj:setOutlineHighlightCol(1.0, 0.5, 0.0, 0.5)
                    else
                        obj:setOutlineHighlight(false)
                    end
                end
            end
        end
    end
end

Events.OnTick.Add(onTick)
DeadwireConfig.log("CamoVisibility initialized (client)")
