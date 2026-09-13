-- Deadwire ServerCommands: OnClientCommand dispatcher
-- Server: validates client requests and executes authoritative actions
--
-- All game-state mutations happen here. Clients request via sendClientCommand,
-- server validates, executes, and broadcasts results via sendServerCommand.

require "Deadwire/Config"
require "Deadwire/WireNetwork"
require "Deadwire/WireManager"

DeadwireServerCommands = DeadwireServerCommands or {}

-- Command handler table
local handlers = {}

-- A WireTriggered report is a claim, not an observation. Detection has to run
-- client-side (OnZombieUpdate is a client event), so any client can send this
-- for any coordinates and the server must re-derive the fact for itself: is
-- something actually standing on that wire right now.
--
-- What this replaces is #31. The old gate measured how far away the REPORTING
-- player was, but the reporter is whichever client's OnZombieUpdate saw the
-- zombie, and the zombie can be anywhere loaded. Trip lines therefore only
-- fired when a player was already within 3 tiles of them, which is the mod's
-- core feature not working.
--
-- 3x3 rather than the single tile: on a dedicated server the report is a tick
-- or two behind where the entity has since moved to.
local TRIGGER_SCAN_RADIUS = 1

-- Loose bound on the reporter, defence in depth only. Nothing legitimate
-- reports a wire on the far side of the loaded map. This is deliberately NOT
-- a proximity check -- proximity is what was wrong before.
local TRIGGER_SANITY_DIST = 100

-- Is a zombie or a player on the wire square or one of its 8 neighbours?
-- IsoGridSquare.getMovingObjects() is the live list, so this is the server's
-- own reading of world state rather than the client's word for it.
local function triggeringEntityNear(x, y, z)
    local cell = getCell()
    if not cell then return false end

    for dx = -TRIGGER_SCAN_RADIUS, TRIGGER_SCAN_RADIUS do
        for dy = -TRIGGER_SCAN_RADIUS, TRIGGER_SCAN_RADIUS do
            local sq = cell:getGridSquare(x + dx, y + dy, z)
            local movers = sq and sq:getMovingObjects()
            if movers then
                for i = 0, movers:size() - 1 do
                    local o = movers:get(i)
                    if o and (instanceof(o, "IsoZombie") or instanceof(o, "IsoPlayer")) then
                        return true
                    end
                end
            end
        end
    end
    return false
end

-- DRY: validate args contain position fields
local function hasPosition(args)
    return args and args.x and args.y and args.z
end

-- Admin/privileged check.
-- Capability.CanBuildAnywhere does not exist in 42.20; indexing the enum
-- yielded nil, hasCapability(nil) returned false, and admins were silently
-- denied. The real capability is UseBuildCheat. getRole() can also return nil
-- (single player, or a player with no role assigned), which threw. Fixes #14.
local function isPrivileged(player)
    if not player then return false end
    local role = player:getRole()
    if not role then return false end
    return role:hasCapability(Capability.UseBuildCheat)
end

-- Is this player close enough to touch that wire?
--
-- Unlike a WireTriggered report, where the thing being validated is a zombie
-- somewhere else (#31), here the player IS the actor, so their own distance is
-- the right thing to check.
--
-- Both callers reach the server behind luautils.walkAdj plus a timed action, so
-- the player has walked adjacent and is within about 1.6 tiles when the command
-- is sent. 4 is that plus slack for the server's copy of a moving player's
-- position lagging the client's in multiplayer. Floor is exact: a wire one
-- storey up is not within arm's reach.
local INTERACT_MAX_DIST = 4

local function withinReach(player, x, y, z)
    local sq = player and player:getSquare()
    if not sq then return false end
    if sq:getZ() ~= z then return false end
    return math.abs(sq:getX() - x) <= INTERACT_MAX_DIST
       and math.abs(sq:getY() - y) <= INTERACT_MAX_DIST
end

-----------------------------------------------------------
-- Main Dispatcher
-----------------------------------------------------------

local function onClientCommand(module, command, player, args)
    if module ~= DeadwireConfig.MODULE then return end

    if not DeadwireConfig.getSandbox("EnableMod", true) then
        DeadwireConfig.debugLog("Mod disabled, ignoring: " .. command)
        return
    end

    local handler = handlers[command]
    if handler then
        DeadwireConfig.debugLog("Command: " .. command .. " from " .. (player:getUsername() or "SP"))
        handler(player, args)
    else
        DeadwireConfig.log("Unknown command: " .. command)
    end
end

-- PlaceWire used to live here: a plain server command that trusted args.x/y/z
-- with no proximity or validity check, so a modified client could place wires
-- on any loaded square at any range. Nothing ever called it. The real placement
-- path is ISDeadwireTripLine in BuildActions.lua, which the engine validates
-- server-side by calling our isValid from BuildAction.isValid, and which
-- consumes the kit itself. Deleted with its client wrapper and its tests (#36).

-----------------------------------------------------------
-- RemoveWire: Client requests wire removal
-----------------------------------------------------------

handlers["RemoveWire"] = function(player, args)
    if not hasPosition(args) then
        DeadwireConfig.log("RemoveWire: invalid args")
        return
    end

    local wire = DeadwireNetwork.getTile(args.x, args.y, args.z)
    if not wire then
        DeadwireConfig.debugLog("RemoveWire: no wire at " .. args.x .. "," .. args.y .. "," .. args.z)
        return
    end

    -- Only owner or admin can remove
    local username = player:getUsername() or "SP"
    if wire.ownerId ~= username and not isPrivileged(player) then
        DeadwireConfig.log("RemoveWire: " .. username .. " not authorized")
        return
    end

    if not withinReach(player, args.x, args.y, args.z) then
        DeadwireConfig.log("RemoveWire: " .. username .. " too far from "
            .. args.x .. "," .. args.y .. "," .. args.z)
        return
    end

    -- Remember the type before the entry goes away.
    local wireType = wire.wireType

    -- Destroy IsoThumpable + unregister + remove from save
    DeadwireWireManager.destroyWire(args.x, args.y, args.z)

    -- Taking your own wire back up returns the kit whole. This is deliberately
    -- not the salvage roll a destroyed wire gets: the roll exists because a
    -- line something walked into came apart, and making a careful pickup a
    -- gamble too would punish doing it properly. It also sidesteps the
    -- question of which cord the kit was built with, since the kit itself is
    -- what comes back.
    local kitItem = DeadwireConfig.KitItems[wireType]
    if kitItem then
        player:getInventory():AddItem(kitItem)
    else
        DeadwireConfig.log("RemoveWire: " .. tostring(wireType)
            .. " has no kit item, nothing returned to " .. username)
    end

    sendServerCommand(DeadwireConfig.MODULE, "WireDestroyed", {
        x = args.x,
        y = args.y,
        z = args.z,
    })
end

-----------------------------------------------------------
-- WireTriggered: Client reports a wire was triggered
-- Server processes state changes (break, cooldown, camo degrade)
-- and broadcasts to all clients for MP sound.
-----------------------------------------------------------

handlers["WireTriggered"] = function(player, args)
    if not hasPosition(args) or not args.wireType then return end

    -- Sanity bound on the reporter first, because it is one comparison and
    -- rules out a client reporting coordinates it has no business knowing.
    -- Floor is not checked here: a player on any floor can see a zombie on
    -- another, and the wire's own floor is checked below.
    local psq = player:getSquare()
    if not psq
        or math.abs(psq:getX() - args.x) > TRIGGER_SANITY_DIST
        or math.abs(psq:getY() - args.y) > TRIGGER_SANITY_DIST then
        DeadwireConfig.debugLog("WireTriggered: rejected out-of-range report from "
            .. (player:getUsername() or "SP"))
        return
    end

    local wire = DeadwireNetwork.getTile(args.x, args.y, args.z)
    if not wire then return end

    -- The real gate: something has to actually be there. Costs 9 square
    -- lookups and only runs once a wire is known to exist at those coords.
    if not triggeringEntityNear(args.x, args.y, args.z) then
        DeadwireConfig.debugLog("WireTriggered: nothing on or beside "
            .. args.x .. "," .. args.y .. "," .. args.z .. ", report ignored")
        return
    end

    local wireType = wire.wireType
    local defaults = DeadwireConfig.WireDefaults[wireType]
    if not defaults then return end

    -- Determine sound info for broadcast
    local soundMap = {
        tin_can_tripline    = DeadwireConfig.Sounds.TIN_CAN_RATTLE,
        reinforced_tripline = DeadwireConfig.Sounds.WIRE_RATTLE,
        bell_tripline       = DeadwireConfig.Sounds.BELL_RING,
    }
    local soundName = soundMap[wireType]
    local soundRadius = defaults.soundRadius or 25
    local multiplier = DeadwireConfig.getSandbox("SoundMultiplier", 1.0)
    soundRadius = math.floor(soundRadius * multiplier)

    -- State changes based on wire type
    local cooldownSeconds = nil
    if DeadwireConfig.breaksOnTrigger(wireType) then
        -- Single-use: destroy wire, and leave a fraction of its durable parts
        -- on the tile. An empty tile reads as the wire having vanished, which
        -- looks like a bug rather than a wire that came apart.
        local sq = getWorld():getCell():getGridSquare(args.x, args.y, args.z)
        DeadwireWireManager.destroyWire(args.x, args.y, args.z)
        DeadwireWireManager.salvageWire(wireType, sq)
        sendServerCommand(DeadwireConfig.MODULE, "WireDestroyed", {
            x = args.x,
            y = args.y,
            z = args.z,
        })
    else
        -- Reusable: set cooldown. cooldownSeconds is real seconds (#16), and is
        -- declared per type in Config with no fallback here, so a type that
        -- forgets one says so instead of quietly borrowing another type of
        -- wire's number the way tanglefoot borrowed 36 (#37). Zero means no
        -- cooldown at all.
        local cooldownSec = defaults.cooldownSeconds
        if cooldownSec == nil then
            DeadwireConfig.log("WireTriggered: " .. wireType
                .. " declares no cooldownSeconds, wire will re-arm immediately")
        elseif cooldownSec > 0 then
            cooldownSeconds = DeadwireNetwork.setCooldown(args.x, args.y, args.z, cooldownSec)
        end
    end

    -- Degrade camo durability if camouflaged. Both branches write through to
    -- the save, or a reload restores camo the wire has already lost (#34).
    if wire.camouflaged then
        local degrade = DeadwireConfig.getSandbox("CamoTriggerDegrade", 15)
        local newDur = (wire.camoDurability or 0) - degrade
        if newDur <= 0 then
            DeadwireNetwork.setCamouflaged(args.x, args.y, args.z, false, 0)
            DeadwireWireManager.saveCamo(args.x, args.y, args.z, false, 0)
            sendServerCommand(DeadwireConfig.MODULE, "WireCamouflaged", {
                x = args.x, y = args.y, z = args.z,
                camouflaged = false, durability = 0,
            })
        else
            wire.camoDurability = newDur
            DeadwireWireManager.saveCamo(args.x, args.y, args.z, true, newDur)
        end
    end

    -- Log trigger if enabled
    if DeadwireConfig.getSandbox("LogWireTriggers", false) then
        local username = player:getUsername() or "SP"
        DeadwireConfig.log("Wire triggered: " .. wireType .. " at "
            .. args.x .. "," .. args.y .. "," .. args.z .. " by " .. username)
    end

    -- Broadcast: sound for MP audio, cooldownSeconds so each client's own
    -- WireNetwork agrees the wire is spent. Detection runs client-side against
    -- that copy, so without this the cooldown existed only on the server and
    -- every reusable wire re-armed instantly for every client in MP.
    --
    -- This does nothing outside a dedicated server: sendServerCommand returns
    -- immediately in single player and on clients (#35). Single player does not
    -- need it, because both halves of the mod share one tileIndex in memory --
    -- the cooldown set above is already the one Detection will read.
    if soundName or cooldownSeconds then
        sendServerCommand(DeadwireConfig.MODULE, "WireTriggered", {
            x = args.x,
            y = args.y,
            z = args.z,
            soundName = soundName,
            audioRadius = soundRadius,
            cooldownSeconds = cooldownSeconds,
        })
    end
end

-----------------------------------------------------------
-- CamouflageWire: Client requests camouflage application
-----------------------------------------------------------

handlers["CamouflageWire"] = function(player, args)
    if not DeadwireConfig.getSandbox("EnableCamouflage", true) then return end
    if not hasPosition(args) then return end

    local wire = DeadwireNetwork.getTile(args.x, args.y, args.z)
    if not wire or wire.camouflaged then return end

    -- Same authority as removal: hiding someone else's wire is as much a
    -- change to their perimeter as taking it away, and until #36 this handler
    -- had no owner check, no distance check and no material check at all.
    local username = player:getUsername() or "SP"
    if wire.ownerId ~= username and not isPrivileged(player) then
        DeadwireConfig.log("CamouflageWire: " .. username .. " not authorized")
        return
    end

    if not withinReach(player, args.x, args.y, args.z) then
        DeadwireConfig.log("CamouflageWire: " .. username .. " too far from "
            .. args.x .. "," .. args.y .. "," .. args.z)
        return
    end

    -- TODO Sprint 4: Validate materials, skill checks, consume materials

    local durability = DeadwireConfig.getSandbox("CamoMaxDurability", 100)
    DeadwireNetwork.setCamouflaged(args.x, args.y, args.z, true, durability)
    DeadwireWireManager.saveCamo(args.x, args.y, args.z, true, durability)

    sendServerCommand(DeadwireConfig.MODULE, "WireCamouflaged", {
        x = args.x,
        y = args.y,
        z = args.z,
        camouflaged = true,
        durability = durability,
    })
end

-----------------------------------------------------------
-- UncamouflageWire (#56)
--
-- Camouflage was one-way. isValid() refused a second Camouflage once the wire
-- was hidden, and no reverse command existed anywhere in the mod, so a wire
-- you hid stayed hidden for the life of the save. Worse, the sprite looks
-- identical either way, so the owner could not tell by looking whether it had
-- even worked.
--
-- Same authority as hiding it: revealing someone else's wire is as much a
-- change to their perimeter as hiding it.
-----------------------------------------------------------

handlers["UncamouflageWire"] = function(player, args)
    if not hasPosition(args) then return end

    local wire = DeadwireNetwork.getTile(args.x, args.y, args.z)
    if not wire or not wire.camouflaged then return end

    local username = player:getUsername() or "SP"
    if wire.ownerId ~= username and not isPrivileged(player) then
        DeadwireConfig.log("UncamouflageWire: " .. username .. " not authorized")
        return
    end

    if not withinReach(player, args.x, args.y, args.z) then
        DeadwireConfig.log("UncamouflageWire: " .. username .. " too far from "
            .. args.x .. "," .. args.y .. "," .. args.z)
        return
    end

    DeadwireNetwork.setCamouflaged(args.x, args.y, args.z, false, 0)
    DeadwireWireManager.saveCamo(args.x, args.y, args.z, false, 0)

    sendServerCommand(DeadwireConfig.MODULE, "WireCamouflaged", {
        x = args.x,
        y = args.y,
        z = args.z,
        camouflaged = false,
        durability = 0,
    })
end

-----------------------------------------------------------
-- ElectrifyFence / DeElectrifyFence (#52)
--
-- The farmer's half of Tier 3. Server-authoritative like everything else: the
-- client asks, the server finds the fence itself rather than trusting a
-- reported object, per key rule 11.
-----------------------------------------------------------

handlers["ElectrifyFence"] = function(player, args)
    if not DeadwireConfig.isTierEnabled(3) then return end
    if not hasPosition(args) then return end
    if DeadwireFences == nil then return end

    local username = player:getUsername() or "SP"
    if not withinReach(player, args.x, args.y, args.z) then
        DeadwireConfig.log("ElectrifyFence: " .. username .. " too far from "
            .. args.x .. "," .. args.y .. "," .. args.z)
        return
    end

    local sq = getWorld():getCell():getGridSquare(args.x, args.y, args.z)
    local ok, why = DeadwireFences.electrify(sq, username)
    if not ok then
        DeadwireConfig.log("ElectrifyFence refused at " .. args.x .. "," .. args.y
            .. ": " .. tostring(why))
        return
    end

    sendServerCommand(DeadwireConfig.MODULE, "FenceElectrified", {
        x = args.x, y = args.y, z = args.z, electrified = true,
    })
end

handlers["DeElectrifyFence"] = function(player, args)
    if not hasPosition(args) then return end
    if DeadwireFences == nil then return end

    local username = player:getUsername() or "SP"
    if not withinReach(player, args.x, args.y, args.z) then
        DeadwireConfig.log("DeElectrifyFence: " .. username .. " too far from "
            .. args.x .. "," .. args.y .. "," .. args.z)
        return
    end

    local sq = getWorld():getCell():getGridSquare(args.x, args.y, args.z)
    local ok, why = DeadwireFences.deElectrify(sq)
    if not ok then
        DeadwireConfig.log("DeElectrifyFence refused at " .. args.x .. "," .. args.y
            .. ": " .. tostring(why))
        return
    end

    sendServerCommand(DeadwireConfig.MODULE, "FenceElectrified", {
        x = args.x, y = args.y, z = args.z, electrified = false,
    })
end

-----------------------------------------------------------
-- RequestWireSync: a joining client asks for the wire list
--
-- Replaces the Events.OnPlayerConnect hook that never existed (#33). The
-- client cannot be pushed to at a moment the server knows about, so it asks
-- for itself from OnGameStart, and the answer goes to that player alone via
-- the targeted overload sendServerCommand(IsoPlayer, String, String, table),
-- which does exist in 42.20.4.
--
-- Nothing happens here in single player: sendServerCommand is a no-op off a
-- dedicated server, and single player does not need it -- both halves of the
-- mod share one tileIndex in memory.
-----------------------------------------------------------

handlers["RequestWireSync"] = function(player, args)
    if not player then return end

    local wireList = DeadwireWireManager.buildSyncPayload()
    sendServerCommand(player, DeadwireConfig.MODULE, "WireNetworkSync", {
        wires = wireList,
    })
    DeadwireConfig.log("WireNetworkSync: sent " .. #wireList .. " wires to "
        .. (player:getUsername() or "SP"))
end

-----------------------------------------------------------
-- DebugPlaceWire: Place a test wire at the player's feet
-- Admin or DEBUG mode only. For Sprint 1 testing.
-----------------------------------------------------------

handlers["DebugPlaceWire"] = function(player, args)
    if not DeadwireConfig.DEBUG and not isPrivileged(player) then
        return
    end

    local sq = player:getSquare()
    if not sq then return end

    local x, y, z = sq:getX(), sq:getY(), sq:getZ()
    local wireType = (args and args.wireType) or DeadwireConfig.WireTypes.TIN_CAN
    local username = player:getUsername() or "SP"

    -- Remove existing wire at this position first
    if DeadwireNetwork.getTile(x, y, z) then
        DeadwireWireManager.destroyWire(x, y, z)
    end

    local networkId = DeadwireNetwork.generateNetworkId()
    -- Facing is a real argument here, not a constant. The harness used to
    -- hardcode one side for every wire it placed, which read in game as
    -- "wires always sit on the top-left" and briefly looked like a bug in the
    -- mod (Session 27). Default west so the old behaviour is unchanged when
    -- nothing asks.
    local north = args and args.north and true or false
    local obj = DeadwireWireManager.createWire(sq, wireType, username, networkId, north)
    if not obj then return end

    DeadwireConfig.log("DEBUG wire at " .. x .. "," .. y .. "," .. z .. " type=" .. wireType)

    sendServerCommand(DeadwireConfig.MODULE, "WirePlaced", {
        x = x,
        y = y,
        z = z,
        networkId = networkId,
        wireType = wireType,
        ownerId = username,
        north = north,
    })
end

-----------------------------------------------------------
-- DebugListWires: List all registered wires (admin/debug)
-----------------------------------------------------------

handlers["DebugListWires"] = function(player, args)
    if not DeadwireConfig.DEBUG and not isPrivileged(player) then
        return
    end

    local count = 0
    for key, entry in pairs(DeadwireNetwork.getAllTiles()) do
        DeadwireConfig.log("  Wire: " .. key .. " type=" .. entry.wireType
            .. " active=" .. tostring(entry.active)
            .. " owner=" .. tostring(entry.ownerId))
        count = count + 1
    end
    DeadwireConfig.log("Total wires: " .. count)
end

-----------------------------------------------------------
-- Event Registration
-----------------------------------------------------------

Events.OnClientCommand.Add(onClientCommand)
DeadwireConfig.log("ServerCommands initialized")
