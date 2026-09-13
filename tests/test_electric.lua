-- tests/test_electric.lua
-- Tier 3: the power model (Power.lua), the shock (Shock.lua), the electrified
-- deadwire handlers (TriggerHandlers.lua) and the fence (FenceElectrification).
--
-- The one claim the whole tier rests on is "is this run live", so most of what
-- is below is about getting that answer wrong on purpose and checking it
-- notices. Squares in the stub start DEAD, so every live square in here was
-- made live by the test that needed it.

suite("Power: one square")

test("a square with no electricity is not live", function()
    _reset()
    local sq = _makeSquare(1, 1, 0)
    assert_false(DeadwirePower.isSquareLive(sq), "no power, not live")
end)

test("an indoor square with electricity is live", function()
    _reset()
    local sq = _makeSquare(1, 1, 0)
    sq._electricity = true
    sq._outside = false
    assert_true(DeadwirePower.isSquareLive(sq), "power indoors is power")
end)

test("nil square is not live, and does not throw", function()
    _reset()
    assert_false(DeadwirePower.isSquareLive(nil), "no square, no power")
end)

test("outdoors, a generator is gated by the vanilla exterior option", function()
    -- This is vanilla's own pairing, not ours: ISVehicleMenu.lua:1088 checks
    -- AllowExteriorGenerator alongside haveElectricity for exactly this case.
    -- Without it an outdoor perimeter would draw from a generator on a server
    -- that has exterior generators switched off.
    _reset()
    local sq = _makeSquare(1, 1, 0)
    sq._electricity = true      -- generator power
    sq._gridPower = false
    sq._outside = true

    SandboxVars.AllowExteriorGenerator = false
    assert_false(DeadwirePower.isSquareLive(sq),
        "exterior generators off means an outdoor generator run is dead")

    SandboxVars.AllowExteriorGenerator = true
    assert_true(DeadwirePower.isSquareLive(sq),
        "exterior generators on means it runs")
    SandboxVars.AllowExteriorGenerator = nil
end)

test("grid power outdoors survives the exterior generator option", function()
    -- The option gates generators, not the grid. Getting this backwards would
    -- kill every outdoor fence in a town that still has power.
    _reset()
    local sq = _makeSquare(1, 1, 0)
    sq._electricity = true
    sq._gridPower = true
    sq._outside = true

    SandboxVars.AllowExteriorGenerator = false
    assert_true(DeadwirePower.isSquareLive(sq),
        "the grid is not a generator")
    SandboxVars.AllowExteriorGenerator = nil
end)

suite("Power: a run of wire")

test("a run touching one live square is live end to end", function()
    -- The point of the circuit work (#53): an energiser feeds a RUN, so a
    -- wire ten tiles from the powered square is still live.
    _reset()
    local powered
    for i = 0, 9 do
        local sq = _makeSquare(10 + i, 5, 0)
        if i == 0 then powered = sq end
        DeadwireNetwork.registerTile(10 + i, 5, 0, i + 1, "electric_tripline", "alice", true)
    end
    powered._electricity = true
    powered._outside = false

    assert_true(DeadwirePower.isCircuitLive(19, 5, 0),
        "the far end of the run is live too")
end)

test("a run touching nothing powered is dead", function()
    _reset()
    for i = 0, 4 do
        _makeSquare(10 + i, 5, 0)
        DeadwireNetwork.registerTile(10 + i, 5, 0, i + 1, "electric_tripline", "alice", true)
    end
    assert_false(DeadwirePower.isCircuitLive(12, 5, 0), "no power anywhere on the run")
end)

test("power does not jump the gap to a separate run", function()
    -- The case that would make the circuit work pointless: if power leaked
    -- between unconnected runs, a single generator would electrify the map.
    _reset()
    local powered = _makeSquare(10, 5, 0)
    _makeSquare(20, 5, 0)
    DeadwireNetwork.registerTile(10, 5, 0, 1, "electric_tripline", "alice", true)
    DeadwireNetwork.registerTile(20, 5, 0, 2, "electric_tripline", "alice", true)
    powered._electricity = true
    powered._outside = false

    assert_true(DeadwirePower.isCircuitLive(10, 5, 0), "the powered run is live")
    assert_false(DeadwirePower.isCircuitLive(20, 5, 0),
        "the other run is a different circuit and stays dead")
end)

test("cutting a run in half leaves the unpowered half dead", function()
    _reset()
    local powered
    for i = 0, 4 do
        local sq = _makeSquare(30 + i, 5, 0)
        if i == 0 then powered = sq end
        DeadwireNetwork.registerTile(30 + i, 5, 0, i + 1, "electric_tripline", "alice", true)
    end
    powered._electricity = true
    powered._outside = false
    assert_true(DeadwirePower.isCircuitLive(34, 5, 0), "one run to start with")

    DeadwireNetwork.unregisterTile(32, 5, 0)

    assert_true(DeadwirePower.isCircuitLive(30, 5, 0), "the powered half stays live")
    assert_false(DeadwirePower.isCircuitLive(34, 5, 0),
        "the half that lost its connection to the power goes dead")
end)

test("a tile with no wire on it has no circuit and is not live", function()
    _reset()
    _makeSquare(50, 50, 0)._electricity = true
    assert_false(DeadwirePower.isCircuitLive(50, 50, 0),
        "a live square is not a live circuit without wire on it")
end)

suite("Shock: what a live wire does to a body")

test("a shocked player takes damage, is thrown back, and panics", function()
    -- Rob's spec, session 28: damage, fall back, stunned, anxious moodle.
    -- PZ has no player stun and no moodle named anxious, so the knockdown is
    -- the stun and Panic is the moodle.
    _reset()
    local player = _mockPlayer(5, 5, 0, "alice")
    DeadwireShock.shockPlayer(player, _makeSquare(5, 5, 0))

    local hurt = 0
    for _, amount in pairs(player._damage) do hurt = hurt + amount end
    assert_true(hurt > 0, "the shock hurt something")
    assert_true(player._panic > 0, "the anxious moodle went up")
    assert_eq(player._variables["BumpFallType"], "pushedBack",
        "thrown away from the wire, not into it")
    assert_true(player._variables["BumpFall"], "and off its feet")
end)

test("shock damage lands on a leg or a foot, never somewhere absurd", function()
    _reset()
    local legs = { Foot_L = true, Foot_R = true, LowerLeg_L = true, LowerLeg_R = true }
    -- Run it enough times to see the random pick spread, and check every
    -- landing is somewhere a shin-height wire could actually reach.
    for i = 1, 40 do
        local player = _mockPlayer(5, 5, 0, "alice")
        DeadwireShock.shockPlayer(player, _makeSquare(5, 5, 0))
        for part, _ in pairs(player._damage) do
            assert_true(legs[part], "shocked " .. tostring(part) .. ", which is not a leg")
        end
    end
end)

test("zero damage still throws the player back", function()
    -- A server owner turning the damage off wants a fence that hurts less,
    -- not one that stops working.
    _reset()
    SandboxVars.Deadwire.ShockPlayerDamage = 0
    local player = _mockPlayer(5, 5, 0, "alice")
    DeadwireShock.shockPlayer(player, _makeSquare(5, 5, 0))

    local hurt = 0
    for _, amount in pairs(player._damage) do hurt = hurt + amount end
    assert_eq(hurt, 0, "no damage was asked for and none was done")
    assert_true(player._variables["BumpFall"], "but it still threw him")
end)

test("a shocked zombie is killed or put down, and says which", function()
    _reset()
    SandboxVars.Deadwire.ShockZombieKillChance = 100
    local zed = _mockZombie(5, 5, 0)
    assert_eq(DeadwireShock.shockZombie(zed, _makeSquare(5, 5, 0)), "killed",
        "a certain kill kills")
    assert_true(zed._killed, "and the zombie knows about it")

    SandboxVars.Deadwire.ShockZombieKillChance = 0
    local other = _mockZombie(6, 5, 0)
    assert_eq(DeadwireShock.shockZombie(other, _makeSquare(6, 5, 0)), "downed",
        "no kill chance means knocked down instead")
    assert_true(other._knockedDown, "knocked down")
    assert_true(other._staggeredBack, "and thrown off the wire")
    assert_false(other._killed, "but not killed")
end)

suite("Electrified deadwire: powered and unpowered (#13)")

local function crossElectricWire(live)
    _reset()
    _makeSquare(10, 9, 0)
    local sq = _makeSquare(10, 10, 0)
    DeadwireNetwork.registerTile(10, 10, 0, 1, "electric_tripline", "alice", true)
    if live then
        sq._electricity = true
        sq._outside = false
    end

    local player = _mockPlayer(10, 9, 0, "bob")
    Events.OnPlayerUpdate:Fire(player)
    _setOsTime(os.time() + 30)
    _moveTo(player, 10, 10, 0)
    Events.OnPlayerUpdate:Fire(player)
    return player
end

test("crossing a live deadwire shocks the player", function()
    local player = crossElectricWire(true)
    local hurt = 0
    for _, amount in pairs(player._damage) do hurt = hurt + amount end
    assert_true(hurt > 0, "a live wire bites")
    assert_true(player._panic > 0, "and frightens")
end)

test("crossing a DEAD deadwire is still a trip line, and still harmless", function()
    -- #13 is explicit about this: a survivalist whose generator ran dry should
    -- still have a perimeter alarm, not a wire that silently does nothing at
    -- the moment it matters most.
    local player = crossElectricWire(false)
    local hurt = 0
    for _, amount in pairs(player._damage) do hurt = hurt + amount end
    assert_eq(hurt, 0, "an unpowered wire does no damage")
    assert_eq(player._panic, 0, "and does not frighten")
    assert_true(#_getSoundCalls() > 0, "but it still makes a noise")
end)

test("the electrified deadwire is the quietest trip line, not the loudest", function()
    -- A survivalist's wire is meant not to be found. This is the opposite of
    -- the bell, and the opposite of the fence in #52, on purpose.
    local elec = DeadwireConfig.WireDefaults.electric_tripline.soundRadius
    assert_true(elec < DeadwireConfig.WireDefaults.bell_tripline.soundRadius,
        "quieter than the bell")
    assert_true(elec < DeadwireConfig.WireDefaults.reinforced_tripline.soundRadius,
        "quieter than reinforced")
    assert_true(elec < DeadwireConfig.WireDefaults.tin_can_tripline.soundRadius,
        "quieter even than the tin cans")
end)

test("the electrified deadwire is tier 3, so the tier switch reaches it", function()
    assert_eq(DeadwireConfig.WireDefaults.electric_tripline.tier, 3, "tier 3")
    SandboxVars.Deadwire.EnableTier3 = false
    assert_false(DeadwireConfig.isTierEnabled(3), "and the switch turns it off")
    SandboxVars.Deadwire.EnableTier3 = nil
end)

test("it has a sprite for both facings, or it would never place", function()
    -- The pair was packed into the tilesheet for #13 and deliberately left out
    -- of Sprites until the feature existed. createWire returns nil without it.
    local sprites = DeadwireConfig.Sprites.electric_tripline
    assert_not_nil(sprites, "electric has a sprite entry at last")
    assert_not_nil(sprites.north, "north facing")
    assert_not_nil(sprites.east, "west facing")
end)

suite("Electrified fence: the farmer's half (#52)")

local function fenceAt(x, y, z, live)
    local sq = _makeSquare(x, y, z)
    local fence = {
        _class = "IsoThumpable",
        _modData = {},
        getModData = function(self) return self._modData end,
        getNorth = function() return true end,
        getSquare = function() return sq end,
    }
    sq:AddSpecialObject(fence)
    if live then
        sq._electricity = true
        sq._outside = false
    end
    return sq, fence
end

test("a fence can be electrified and the mod remembers it", function()
    _reset()
    local sq = fenceAt(60, 60, 0, true)
    assert_true(DeadwireFences.electrify(sq, "alice"), "electrified")
    assert_true(DeadwireFences.isElectrified(60, 60, 0), "and it stuck")
end)

test("the list of live fences is ours, not the fence object's", function()
    -- #52 flagged hanging modData on an object we did not create as an
    -- unverified, load-bearing risk: if it does not survive a reload the
    -- feature needs a different attachment model. Keeping the register in our
    -- own GlobalModData, which the wires already prove survives, turns that
    -- into a cosmetic unknown. This test is what pins the choice down.
    _reset()
    local sq, fence = fenceAt(61, 61, 0, true)
    DeadwireFences.electrify(sq, "alice")

    fence._modData = {}   -- the fence forgets everything, as a reload might
    assert_true(DeadwireFences.isElectrified(61, 61, 0),
        "our register still knows, because it never asked the fence")
end)

test("a square with no fence on it cannot be electrified", function()
    _reset()
    local bare = _makeSquare(62, 62, 0)
    local ok, why = DeadwireFences.electrify(bare, "alice")
    assert_false(ok, "nothing to electrify")
    assert_eq(why, "no fence here", "and it says so")
end)

test("one of our own wires is not a fence", function()
    -- Electrifying our own trip line is what #13 is for, and doing it through
    -- this path would give a wire two separate shock systems.
    _reset()
    local sq = _makeSquare(63, 63, 0)
    sq:AddSpecialObject({
        _class = "IsoThumpable",
        _modData = { dw_type = "tin_can_tripline" },
        getModData = function(self) return self._modData end,
    })
    local ok = DeadwireFences.electrify(sq, "alice")
    assert_false(ok, "a deadwire is not a fence")
end)

test("disconnecting a fence takes it off the register", function()
    _reset()
    local sq = fenceAt(64, 64, 0, true)
    DeadwireFences.electrify(sq, "alice")
    assert_true(DeadwireFences.deElectrify(sq), "disconnected")
    assert_false(DeadwireFences.isElectrified(64, 64, 0), "and it is off the list")
end)

test("a live fence shocks a zombie standing against it", function()
    _reset()
    SandboxVars.Deadwire.FencePulseChance = 100
    SandboxVars.Deadwire.ShockZombieKillChance = 0
    SandboxVars.Deadwire.FenceBreakChance = 0

    local sq = fenceAt(70, 70, 0, true)
    DeadwireFences.electrify(sq, "alice")

    local neighbour = _makeSquare(71, 70, 0)
    local zed = _mockZombie(71, 70, 0)
    neighbour:_addMover(zed)

    assert_true(DeadwireFences.pulseAll() > 0, "the pulse found it")
    assert_true(zed._knockedDown, "and put it down")
end)

test("an UNPOWERED fence does nothing at all", function()
    _reset()
    SandboxVars.Deadwire.FencePulseChance = 100
    local sq = fenceAt(72, 72, 0, false)   -- electrified but not powered
    DeadwireFences.electrify(sq, "alice")

    local neighbour = _makeSquare(73, 72, 0)
    local zed = _mockZombie(73, 72, 0)
    neighbour:_addMover(zed)

    assert_eq(DeadwireFences.pulseAll(), 0, "no power, no pulse")
    assert_false(zed._knockedDown, "and the zombie walks on")
end)

test("the pulse roll is the pulse timing, so zero chance never bites", function()
    -- An energiser pulses on a clock, not on contact, and the roll is whether
    -- the body was touching when the pulse arrived. Turning it to zero is a
    -- server owner switching the bite off, and it must actually switch off.
    _reset()
    SandboxVars.Deadwire.FencePulseChance = 0
    local sq = fenceAt(74, 74, 0, true)
    DeadwireFences.electrify(sq, "alice")

    local neighbour = _makeSquare(75, 74, 0)
    local zed = _mockZombie(75, 74, 0)
    neighbour:_addMover(zed)

    assert_eq(DeadwireFences.pulseAll(), 0, "never pulses")
    assert_false(zed._knockedDown, "and never bites")
end)

test("a dead zombie against the fence is not shocked again", function()
    -- Without this the pulse would go on knocking down a corpse once a second
    -- for the life of the save.
    _reset()
    SandboxVars.Deadwire.FencePulseChance = 100
    SandboxVars.Deadwire.FenceBreakChance = 0
    local sq = fenceAt(76, 76, 0, true)
    DeadwireFences.electrify(sq, "alice")

    local neighbour = _makeSquare(77, 76, 0)
    local zed = _mockZombie(77, 76, 0, false)   -- already dead
    neighbour:_addMover(zed)

    assert_eq(DeadwireFences.pulseAll(), 0, "corpses do not conduct")
end)

test("turning tier 3 off stops the fence pulsing", function()
    _reset()
    SandboxVars.Deadwire.FencePulseChance = 100
    local sq = fenceAt(78, 78, 0, true)
    DeadwireFences.electrify(sq, "alice")
    local neighbour = _makeSquare(79, 78, 0)
    neighbour:_addMover(_mockZombie(79, 78, 0))

    SandboxVars.Deadwire.EnableTier3 = false
    assert_eq(DeadwireFences.pulseAll(), 0, "the tier switch reaches the fence too")
    SandboxVars.Deadwire.EnableTier3 = nil
end)

test("the wiring can burn out, but the fence itself is never destroyed", function()
    -- A fence already has deflection and cover built into it in a way a bare
    -- wire does not, so electrifying it must not blow up the thing it is
    -- attached to. Burning out means reconnecting, not rebuilding.
    _reset()
    SandboxVars.Deadwire.FencePulseChance = 100
    SandboxVars.Deadwire.FenceBreakChance = 100
    SandboxVars.Deadwire.ShockZombieKillChance = 0

    local sq, fence = fenceAt(80, 80, 0, true)
    DeadwireFences.electrify(sq, "alice")
    local neighbour = _makeSquare(81, 80, 0)
    neighbour:_addMover(_mockZombie(81, 80, 0))

    DeadwireFences.pulseAll()
    assert_false(DeadwireFences.isElectrified(80, 80, 0), "the wiring burned out")
    assert_not_nil(DeadwireFences.findFence(sq), "the fence is still standing")
end)
