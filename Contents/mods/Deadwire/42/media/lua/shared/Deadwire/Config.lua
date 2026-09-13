-- Deadwire Config: Constants, wire type definitions, sandbox helpers
-- Shared: runs on both client and server

DeadwireConfig = DeadwireConfig or {}

-- Module name for MP commands
DeadwireConfig.MODULE = "Deadwire"

-- Debug mode (set true for development, false for release)
DeadwireConfig.DEBUG = false

-----------------------------------------------------------
-- Wire Types
-----------------------------------------------------------
DeadwireConfig.WireTypes = {
    TIN_CAN       = "tin_can_tripline",
    REINFORCED    = "reinforced_tripline",
    BELL          = "bell_tripline",
    TANGLEFOOT    = "tanglefoot",
    PULL_ALARM    = "pull_alarm",
    -- Tier 3a (#13) is the survivalist's half: a reinforced trip line with
    -- current in it. Named for what it is. The farmer's half (#52) is not a
    -- wire type at all -- it is a flag hung on a fence the game already built,
    -- so it never appears in this table.
    ELECTRIC      = "electric_tripline",
    ELECTRIC_BARBED = "electric_barbed",
}

-----------------------------------------------------------
-- Tier Definitions
-----------------------------------------------------------
DeadwireConfig.Tiers = {
    [0] = { "tin_can_tripline" },
    [1] = { "reinforced_tripline", "bell_tripline", "tanglefoot" },
    [2] = { "pull_alarm" },
    [3] = { "electric_tripline" },
    [4] = { "electric_barbed" },
}

-----------------------------------------------------------
-- Wire Property Defaults (overridden by SandboxVars)
--
-- cooldownSeconds is REAL seconds, not game time. See the cooldown section of
-- WireNetwork.lua for why (#16). Reinforced and Bell currently differ only in
-- sound clip and radius; the cooldown is the obvious lever to separate them
-- and is deliberately left equal pending a balance decision.
--
-- Every type declares it, including the ones that do not want one. The reader
-- used to fall back to `or 36`, so tanglefoot silently inherited the Tier 1
-- trip line cooldown and a horde walking into it got one 40 percent roll per
-- tile per 36 real seconds instead of a roll each (#37). A missing value now
-- logs. Tin can keeps 36 for when TinCanBreakOnTrigger is off, which is the
-- number it was already getting; changing it is a balance call, not this fix.
--
-- maxSpan and proneDuration used to sit in this table. Nothing read either one,
-- while the sandbox tooltips told server owners that lines "span up to 4 / 8
-- tiles" and that a tripped zombie stays down for three seconds. A wire is one
-- tile and knockDown(false) uses vanilla get-up timing. The text came down with
-- them; the behaviour is #45 (#38).
-----------------------------------------------------------
DeadwireConfig.WireDefaults = {
    tin_can_tripline = {
        health = 50,
        soundRadius = 25,
        soundVolume = 60,
        breakOnTrigger = true,
        cooldownSeconds = 36,   -- only reached with TinCanBreakOnTrigger off
        tier = 0,
    },
    reinforced_tripline = {
        health = 150,
        soundRadius = 40,
        soundVolume = 80,
        breakOnTrigger = false,
        cooldownSeconds = 36,
        tier = 1,
    },
    bell_tripline = {
        health = 150,
        soundRadius = 60,
        soundVolume = 80,
        breakOnTrigger = false,
        cooldownSeconds = 36,
        tier = 1,
    },
    tanglefoot = {
        health = 100,
        tripChance = 40,
        cooldownSeconds = 0,    -- no cooldown: every zombie entering gets a roll
        tier = 1,
    },
    -- Tier 3a (#13). Same shape as reinforced, because that is what it is when
    -- the power is off: a trip line you cross, not a barrier. The sound radius
    -- is deliberately the SMALLEST of the trip lines. A survivalist's wire is
    -- meant not to be found, and a loud one defeats it -- the opposite of the
    -- bell, and the opposite of the fence in #52.
    electric_tripline = {
        health = 150,
        soundRadius = 20,
        soundVolume = 50,
        breakOnTrigger = false,
        cooldownSeconds = 12,   -- a live wire re-arms far quicker than a bell
        tier = 3,
    },
}

-----------------------------------------------------------
-- Sprites (per wire type, from deadwire_01 tilesheet)
--
-- Indices follow the ALPHABETICAL order of the PNGs in media/textures/, which
-- is how pz_tilesheet.py globs them. Adding a sprite whose name sorts before
-- an existing one renumbers everything after it, silently. deadwire_01_2 and
-- _3 are the electric pair, banked for #13 and deliberately absent from this
-- table: both consumers (WireManager, BuildActions) do a keyed lookup, so a
-- packed sprite with no entry here is inert.
--
--   0/1 bell_e/bell_n      2/3 electric_e/electric_n   4/5 reinforced_e/_n
--   6/7 tanglefoot_e/_n    8/9 tincan_e/tincan_n
-----------------------------------------------------------
DeadwireConfig.Sprites = {
    bell_tripline       = { north = "deadwire_01_1", east = "deadwire_01_0" },
    electric_tripline   = { north = "deadwire_01_3", east = "deadwire_01_2" },
    reinforced_tripline = { north = "deadwire_01_5", east = "deadwire_01_4" },
    tanglefoot          = { north = "deadwire_01_7", east = "deadwire_01_6" },
    tin_can_tripline    = { north = "deadwire_01_9", east = "deadwire_01_8" },
}

-- There is deliberately no FALLBACK_SPRITE. It used to be
-- "construction_01_24", a vanilla metal wall frame, and it was unreachable:
-- createWire returns nil for any type without WireDefaults before it ever asks
-- for a sprite, all four real types have both sprites, and BuildActions only
-- ever sees the four the UI offers. A fallback around a name that might be a
-- typo is indistinguishable from a fallback around a real gap, which is rule 7
-- and has cost this project three features. A missing sprite now logs (#39).

-----------------------------------------------------------
-- Kit Items (wireType -> inventory item fullname)
-----------------------------------------------------------
DeadwireConfig.KitItems = {
    tin_can_tripline    = "Base.Deadwire_TinCanTripLineKit",
    reinforced_tripline = "Base.Deadwire_ReinforcedTripLineKit",
    bell_tripline       = "Base.Deadwire_BellTripLineKit",
    tanglefoot          = "Base.Deadwire_TanglefootKit",
    electric_tripline   = "Base.Deadwire_ElectricTripLineKit",
}

-----------------------------------------------------------
-- Salvage: what a destroyed wire leaves on the tile
--
-- A destroyed single-use wire used to leave nothing at all, which reads as a
-- bug rather than a mechanic (Rob, Session 23: "it just looks like a bug").
--
-- Only the durable parts are listed. The cord is what snapped -- that is why
-- the wire is destroyed -- so it never comes back. That is also why there is
-- no ambiguity here: the recipes accept any of fishing line, twine or electric
-- wire in that slot and the kit does not record which one the player used, so
-- a cord refund would have to invent an answer. The thing that broke is the
-- thing you do not get back.
--
-- Where a durable slot is still a choice (tanglefoot takes any of five
-- branch-like items), one canonical item stands in for the slot. TreeBranch2
-- is the real 42.20 name; Base.TreeBranch does not exist.
--
-- Deliberate removal does NOT use this table. It returns the whole kit,
-- because carefully picking your own wire back up should not be a gamble.
-- See the RemoveWire handler in ServerCommands.lua.
-----------------------------------------------------------
DeadwireConfig.Salvage = {
    tin_can_tripline = {
        { item = "Base.TinCanEmpty", count = 3 },
        { item = "Base.Nails",       count = 2 },
    },
    reinforced_tripline = {
        { item = "Base.Wire",        count = 1 },
        { item = "Base.TinCanEmpty", count = 3 },
        { item = "Base.Nails",       count = 2 },
    },
    bell_tripline = {
        { item = "Base.Wire",  count = 1 },
        { item = "Base.Bell",  count = 1 },
        { item = "Base.Nails", count = 2 },
    },
    tanglefoot = {
        { item = "Base.TreeBranch2", count = 3 },
        { item = "Base.Nails",       count = 2 },
    },
}

-- One roll per destroyed wire, applied to every slot in its salvage list.
-- 0 means the line was wrecked, 100 means it came apart cleanly and everything
-- durable survived. The default ceiling is deliberately below 100: a wire that
-- was destroyed by something walking into it should usually cost you
-- materials, or there is no reason to prefer picking it up by hand.
function DeadwireConfig.rollSalvagePercent()
    local minPct = DeadwireConfig.getSandbox("SalvageMinPercent", 0)
    local maxPct = DeadwireConfig.getSandbox("SalvageMaxPercent", 60)
    if maxPct < minPct then maxPct = minPct end
    return minPct + ZombRand(maxPct - minPct + 1)
end

-----------------------------------------------------------
-- Sound Names
-----------------------------------------------------------
DeadwireConfig.Sounds = {
    TIN_CAN_RATTLE   = "Deadwire_TinCanRattle",
    WIRE_RATTLE      = "Deadwire_WireRattle",
    BELL_RING        = "Deadwire_BellRing",
    ELEC_ZAP         = "Deadwire_ElecZap",
}

-- ALARM_BELL and CAR_HORN used to sit in that table for Phase 2's pull-alarms.
-- Neither had an ogg, a sound script block, or a single caller: three names for
-- sounds that could not play. A declared name for a thing that does not exist
-- is the shape rule 7 is about, so they are gone until the audio arrives with
-- the feature.

-----------------------------------------------------------
-- Sandbox Helpers
-----------------------------------------------------------

-- Get a SandboxVars.Deadwire value with fallback default
function DeadwireConfig.getSandbox(key, default)
    if SandboxVars and SandboxVars.Deadwire and SandboxVars.Deadwire[key] ~= nil then
        return SandboxVars.Deadwire[key]
    end
    return default
end

-- Per-type property overrides.
--
-- WireDefaults has always been commented "(overridden by SandboxVars)" but
-- nothing ever read these three options, so the server settings screen offered
-- players three knobs that did nothing at all. Each option's declared default
-- in sandbox-options.txt already matches the WireDefaults value it shadows.
--
-- Bell deliberately has no health option: the tooltip for ReinforcedHealth says
-- "reinforced trip lines", and inventing a second meaning for it would be worse
-- than the gap. Bell keeps the WireDefaults value.

local healthOptions = {
    tin_can_tripline    = "TripLineHealth",
    reinforced_tripline = "ReinforcedHealth",
}

function DeadwireConfig.getWireHealth(wireType)
    local defaults = DeadwireConfig.WireDefaults[wireType]
    local fallback = (defaults and defaults.health) or 50
    local key = healthOptions[wireType]
    if not key then return fallback end
    return DeadwireConfig.getSandbox(key, fallback)
end

function DeadwireConfig.breaksOnTrigger(wireType)
    local defaults = DeadwireConfig.WireDefaults[wireType]
    local fallback = (defaults and defaults.breakOnTrigger) or false
    if wireType == DeadwireConfig.WireTypes.TIN_CAN then
        return DeadwireConfig.getSandbox("TinCanBreakOnTrigger", fallback)
    end
    return fallback
end

-- Check if a tier is enabled
function DeadwireConfig.isTierEnabled(tier)
    if not DeadwireConfig.getSandbox("EnableMod", true) then
        return false
    end
    local keys = {
        [0] = "EnableTier0",
        [1] = "EnableTier1",
        [2] = "EnableTier2",
        [3] = "EnableTier3",
        [4] = "EnableTier4",
    }
    return DeadwireConfig.getSandbox(keys[tier], true)
end

-----------------------------------------------------------
-- Logging
-----------------------------------------------------------

function DeadwireConfig.debugLog(msg)
    if DeadwireConfig.DEBUG then
        print("[Deadwire] " .. tostring(msg))
    end
end

function DeadwireConfig.log(msg)
    print("[Deadwire] " .. tostring(msg))
end
