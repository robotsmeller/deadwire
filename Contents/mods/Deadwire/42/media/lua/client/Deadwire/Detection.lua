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

-----------------------------------------------------------
-- Which edge did this step cross? (#55)
--
-- A wire lies on ONE edge of its tile: north=true is the tile's north edge,
-- north=false its west edge. Until now detection fired on tile occupancy
-- alone, so walking the length of your own perimeter set off every wire in
-- it, exactly as if you had crossed them. Reinforced then knocked you flat
-- for walking beside your own fence.
--
-- An edge is shared between two tiles, and the convention that makes the
-- arithmetic honest is that the edge belongs to the tile on its far side:
-- the boundary between (x, y-1) and (x, y) is the NORTH edge of (x, y), and
-- the boundary between (x-1, y) and (x, y) is the WEST edge of (x, y). So a
-- step resolves to the edge it broke, and the wire that owns that edge is
-- the only one that fires -- whether the walker ended up on the wire's tile
-- or on the one next door.
--
-- Diagonal steps clip a corner and are credited to both components. That is
-- deliberately the generous reading: a wire you can sidestep by approaching
-- it diagonally would be a worse bug than the one being fixed.
local function crossedEdges(fromX, fromY, toX, toY)
    local edges = {}
    local dx, dy = toX - fromX, toY - fromY

    -- Anything bigger than one tile is a teleport, a vehicle exit or a
    -- dropped frame, not a step over a wire. Crediting it to an edge would
    -- be inventing a crossing that never happened.
    if math.abs(dx) > 1 or math.abs(dy) > 1 then return edges end

    if dy ~= 0 then
        local edgeY = (dy > 0) and toY or fromY
        table.insert(edges, { x = fromX, y = edgeY, north = true })
        if dx ~= 0 then
            table.insert(edges, { x = toX, y = edgeY, north = true })
        end
    end

    if dx ~= 0 then
        local edgeX = (dx > 0) and toX or fromX
        table.insert(edges, { x = edgeX, y = fromY, north = false })
        if dy ~= 0 then
            table.insert(edges, { x = edgeX, y = toY, north = false })
        end
    end

    return edges
end

-- The wire whose own edge this step broke, or nil. A wire with no recorded
-- facing (saved before #55, and not yet recovered off its IsoObject) matches
-- any edge on its tile: the old occupancy behaviour, kept on purpose so that
-- an old save degrades to the previous bug rather than to a dead perimeter.
local function findCrossedWire(fromX, fromY, toX, toY, z)
    for _, edge in ipairs(crossedEdges(fromX, fromY, toX, toY)) do
        local wire = DeadwireNetwork.getTile(edge.x, edge.y, z)
        if wire and wire.active
            and (wire.north == nil or wire.north == edge.north)
        then
            return wire, edge
        end
    end
    return nil
end

DeadwireDetection.crossedEdges = crossedEdges
DeadwireDetection.findCrossedWire = findCrossedWire

local function detectEntity(entity, isZombie)
    if not DeadwireConfig.getSandbox("EnableMod", true) then return end

    local affectsKey = isZombie and "WireAffectsZombies" or "WireAffectsPlayers"
    if not DeadwireConfig.getSandbox(affectsKey, true) then return end

    if isZombie and not entity:isAlive() then return end

    local entitySq = entity:getSquare()
    if not entitySq then return end

    local ex, ey, z = entitySq:getX(), entitySq:getY(), entitySq:getZ()

    -- Where the entity was on the previous tile it occupied. Tracked on every
    -- update regardless of whether a wire is anywhere near, because the step
    -- that matters is the one INTO the wire, and by the time we know a wire is
    -- involved the previous tile is the only thing that can tell us which way
    -- the walker was going.
    local data = entity:getModData()
    local lastX, lastY, lastZ = data["dw_lastX"], data["dw_lastY"], data["dw_lastZ"]
    local moved = (lastX ~= ex or lastY ~= ey or lastZ ~= z)
    if not moved then return end

    data["dw_lastX"], data["dw_lastY"], data["dw_lastZ"] = ex, ey, z

    -- First sighting of this entity, or it changed floor. Neither is a step
    -- across a wire on this level.
    if lastX == nil or lastY == nil or lastZ ~= z then return end

    local wire, edge = findCrossedWire(lastX, lastY, ex, ey, z)
    if not wire then return end

    local x, y = wire.x, wire.y
    local sq = getCell():getGridSquare(x, y, z)
    if not sq then return end

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

    -- De-duplicate: prevent the same entity from firing the same wire twice in
    -- a tick cycle (MP latency means the cooldown may not have reached this
    -- client yet). Real seconds, not game hours.
    --
    -- Two fixed keys, not one per tile. This used to write "dw_t_<x,y,z>" for
    -- every tile an entity ever crossed and never remove any of them, and
    -- modData persists with the entity, so a long-lived zombie patrolling a
    -- wired perimeter accumulated a key per tile for the life of the save
    -- (#41). Entities from an older save still carry those orphans; they are
    -- inert and not worth a migration pass.
    local key = DeadwireNetwork.tileKey(x, y, z)
    local now = os.time()  -- real-time seconds (not game-hours)
    local DEDUP_SECONDS = 1  -- 1 real second
    if data["dw_lastTile"] == key
        and data["dw_lastTime"]
        and (now - data["dw_lastTime"]) < DEDUP_SECONDS then
        return
    end
    data["dw_lastTile"] = key
    data["dw_lastTime"] = now

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
