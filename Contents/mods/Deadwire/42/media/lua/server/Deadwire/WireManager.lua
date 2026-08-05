-- Deadwire WireManager: Server-authoritative wire lifecycle + persistence
-- Server: creates/destroys IsoThumpable objects, persists via GlobalModData
--
-- All wire creation/destruction goes through this module. On game load,
-- rebuilds WireNetwork from saved GlobalModData so detection works
-- immediately without re-placing wires.

require "Deadwire/Config"
require "Deadwire/WireNetwork"

DeadwireWireManager = DeadwireWireManager or {}

-- GlobalModData key for persistence
local SAVE_KEY = "DeadwireWires"

-- Resolve sprite name for a wire type and orientation
local function getSprite(wireType, north)
    local sprites = DeadwireConfig.Sprites[wireType]
    if not sprites then return DeadwireConfig.FALLBACK_SPRITE end
    if north then
        return sprites.north or DeadwireConfig.FALLBACK_SPRITE
    else
        return sprites.east or DeadwireConfig.FALLBACK_SPRITE
    end
end

-----------------------------------------------------------
-- Wire Creation
-----------------------------------------------------------

function DeadwireWireManager.createWire(sq, wireType, ownerId, networkId, north)
    if not sq then return nil end

    local x, y, z = sq:getX(), sq:getY(), sq:getZ()

    -- Don't stack wires on same tile
    if DeadwireNetwork.getTile(x, y, z) then
        DeadwireConfig.debugLog("WireManager: tile occupied at " .. x .. "," .. y .. "," .. z)
        return nil
    end

    local defaults = DeadwireConfig.WireDefaults[wireType]
    if not defaults then
        DeadwireConfig.log("WireManager: unknown wire type " .. tostring(wireType))
        return nil
    end

    -- Create IsoThumpable in the world
    local sprite = getSprite(wireType, north or false)
    local health = DeadwireConfig.getWireHealth(wireType)
    local obj = IsoThumpable.new(getWorld():getCell(), sq, sprite, north or false, nil)
    obj:setName("DeadwireTripLine")
    obj:setMaxHealth(health)
    obj:setHealth(health)
    obj:setCanPassThrough(true)
    obj:setBlockAllTheSquare(false)
    obj:setIsThumpable(false)

    -- Store wire data in object ModData
    local data = obj:getModData()
    data["dw_type"] = wireType
    data["dw_networkId"] = networkId
    data["dw_owner"] = ownerId
    data["dw_active"] = true

    sq:AddSpecialObject(obj)
    obj:transmitCompleteItemToClients()
    -- NOTE: RecalcAllWithNeighbours intentionally NOT called here.
    -- Trip wires must be transparent to zombie pathfinding so zombies walk
    -- through them (triggering the alarm). Calling RecalcAllWithNeighbours
    -- would also update adjacent tiles (e.g. doors), causing door-blocking
    -- even when canPassThrough=true. Recalc only happens on wire removal.
    -- Fixes #8: wire placed near door blocks passage.

    -- Register in WireNetwork for detection
    local entry = DeadwireNetwork.registerTile(x, y, z, networkId, wireType, ownerId)
    entry.isoObject = obj

    -- Persist to GlobalModData
    DeadwireWireManager.saveWire(x, y, z, networkId, wireType, ownerId)

    DeadwireConfig.debugLog("WireManager: created " .. wireType .. " at " .. x .. "," .. y .. "," .. z)
    return obj
end

-----------------------------------------------------------
-- Wire Destruction
-----------------------------------------------------------

function DeadwireWireManager.destroyWire(x, y, z)
    local entry = DeadwireNetwork.getTile(x, y, z)
    if not entry then return false end

    -- Remove IsoThumpable from world
    local sq = nil
    local obj = entry.isoObject
    if obj then
        sq = obj:getSquare()
        if sq then
            sq:transmitRemoveItemFromSquare(obj)
        end
    else
        -- No cached ref — find it on the square
        sq = getWorld():getCell():getGridSquare(x, y, z)
        if sq then
            local objects = sq:getSpecialObjects()
            for i = 0, objects:size() - 1 do
                local o = objects:get(i)
                if o and o:getModData() and o:getModData()["dw_type"] then
                    sq:transmitRemoveItemFromSquare(o)
                    break
                end
            end
        end
    end

    -- Restore pathfinding after removal so the tile and adjacent tiles
    -- (e.g. doors) recalculate correctly now that the wire is gone.
    if sq then
        sq:RecalcAllWithNeighbours(true)
    end

    -- Unregister from WireNetwork
    DeadwireNetwork.unregisterTile(x, y, z)

    -- Remove from GlobalModData
    DeadwireWireManager.removeSavedWire(x, y, z)

    DeadwireConfig.debugLog("WireManager: destroyed wire at " .. x .. "," .. y .. "," .. z)
    return true
end

-----------------------------------------------------------
-- Persistence: Save
-----------------------------------------------------------

function DeadwireWireManager.saveWire(x, y, z, networkId, wireType, ownerId)
    local saved = ModData.getOrCreate(SAVE_KEY)
    local key = DeadwireNetwork.tileKey(x, y, z)
    saved[key] = {
        x = x,
        y = y,
        z = z,
        networkId = networkId,
        wireType = wireType,
        ownerId = ownerId,
    }
end

function DeadwireWireManager.removeSavedWire(x, y, z)
    local saved = ModData.getOrCreate(SAVE_KEY)
    local key = DeadwireNetwork.tileKey(x, y, z)
    saved[key] = nil
end

-----------------------------------------------------------
-- Persistence: Load (rebuild WireNetwork on game start)
-----------------------------------------------------------

function DeadwireWireManager.loadAll()
    local saved = ModData.getOrCreate(SAVE_KEY)

    -- Clear existing network state
    DeadwireNetwork.clear()

    local count = 0
    local maxNetworkId = 0

    for key, wire in pairs(saved) do
        if wire.x and wire.y and wire.z and wire.networkId and wire.wireType then
            DeadwireNetwork.registerTile(
                wire.x, wire.y, wire.z,
                wire.networkId, wire.wireType, wire.ownerId
            )
            if wire.networkId > maxNetworkId then
                maxNetworkId = wire.networkId
            end
            count = count + 1
        end
    end

    -- Restore network ID counter so new wires don't collide
    DeadwireNetwork.setNextNetworkId(maxNetworkId + 1)

    DeadwireConfig.log("WireManager: loaded " .. count .. " wires from save (nextId=" .. (maxNetworkId + 1) .. ")")
end

-----------------------------------------------------------
-- Reconnect IsoObject references after chunk load
-- Called when squares load in; finds Deadwire objects and
-- links them back to WireNetwork entries.
-----------------------------------------------------------

function DeadwireWireManager.reconnectSquare(sq)
    if not sq then return end

    local objects = sq:getSpecialObjects()
    for i = 0, objects:size() - 1 do
        local obj = objects:get(i)
        if obj then
            local data = obj:getModData()
            if data and data["dw_type"] then
                local x, y, z = sq:getX(), sq:getY(), sq:getZ()
                DeadwireNetwork.setIsoObject(x, y, z, obj)
            end
        end
    end
end

-----------------------------------------------------------
-- Event Hooks
-----------------------------------------------------------

local function onInitGlobalModData(isNewGame)
    DeadwireWireManager.loadAll()
end

local function onLoadGridsquare(sq)
    DeadwireWireManager.reconnectSquare(sq)
end

-----------------------------------------------------------
-- Resync on player connect: send full wire list to the
-- joining client so their local WireNetwork is populated.
-- Fixes the critical bug: owner can't remove own wire after
-- reconnecting because client WireNetwork was empty.
--
-- Broadcast approach: sendServerCommand(module, command, args) goes to all clients.
-- registerTile is idempotent so existing clients safely re-register their wires
-- without duplicates. This avoids the unverified targeted 4-arg overload.
-----------------------------------------------------------

local function onPlayerConnect(player)
    local saved = ModData.getOrCreate(SAVE_KEY)
    local wireList = {}
    for key, wire in pairs(saved) do
        if wire.x and wire.y and wire.z and wire.networkId and wire.wireType then
            table.insert(wireList, {
                x         = wire.x,
                y         = wire.y,
                z         = wire.z,
                networkId = wire.networkId,
                wireType  = wire.wireType,
                ownerId   = wire.ownerId,
            })
        end
    end
    sendServerCommand(DeadwireConfig.MODULE, "WireNetworkSync", {
        wires = wireList,
    })
    DeadwireConfig.log("WireNetworkSync: broadcast " .. #wireList
        .. " wires (triggered by " .. (player:getUsername() or "?") .. " connect)")
end

Events.OnInitGlobalModData.Add(onInitGlobalModData)
Events.LoadGridsquare.Add(onLoadGridsquare)
Events.OnPlayerConnect.Add(onPlayerConnect)
DeadwireConfig.log("WireManager initialized (server)")
