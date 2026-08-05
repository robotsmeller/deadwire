-- tests/test_config.lua
-- Tests for DeadwireConfig (Config.lua)
-- Modules are already require'd by run.lua. Stubs are already loaded.

suite("DeadwireConfig.getSandbox")

test("returns default when SandboxVars.Deadwire is empty", function()
    SandboxVars = { Deadwire = {} }
    assert_eq(DeadwireConfig.getSandbox("EnableMod", true), true)
    assert_eq(DeadwireConfig.getSandbox("SomeInt", 42), 42)
    assert_eq(DeadwireConfig.getSandbox("SomeStr", "hello"), "hello")
end)

test("returns value when SandboxVars.Deadwire[key] is set", function()
    SandboxVars = { Deadwire = { EnableMod = false, SoundRadius = 99 } }
    assert_eq(DeadwireConfig.getSandbox("EnableMod", true), false)
    assert_eq(DeadwireConfig.getSandbox("SoundRadius", 0), 99)
    SandboxVars = { Deadwire = {} }
end)

test("returns false (not default) when SandboxVars.Deadwire[key] is false", function()
    -- Verify that a stored false is returned, not the default true
    SandboxVars = { Deadwire = { EnableTier1 = false } }
    assert_eq(DeadwireConfig.getSandbox("EnableTier1", true), false)
    SandboxVars = { Deadwire = {} }
end)

test("returns default when SandboxVars is nil", function()
    SandboxVars = nil
    local result = DeadwireConfig.getSandbox("EnableMod", true)
    assert_eq(result, true)
    SandboxVars = { Deadwire = {} }
end)

test("returns default when SandboxVars.Deadwire is nil", function()
    SandboxVars = {}
    local result = DeadwireConfig.getSandbox("EnableMod", true)
    assert_eq(result, true)
    SandboxVars = { Deadwire = {} }
end)

test("default can be nil (returns nil when key absent)", function()
    SandboxVars = { Deadwire = {} }
    assert_nil(DeadwireConfig.getSandbox("NonExistentKey", nil))
end)


suite("DeadwireConfig.isTierEnabled")

test("tier 0 is enabled by default", function()
    SandboxVars = { Deadwire = {} }
    assert_true(DeadwireConfig.isTierEnabled(0))
end)

test("tier 1 is enabled by default", function()
    SandboxVars = { Deadwire = {} }
    assert_true(DeadwireConfig.isTierEnabled(1))
end)

test("tier 2 is enabled by default", function()
    SandboxVars = { Deadwire = {} }
    assert_true(DeadwireConfig.isTierEnabled(2))
end)

test("tier 3 is enabled by default", function()
    SandboxVars = { Deadwire = {} }
    assert_true(DeadwireConfig.isTierEnabled(3))
end)

test("tier 4 is enabled by default", function()
    SandboxVars = { Deadwire = {} }
    assert_true(DeadwireConfig.isTierEnabled(4))
end)

test("all tiers disabled when EnableMod = false", function()
    SandboxVars = { Deadwire = { EnableMod = false } }
    assert_false(DeadwireConfig.isTierEnabled(0), "tier 0 should be disabled")
    assert_false(DeadwireConfig.isTierEnabled(1), "tier 1 should be disabled")
    assert_false(DeadwireConfig.isTierEnabled(2), "tier 2 should be disabled")
    assert_false(DeadwireConfig.isTierEnabled(3), "tier 3 should be disabled")
    assert_false(DeadwireConfig.isTierEnabled(4), "tier 4 should be disabled")
    SandboxVars = { Deadwire = {} }
end)

test("tier 0 disabled individually via EnableTier0 = false", function()
    SandboxVars = { Deadwire = { EnableTier0 = false } }
    assert_false(DeadwireConfig.isTierEnabled(0))
    -- Other tiers unaffected
    assert_true(DeadwireConfig.isTierEnabled(1))
    SandboxVars = { Deadwire = {} }
end)

test("tier 1 disabled individually via EnableTier1 = false", function()
    SandboxVars = { Deadwire = { EnableTier1 = false } }
    assert_false(DeadwireConfig.isTierEnabled(1))
    assert_true(DeadwireConfig.isTierEnabled(0))
    SandboxVars = { Deadwire = {} }
end)

test("tier 2 disabled individually via EnableTier2 = false", function()
    SandboxVars = { Deadwire = { EnableTier2 = false } }
    assert_false(DeadwireConfig.isTierEnabled(2))
    assert_true(DeadwireConfig.isTierEnabled(1))
    SandboxVars = { Deadwire = {} }
end)

test("tier 3 disabled individually via EnableTier3 = false", function()
    SandboxVars = { Deadwire = { EnableTier3 = false } }
    assert_false(DeadwireConfig.isTierEnabled(3))
    assert_true(DeadwireConfig.isTierEnabled(2))
    SandboxVars = { Deadwire = {} }
end)

test("tier 4 disabled individually via EnableTier4 = false", function()
    SandboxVars = { Deadwire = { EnableTier4 = false } }
    assert_false(DeadwireConfig.isTierEnabled(4))
    assert_true(DeadwireConfig.isTierEnabled(3))
    SandboxVars = { Deadwire = {} }
end)

test("EnableMod = false overrides individual tier key set to true", function()
    -- Even if EnableTier0 = true, EnableMod = false wins
    SandboxVars = { Deadwire = { EnableMod = false, EnableTier0 = true } }
    assert_false(DeadwireConfig.isTierEnabled(0))
    SandboxVars = { Deadwire = {} }
end)


suite("DeadwireConfig.WireTypes")

test("WireTypes has exactly the 7 expected keys", function()
    local expected = { "TIN_CAN", "REINFORCED", "BELL", "TANGLEFOOT", "PULL_ALARM", "ELECTRIC", "ELECTRIC_BARBED" }
    for _, key in ipairs(expected) do
        assert_not_nil(DeadwireConfig.WireTypes[key], "missing WireTypes." .. key)
    end
    -- Count keys to confirm no extras
    local count = 0
    for _ in pairs(DeadwireConfig.WireTypes) do count = count + 1 end
    assert_eq(count, 7, "WireTypes key count")
end)

test("WireTypes values are non-empty strings", function()
    for k, v in pairs(DeadwireConfig.WireTypes) do
        assert_eq(type(v), "string", "WireTypes." .. k .. " should be a string")
        assert_true(#v > 0, "WireTypes." .. k .. " should be non-empty")
    end
end)

test("WireTypes.TIN_CAN value is tin_can_tripline", function()
    assert_eq(DeadwireConfig.WireTypes.TIN_CAN, "tin_can_tripline")
end)

test("WireTypes.REINFORCED value is reinforced_tripline", function()
    assert_eq(DeadwireConfig.WireTypes.REINFORCED, "reinforced_tripline")
end)

test("WireTypes.BELL value is bell_tripline", function()
    assert_eq(DeadwireConfig.WireTypes.BELL, "bell_tripline")
end)

test("WireTypes.TANGLEFOOT value is tanglefoot", function()
    assert_eq(DeadwireConfig.WireTypes.TANGLEFOOT, "tanglefoot")
end)


suite("DeadwireConfig.WireDefaults")

test("WireDefaults has entry for tin_can_tripline", function()
    assert_not_nil(DeadwireConfig.WireDefaults["tin_can_tripline"])
end)

test("WireDefaults has entry for reinforced_tripline", function()
    assert_not_nil(DeadwireConfig.WireDefaults["reinforced_tripline"])
end)

test("WireDefaults has entry for bell_tripline", function()
    assert_not_nil(DeadwireConfig.WireDefaults["bell_tripline"])
end)

test("WireDefaults has entry for tanglefoot", function()
    assert_not_nil(DeadwireConfig.WireDefaults["tanglefoot"])
end)

test("tin_can_tripline.breakOnTrigger is true", function()
    assert_true(DeadwireConfig.WireDefaults["tin_can_tripline"].breakOnTrigger,
        "tin_can_tripline breakOnTrigger should be true")
end)

test("reinforced_tripline.breakOnTrigger is false", function()
    assert_false(DeadwireConfig.WireDefaults["reinforced_tripline"].breakOnTrigger,
        "reinforced_tripline breakOnTrigger should be false")
end)

test("bell_tripline.breakOnTrigger is false", function()
    assert_false(DeadwireConfig.WireDefaults["bell_tripline"].breakOnTrigger,
        "bell_tripline breakOnTrigger should be false")
end)

test("tin_can_tripline has required numeric fields", function()
    local d = DeadwireConfig.WireDefaults["tin_can_tripline"]
    assert_not_nil(d.health, "health")
    assert_not_nil(d.maxSpan, "maxSpan")
    assert_not_nil(d.soundRadius, "soundRadius")
    assert_not_nil(d.soundVolume, "soundVolume")
    assert_not_nil(d.tier, "tier")
    assert_eq(d.tier, 0, "tin_can tier should be 0")
end)

test("reinforced_tripline has cooldownSeconds field", function()
    local d = DeadwireConfig.WireDefaults["reinforced_tripline"]
    assert_not_nil(d.cooldownSeconds, "cooldownSeconds")
    assert_gte(d.cooldownSeconds, 1, "cooldownSeconds should be positive")
end)

test("bell_tripline has cooldownSeconds field", function()
    local d = DeadwireConfig.WireDefaults["bell_tripline"]
    assert_not_nil(d.cooldownSeconds, "cooldownSeconds")
    assert_gte(d.cooldownSeconds, 1, "cooldownSeconds should be positive")
end)

test("tanglefoot has tripChance and proneDuration fields", function()
    local d = DeadwireConfig.WireDefaults["tanglefoot"]
    assert_not_nil(d.tripChance, "tripChance")
    assert_not_nil(d.proneDuration, "proneDuration")
end)

test("tanglefoot has tier 1", function()
    assert_eq(DeadwireConfig.WireDefaults["tanglefoot"].tier, 1)
end)

test("reinforced_tripline has tier 1", function()
    assert_eq(DeadwireConfig.WireDefaults["reinforced_tripline"].tier, 1)
end)


suite("DeadwireConfig.Tiers")

test("Tiers[0] contains tin_can_tripline", function()
    local found = false
    for _, v in ipairs(DeadwireConfig.Tiers[0]) do
        if v == "tin_can_tripline" then found = true end
    end
    assert_true(found, "Tiers[0] should contain tin_can_tripline")
end)

test("Tiers[1] contains reinforced_tripline, bell_tripline, tanglefoot", function()
    local set = {}
    for _, v in ipairs(DeadwireConfig.Tiers[1]) do set[v] = true end
    assert_true(set["reinforced_tripline"], "Tiers[1] missing reinforced_tripline")
    assert_true(set["bell_tripline"],       "Tiers[1] missing bell_tripline")
    assert_true(set["tanglefoot"],           "Tiers[1] missing tanglefoot")
end)


suite("DeadwireConfig logging")

test("debugLog does not throw when DEBUG is true", function()
    local prev = DeadwireConfig.DEBUG
    DeadwireConfig.DEBUG = true
    DeadwireConfig.debugLog("test message")
    DeadwireConfig.DEBUG = prev
end)

test("debugLog does not throw when DEBUG is false", function()
    local prev = DeadwireConfig.DEBUG
    DeadwireConfig.DEBUG = false
    DeadwireConfig.debugLog("silent message")
    DeadwireConfig.DEBUG = prev
end)

test("log does not throw", function()
    DeadwireConfig.log("log test message")
end)

test("debugLog handles non-string argument without throwing", function()
    local prev = DeadwireConfig.DEBUG
    DeadwireConfig.DEBUG = true
    DeadwireConfig.debugLog(12345)
    DeadwireConfig.debugLog(nil)
    DeadwireConfig.debugLog(true)
    DeadwireConfig.DEBUG = prev
end)


-----------------------------------------------------------------
-- Per-type SandboxVars overrides
--
-- These three options existed in sandbox-options.txt and were shown to players
-- on the server settings screen, but nothing in the mod ever read them, so
-- setting them did nothing. Regression tests for that.
-----------------------------------------------------------------

suite("DeadwireConfig.getWireHealth")

test("falls back to WireDefaults when the option is unset", function()
    _reset()
    assert_eq(DeadwireConfig.getWireHealth("tin_can_tripline"),
        DeadwireConfig.WireDefaults.tin_can_tripline.health)
    assert_eq(DeadwireConfig.getWireHealth("reinforced_tripline"),
        DeadwireConfig.WireDefaults.reinforced_tripline.health)
end)

test("TripLineHealth overrides tin can health", function()
    _reset()
    SandboxVars.Deadwire.TripLineHealth = 400
    assert_eq(DeadwireConfig.getWireHealth("tin_can_tripline"), 400)
end)

test("ReinforcedHealth overrides reinforced health", function()
    _reset()
    SandboxVars.Deadwire.ReinforcedHealth = 900
    assert_eq(DeadwireConfig.getWireHealth("reinforced_tripline"), 900)
end)

test("the two health options do not bleed into each other", function()
    _reset()
    SandboxVars.Deadwire.TripLineHealth = 400
    SandboxVars.Deadwire.ReinforcedHealth = 900
    assert_eq(DeadwireConfig.getWireHealth("tin_can_tripline"), 400)
    assert_eq(DeadwireConfig.getWireHealth("reinforced_tripline"), 900)
end)

test("bell is unaffected by ReinforcedHealth (no option of its own)", function()
    _reset()
    SandboxVars.Deadwire.ReinforcedHealth = 900
    assert_eq(DeadwireConfig.getWireHealth("bell_tripline"),
        DeadwireConfig.WireDefaults.bell_tripline.health)
end)

test("unknown wire type returns the 50 fallback without throwing", function()
    _reset()
    assert_eq(DeadwireConfig.getWireHealth("definitely_not_a_wire"), 50)
end)


suite("DeadwireConfig.breaksOnTrigger")

test("tin can breaks by default", function()
    _reset()
    assert_true(DeadwireConfig.breaksOnTrigger("tin_can_tripline"))
end)

test("TinCanBreakOnTrigger=false makes tin can reusable", function()
    _reset()
    SandboxVars.Deadwire.TinCanBreakOnTrigger = false
    assert_false(DeadwireConfig.breaksOnTrigger("tin_can_tripline"))
end)

test("reusable wires are unaffected by TinCanBreakOnTrigger", function()
    _reset()
    SandboxVars.Deadwire.TinCanBreakOnTrigger = true
    assert_false(DeadwireConfig.breaksOnTrigger("reinforced_tripline"))
    assert_false(DeadwireConfig.breaksOnTrigger("bell_tripline"))
end)

test("unknown wire type does not break and does not throw", function()
    _reset()
    assert_false(DeadwireConfig.breaksOnTrigger("definitely_not_a_wire"))
end)
