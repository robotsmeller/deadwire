-- tests/test_detection.lua
-- Tests for Detection.lua (DeadwireDetection)
-- Modules are already require'd by run.lua. Stubs are already loaded.
--
-- Detection fires through Events.OnZombieUpdate / Events.OnPlayerUpdate.
-- We replace DeadwireDetection.zombieHandlers / .playerHandlers per-test
-- to track dispatch, and use _getSoundCalls() to detect the fallback path.

suite("Detection: zombie on wire tile")

test("zombie on registered wire tile calls registered handler", function()
    _reset()
    local sq = _makeSquare(10, 20, 0)
    DeadwireNetwork.registerTile(10, 20, 0, 1, "tin_can_tripline", "alice")

    local called = false
    DeadwireDetection.zombieHandlers["tin_can_tripline"] = function(entity, square, wire)
        called = true
    end

    local zombie = _mockZombie(10, 20, 0)
    Events.OnZombieUpdate:Fire(zombie)

    assert_true(called, "zombie handler should have been called")

    DeadwireDetection.zombieHandlers["tin_can_tripline"] = nil
end)

test("zombie on empty tile does not call handler", function()
    _reset()
    _makeSquare(10, 20, 0)
    -- No wire registered at (10,20,0)

    local called = false
    DeadwireDetection.zombieHandlers["tin_can_tripline"] = function()
        called = true
    end

    local zombie = _mockZombie(10, 20, 0)
    Events.OnZombieUpdate:Fire(zombie)

    assert_false(called, "handler should NOT be called for empty tile")

    DeadwireDetection.zombieHandlers["tin_can_tripline"] = nil
end)

test("dead zombie on wire tile does not call handler", function()
    _reset()
    local sq = _makeSquare(10, 20, 0)
    DeadwireNetwork.registerTile(10, 20, 0, 1, "tin_can_tripline", "alice")

    local called = false
    DeadwireDetection.zombieHandlers["tin_can_tripline"] = function()
        called = true
    end

    local zombie = _mockZombie(10, 20, 0, false)  -- alive = false
    Events.OnZombieUpdate:Fire(zombie)

    assert_false(called, "dead zombie should not trigger wire")

    DeadwireDetection.zombieHandlers["tin_can_tripline"] = nil
end)


suite("Detection: player on wire tile")

test("player on registered wire tile calls registered handler", function()
    _reset()
    local sq = _makeSquare(5, 5, 0)
    DeadwireNetwork.registerTile(5, 5, 0, 1, "reinforced_tripline", "alice")

    local called = false
    DeadwireDetection.playerHandlers["reinforced_tripline"] = function(entity, square, wire)
        called = true
    end

    local player = _mockPlayer(5, 5, 0, "bob")
    Events.OnPlayerUpdate:Fire(player)

    assert_true(called, "player handler should have been called")

    DeadwireDetection.playerHandlers["reinforced_tripline"] = nil
end)

test("player on empty tile does not call handler", function()
    _reset()
    _makeSquare(5, 5, 0)
    -- No wire at (5,5,0)

    local called = false
    DeadwireDetection.playerHandlers["reinforced_tripline"] = function()
        called = true
    end

    local player = _mockPlayer(5, 5, 0, "bob")
    Events.OnPlayerUpdate:Fire(player)

    assert_false(called, "handler should NOT be called for empty tile")

    DeadwireDetection.playerHandlers["reinforced_tripline"] = nil
end)


suite("Detection: fallback sound")

test("no registered handler for wire type triggers fallback addSound", function()
    _reset()
    _clearSounds()
    local sq = _makeSquare(3, 3, 0)
    DeadwireNetwork.registerTile(3, 3, 0, 1, "bell_tripline", "alice")

    -- Ensure no handler is registered for this type
    DeadwireDetection.zombieHandlers["bell_tripline"] = nil

    local zombie = _mockZombie(3, 3, 0)
    Events.OnZombieUpdate:Fire(zombie)

    local sounds = _getSoundCalls()
    assert_gte(#sounds, 1, "fallback addSound should have been called")
    assert_eq(sounds[1].x, 3)
    assert_eq(sounds[1].y, 3)
    assert_eq(sounds[1].z, 0)
end)


suite("Detection: deduplication")

test("same zombie on same tile at same world time triggers handler only once", function()
    _reset()
    _setOsTime(1000000)
    local sq = _makeSquare(7, 7, 0)
    DeadwireNetwork.registerTile(7, 7, 0, 1, "tin_can_tripline", "alice")

    local count = 0
    DeadwireDetection.zombieHandlers["tin_can_tripline"] = function()
        count = count + 1
    end

    -- os.time stays at 1000000 for both fires (dedup blocks second)
    local zombie = _mockZombie(7, 7, 0)
    Events.OnZombieUpdate:Fire(zombie)
    Events.OnZombieUpdate:Fire(zombie)

    assert_eq(count, 1, "handler should be called exactly once (dedup)")

    DeadwireDetection.zombieHandlers["tin_can_tripline"] = nil
end)

test("same zombie triggers wire again after 2 seconds have passed", function()
    _reset()
    _setOsTime(1000000)
    local sq = _makeSquare(7, 7, 0)
    DeadwireNetwork.registerTile(7, 7, 0, 1, "tin_can_tripline", "alice")

    local count = 0
    DeadwireDetection.zombieHandlers["tin_can_tripline"] = function()
        count = count + 1
    end

    local zombie = _mockZombie(7, 7, 0)
    Events.OnZombieUpdate:Fire(zombie)
    assert_eq(count, 1, "first trigger should fire")

    -- Advance os.time by 2 real seconds — past the 1-second dedup window
    _setOsTime(1000002)
    Events.OnZombieUpdate:Fire(zombie)
    assert_eq(count, 2, "second trigger should fire after dedup window expires")

    DeadwireDetection.zombieHandlers["tin_can_tripline"] = nil
end)


suite("Detection: cooldown")

test("wire on cooldown prevents handler from firing", function()
    _reset()
    local sq = _makeSquare(8, 8, 0)
    DeadwireNetwork.registerTile(8, 8, 0, 1, "reinforced_tripline", "alice")

    -- Set cooldown that expires far in the future (1 hour from now)
    _setWorldAge(0)
    DeadwireNetwork.setCooldown(8, 8, 0, 1.0)

    local called = false
    DeadwireDetection.zombieHandlers["reinforced_tripline"] = function()
        called = true
    end

    local zombie = _mockZombie(8, 8, 0)
    Events.OnZombieUpdate:Fire(zombie)

    assert_false(called, "handler should NOT fire when wire is on cooldown")

    DeadwireDetection.zombieHandlers["reinforced_tripline"] = nil
end)


suite("Detection: sandbox flags")

test("EnableMod = false prevents zombie trigger", function()
    _reset()
    local sq = _makeSquare(1, 1, 0)
    DeadwireNetwork.registerTile(1, 1, 0, 1, "tin_can_tripline", "alice")
    SandboxVars.Deadwire.EnableMod = false

    local called = false
    DeadwireDetection.zombieHandlers["tin_can_tripline"] = function()
        called = true
    end

    local zombie = _mockZombie(1, 1, 0)
    Events.OnZombieUpdate:Fire(zombie)

    assert_false(called, "zombie handler should not fire when EnableMod = false")

    DeadwireDetection.zombieHandlers["tin_can_tripline"] = nil
end)

test("EnableMod = false prevents player trigger", function()
    _reset()
    local sq = _makeSquare(1, 1, 0)
    DeadwireNetwork.registerTile(1, 1, 0, 1, "tin_can_tripline", "alice")
    SandboxVars.Deadwire.EnableMod = false

    local called = false
    DeadwireDetection.playerHandlers["tin_can_tripline"] = function()
        called = true
    end

    local player = _mockPlayer(1, 1, 0, "bob")
    Events.OnPlayerUpdate:Fire(player)

    assert_false(called, "player handler should not fire when EnableMod = false")

    DeadwireDetection.playerHandlers["tin_can_tripline"] = nil
end)

test("WireAffectsZombies = false prevents zombie trigger", function()
    _reset()
    local sq = _makeSquare(2, 2, 0)
    DeadwireNetwork.registerTile(2, 2, 0, 1, "tin_can_tripline", "alice")
    SandboxVars.Deadwire.WireAffectsZombies = false

    local called = false
    DeadwireDetection.zombieHandlers["tin_can_tripline"] = function()
        called = true
    end

    local zombie = _mockZombie(2, 2, 0)
    Events.OnZombieUpdate:Fire(zombie)

    assert_false(called, "zombie should not trigger when WireAffectsZombies = false")

    DeadwireDetection.zombieHandlers["tin_can_tripline"] = nil
end)

test("WireAffectsPlayers = false prevents player trigger", function()
    _reset()
    local sq = _makeSquare(2, 2, 0)
    DeadwireNetwork.registerTile(2, 2, 0, 1, "tin_can_tripline", "alice")
    SandboxVars.Deadwire.WireAffectsPlayers = false

    local called = false
    DeadwireDetection.playerHandlers["tin_can_tripline"] = function()
        called = true
    end

    local player = _mockPlayer(2, 2, 0, "bob")
    Events.OnPlayerUpdate:Fire(player)

    assert_false(called, "player should not trigger when WireAffectsPlayers = false")

    DeadwireDetection.playerHandlers["tin_can_tripline"] = nil
end)

test("EnableTier0 = false prevents tin_can_tripline trigger", function()
    _reset()
    local sq = _makeSquare(3, 3, 0)
    DeadwireNetwork.registerTile(3, 3, 0, 1, "tin_can_tripline", "alice")
    SandboxVars.Deadwire.EnableTier0 = false

    local called = false
    DeadwireDetection.zombieHandlers["tin_can_tripline"] = function()
        called = true
    end

    local zombie = _mockZombie(3, 3, 0)
    Events.OnZombieUpdate:Fire(zombie)

    assert_false(called, "tier 0 wire should not trigger when EnableTier0 = false")

    DeadwireDetection.zombieHandlers["tin_can_tripline"] = nil
end)


suite("Detection: owner immunity")

test("WireOwnerImmunity = true, player is owner, no trigger", function()
    _reset()
    local sq = _makeSquare(4, 4, 0)
    DeadwireNetwork.registerTile(4, 4, 0, 1, "tin_can_tripline", "alice")
    SandboxVars.Deadwire.WireOwnerImmunity = true

    local called = false
    DeadwireDetection.playerHandlers["tin_can_tripline"] = function()
        called = true
    end

    -- Player is "alice" — the wire owner
    local player = _mockPlayer(4, 4, 0, "alice")
    Events.OnPlayerUpdate:Fire(player)

    assert_false(called, "owner should be immune to their own wire")

    DeadwireDetection.playerHandlers["tin_can_tripline"] = nil
end)

test("WireOwnerImmunity = true, player is NOT owner, trigger fires", function()
    _reset()
    local sq = _makeSquare(4, 4, 0)
    DeadwireNetwork.registerTile(4, 4, 0, 1, "tin_can_tripline", "alice")
    SandboxVars.Deadwire.WireOwnerImmunity = true

    local called = false
    DeadwireDetection.playerHandlers["tin_can_tripline"] = function()
        called = true
    end

    -- Player is "bob" — not the owner
    local player = _mockPlayer(4, 4, 0, "bob")
    Events.OnPlayerUpdate:Fire(player)

    assert_true(called, "non-owner should NOT be immune")

    DeadwireDetection.playerHandlers["tin_can_tripline"] = nil
end)


-----------------------------------------------------------------
-- Faction immunity (FriendlyFireWires)
--
-- The option shipped in sandbox-options.txt from the start and was read by
-- nothing at all, so it was a knob on the server settings screen that did
-- nothing. Default true = a faction mate's wire still triggers.
-----------------------------------------------------------------

suite("Detection: FriendlyFireWires")

local function withPlayerHandler(wireType, fn)
    local called = false
    DeadwireDetection.playerHandlers[wireType] = function() called = true end
    fn()
    DeadwireDetection.playerHandlers[wireType] = nil
    return called
end

test("default (true): faction mate still triggers the wire", function()
    _reset()
    _makeSquare(4, 4, 0)
    DeadwireNetwork.registerTile(4, 4, 0, 1, "tin_can_tripline", "alice")
    _setFaction("alice", "Rangers")
    _setFaction("bob", "Rangers")

    local called = withPlayerHandler("tin_can_tripline", function()
        Events.OnPlayerUpdate:Fire(_mockPlayer(4, 4, 0, "bob"))
    end)

    assert_true(called, "friendly fire is on by default")
end)

test("false: faction mate passes safely", function()
    _reset()
    _makeSquare(4, 4, 0)
    DeadwireNetwork.registerTile(4, 4, 0, 1, "tin_can_tripline", "alice")
    SandboxVars.Deadwire.FriendlyFireWires = false
    _setFaction("alice", "Rangers")
    _setFaction("bob", "Rangers")

    local called = withPlayerHandler("tin_can_tripline", function()
        Events.OnPlayerUpdate:Fire(_mockPlayer(4, 4, 0, "bob"))
    end)

    assert_false(called, "faction mate should pass a mate's wire safely")
end)

test("false: a stranger still triggers the wire", function()
    _reset()
    _makeSquare(4, 4, 0)
    DeadwireNetwork.registerTile(4, 4, 0, 1, "tin_can_tripline", "alice")
    SandboxVars.Deadwire.FriendlyFireWires = false
    _setFaction("alice", "Rangers")
    _setFaction("mallory", "Bandits")

    local called = withPlayerHandler("tin_can_tripline", function()
        Events.OnPlayerUpdate:Fire(_mockPlayer(4, 4, 0, "mallory"))
    end)

    assert_true(called, "a rival faction must not get immunity")
end)

test("false: factionless player still triggers the wire", function()
    _reset()
    _makeSquare(4, 4, 0)
    DeadwireNetwork.registerTile(4, 4, 0, 1, "tin_can_tripline", "alice")
    SandboxVars.Deadwire.FriendlyFireWires = false
    _setFaction("alice", "Rangers")

    local called = withPlayerHandler("tin_can_tripline", function()
        Events.OnPlayerUpdate:Fire(_mockPlayer(4, 4, 0, "nobody"))
    end)

    assert_true(called, "no faction means no immunity")
end)

test("false: zombies are unaffected by the faction check", function()
    _reset()
    _makeSquare(4, 4, 0)
    DeadwireNetwork.registerTile(4, 4, 0, 1, "tin_can_tripline", "alice")
    SandboxVars.Deadwire.FriendlyFireWires = false
    _setFaction("alice", "Rangers")

    local called = false
    DeadwireDetection.zombieHandlers["tin_can_tripline"] = function() called = true end
    Events.OnZombieUpdate:Fire(_mockZombie(4, 4, 0, true))
    DeadwireDetection.zombieHandlers["tin_can_tripline"] = nil

    assert_true(called, "faction immunity is player-only")
end)
