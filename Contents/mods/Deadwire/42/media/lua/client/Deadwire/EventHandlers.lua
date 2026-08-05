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
        args.ownerId
    )

    -- Cache the IsoObject reference for client-side camo visibility
    local sq = getCell():getGridSquare(args.x, args.y, args.z)
    if sq then
        local objects = sq:getSpecialObjects()
        for i = 0, objects:size() - 1 do
            local obj = objects:get(i)
            if obj and obj:getModData() and obj:getModData()["dw_type"] then
                DeadwireNetwork.setIsoObject(args.x, args.y, args.z, obj)
                break
            end
        end
    end

    DeadwireConfig.debugLog("Wire placed at " .. args.x .. "," .. args.y .. "," .. args.z)
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

    -- When uncamouflaging: reset alpha to full opacity before removing from
    -- camo index. Without this the wire stays invisible until next render cycle.
    if not args.camouflaged then
        local entry = DeadwireNetwork.getTile(args.x, args.y, args.z)
        if entry and entry.isoObject then
            entry.isoObject:setAlphaAndTarget(1.0)
            entry.isoObject:setOutlineHighlight(false)
        end
    end

    DeadwireNetwork.setCamouflaged(
        args.x, args.y, args.z,
        args.camouflaged,
        args.durability
    )
    DeadwireConfig.debugLog("Camo updated at " .. args.x .. "," .. args.y .. "," .. args.z)
end

-----------------------------------------------------------
-- WireNetworkSync: Bulk-populate local WireNetwork on connect/rejoin.
-- Server sends all active wires when a player connects so the client's
-- hash-table is populated without waiting for individual WirePlaced events.
-----------------------------------------------------------

handlers["WireNetworkSync"] = function(args)
    if not args or not args.wires then return end
    local count = 0
    for _, wire in ipairs(args.wires) do
        if wire.x and wire.y and wire.z and wire.networkId and wire.wireType then
            DeadwireNetwork.registerTile(
                wire.x, wire.y, wire.z,
                wire.networkId,
                wire.wireType,
                wire.ownerId
            )
            count = count + 1
        end
    end
    DeadwireConfig.log("WireNetworkSync: registered " .. count .. " wires")
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
-- Event Registration
-----------------------------------------------------------

Events.OnServerCommand.Add(onServerCommand)
DeadwireConfig.log("Client EventHandlers initialized")
