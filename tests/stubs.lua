-- tests/stubs.lua
-- PZ API stubs: lets Deadwire Lua modules load and run outside the game engine.
-- Load this before requiring any Deadwire module.
-- All stub state can be reset with _reset() between tests.

-----------------------------------------------------------------
-- Events (PZ event system)
-- Events.SomeName.Add(fn) stores handlers we can invoke in tests.
--
-- This table used to invent any event name it was asked for. That is how
-- Events.OnPlayerConnect -- a name in none of the jar's 23,740 classes, which
-- threw at load in every run mode and meant the join-time wire sync never ran
-- once -- passed 159 tests for a whole release (#33).
--
-- A checker that supplies whatever it is asked for cannot detect an absence.
-- So the allow-list comes from the game itself: tests/pz_events.lua is
-- generated from zombie/Lua/LuaEventManager by
-- `python scripts/verify_names.py --update-events`, and verify_names fails if
-- the committed copy has drifted from the installed jar. The list is committed
-- so the suite still runs on a machine with no game installed.
-----------------------------------------------------------------
local ok, KNOWN_EVENTS = pcall(dofile, "tests/pz_events.lua")
if not ok or type(KNOWN_EVENTS) ~= "table" then
    error("tests/pz_events.lua is missing or unreadable. Run:\n"
        .. "  python scripts/verify_names.py --update-events\n"
        .. "(run the suite from the repo root)")
end

Events = {}
setmetatable(Events, {
    __index = function(t, k)
        if not KNOWN_EVENTS[k] then
            error("Events." .. tostring(k) .. " is not an event this game has.\n"
                .. "Registering it would throw at load and everything after that\n"
                .. "line in the file would never run. Check the name against\n"
                .. "tests/pz_events.lua.", 2)
        end
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
-- Run mode
--
-- isClient() is true ONLY on a multiplayer client. It is false in single
-- player AND on a dedicated server, which is why it, and not isServer(), is
-- the guard for "the authoritative side". Defaults to false, so a module that
-- forgets the guard is exercised in the mode most tests mean.
--
-- isServer() is deliberately not stubbed. Nothing under test calls it, and a
-- stub that answers questions nobody asked is how three checkers here have
-- blessed a bug.
-----------------------------------------------------------------
local _isClient = false
function isClient() return _isClient end
function _setClient(v) _isClient = v and true or false end

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
    local movers = {}
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

        -- Items dropped on the tile. Real signature is
        -- AddWorldInventoryItem(fullType, x, y, z) and it takes 4, 5 or 6
        -- arguments; we call the 4-arg form. Recorded rather than discarded,
        -- because "a destroyed wire leaves something behind" is the whole
        -- point of the salvage path and an empty tile is the bug it fixes.
        _worldItems = {},
        AddWorldInventoryItem = function(self, fullType, ox, oy, oz)
            table.insert(self._worldItems, fullType)
        end,

        -- What ISDeadwireTripLine:isValid asks a square. Both start in the
        -- state that lets a wire be placed; a test that cares about refusal
        -- sets the field itself, so neither answer is invented here.
        _vehicleIntersecting = false,
        _freeOrMidair = true,
        isVehicleIntersecting = function(self) return self._vehicleIntersecting end,
        isFreeOrMidair = function(self) return self._freeOrMidair end,

        -- Live zombies and players on this tile. Real IsoGridSquare returns an
        -- ArrayList here, hence size()/get(i) with a zero base. Starts empty
        -- and only ever holds what a test explicitly put there -- the server's
        -- trigger gate reads this to decide whether anything actually walked
        -- into a wire, so a stub that invented occupants could not tell an
        -- empty tile from an occupied one.
        getMovingObjects = function(self)
            return {
                size = function() return #movers end,
                get  = function(_, i) return movers[i + 1] end,
            }
        end,
        _addMover = function(self, obj)
            table.insert(movers, obj)
        end,
    }
    _squares[key] = sq
    return sq
end

-- Put an existing mock entity on a square. _mockZombie and _mockPlayer call
-- this for themselves when their square exists.
function _placeOn(entity, x, y, z)
    local sq = _squares[x .. "," .. y .. "," .. z]
    if sq then sq:_addMover(entity) end
    return entity
end

-- Walk an entity to another tile, keeping its modData. The old tile keeps the
-- reference in its moving-objects list, which does not matter for anything
-- currently under test and is not worth pretending otherwise about.
function _moveTo(entity, x, y, z)
    entity._sq = _squares[x .. "," .. y .. "," .. z]
    return _placeOn(entity, x, y, z)
end

-- setDrag is what the placement menu hands the engine: a build object the
-- player then positions and clicks down. Recorded rather than executed,
-- because "the menu handed the engine the right ISDeadwireTripLine" is the
-- claim UI.lua is responsible for; whether that object then places a wire is
-- BuildActions' claim, and it has its own tests.
_dragged = {}

local _cell = {
    getGridSquare = function(self, x, y, z)
        return _squares[x .. "," .. y .. "," .. z]
    end,
    setDrag = function(self, obj, playerNum)
        table.insert(_dragged, { obj = obj, playerNum = playerNum })
    end,
}
function _lastDragged() return _dragged[#_dragged] end
function getCell()  return _cell end
function getWorld() return { getCell = function() return _cell end } end
function _clearSquares() _squares = {} end

-----------------------------------------------------------------
-- instanceof (PZ global, used to tell IsoZombie from IsoPlayer)
--
-- Answers from the class the mock declares for itself. A mock that declares
-- nothing is not an instance of anything, so asking about a class no mock
-- sets is false rather than true -- the opposite of the Events table's old
-- behaviour, which invented whatever it was asked for.
-----------------------------------------------------------------
function instanceof(obj, className)
    if type(obj) ~= "table" then return false end
    return obj._class == className
end

-----------------------------------------------------------------
-- Command capture: sendServerCommand / sendClientCommand
-----------------------------------------------------------------
_sentServer = {}
_sentClient = {}

-- Both real overloads exist and PZ picks by the first argument's type:
--   sendServerCommand(module, command, table)             -> every client
--   sendServerCommand(player, module, command, table)     -> that one client
-- Recording only the 3-arg shape would have silently shifted every field by one
-- for the targeted send the join sync uses (#33).
local function _isPlayer(v)
    return type(v) == "table" and v._class == "IsoPlayer"
end

function sendServerCommand(a, b, c, d)
    if _isPlayer(a) then
        table.insert(_sentServer, { target = a, mod = b, cmd = c, args = d })
    else
        table.insert(_sentServer, { target = nil, mod = a, cmd = b, args = c })
    end
end
function sendClientCommand(a, b, c, d)
    if _isPlayer(a) then
        table.insert(_sentClient, { target = a, mod = b, cmd = c, args = d })
    else
        table.insert(_sentClient, { target = nil, mod = a, cmd = b, args = c })
    end
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
            _alpha = 1.0, _outline = false,
            setName                      = function() end,
            setMaxHealth                 = function() end,
            setHealth                    = function() end,
            setCanPassThrough            = function() end,
            setBlockAllTheSquare         = function() end,
            setIsThumpable               = function() end,
            getModData                   = function(self) return self._modData end,
            getSquare                    = function(self) return self._sq end,
            transmitCompleteItemToClients = function() end,
            -- Visual state, recorded so tests can assert an uncamouflaged wire
            -- was actually made visible again rather than merely dropped from
            -- the camo index.
            setAlphaAndTarget    = function(self, a) self._alpha = a end,
            setOutlineHighlight  = function(self, v) self._outline = v end,
            -- The colour is recorded, not discarded: the owner outline is
            -- keyed by wire type so a perimeter of mixed wires is readable at
            -- a glance (#29), and "an outline appeared" would pass even if
            -- every type came out the same white.
            _outlineCol = nil,
            setOutlineHighlightCol = function(self, r, g, b, a)
                self._outlineCol = { r, g, b, a }
            end,
        }
        if sq then sq:AddSpecialObject(obj) end
        return obj
    end,
}

-----------------------------------------------------------------
-- ISBuildingObject stub
--
-- Enough of the vanilla base class for ISDeadwireTripLine to derive from it
-- and be constructed. derive() mirrors ISBaseObject: a fresh table whose
-- __index is the parent, so methods inherit and fields do not. The setters
-- record, because "did new() resolve a sprite for this wire type" is a thing
-- worth asserting.
-----------------------------------------------------------------
ISBuildingObject = {}

function ISBuildingObject:derive(name)
    local o = {}
    setmetatable(o, self)
    self.__index = self
    o.Type = name
    return o
end

function ISBuildingObject:init() end
function ISBuildingObject:setSprite(s) self.sprite = s end
function ISBuildingObject:setNorthSprite(s) self.northSprite = s end
function ISBuildingObject.render() end

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
-- PlayWorldSound is the audible clip a player hears, as opposed to
-- addSound above, which is the noise zombies path towards. They are different
-- systems and Deadwire calls both, so recording only one would have let a
-- silent wire pass a test named for its sound.
-- Real signature: PlayWorldSound(name, square, floor, radius, volume, doWorldSound)
local _worldSounds = {}
function getSoundManager()
    return {
        PlayWorldSound = function(_, name, sq, floor, radius, volume, doWorld)
            table.insert(_worldSounds, {
                name = name, sq = sq, radius = radius, volume = volume,
            })
        end
    }
end
function _getWorldSounds() return _worldSounds end
function _lastWorldSound() return _worldSounds[#_worldSounds] end
function _clearSounds() _soundCalls = {} end
function _getSoundCalls() return _soundCalls end

-----------------------------------------------------------------
-- Entity builders for detection tests
-----------------------------------------------------------------
-- Detection fires on a tile CROSSING, not on tile occupancy (#55), so a mock
-- that has never been anywhere cannot trigger anything: with no previous tile
-- there is no step, and with no step there is no edge to have broken. Every
-- mock therefore arrives from the tile directly north of it, which is the
-- ordinary case a test means when it says "a zombie on the wire tile".
-- _stepTo below is for tests that care which way it came from.
local function _seedArrival(modData, x, y, z)
    modData["dw_lastX"] = x
    modData["dw_lastY"] = y - 1
    modData["dw_lastZ"] = z
end

function _mockZombie(x, y, z, alive)
    local modData = {}
    _seedArrival(modData, x, y, z)
    local sq = _squares[x .. "," .. y .. "," .. z]
    local z_ = {
        _class      = "IsoZombie",
        _sq         = sq,
        _x = x, _y = y, _z = z,
        isAlive     = function() return alive ~= false end,
        getSquare   = function(self) return self._sq end,
        getModData  = function() return modData end,
        getUsername = function() return nil end,
        getX        = function(self) return self._x end,
        getY        = function(self) return self._y end,
        getZ        = function(self) return self._z end,

        -- Tanglefoot skips crawlers unless configured otherwise, and knocks the
        -- rest down. Standing by default; _mockCrawler below is the other case.
        _crawling    = false,
        _knockedDown = false,
        isCrawling   = function(self) return self._crawling end,
        knockDown    = function(self, _fall) self._knockedDown = true end,
    }
    return _placeOn(z_, x, y, z)
end

-- A zombie already on the floor. Tanglefoot leaves these alone unless
-- TanglefootAffectsCrawlers is on.
function _mockCrawler(x, y, z)
    local zed = _mockZombie(x, y, z)
    zed._crawling = true
    return zed
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
    -- Real ItemContainer:AddItem takes a fullType string and returns the item.
    -- The salvage path hands a kit straight back to the player who pulled a
    -- wire up, so this has to actually add rather than no-op.
    inv.AddItem = function(self, fullType)
        local item = { fullType = fullType }
        table.insert(self._items, item)
        return item
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
    _seedArrival(modData, x, y, z)
    local sq = _squares[x .. "," .. y .. "," .. z]
    local inv = _makeInventory()
    local p = {
        _class        = "IsoPlayer",
        _sq           = sq,
        _x = x, _y = y, _z = z,
        isAlive       = function() return true end,
        getSquare     = function(self) return self._sq end,
        getModData    = function() return modData end,
        getUsername   = function() return username or "testplayer" end,
        getInventory  = function() return inv end,
        isAccessLevel = function() return false end,
        getPlayerNum  = function() return 0 end,
        getRole       = function() return {
            hasCapability = function() return false end
        } end,

        -- Position. CamoVisibility floors these to pick the tiles in range, so
        -- a fractional coordinate is the honest shape; tests that care set _x
        -- directly.
        getX = function(self) return self._x end,
        getY = function(self) return self._y end,
        getZ = function(self) return self._z end,

        -- Skills. Level 0 unless a test says otherwise, and reading a perk this
        -- player has no entry for gives 0 rather than nil -- the real
        -- getPerkLevel does the same, which is precisely why Perks.Foraging
        -- being nil went unnoticed for so long (#17).
        _perkLevels  = {},
        getPerkLevel = function(self, perk) return self._perkLevels[perk] or 0 end,

        -- Tanglefoot's player branch: a stagger and optional foot damage.
        _bumpType = nil,
        _variables = {},
        setBumpType = function(self, t) self._bumpType = t end,
        setVariable = function(self, k, v) self._variables[k] = v end,
        _damage = {},
        getBodyDamage = function(self)
            local dmg = self._damage
            return {
                getBodyPart = function(_, partType)
                    return {
                        AddDamage = function(_, amount)
                            dmg[partType] = (dmg[partType] or 0) + amount
                        end,
                    }
                end,
            }
        end,

        -- Timed actions. Instant mode is a debug convenience in the real game
        -- and off here, so maxTime arrives as the caller passed it.
        isTimedActionInstant = function() return false end,
        _facing = nil,
        faceLocation = function(self, fx, fy) self._facing = { x = fx, y = fy } end,
    }
    return _placeOn(p, x, y, z)
end

-- Set a skill level on a mock player.
function _setPerk(player, perk, level) player._perkLevels[perk] = level end

-- How much damage a body part has taken, for the tanglefoot player branch.
function _getBodyPartDamage(player, partType) return player._damage[partType] or 0 end

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
-- Timed action queue
--
-- ISTimedActionQueue.add is called with dot syntax by UI.lua. Recording the
-- action rather than running it is the point: the assertion worth making is
-- "the right action, for the right tile, was queued", and running it here
-- would skip the walk the queue exists to wait for.
-----------------------------------------------------------------
_queuedActions = {}
ISTimedActionQueue = {
    add = function(action)
        table.insert(_queuedActions, action)
        return action
    end,
}
function _lastQueuedAction() return _queuedActions[#_queuedActions] end

-----------------------------------------------------------------
-- luautils.walkAdj
--
-- Real signature: luautils.walkAdj(character, square, toDoor) -> boolean, false
-- when no adjacent tile is reachable. Defaults to true, so a module that
-- forgets to check the result is still exercised on the path that matters; a
-- test that cares about the refusal calls _setWalkAdj(false) itself.
-----------------------------------------------------------------
local _walkAdjResult = true
_walkAdjCalls = {}
luautils = luautils or {}
luautils.walkAdj = function(character, square, toDoor)
    table.insert(_walkAdjCalls, {
        character = character, square = square, toDoor = toDoor,
    })
    return _walkAdjResult
end
function _setWalkAdj(v) _walkAdjResult = v and true or false end

-----------------------------------------------------------------
-- Context menu
--
-- Real ISContextMenu:addOption(name, target, onSelect, ...) returns the option
-- table, and addSubMenu(option, submenu) hangs a submenu off one. Options keep
-- their callback and arguments, so a test can assert what clicking the option
-- would actually do rather than only that a label appeared.
-----------------------------------------------------------------
function _makeContextMenu()
    local menu = { options = {}, subMenus = {} }
    menu.addOption = function(self, name, target, onSelect, ...)
        local opt = {
            name = name, target = target, onSelect = onSelect, args = { ... },
        }
        table.insert(self.options, opt)
        return opt
    end
    menu.addSubMenu = function(self, option, submenu)
        table.insert(self.subMenus, { option = option, menu = submenu })
    end
    return menu
end

ISContextMenu = {
    getNew = function(_, _parent) return _makeContextMenu() end,
}

-- Labels in order, for asserting which options a menu offered.
function _optionLabels(menu)
    local names = {}
    for _, opt in ipairs(menu.options) do table.insert(names, opt.name) end
    return names
end

-- Find an option by exact label. Returns nil when absent, which is the
-- assertion most of the UI tests are making.
function _findOption(menu, label)
    for _, opt in ipairs(menu.options) do
        if opt.name == label then return opt end
    end
    return nil
end

-- Run an option's callback the way the engine does:
-- onSelect(target, unpack(args)).
function _clickOption(opt)
    return opt.onSelect(opt.target, table.unpack(opt.args))
end

-- The submenu attached to a given parent option, or nil.
function _subMenuOf(menu, option)
    for _, entry in ipairs(menu.subMenus) do
        if entry.option == option then return entry.menu end
    end
    return nil
end

-----------------------------------------------------------------
-- Local player and admin status
--
-- getPlayer() is the local player; getSpecificPlayer(n) is the player behind a
-- given split-screen index. Both start nil: a module that reads one without a
-- test having set it gets nil and has to cope, which is what the real game
-- hands it before a player exists.
-----------------------------------------------------------------
local _localPlayer = nil
local _specificPlayers = {}
local _isAdmin = false

function getPlayer() return _localPlayer end
function getSpecificPlayer(playerNum) return _specificPlayers[playerNum or 0] end
function isAdmin() return _isAdmin end

function _setLocalPlayer(p) _localPlayer = p end
function _setSpecificPlayer(n, p) _specificPlayers[n] = p end
function _setAdmin(v) _isAdmin = v and true or false end

-----------------------------------------------------------------
-- Perks
--
-- PlantScavenging is the real 42.20 name for the skill shown in-game as
-- "Foraging". Perks.Foraging does not exist: reading it yields nil,
-- getPerkLevel(nil) returns 0, and every player sits permanently at level 0 --
-- which made camouflaged wires invisible to everyone (#17).
--
-- So this refuses any other key rather than answering it. verify_names.py is
-- the authority on which perk names the jar has; this table only makes the
-- absence loud instead of silent.
-----------------------------------------------------------------
local KNOWN_PERKS = { PlantScavenging = "PlantScavenging" }
Perks = setmetatable({}, {
    __index = function(_, k)
        if KNOWN_PERKS[k] then return KNOWN_PERKS[k] end
        error("Perks." .. tostring(k) .. " is not a perk name this game has.\n"
            .. "Reading it yields nil, getPerkLevel(nil) returns 0, and every\n"
            .. "player is silently level 0 forever (#17). Check the name with\n"
            .. "scripts/verify_names.py.", 2)
    end,
})

-----------------------------------------------------------------
-- BodyPartType
--
-- Only the member the mod uses, for the same reason Capability declares only
-- UseBuildCheat: a table that answers whatever it is asked cannot detect a
-- typo.
-----------------------------------------------------------------
BodyPartType = { Foot_L = "Foot_L" }

-----------------------------------------------------------------
-- Climate
--
-- getClimateManager():getRainIntensity() is the real path. The old code called
-- Climate.GetInstance():getRainStrength(), and no part of that exists in
-- 42.20, so weather never degraded camouflage once (#18). Starts dry, so a
-- test that wants rain has to say so.
-----------------------------------------------------------------
local _rainIntensity = 0
function getClimateManager()
    return { getRainIntensity = function() return _rainIntensity end }
end
function _setRainIntensity(v) _rainIntensity = v end

-----------------------------------------------------------------
-- ZombRand
--
-- Real ZombRand(n) returns an integer in [0, n-1]. Scripted rather than
-- random: a trip-chance test that rolls real dice proves nothing repeatable.
--
-- _setZombRand takes one value, or several that it then cycles through. The
-- sequence form is not a luxury: a stub that answers the same number forever
-- cannot tell one roll shared across a wire apart from one roll per part, and
-- it silently blessed exactly that bug in the salvage code.
--
-- A bound below 1 is refused rather than answered. The real ZombRand takes a
-- positive bound, and a negative one here always means a range was computed
-- backwards somewhere upstream -- which is a bug worth failing on, not one to
-- paper over with Lua's modulo happening to return 0.
-----------------------------------------------------------------
local _zombRandValues = { 0 }
local _zombRandIndex = 0

function ZombRand(n)
    if type(n) ~= "number" or n < 1 then
        error("ZombRand(" .. tostring(n) .. ") -- the real one takes a positive\n"
            .. "bound. A bound below 1 means a range was computed backwards\n"
            .. "before it got here.", 2)
    end
    _zombRandIndex = _zombRandIndex + 1
    local v = _zombRandValues[((_zombRandIndex - 1) % #_zombRandValues) + 1]
    return v % n
end

-- One value, or a sequence to cycle through on successive calls.
function _setZombRand(...)
    local vals = { ... }
    if #vals == 0 then vals = { 0 } end
    _zombRandValues = vals
    _zombRandIndex = 0
end

-----------------------------------------------------------------
-- ProceduralDistributions
--
-- Starts empty on purpose. LootDistribution warns loudly for a name that is
-- not there, and that warning is the behaviour worth testing, so the stub must
-- not invent tables. _addDistribution puts a real one in.
-----------------------------------------------------------------
ProceduralDistributions = { list = {} }
function _addDistribution(name)
    ProceduralDistributions.list[name] = { items = {} }
    return ProceduralDistributions.list[name]
end

-----------------------------------------------------------------
-- World objects for the context menu
--
-- OnFillWorldObjectContextMenu is handed a plain array of IsoObjects. UI.lua
-- walks it looking for the first one with a square, so the mock declares the
-- class instanceof() is asked about.
-----------------------------------------------------------------
function _mockWorldObject(sq)
    return {
        _class    = "IsoObject",
        _sq       = sq,
        getSquare = function(self) return self._sq end,
    }
end

-----------------------------------------------------------------
-- Global reset: call between test suites for clean slate
-----------------------------------------------------------------
function _reset()
    _isClient = false
    _worldAgeHours = 0
    _osTime = 0
    _squares = {}
    _modStore = {}
    _sentServer = {}
    _sentClient = {}
    _soundCalls = {}
    _factions = {}
    _worldSounds = {}
    _dragged = {}
    _queuedActions = {}
    _walkAdjCalls = {}
    _walkAdjResult = true
    _localPlayer = nil
    _specificPlayers = {}
    _isAdmin = false
    _rainIntensity = 0
    _zombRandValues = { 0 }
    _zombRandIndex = 0
    ProceduralDistributions.list = {}
    SandboxVars = { Deadwire = {} }
    -- Reset WireNetwork internal state (if loaded)
    if DeadwireNetwork then DeadwireNetwork.clear() end
end
