-- Deadwire Detection: OnZombieUpdate + OnPlayerUpdate tile detection
-- Client: runs on client (SP + MP client). Same pattern as Spear Traps.
--
-- OnZombieUpdate/OnPlayerUpdate are client-context events. PZ syncs zombie
-- state changes (stagger, knockdown, kill) to the server automatically.
-- Wire state changes (break, durability) go through sendClientCommand.
--
-- Wire type handlers registered via registerZombieHandler / registerPlayerHandler.
-- Sprint 3 adds TripLineHandler, ReinforcedHandler, etc. Until then, fallback
-- handler makes noise for testing.

require "Deadwire/Config"
require "Deadwire/WireNetwork"

DeadwireDetection = DeadwireDetection or {}

DeadwireDetection.zombieHandlers = {}
DeadwireDetection.playerHandlers = {}

-----------------------------------------------------------
-- Handler Registration (called by handler modules)
-----------------------------------------------------------

function DeadwireDetection.registerZombieHandler(wireType, handler)
    DeadwireDetection.zombieHandlers[wireType] = handler
    DeadwireConfig.debugLog("Registered zombie handler: " .. wireType)
end

function DeadwireDetection.registerPlayerHandler(wireType, handler)
    DeadwireDetection.playerHandlers[wireType] = handler
    DeadwireConfig.debugLog("Registered player handler: " .. wireType)
end

-----------------------------------------------------------
-- Shared Detection Logic (DRY: one path for both entity types)
-----------------------------------------------------------

local function detectEntity(entity, isZombie)
    if not DeadwireConfig.getSandbox("EnableMod", true) then return end

    local affectsKey = isZombie and "WireAffectsZombies" or "WireAffectsPlayers"
    if not DeadwireConfig.getSandbox(affectsKey, true) then return end

    if isZombie and not entity:isAlive() then return end

    local sq = entity:getSquare()
    if not sq then return end

    local x, y, z = sq:getX(), sq:getY(), sq:getZ()
    local wire = DeadwireNetwork.getTile(x, y, z)
    if not wire or not wire.active then return end

    if DeadwireNetwork.isOnCooldown(x, y, z) then return end

    local defaults = DeadwireConfig.WireDefaults[wire.wireType]
    if defaults and not DeadwireConfig.isTierEnabled(defaults.tier) then return end

    -- Player-only: owner immunity
    if not isZombie and DeadwireConfig.getSandbox("WireOwnerImmunity", false) then
        local username = entity:getUsername()
        if username and wire.ownerId == username then return end
    end

    -- Player-only: faction immunity. FriendlyFireWires defaults to true, meaning
    -- a faction mate's wire DOES trigger; turning it off makes the perimeter safe
    -- for the group. The option shipped in sandbox-options.txt and was read by
    -- nothing at all until now, so it was a settings-screen knob that did nothing.
    --
    -- isInSameFaction(IsoPlayer, String) is the overload that matters: the wire
    -- stores its owner as a username, and that owner may be offline with no
    -- IsoPlayer to compare against.
    if not isZombie and not DeadwireConfig.getSandbox("FriendlyFireWires", true) then
        if wire.ownerId and Faction.isInSameFaction(entity, wire.ownerId) then
            DeadwireConfig.debugLog("Faction mate passed wire at " .. x .. "," .. y)
            return
        end
    end

    -- De-duplicate: prevent same entity from firing multiple triggers
    -- within the same tick cycle (MP latency means cooldown may not be
    -- set on client yet). Uses timestamp with 1-second expiry window.
    local key = DeadwireNetwork.tileKey(x, y, z)
    local data = entity:getModData()
    local now = os.time()  -- real-time seconds (not game-hours)
    local lastTrigger = data["dw_t_" .. key]
    local DEDUP_SECONDS = 1  -- 1 real second
    if lastTrigger and (now - lastTrigger) < DEDUP_SECONDS then return end
    data["dw_t_" .. key] = now

    local label = isZombie and "Zombie" or "Player"
    DeadwireConfig.debugLog(label .. " triggered wire at " .. key .. " type=" .. wire.wireType)

    -- Dispatch to registered handler
    local handlers = isZombie and DeadwireDetection.zombieHandlers or DeadwireDetection.playerHandlers
    local handler = handlers[wire.wireType]
    if handler then
        handler(entity, sq, wire)
    else
        -- Fallback: make noise so detection is verifiable in testing.
        -- Client-side sound: attracts nearby zombies + audible to player.
        local radius = defaults and defaults.soundRadius or 25
        local volume = defaults and defaults.soundVolume or 60
        getWorldSoundManager():addSound(nil, x, y, z, radius, volume, false)

        -- TODO Sprint 3: sendClientCommand for server-side wire state changes
        -- (break single-use wires, degrade durability, log triggers)
    end
end

-----------------------------------------------------------
-- Event Callbacks
-----------------------------------------------------------

local function onZombieUpdate(zombie)
    detectEntity(zombie, true)
end

local function onPlayerUpdate(player)
    detectEntity(player, false)
end

-----------------------------------------------------------
-- Event Registration
-----------------------------------------------------------

Events.OnZombieUpdate.Add(onZombieUpdate)
Events.OnPlayerUpdate.Add(onPlayerUpdate)
DeadwireConfig.debugLog("Detection system initialized (client)")
