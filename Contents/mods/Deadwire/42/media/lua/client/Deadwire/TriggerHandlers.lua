-- Deadwire TriggerHandlers: Wire-type-specific trigger behavior
-- Client: registered with DeadwireDetection, called when entity steps on wire
--
-- Each handler:
--   1. Plays audible sound locally (immediate, works in SP)
--   2. Makes zombie-AI world sound (client-side)
--   3. Applies entity effects (knockdown, stumble)
--   4. Sends WireTriggered to server for state changes (break, cooldown, log)

require "Deadwire/Config"
require "Deadwire/WireNetwork"
require "Deadwire/Detection"
require "Deadwire/ClientCommands"
require "Deadwire/Power"
require "Deadwire/Shock"

-----------------------------------------------------------
-- Helpers
-----------------------------------------------------------

local function getSoundRadius(wireType)
    local defaults = DeadwireConfig.WireDefaults[wireType]
    local baseRadius = defaults and defaults.soundRadius or 25
    local multiplier = DeadwireConfig.getSandbox("SoundMultiplier", 1.0)
    return math.floor(baseRadius * multiplier)
end

local function getSoundVolume(wireType)
    local defaults = DeadwireConfig.WireDefaults[wireType]
    return defaults and defaults.soundVolume or 60
end

local function notifyServer(sq, wireType)
    local x, y, z = sq:getX(), sq:getY(), sq:getZ()
    DeadwireClientCommands.wireTriggered(x, y, z, wireType)
end

-----------------------------------------------------------
-- Tin Can Trip Line (Tier 0)
-- Single-use, rattling cans, moderate noise
-----------------------------------------------------------

local function tinCanZombieHandler(zombie, sq, wire)
    local x, y, z = sq:getX(), sq:getY(), sq:getZ()
    local radius = getSoundRadius(wire.wireType)
    local volume = getSoundVolume(wire.wireType)

    -- In SP play locally (no server broadcast). In MP the server broadcasts to all clients.
    if not isClient() then
        getSoundManager():PlayWorldSound(DeadwireConfig.Sounds.TIN_CAN_RATTLE, sq, 0, radius, 1.0, false)
    end

    -- Zombie-AI world sound (attracts nearby zombies, always local)
    getWorldSoundManager():addSound(nil, x, y, z, radius, volume, false)

    -- Server handles break + broadcast
    notifyServer(sq, wire.wireType)
end

local function tinCanPlayerHandler(player, sq, wire)
    local x, y, z = sq:getX(), sq:getY(), sq:getZ()
    local radius = getSoundRadius(wire.wireType)
    local volume = getSoundVolume(wire.wireType)

    if not isClient() then
        getSoundManager():PlayWorldSound(DeadwireConfig.Sounds.TIN_CAN_RATTLE, sq, 0, radius, 1.0, false)
    end
    getWorldSoundManager():addSound(nil, x, y, z, radius, volume, false)

    notifyServer(sq, wire.wireType)
end

-----------------------------------------------------------
-- Reinforced Trip Line (Tier 1)
-- Reusable, wire rattle, louder than tin cans
-----------------------------------------------------------

local function reinforcedZombieHandler(zombie, sq, wire)
    local x, y, z = sq:getX(), sq:getY(), sq:getZ()
    local radius = getSoundRadius(wire.wireType)
    local volume = getSoundVolume(wire.wireType)

    if not isClient() then
        getSoundManager():PlayWorldSound(DeadwireConfig.Sounds.WIRE_RATTLE, sq, 0, radius, 1.0, false)
    end
    getWorldSoundManager():addSound(nil, x, y, z, radius, volume, false)

    notifyServer(sq, wire.wireType)
end

local function reinforcedPlayerHandler(player, sq, wire)
    local x, y, z = sq:getX(), sq:getY(), sq:getZ()
    local radius = getSoundRadius(wire.wireType)
    local volume = getSoundVolume(wire.wireType)

    if not isClient() then
        getSoundManager():PlayWorldSound(DeadwireConfig.Sounds.WIRE_RATTLE, sq, 0, radius, 1.0, false)
    end
    getWorldSoundManager():addSound(nil, x, y, z, radius, volume, false)

    notifyServer(sq, wire.wireType)
end

-----------------------------------------------------------
-- Bell Trip Line (Tier 1)
-- Reusable, bell ring, loudest alarm wire
-----------------------------------------------------------

local function bellZombieHandler(zombie, sq, wire)
    local x, y, z = sq:getX(), sq:getY(), sq:getZ()
    local radius = getSoundRadius(wire.wireType)
    local volume = getSoundVolume(wire.wireType)

    if not isClient() then
        getSoundManager():PlayWorldSound(DeadwireConfig.Sounds.BELL_RING, sq, 0, radius, 1.0, false)
    end
    getWorldSoundManager():addSound(nil, x, y, z, radius, volume, false)

    notifyServer(sq, wire.wireType)
end

local function bellPlayerHandler(player, sq, wire)
    local x, y, z = sq:getX(), sq:getY(), sq:getZ()
    local radius = getSoundRadius(wire.wireType)
    local volume = getSoundVolume(wire.wireType)

    if not isClient() then
        getSoundManager():PlayWorldSound(DeadwireConfig.Sounds.BELL_RING, sq, 0, radius, 1.0, false)
    end
    getWorldSoundManager():addSound(nil, x, y, z, radius, volume, false)

    notifyServer(sq, wire.wireType)
end

-----------------------------------------------------------
-- Tanglefoot (Tier 1)
-- Silent area denial. Trips zombies prone, stumbles players.
-----------------------------------------------------------

local function tanglefootZombieHandler(zombie, sq, wire)
    local tripChance = DeadwireConfig.getSandbox("TanglefootTripChance",
        DeadwireConfig.WireDefaults.tanglefoot.tripChance)

    -- Skip crawlers unless configured to affect them
    if zombie:isCrawling() and not DeadwireConfig.getSandbox("TanglefootAffectsCrawlers", false) then
        return
    end

    -- Roll trip chance
    if ZombRand(100) < tripChance then
        zombie:knockDown(false)
        DeadwireConfig.debugLog("Tanglefoot tripped zombie at " .. sq:getX() .. "," .. sq:getY())
    end

    -- Silent trap, so nothing is broadcast for sound. This told the server to
    -- degrade tanglefoot durability, which the server has never done: it
    -- degrades camouflage and logs the trigger, and that is all. Tanglefoot
    -- wear is #45 (#38).
    notifyServer(sq, wire.wireType)
end

local function tanglefootPlayerHandler(player, sq, wire)
    -- Players stumble (brief movement penalty) if enabled
    if DeadwireConfig.getSandbox("PlayerTripStumble", true) then
        player:setBumpType("stagger")
        player:setVariable("BumpDone", false)
        player:setVariable("BumpFall", true)
        player:setVariable("BumpFallType", "pushedFront")
        DeadwireConfig.debugLog("Tanglefoot stumbled player at " .. sq:getX() .. "," .. sq:getY())
    end

    -- Optional damage
    local damage = DeadwireConfig.getSandbox("PlayerTripDamage", 5)
    if damage > 0 then
        local bodyDamage = player:getBodyDamage()
        if bodyDamage then
            local part = bodyDamage:getBodyPart(BodyPartType.Foot_L)
            if part then
                part:AddDamage(damage)
            end
        end
    end

    notifyServer(sq, wire.wireType)
end

-----------------------------------------------------------
-- Electrified Deadwire (Tier 3a, #13)
--
-- The survivalist's half. A reinforced trip line with current in it, and the
-- opposite of the fence next door in intent: a pasture fence works by being
-- seen, this one works by being stepped into before you knew it was there.
-- Hence the smallest sound radius of any trip line, and hence camouflage
-- mattering more here than anywhere else in the mod.
--
-- Unpowered, it is a reinforced trip line and nothing else -- it rattles and
-- does no damage. That is on purpose (#13): a survivalist whose generator ran
-- dry still has a perimeter alarm, rather than a wire that silently does
-- nothing at the moment it matters most.
-----------------------------------------------------------

local function electricRattle(sq, wire)
    local x, y, z = sq:getX(), sq:getY(), sq:getZ()
    local radius = getSoundRadius(wire.wireType)
    local volume = getSoundVolume(wire.wireType)

    if not isClient() then
        getSoundManager():PlayWorldSound(DeadwireConfig.Sounds.WIRE_RATTLE, sq, 0, radius, 1.0, false)
    end
    getWorldSoundManager():addSound(nil, x, y, z, radius, volume, false)
end

local function electricZap(sq, wire)
    local x, y, z = sq:getX(), sq:getY(), sq:getZ()
    local radius = getSoundRadius(wire.wireType)
    local volume = getSoundVolume(wire.wireType)

    if not isClient() then
        getSoundManager():PlayWorldSound(DeadwireConfig.Sounds.ELEC_ZAP, sq, 0, radius, 1.0, false)
    end
    getWorldSoundManager():addSound(nil, x, y, z, radius, volume, false)
end

local function electricZombieHandler(zombie, sq, wire)
    if DeadwirePower.isCircuitLive(sq:getX(), sq:getY(), sq:getZ()) then
        electricZap(sq, wire)
        DeadwireShock.shockZombie(zombie, sq)
    else
        electricRattle(sq, wire)
    end

    notifyServer(sq, wire.wireType)
end

local function electricPlayerHandler(player, sq, wire)
    if DeadwirePower.isCircuitLive(sq:getX(), sq:getY(), sq:getZ()) then
        electricZap(sq, wire)
        DeadwireShock.shockPlayer(player, sq)
    else
        electricRattle(sq, wire)
    end

    notifyServer(sq, wire.wireType)
end

-----------------------------------------------------------
-- Register All Handlers
-----------------------------------------------------------

DeadwireDetection.registerZombieHandler("tin_can_tripline", tinCanZombieHandler)
DeadwireDetection.registerPlayerHandler("tin_can_tripline", tinCanPlayerHandler)

DeadwireDetection.registerZombieHandler("reinforced_tripline", reinforcedZombieHandler)
DeadwireDetection.registerPlayerHandler("reinforced_tripline", reinforcedPlayerHandler)

DeadwireDetection.registerZombieHandler("bell_tripline", bellZombieHandler)
DeadwireDetection.registerPlayerHandler("bell_tripline", bellPlayerHandler)

DeadwireDetection.registerZombieHandler("tanglefoot", tanglefootZombieHandler)
DeadwireDetection.registerPlayerHandler("tanglefoot", tanglefootPlayerHandler)

DeadwireDetection.registerZombieHandler("electric_tripline", electricZombieHandler)
DeadwireDetection.registerPlayerHandler("electric_tripline", electricPlayerHandler)

DeadwireConfig.log("TriggerHandlers initialized (client)")
