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

-- Resolve sprite name for a wire type and orientation.
-- Returns nil and says so rather than substituting a vanilla sprite: a wall
-- frame standing in for a missing trip wire looked like a working feature (#39).
local function getSprite(wireType, north)
    local sprites = DeadwireConfig.Sprites[wireType]
    local name = sprites and (north and sprites.north or sprites.east)
    if not name then
        DeadwireConfig.log("WireManager: no "
            .. (north and "north" or "east") .. " sprite for " .. tostring(wireType))
        return nil
    end
    return name
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
    if not sprite then return nil end
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
    -- The facing the sprite and the IsoThumpable were both built from. Kept
    -- so detection can tell crossing the wire from walking alongside it
    -- (#55), and so a reload can restore it without guessing.
    data["dw_north"] = north and true or false

    sq:AddSpecialObject(obj)
    obj:transmitCompleteItemToClients()
    -- NOTE: RecalcAllWithNeighbours intentionally NOT called here.
    -- Trip wires must be transparent to zombie pathfinding so zombies walk
    -- through them (triggering the alarm). Calling RecalcAllWithNeighbours
    -- would also update adjacent tiles (e.g. doors), causing door-blocking
    -- even when canPassThrough=true. Recalc only happens on wire removal.
    -- Fixes #8: wire placed near door blocks passage.

    -- Register in WireNetwork for detection
    local entry = DeadwireNetwork.registerTile(x, y, z, networkId, wireType, ownerId, north and true or false)
    entry.isoObject = obj

    -- Persist to GlobalModData
    DeadwireWireManager.saveWire(x, y, z, networkId, wireType, ownerId, north and true or false)

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
-- Salvage
--
-- Deliberately NOT inside destroyWire. Both callers destroy a wire and they
-- want different things left behind: a player pulling their own wire up gets
-- the kit back whole, and a wire something walked into scatters a fraction of
-- its durable parts. Folding this into destroyWire would give one of them the
-- wrong answer, and destroyWire is also called from paths that should drop
-- nothing at all.
--
-- Returns the number of items dropped, so a caller can log an empty result
-- rather than guess at it.
-----------------------------------------------------------

function DeadwireWireManager.salvageWire(wireType, sq)
    if not sq then return 0 end

    local parts = DeadwireConfig.Salvage[wireType]
    if not parts then
        DeadwireConfig.log("salvageWire: no salvage list for " .. tostring(wireType)
            .. ", nothing will be left on the tile")
        return 0
    end

    -- One roll for the whole wire, not one per slot. Half a trip line is half
    -- of everything, which is what a player reads off the ground; independent
    -- rolls per slot would average out and never look like a bad break.
    local percent = DeadwireConfig.rollSalvagePercent()

    local x, y, z = sq:getX(), sq:getY(), sq:getZ()
    local dropped = 0
    for _, part in ipairs(parts) do
        local n = math.floor(part.count * percent / 100)
        for _ = 1, n do
            sq:AddWorldInventoryItem(part.item, 0.0, 0.0, 0.0)
            dropped = dropped + 1
        end
    end

    DeadwireConfig.debugLog("salvageWire: " .. tostring(wireType) .. " at "
        .. x .. "," .. y .. "," .. z .. " rolled " .. percent .. "%, dropped " .. dropped)
    return dropped
end

-----------------------------------------------------------
-- Persistence: Save
-----------------------------------------------------------

function DeadwireWireManager.saveWire(x, y, z, networkId, wireType, ownerId, north)
    local saved = ModData.getOrCreate(SAVE_KEY)
    local key = DeadwireNetwork.tileKey(x, y, z)
    saved[key] = {
        x = x,
        y = y,
        z = z,
        networkId = networkId,
        wireType = wireType,
        ownerId = ownerId,
        north = north and true or false,
        camouflaged = false,
        camoDurability = 0,
    }
end

-- Camouflage lives in two places: the live WireNetwork entry, and the saved
-- entry here. Only the first was ever written, so every save and reload -- and
-- every dedicated server restart -- silently stripped camo from every wire
-- (#34). Call this after any change to either camo field.
function DeadwireWireManager.saveCamo(x, y, z, camouflaged, durability)
    local saved = ModData.getOrCreate(SAVE_KEY)
    local entry = saved[DeadwireNetwork.tileKey(x, y, z)]
    if not entry then return end
    entry.camouflaged = camouflaged and true or false
    entry.camoDurability = durability or 0
end

-- Same two-places problem as saveCamo: the live entry and the saved entry are
-- separate, and only writing the first loses it on reload.
function DeadwireWireManager.saveNorth(x, y, z, north)
    local saved = ModData.getOrCreate(SAVE_KEY)
    local entry = saved[DeadwireNetwork.tileKey(x, y, z)]
    if not entry then return end
    entry.north = north and true or false
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
            -- wire.north is nil for anything saved before #55. Passing the
            -- nil through on purpose: registerTile treats it as "facing
            -- unknown" and detection falls back to the old occupancy rule for
            -- that tile, rather than a wire from an old save going inert.
            -- reconnectSquare recovers the real facing off the object when
            -- the chunk loads.
            DeadwireNetwork.registerTile(
                wire.x, wire.y, wire.z,
                wire.networkId, wire.wireType, wire.ownerId, wire.north
            )
            -- registerTile always starts a tile uncamouflaged, so camo has to
            -- be reapplied here or it is lost on every load (#34).
            if wire.camouflaged then
                DeadwireNetwork.setCamouflaged(
                    wire.x, wire.y, wire.z, true, wire.camoDurability or 0
                )
            end
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

                -- Recover the facing for wires saved before #55, which have
                -- none recorded. The object itself has always known: getNorth()
                -- is the same flag it was constructed with. Prefer our own
                -- stored value when there is one, fall back to the object, and
                -- write the answer back to the save so the recovery happens
                -- once rather than every chunk load.
                local entry = DeadwireNetwork.getTile(x, y, z)
                if entry and entry.north == nil then
                    local north = data["dw_north"]
                    if north == nil and obj.getNorth then
                        north = obj:getNorth()
                    end
                    if north ~= nil then
                        entry.north = north and true or false
                        data["dw_north"] = entry.north
                        DeadwireWireManager.saveNorth(x, y, z, entry.north)
                        DeadwireConfig.debugLog("Recovered facing for pre-#55 wire at "
                            .. x .. "," .. y .. "," .. z .. " north=" .. tostring(entry.north))
                    end
                end
            end
        end
    end
end

-----------------------------------------------------------
-- Event Hooks
-----------------------------------------------------------

local function onInitGlobalModData(isNewGame)
    -- On a multiplayer client this file runs too, and the table it would read
    -- is the client's own -- always empty, so loadAll cleared the network and
    -- logged "loaded 0 wires" at a player whose wires were all on the server
    -- (#35). Still clear here, so leaving one server and joining another does
    -- not carry stale tiles over; the real list arrives from RequestWireSync.
    if isClient() then
        DeadwireNetwork.clear()
        return
    end

    DeadwireWireManager.loadAll()
end

local function onLoadGridsquare(sq)
    DeadwireWireManager.reconnectSquare(sq)
end

-----------------------------------------------------------
-- Join sync payload: every saved wire, for a client whose
-- local WireNetwork is empty. Without it a joining player's
-- detection ignores existing wires and the context menu
-- never offers Remove on their own wire.
--
-- There is no event hook here on purpose. This used to hang off
-- Events.OnPlayerConnect, which does not exist in 42.20.4 -- the name is in
-- none of the jar's classes and is absent from LuaEventManager's registry, so
-- it threw at load in every run mode and the sync never ran once (#33). The
-- client now asks: OnGameStart sends RequestWireSync, and the handler in
-- ServerCommands answers this list to that one player.
-----------------------------------------------------------

function DeadwireWireManager.buildSyncPayload()
    local saved = ModData.getOrCreate(SAVE_KEY)
    local wireList = {}
    for key, wire in pairs(saved) do
        if wire.x and wire.y and wire.z and wire.networkId and wire.wireType then
            table.insert(wireList, {
                x              = wire.x,
                y              = wire.y,
                z              = wire.z,
                networkId      = wire.networkId,
                wireType       = wire.wireType,
                ownerId        = wire.ownerId,
                north          = wire.north,
                camouflaged    = wire.camouflaged and true or false,
                camoDurability = wire.camoDurability or 0,
            })
        end
    end
    return wireList
end

Events.OnInitGlobalModData.Add(onInitGlobalModData)
Events.LoadGridsquare.Add(onLoadGridsquare)
DeadwireConfig.log("WireManager initialized (server)")
