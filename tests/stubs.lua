-- tests/stubs.lua
-- PZ API stubs: lets Deadwire Lua modules load and run outside the game engine.
-- Load this before requiring any Deadwire module.
-- All stub state can be reset with _reset() between tests.

-----------------------------------------------------------------
-- Events (PZ event system)
-- Events.SomeName.Add(fn) stores handlers we can invoke in tests.
-----------------------------------------------------------------
Events = {}
setmetatable(Events, {
    __index = function(t, k)
        local ev = { _handlers = {} }
        -- Add: called with dot syntax in PZ code, e.g. Events.OnZombieUpdate.Add(fn)
        ev.Add  = function(fn) table.insert(ev._handlers, fn) end
        -- Fire: called with colon syntax in tests, e.g. Events.OnZombieUpdate:Fire(zombie)
        -- Colon passes the table as first arg; remaining args go to handlers.
        ev.Fire = function(_, ...) for _, fn in ipairs(ev._handlers) do fn(...) end end
        t[k] = ev
        return ev
    end
})

-----------------------------------------------------------------
-- SandboxVars (overridable per test)
-----------------------------------------------------------------
SandboxVars = { Deadwire = {} }

-----------------------------------------------------------------
-- Game time (controls cooldown / dedup timestamp logic)
-----------------------------------------------------------------
local _worldAgeHours = 0
function getGameTime()
    return { getWorldAgeHours = function() return _worldAgeHours end }
end
function _setWorldAge(h) _worldAgeHours = h end  -- test control

-----------------------------------------------------------------
-- World cells and grid squares
-----------------------------------------------------------------
local _squares = {}

function _makeSquare(x, y, z)
    local key = x .. "," .. y .. "," .. z
    local objects = {}
    local sq = {
        _x = x, _y = y, _z = z,
        getX = function(self) return self._x end,
        getY = function(self) return self._y end,
        getZ = function(self) return self._z end,
        getSpecialObjects = function(self)
            return {
                size = function() return #objects end,
                get  = function(_, i) return objects[i + 1] end,
            }
        end,
        AddSpecialObject = function(self, obj)
            table.insert(objects, obj)
        end,
        transmitRemoveItemFromSquare = function(self, obj)
            for i, o in ipairs(objects) do
                if o == obj then table.remove(objects, i); return end
            end
        end,
        RecalcAllWithNeighbours = function() end,
    }
    _squares[key] = sq
    return sq
end

local _cell = {
    getGridSquare = function(self, x, y, z)
        return _squares[x .. "," .. y .. "," .. z]
    end,
}
function getCell()  return _cell end
function getWorld() return { getCell = function() return _cell end } end
function _clearSquares() _squares = {} end

-----------------------------------------------------------------
-- Command capture: sendServerCommand / sendClientCommand
-----------------------------------------------------------------
_sentServer = {}
_sentClient = {}

function sendServerCommand(mod, cmd, args)
    table.insert(_sentServer, { mod = mod, cmd = cmd, args = args })
end
function sendClientCommand(mod, cmd, args)
    table.insert(_sentClient, { mod = mod, cmd = cmd, args = args })
end
function _clearCommands()
    _sentServer = {}
    _sentClient = {}
end

-- Helper: find a sent server command by cmd name
function _findServerCmd(cmd)
    for _, entry in ipairs(_sentServer) do
        if entry.cmd == cmd then return entry end
    end
    return nil
end

-----------------------------------------------------------------
-- IsoThumpable stub
-----------------------------------------------------------------
IsoThumpable = {
    new = function(cell, sq, sprite, north, extra)
        local modData = {}
        local obj = {
            _sq = sq, _sprite = sprite, _modData = modData,
            setName                      = function() end,
            setMaxHealth                 = function() end,
            setHealth                    = function() end,
            setCanPassThrough            = function() end,
            setBlockAllTheSquare         = function() end,
            setIsThumpable               = function() end,
            getModData                   = function(self) return self._modData end,
            getSquare                    = function(self) return self._sq end,
            transmitCompleteItemToClients = function() end,
        }
        if sq then sq:AddSpecialObject(obj) end
        return obj
    end,
}

-----------------------------------------------------------------
-- ModData (GlobalModData persistence stub)
-----------------------------------------------------------------
local _modStore = {}
ModData = {
    getOrCreate = function(key)
        if not _modStore[key] then _modStore[key] = {} end
        return _modStore[key]
    end,
}
function _clearModData() _modStore = {} end

-----------------------------------------------------------------
-- os.time stub (controls the dedup window in Detection.lua)
-- Detection uses os.time() with a 1-real-second dedup window.
-----------------------------------------------------------------
local _osTime = 0
local _orig_os_time = os.time
os.time = function() return _osTime end
function _setOsTime(t) _osTime = t end   -- test control

-----------------------------------------------------------------
-- Faction stub (Detection.lua faction immunity)
-- Real signature: Faction.isInSameFaction(IsoPlayer, String) -> boolean.
-- Tests declare membership by username via _setFaction.
-----------------------------------------------------------------
local _factions = {}   -- username -> faction name

Faction = {
    isInSameFaction = function(player, ownerUsername)
        if not player or not ownerUsername then return false end
        local mine = _factions[player:getUsername()]
        return mine ~= nil and mine == _factions[ownerUsername]
    end,
}

function _setFaction(username, factionName) _factions[username] = factionName end
function _clearFactions() _factions = {} end

-----------------------------------------------------------------
-- PZ capability system stub
-- UseBuildCheat is the real 42.20 name. CanBuildAnywhere, which this stub
-- used to declare, does not exist in the game -- so the stub was validating
-- a call that could never work. Deliberately the only key defined: any other
-- Capability.X in mod code resolves to nil here and fails loudly.
-----------------------------------------------------------------
Capability = { UseBuildCheat = "UseBuildCheat" }

-----------------------------------------------------------------
-- Sound stubs (no-op; we only care about logic, not audio)
-- getWorldSoundManager():addSound(emitter, x, y, z, radius, volume, blocked)
-- Called with colon syntax, so arg layout is: self, emitter, x, y, z, radius, volume, blocked
-----------------------------------------------------------------
local _soundCalls = {}
function getWorldSoundManager()
    return {
        addSound = function(_, emitter, x, y, z, radius, volume, blocked)
            table.insert(_soundCalls, { x=x, y=y, z=z, radius=radius, volume=volume })
        end
    }
end
function getSoundManager()
    return { PlayWorldSound = function() end }
end
function _clearSounds() _soundCalls = {} end
function _getSoundCalls() return _soundCalls end

-----------------------------------------------------------------
-- Entity builders for detection tests
-----------------------------------------------------------------
function _mockZombie(x, y, z, alive)
    local modData = {}
    local sq = _squares[x .. "," .. y .. "," .. z]
    return {
        isAlive     = function() return alive ~= false end,
        getSquare   = function() return sq end,
        getModData  = function() return modData end,
        getUsername = function() return nil end,
    }
end

-- Inventory stub: only the container methods Deadwire actually calls.
local function _makeInventory()
    local inv = { _items = {} }
    inv.getFirstTypeRecurse = function(self, fullType)
        for _, it in ipairs(self._items) do
            if it.fullType == fullType then return it end
        end
        return nil
    end
    inv.getItemsFromFullType = function(self, fullType, _recurse)
        local found = {}
        for _, it in ipairs(self._items) do
            if it.fullType == fullType then table.insert(found, it) end
        end
        return {
            size = function() return #found end,
            get  = function(_, i) return found[i + 1] end,
        }
    end
    inv.Remove = function(self, item)
        for i, it in ipairs(self._items) do
            if it == item then table.remove(self._items, i); return end
        end
    end
    return inv
end

-- Put an item in a mock player's inventory. Returns the item table.
function _giveItem(player, fullType)
    local item = { fullType = fullType }
    table.insert(player:getInventory()._items, item)
    return item
end

function _countItems(player, fullType)
    local n = 0
    for _, it in ipairs(player:getInventory()._items) do
        if it.fullType == fullType then n = n + 1 end
    end
    return n
end

function _mockPlayer(x, y, z, username)
    local modData = {}
    local sq = _squares[x .. "," .. y .. "," .. z]
    local inv = _makeInventory()
    return {
        isAlive       = function() return true end,
        getSquare     = function() return sq end,
        getModData    = function() return modData end,
        getUsername   = function() return username or "testplayer" end,
        getInventory  = function() return inv end,
        isAccessLevel = function() return false end,
        getRole       = function() return {
            hasCapability = function() return false end
        } end,
    }
end

function _mockAdmin(x, y, z, username)
    local p = _mockPlayer(x, y, z, username)
    p.isAccessLevel = function() return true end
    p.getRole = function() return {
        hasCapability = function(_, cap) return cap == Capability.UseBuildCheat end
    } end
    return p
end

-- A player whose getRole() returns nil, as happens in single player. This used
-- to throw on `player:getRole():hasCapability(...)`.
function _mockRolelessPlayer(x, y, z, username)
    local p = _mockPlayer(x, y, z, username)
    p.getRole = function() return nil end
    return p
end

-----------------------------------------------------------------
-- Global reset: call between test suites for clean slate
-----------------------------------------------------------------
function _reset()
    _worldAgeHours = 0
    _osTime = 0
    _squares = {}
    _modStore = {}
    _sentServer = {}
    _sentClient = {}
    _soundCalls = {}
    _factions = {}
    SandboxVars = { Deadwire = {} }
    -- Reset WireNetwork internal state (if loaded)
    if DeadwireNetwork then DeadwireNetwork.clear() end
end
