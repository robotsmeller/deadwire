-- Deadwire WireNetwork: Hash-table tile index for O(1) detection lookup
-- Shared: runs on both client and server
--
-- Primary data structure for the entire mod. OnZombieUpdate calls getTile()
-- every zombie tick — must be fast. String-key hash table gives O(1) lookup.

require "Deadwire/Config"

DeadwireNetwork = DeadwireNetwork or {}

-- Primary tile index: "x,y,z" -> wire entry
local tileIndex = {}

-- Network index: networkId -> { tiles = {"x,y,z", ...}, wireType, ownerId }
local networks = {}

-- Camouflaged tile subset for efficient client-side iteration
local camoTiles = {}

-- Server-side network ID counter
local nextNetworkId = 1

-----------------------------------------------------------
-- Key Helpers
-----------------------------------------------------------

function DeadwireNetwork.tileKey(x, y, z)
    return math.floor(x) .. "," .. math.floor(y) .. "," .. math.floor(z)
end

function DeadwireNetwork.parseKey(key)
    local x, y, z
    local i = 1
    for part in string.gmatch(key, "[^,]+") do
        if i == 1 then x = tonumber(part)
        elseif i == 2 then y = tonumber(part)
        elseif i == 3 then z = tonumber(part)
        end
        i = i + 1
    end
    return x, y, z
end

-----------------------------------------------------------
-- Network ID Generation (server only)
-----------------------------------------------------------

function DeadwireNetwork.generateNetworkId()
    local id = nextNetworkId
    nextNetworkId = nextNetworkId + 1
    return id
end

-----------------------------------------------------------
-- Tile Registration
-----------------------------------------------------------

-- `north` is which edge of the tile the wire lies on: true = the north edge,
-- false = the west edge. It is the same flag the sprite and the IsoThumpable
-- are built from, and until #55 it was thrown away the moment the object was
-- created. Detection needs it to tell crossing a wire from walking beside one.
--
-- It is deliberately allowed to be nil. Wires saved before #55 have no
-- recorded facing, and a nil here means "unknown", which detection treats as
-- the old occupancy behaviour rather than silently refusing to fire.
function DeadwireNetwork.registerTile(x, y, z, networkId, wireType, ownerId, north)
    x = math.floor(x)
    y = math.floor(y)
    z = math.floor(z)
    local key = DeadwireNetwork.tileKey(x, y, z)

    -- Idempotent: if already registered, update fields and return existing.
    -- Prevents duplicate entries when both server and client register the
    -- same tile (host machine in MP receives its own WirePlaced broadcast).
    if tileIndex[key] then
        local existing = tileIndex[key]
        existing.networkId = networkId
        existing.wireType = wireType
        existing.ownerId = ownerId
        existing.active = true
        if north ~= nil then existing.north = north end
        return existing
    end

    local entry = {
        networkId = networkId,
        wireType = wireType,
        active = true,
        x = x,
        y = y,
        z = z,
        ownerId = ownerId,
        north = north,
        camouflaged = false,
        camoDurability = 0,
        cooldownUntil = 0,
        isoObject = nil,
    }
    tileIndex[key] = entry

    if not networks[networkId] then
        networks[networkId] = {
            tiles = {},
            wireType = wireType,
            ownerId = ownerId,
        }
    end
    table.insert(networks[networkId].tiles, key)

    DeadwireNetwork.recomputeCircuits()

    DeadwireConfig.debugLog("Registered tile " .. key .. " network=" .. networkId .. " type=" .. wireType)
    return entry
end

function DeadwireNetwork.unregisterTile(x, y, z)
    local key = DeadwireNetwork.tileKey(x, y, z)
    local entry = tileIndex[key]
    if not entry then return end

    local network = networks[entry.networkId]
    if network then
        for i, tileKey in ipairs(network.tiles) do
            if tileKey == key then
                table.remove(network.tiles, i)
                break
            end
        end
        if #network.tiles == 0 then
            networks[entry.networkId] = nil
        end
    end

    if entry.camouflaged then
        camoTiles[key] = nil
    end

    tileIndex[key] = nil
    DeadwireNetwork.recomputeCircuits()
    DeadwireConfig.debugLog("Unregistered tile " .. key)
end

-----------------------------------------------------------
-- Circuit adjacency (#53)
--
-- An energiser powers a *run* of wire, not a radius, and `networks` could
-- never express that: every placement minted a fresh networkId, so the table
-- was a 1:1 mirror of tileIndex with no adjacency in it at all.
--
-- A circuit is a connected component over orthogonally adjacent wire tiles on
-- one z level. Recomputed whole on every place and remove, never on a tick.
-- Placement is rare and the tile set is small, and a full re-flood gets the
-- hard case -- pulling a wire out of the middle of a run has to SPLIT it into
-- two circuits -- for free, which is the case that makes union-find awkward.
-- The pulse and the zombie tick only ever read entry.circuitId.
-----------------------------------------------------------

local NEIGHBOUR_OFFSETS = {
    { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 },
}

function DeadwireNetwork.recomputeCircuits()
    local seen = {}
    local nextCircuit = 1

    for key, entry in pairs(tileIndex) do
        if not seen[key] then
            -- Breadth-first walk out from this tile, stamping one id on
            -- everything reachable through orthogonal adjacency.
            local circuitId = nextCircuit
            nextCircuit = nextCircuit + 1

            local queue = { key }
            seen[key] = true
            local head = 1
            while head <= #queue do
                local currentKey = queue[head]
                head = head + 1
                local current = tileIndex[currentKey]
                if current then
                    current.circuitId = circuitId
                    for _, off in ipairs(NEIGHBOUR_OFFSETS) do
                        local nKey = DeadwireNetwork.tileKey(
                            current.x + off[1], current.y + off[2], current.z)
                        if tileIndex[nKey] and not seen[nKey] then
                            seen[nKey] = true
                            table.insert(queue, nKey)
                        end
                    end
                end
            end
        end
    end
end

-- Every tile sharing a circuit with this one, the tile itself included.
-- Returns an empty table for a tile that holds no wire.
function DeadwireNetwork.getCircuitTiles(x, y, z)
    local entry = tileIndex[DeadwireNetwork.tileKey(x, y, z)]
    if not entry or not entry.circuitId then return {} end

    local out = {}
    for _, other in pairs(tileIndex) do
        if other.circuitId == entry.circuitId then
            table.insert(out, other)
        end
    end
    return out
end

-----------------------------------------------------------
-- Tile Lookup (called from OnZombieUpdate — must be fast)
-----------------------------------------------------------

function DeadwireNetwork.getTile(x, y, z)
    return tileIndex[DeadwireNetwork.tileKey(x, y, z)]
end

-----------------------------------------------------------
-- Network Queries
-----------------------------------------------------------

function DeadwireNetwork.getNetworkTiles(networkId)
    local network = networks[networkId]
    if not network then return {} end
    local tiles = {}
    for _, key in ipairs(network.tiles) do
        local entry = tileIndex[key]
        if entry then
            table.insert(tiles, entry)
        end
    end
    return tiles
end

function DeadwireNetwork.getNetwork(networkId)
    return networks[networkId]
end

-----------------------------------------------------------
-- Camouflage
-----------------------------------------------------------

-- The alpha reset lives here, not in the client's WireCamouflaged handler,
-- because sendServerCommand does nothing outside a dedicated server: in single
-- player that handler never runs. Uncamouflaging a wire removes it from
-- camoTiles, and CamoVisibility only ever touches tiles in camoTiles, so
-- whatever alpha it was last left at is permanent. A single-player player below
-- the detection level with CamoVisibleToOwner off was left with a wire stuck at
-- alpha 0 -- invisible and still armed -- for good (#35).
--
-- Putting it here means it runs on whichever side flips the flag.
function DeadwireNetwork.setCamouflaged(x, y, z, camouflaged, durability)
    local key = DeadwireNetwork.tileKey(x, y, z)
    local entry = tileIndex[key]
    if not entry then return end

    local wasCamouflaged = entry.camouflaged
    entry.camouflaged = camouflaged
    entry.camoDurability = durability or 0

    if camouflaged then
        camoTiles[key] = entry
    else
        camoTiles[key] = nil
        if wasCamouflaged and entry.isoObject then
            entry.isoObject:setAlphaAndTarget(1.0)
            entry.isoObject:setOutlineHighlight(false)
            -- Keep CamoVisibility's own record of what it outlined honest, or
            -- it believes an outline is up that this line just took down.
            entry.dwOutlined = false
        end
    end
end

function DeadwireNetwork.getCamoTiles()
    return camoTiles
end

-----------------------------------------------------------
-- IsoObject Reference (client-side)
-----------------------------------------------------------

function DeadwireNetwork.setIsoObject(x, y, z, obj)
    local entry = tileIndex[DeadwireNetwork.tileKey(x, y, z)]
    if entry then
        entry.isoObject = obj
    end
end

-- Find this wire's IsoThumpable on its own square and cache it. Returns the
-- object, or nil if the chunk is not loaded or nothing is there.
--
-- The Lua command that announces a wire and the object sync that carries the
-- IsoThumpable are separate packets. When the command lands first the reference
-- is nil, and LoadGridsquare will not fire again for a chunk that is already
-- loaded, so anything needing the object skips that tile for good -- which
-- leaves a freshly camouflaged wire fully visible (#41).
function DeadwireNetwork.relinkIsoObject(x, y, z)
    local entry = tileIndex[DeadwireNetwork.tileKey(x, y, z)]
    if not entry then return nil end

    local cell = getCell()
    local sq = cell and cell:getGridSquare(x, y, z)
    if not sq then return nil end

    local objects = sq:getSpecialObjects()
    for i = 0, objects:size() - 1 do
        local obj = objects:get(i)
        if obj and obj:getModData() and obj:getModData()["dw_type"] then
            entry.isoObject = obj
            return obj
        end
    end
    return nil
end

-----------------------------------------------------------
-- Cooldown
--
-- Measured in real seconds (os.time), not game hours. The cooldown exists to
-- stop one zombie crowd spamming the same alarm, which is a real-time problem:
-- under game time the same config number meant a different real duration on
-- every server, and at the default day length 36 game-seconds worked out to
-- about 1.5 real seconds -- shorter than Detection's own dedup window, so the
-- cooldown did essentially nothing. Fixes #16.
--
-- Detection.lua already uses os.time() for its dedup window, so both clocks in
-- this mod now agree.
-----------------------------------------------------------

function DeadwireNetwork.isOnCooldown(x, y, z)
    local entry = tileIndex[DeadwireNetwork.tileKey(x, y, z)]
    if not entry or entry.cooldownUntil <= 0 then return false end
    return os.time() < entry.cooldownUntil
end

-- Returns the duration actually applied, or nil if there is no such tile, so
-- the server can tell clients how long to mirror it for.
--
-- Deliberately a duration and not an absolute expiry: server and clients are
-- different machines, and while os.time() is UTC epoch (so timezone is not a
-- factor) their wall clocks can still be skewed. Each side adds the duration
-- to its own clock, which costs network latency in accuracy and is immune to
-- skew -- the far worse error.
function DeadwireNetwork.setCooldown(x, y, z, durationSeconds)
    local entry = tileIndex[DeadwireNetwork.tileKey(x, y, z)]
    if not entry then return nil end
    entry.cooldownUntil = os.time() + durationSeconds
    return durationSeconds
end

-----------------------------------------------------------
-- Player Wire Count
-----------------------------------------------------------

function DeadwireNetwork.getPlayerTileCount(ownerId)
    local count = 0
    for _, entry in pairs(tileIndex) do
        if entry.ownerId == ownerId then
            count = count + 1
        end
    end
    return count
end

-----------------------------------------------------------
-- Utility
-----------------------------------------------------------

function DeadwireNetwork.getAllTiles()
    return tileIndex
end

function DeadwireNetwork.clear()
    tileIndex = {}
    networks = {}
    camoTiles = {}
    nextNetworkId = 1
end

function DeadwireNetwork.setNextNetworkId(id)
    nextNetworkId = id
end
