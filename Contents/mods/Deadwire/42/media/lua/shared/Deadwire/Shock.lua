-- Deadwire Shock: what a live wire does to whatever touched it.
-- Shared, because the trip line (#13) and the fence (#52) do the same thing to
-- a body and differ only in what put the body there.
--
-- THERE IS NO ELECTROCUTION SYSTEM IN THE GAME. Zero classes in the 42.20 jar
-- contain the string "electrocut": no damage type, no status effect, no
-- moodle, no death cause. Everything below is assembled out of primitives that
-- do exist, each one checked against the jar before it was written here:
--
--   IsoZombie:knockDown(boolean)        IsoZombie:setStaggerBack(boolean)
--   IsoZombie:Kill(IsoGameCharacter)    BodyPart:AddDamage(float)
--   BodyDamage:IncreasePanic(int)       IsoPlayer:setBumpType(String)
--   IsoGameCharacter:setVariable(String, String)
--
-- Rob's spec for a player, session 28: damage, fall back, stunned, and an
-- anxious moodle for a while. PZ has no player stun and no moodle named
-- "anxious"; the knockdown IS the stun, and Panic is the moodle that reads as
-- anxiety. Panic decays on its own, so the amount set is also the duration --
-- which is why ShockPanic is one number and not two.

require "Deadwire/Config"

DeadwireShock = DeadwireShock or {}

-- Feet and lower legs. A trip line is at shin height and a fence is waist
-- height on a body that walked into it, so the current goes through the legs.
-- Picked at random rather than always the left foot, which is what the
-- tanglefoot handler does and which means a player limps on exactly one side
-- forever no matter how they were hurt.
local SHOCK_PARTS = {
    "Foot_L", "Foot_R", "LowerLeg_L", "LowerLeg_R",
}

function DeadwireShock.pickBodyPart()
    return SHOCK_PARTS[ZombRand(#SHOCK_PARTS) + 1]
end

-----------------------------------------------------------
-- Players
-----------------------------------------------------------

function DeadwireShock.shockPlayer(player, sq)
    if not player then return false end

    local damage = DeadwireConfig.getSandbox("ShockPlayerDamage", 15)
    local panic = DeadwireConfig.getSandbox("ShockPanic", 35)

    -- Damage: one leg or foot, not always the same one.
    if damage > 0 then
        local bodyDamage = player:getBodyDamage()
        if bodyDamage then
            local partName = DeadwireShock.pickBodyPart()
            local part = bodyDamage:getBodyPart(BodyPartType[partName])
            if part then
                part:AddDamage(damage)
            end
        end
    end

    -- Thrown back and put down. setBumpType plus the three Bump variables is
    -- the same sequence the tanglefoot handler uses for a stumble; the
    -- difference here is pushedBack rather than pushedFront, because you do
    -- not fall towards a thing that just threw you off it.
    player:setBumpType("stagger")
    player:setVariable("BumpDone", false)
    player:setVariable("BumpFall", true)
    player:setVariable("BumpFallType", "pushedBack")

    -- The anxious moodle. IncreasePanic takes an int and the level decays by
    -- itself, so this is both "how bad" and "how long".
    if panic > 0 then
        local bodyDamage = player:getBodyDamage()
        if bodyDamage then
            bodyDamage:IncreasePanic(panic)
        end
    end

    DeadwireConfig.debugLog("Shocked player for " .. damage .. " damage, panic +" .. panic)
    return true
end

-----------------------------------------------------------
-- Zombies
-----------------------------------------------------------

-- Returns "killed", "downed" or "staggered", so a caller can report what
-- actually happened rather than what it asked for.
function DeadwireShock.shockZombie(zombie, sq)
    if not zombie then return nil end

    local killChance = DeadwireConfig.getSandbox("ShockZombieKillChance", 25)

    if killChance > 0 and ZombRand(100) < killChance then
        zombie:Kill(nil)
        DeadwireConfig.debugLog("Shock killed a zombie")
        return "killed"
    end

    zombie:setStaggerBack(true)
    zombie:knockDown(false)
    DeadwireConfig.debugLog("Shock put a zombie down")
    return "downed"
end

DeadwireConfig.debugLog("Shock initialized")
