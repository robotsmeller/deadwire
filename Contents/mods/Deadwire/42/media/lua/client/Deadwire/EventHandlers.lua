-- Deadwire EventHandlers: OnServerCommand listener
-- Client: handles server broadcasts for sound effects and local state updates
--
-- When the server triggers a wire, it broadcasts to all clients. This module
-- plays the appropriate sound effect and updates the local WireNetwork cache.

require "Deadwire/Config"
require "Deadwire/WireNetwork"

DeadwireEventHandlers = DeadwireEventHandlers or {}

local handlers = {}

-- DRY: validate args contain position fields
local function hasPosition(args)
    return args and args.x and args.y and args.z
end

-- DRY: validate position args and return grid square (or nil)
local function getSquareFromArgs(args)
    if not hasPosition(args) then return nil end
    return getCell():getGridSquare(args.x, args.y, args.z)
end

-----------------------------------------------------------
-- Main Dispatcher
-----------------------------------------------------------

local function onServerCommand(module, command, args)
    if module ~= DeadwireConfig.MODULE then return end

    local handler = handlers[command]
    if handler then
        handler(args)
    else
        DeadwireConfig.debugLog("Unknown server command: " .. command)
    end
end

-----------------------------------------------------------
-- WireTriggered: Play sound effect and apply the server's cooldown
--
-- Detection (Detection.lua) checks isOnCooldown against this client's own
-- WireNetwork copy, so the server's cooldown has to be mirrored here or the
-- wire re-arms immediately on every client in MP.
-----------------------------------------------------------

handlers["WireTriggered"] = function(args)
    if not hasPosition(args) then return end

    if args.cooldownSeconds then
        DeadwireNetwork.setCooldown(args.x, args.y, args.z, args.cooldownSeconds)
    end

    -- No soundName means a silent trap (tanglefoot). Do not substitute one:
    -- the previous default of TIN_CAN_RATTLE would have made it audible.
    if not args.soundName then return end

    local sq = getSquareFromArgs(args)
    if not sq then return end

    local audioRadius = args.audioRadius or 15
    getSoundManager():PlayWorldSound(args.soundName, sq, 0, audioRadius, 1.0, false)
    DeadwireConfig.debugLog("Sound: " .. args.soundName .. " at " .. args.x .. "," .. args.y .. "," .. args.z)
end

-----------------------------------------------------------
-- WirePlaced: Update local wire network cache
-----------------------------------------------------------

handlers["WirePlaced"] = function(args)
    if not hasPosition(args) then return end
    DeadwireNetwork.registerTile(
        args.x, args.y, args.z,
        args.networkId,
        args.wireType,
        args.ownerId,
        args.north
    )

    -- Cache the IsoObject reference for client-side camo visibility
    DeadwireNetwork.relinkIsoObject(args.x, args.y, args.z)

    DeadwireConfig.debugLog("Wire placed at " .. args.x .. "," .. args.y .. "," .. args.z)
end

-----------------------------------------------------------
-- FencePulse / FenceElectrified (#52)
--
-- Dead in single player, like every other handler in this file:
-- sendServerCommand is a no-op off a dedicated server, and in single player
-- the pulse already played its own sound locally. These exist so a
-- multiplayer client hears a fence bite something it did not compute.
-----------------------------------------------------------

handlers["FencePulse"] = function(args)
    if not hasPosition(args) then return end
    if not args.soundName then return end

    local sq = getSquareFromArgs(args)
    if not sq then return end

    getSoundManager():PlayWorldSound(args.soundName, sq, 0, 20, 1.0, false)
    DeadwireConfig.debugLog("Fence pulsed at " .. args.x .. "," .. args.y)
end

handlers["FenceElectrified"] = function(args)
    if not hasPosition(args) then return end
    DeadwireConfig.debugLog("Fence at " .. args.x .. "," .. args.y
        .. (args.electrified and " is live" or " is dead"))
end

-----------------------------------------------------------
-- WireDestroyed: Remove from local cache
-----------------------------------------------------------

handlers["WireDestroyed"] = function(args)
    if not hasPosition(args) then return end

    DeadwireNetwork.unregisterTile(args.x, args.y, args.z)
    DeadwireConfig.debugLog("Wire destroyed at " .. args.x .. "," .. args.y .. "," .. args.z)
end

-----------------------------------------------------------
-- WireCamouflaged: Update local camouflage state
-----------------------------------------------------------

handlers["WireCamouflaged"] = function(args)
    if not hasPosition(args) then return end

    -- The alpha and outline reset used to live here. It is inside
    -- WireNetwork.setCamouflaged now, because this handler only ever runs on a
    -- multiplayer client -- single player never receives a server command at
    -- all, so the reset never happened there (#35).
    DeadwireNetwork.setCamouflaged(
        args.x, args.y, args.z,
        args.camouflaged,
        args.durability
    )
    DeadwireConfig.debugLog("Camo updated at " .. args.x .. "," .. args.y .. "," .. args.z)
end

-----------------------------------------------------------
-- WireNetworkSync: Bulk-populate local WireNetwork on join.
--
-- The server answers this to one player in reply to RequestWireSync below.
-- Until #33 it was hung off an event that does not exist, so a joining client
-- had an empty WireNetwork: detection ignored every existing wire, the context
-- menu never offered Remove on the player's own wire, and CamoVisibility hid
-- nothing.
--
-- The per-wire object lookup is not optional here. Chunks around the spawn
-- point are already loaded by the time this arrives and LoadGridsquare will
-- not fire for them again, so without it those wires never get an isoObject.
-----------------------------------------------------------

handlers["WireNetworkSync"] = function(args)
    if not args or not args.wires then return end
    local count = 0
    local linked = 0
    for _, wire in ipairs(args.wires) do
        if wire.x and wire.y and wire.z and wire.networkId and wire.wireType then
            DeadwireNetwork.registerTile(
                wire.x, wire.y, wire.z,
                wire.networkId,
                wire.wireType,
                wire.ownerId,
                wire.north
            )
            if wire.camouflaged then
                DeadwireNetwork.setCamouflaged(
                    wire.x, wire.y, wire.z, true, wire.camoDurability or 0
                )
            end
            if DeadwireNetwork.relinkIsoObject(wire.x, wire.y, wire.z) then
                linked = linked + 1
            end
            count = count + 1
        end
    end
    DeadwireConfig.log("WireNetworkSync: registered " .. count
        .. " wires (" .. linked .. " already in loaded chunks)")
end

-----------------------------------------------------------
-- ElectricZap: Play zap sound (Phase 3, but handler ready)
-----------------------------------------------------------

handlers["ElectricZap"] = function(args)
    local sq = getSquareFromArgs(args)
    if not sq then return end

    getSoundManager():PlayWorldSound(
        args.soundName or DeadwireConfig.Sounds.ELEC_ZAP,
        sq, 0, args.audioRadius or 15, 1.0, false
    )
end

-----------------------------------------------------------
-- Ask the server for the wire list once the world is up.
--
-- isClient() is true only on a multiplayer client, which is exactly who needs
-- this: single player shares one tileIndex between both halves of the mod, and
-- a dedicated server never runs client/ code at all.
-----------------------------------------------------------

local function onGameStart()
    if not isClient() then return end
    sendClientCommand(DeadwireConfig.MODULE, "RequestWireSync", {})
    DeadwireConfig.debugLog("RequestWireSync sent")
end

-----------------------------------------------------------
-- Event Registration
-----------------------------------------------------------

Events.OnServerCommand.Add(onServerCommand)
Events.OnGameStart.Add(onGameStart)
DeadwireConfig.log("Client EventHandlers initialized")
