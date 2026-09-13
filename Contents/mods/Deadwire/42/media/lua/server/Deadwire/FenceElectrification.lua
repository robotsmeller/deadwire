-- Deadwire FenceElectrification: the farmer's half of Tier 3 (#52).
--
-- Electrify a fence the game already built, rather than placing a wire. The
-- opposite of the deadwire next door in every way that matters: a pasture
-- fence is MEANT to be seen, because the animal learns the line and then stays
-- off it, and the deterrent is that it is obvious. So it is permanent, it is
-- visible, and camouflage deliberately does not apply to it at all.
--
-- Lives in server/ for load order, and guards with isClient() rather than
-- relying on the directory, per key rule 10.
--
-- WHY THE FENCE LIST IS OURS AND NOT THE FENCE'S
--
-- #52 proposed hanging modData on the fence object. That object is the game's,
-- not ours, and whether our modData survives a save and reload on a foreign
-- object is the "unverified and load-bearing" risk the issue itself flags: if
-- it does not, the feature needs a different attachment model entirely.
--
-- So the list of electrified fences is kept in OUR GlobalModData, the same
-- place the wires already persist to and the one thing here that is known to
-- survive a reload. The object's own modData is still stamped, but only as a
-- convenience flag for the context menu -- nothing reads it to decide whether
-- a fence is live. That turns a load-bearing unknown into a cosmetic one.
--
-- THE 50% ROLL IS NOT A FUDGE FACTOR. A real energiser pulses on a clock,
-- about once a second, not on contact. Whether something gets bitten is
-- whether it was touching the wire when the pulse arrived, so the roll IS the
-- pulse timing. A cow learns and stays off; a zombie does not learn, which is
-- the whole fantasy.

require "Deadwire/Config"
require "Deadwire/Power"
require "Deadwire/Shock"

if isClient() then return end

DeadwireFences = DeadwireFences or {}

local SAVE_KEY = "DeadwireFences"

-- ~1s at 60fps, the same throttle CamoVisibility already uses. Cost scales
-- with fence length times pulse rate, NOT with zombie count times tick rate,
-- which is the inversion #52 is built on: polling adjacency on the zombie tick
-- is exactly what the #30 review said never to do.
local TICK_INTERVAL = 60
local tickCounter = 0

-----------------------------------------------------------
-- The register of live fences
-----------------------------------------------------------

local function store()
    return ModData.getOrCreate(SAVE_KEY)
end

function DeadwireFences.fenceKey(x, y, z)
    return math.floor(x) .. "," .. math.floor(y) .. "," .. math.floor(z)
end

function DeadwireFences.isElectrified(x, y, z)
    return store()[DeadwireFences.fenceKey(x, y, z)] ~= nil
end

function DeadwireFences.all()
    return store()
end

-- A fence is any IsoThumpable on the square that is not one of ours. Ours
-- carry dw_type, and electrifying our own trip line is what #13 is for.
function DeadwireFences.findFence(sq)
    if not sq then return nil end
    local objs = sq:getSpecialObjects()
    if not objs then return nil end
    for i = 0, objs:size() - 1 do
        local o = objs:get(i)
        if o and instanceof(o, "IsoThumpable") then
            local data = o:getModData()
            if not (data and data["dw_type"]) then
                return o
            end
        end
    end
    return nil
end

function DeadwireFences.electrify(sq, ownerId)
    if not sq then return false, "no square" end
    local fence = DeadwireFences.findFence(sq)
    if not fence then return false, "no fence here" end

    local x, y, z = sq:getX(), sq:getY(), sq:getZ()
    local id = DeadwireFences.fenceKey(x, y, z)
    if store()[id] then return false, "already electrified" end

    store()[id] = {
        x = x, y = y, z = z,
        ownerId = ownerId,
        north = fence.getNorth and fence:getNorth() or nil,
    }

    -- Convenience flag only. Nothing reads this to decide whether the fence is
    -- live; see the header for why.
    local data = fence:getModData()
    if data then data["dw_electrified"] = true end

    DeadwirePower.adjustGeneratorDraw(sq, DeadwirePower.drawPerCircuit())
    DeadwireConfig.log("Fence electrified at " .. id .. " by " .. tostring(ownerId))
    return true
end

function DeadwireFences.deElectrify(sq)
    if not sq then return false, "no square" end
    local x, y, z = sq:getX(), sq:getY(), sq:getZ()
    local id = DeadwireFences.fenceKey(x, y, z)
    if not store()[id] then return false, "not electrified" end

    store()[id] = nil

    local fence = DeadwireFences.findFence(sq)
    if fence then
        local data = fence:getModData()
        if data then data["dw_electrified"] = nil end
    end

    DeadwirePower.adjustGeneratorDraw(sq, -DeadwirePower.drawPerCircuit())
    DeadwireConfig.log("Fence de-electrified at " .. id)
    return true
end

-----------------------------------------------------------
-- The pulse
-----------------------------------------------------------

-- Everything standing against this fence. A fence is a barrier, so nothing
-- ever stands ON its tile -- the bodies are on the squares either side of the
-- edge it occupies, plus its own square for the vault case, where a zombie
-- crossing may pass through the fence's square and be caught for free.
local function bodiesTouching(cell, x, y, z)
    local found = {}
    local offsets = { {0,0}, {1,0}, {-1,0}, {0,1}, {0,-1} }
    for _, off in ipairs(offsets) do
        local sq = cell:getGridSquare(x + off[1], y + off[2], z)
        if sq then
            local movers = sq:getMovingObjects()
            if movers then
                for i = 0, movers:size() - 1 do
                    local m = movers:get(i)
                    if m then table.insert(found, m) end
                end
            end
        end
    end
    return found
end

function DeadwireFences.pulseOne(cell, entry)
    local sq = cell:getGridSquare(entry.x, entry.y, entry.z)
    if not sq then return 0 end
    if not DeadwirePower.isSquareLive(sq) then return 0 end

    local pulseChance = DeadwireConfig.getSandbox("FencePulseChance", 50)
    local breakChance = DeadwireConfig.getSandbox("FenceBreakChance", 2)
    local hits = 0

    for _, body in ipairs(bodiesTouching(cell, entry.x, entry.y, entry.z)) do
        -- The roll is the pulse arriving, so it is rolled per body per pulse.
        if ZombRand(100) < pulseChance then
            if instanceof(body, "IsoZombie") then
                if body:isAlive() then
                    DeadwireShock.shockZombie(body, sq)
                    hits = hits + 1
                end
            elseif instanceof(body, "IsoPlayer") then
                if not DeadwireConfig.getSandbox("WireOwnerImmunity", false)
                    or entry.ownerId ~= body:getUsername()
                then
                    DeadwireShock.shockPlayer(body, sq)
                    hits = hits + 1
                end
            end
        end
    end

    if hits > 0 then
        getWorldSoundManager():addSound(nil, entry.x, entry.y, entry.z, 20, 40, false)
        sendServerCommand(DeadwireConfig.MODULE, "FencePulse", {
            x = entry.x, y = entry.y, z = entry.z,
            soundName = DeadwireConfig.Sounds.ELEC_ZAP,
        })

        -- A fence already has deflection and cover built into it in a way a
        -- bare wire does not, so electrifying it must not blow up the thing it
        -- is attached to. Deliberately a number, not a mechanism.
        if breakChance > 0 and ZombRand(100) < breakChance then
            DeadwireFences.deElectrify(sq)
            DeadwireConfig.log("Fence electrification burned out at "
                .. DeadwireFences.fenceKey(entry.x, entry.y, entry.z))
        end
    end

    return hits
end

function DeadwireFences.pulseAll()
    if not DeadwireConfig.isTierEnabled(3) then return 0 end
    local cell = getWorld() and getWorld():getCell() or nil
    if not cell then return 0 end

    local total = 0
    -- Copied to a list first: pulseOne can de-electrify a fence, and mutating
    -- the table being walked is how you skip entries at random.
    local entries = {}
    for _, entry in pairs(store()) do table.insert(entries, entry) end
    for _, entry in ipairs(entries) do
        total = total + DeadwireFences.pulseOne(cell, entry)
    end
    return total
end

local function onTick()
    tickCounter = tickCounter + 1
    if tickCounter < TICK_INTERVAL then return end
    tickCounter = 0
    DeadwireFences.pulseAll()
end

Events.OnTick.Add(onTick)
DeadwireConfig.log("FenceElectrification initialized (server)")
