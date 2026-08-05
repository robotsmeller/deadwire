-- tests/test_server_commands.lua
-- Tests for ServerCommands.lua handlers (invoked via Events.OnClientCommand:Fire)
-- Modules are already require'd by run.lua. Stubs are already loaded.
--
-- WireManager is replaced with a lightweight mock so tests do not need a real
-- PZ world. The mock registers tiles into WireNetwork so downstream checks
-- (e.g. "tile already occupied") work correctly.

-----------------------------------------------------------------
-- WireManager mock (applied once, reset between tests)
-----------------------------------------------------------------
local _createdWires = {}
local _destroyedWires = {}

DeadwireWireManager.createWire = function(sq, wireType, ownerId, networkId)
    table.insert(_createdWires, { sq = sq, wireType = wireType, ownerId = ownerId, networkId = networkId })
    -- Register in WireNetwork so PlaceWire's duplicate-check sees it as placed
    local x, y, z = sq:getX(), sq:getY(), sq:getZ()
    DeadwireNetwork.registerTile(x, y, z, networkId, wireType, ownerId)
    return { _fake = true }   -- non-nil = success
end

DeadwireWireManager.destroyWire = function(x, y, z)
    table.insert(_destroyedWires, { x = x, y = y, z = z })
    DeadwireNetwork.unregisterTile(x, y, z)
    return true
end

-- Helper: full reset between tests
local function resetAll()
    _reset()          -- clears network, squares, commands, sandbox, world age
    _createdWires  = {}
    _destroyedWires = {}
    _clearCommands()
end

-- A player holding the kit for `wireType` (default: tin can).
--
-- PlaceWire now refuses a player who is not carrying the kit (#15), so every
-- PlaceWire test needs one -- otherwise the no-op tests below would pass
-- because the player is empty-handed rather than because of the condition
-- each is actually meant to exercise.
local function _kittedPlayer(x, y, z, name, wireType)
    local player = _mockPlayer(x, y, z, name)
    _giveItem(player, DeadwireConfig.KitItems[wireType or "tin_can_tripline"])
    return player
end

-----------------------------------------------------------------
-- PlaceWire tests
-----------------------------------------------------------------
suite("ServerCommands: PlaceWire")

test("valid args and empty tile: createWire called, WirePlaced broadcast sent", function()
    resetAll()
    local sq = _makeSquare(10, 20, 0)
    local player = _kittedPlayer(10, 20, 0, "alice")

    Events.OnClientCommand:Fire("Deadwire", "PlaceWire", player, {
        x = 10, y = 20, z = 0, wireType = "tin_can_tripline"
    })

    assert_eq(#_createdWires, 1, "createWire should have been called once")
    assert_eq(_createdWires[1].wireType, "tin_can_tripline")
    assert_eq(_createdWires[1].ownerId, "alice")

    local cmd = _findServerCmd("WirePlaced")
    assert_not_nil(cmd, "WirePlaced broadcast should have been sent")
    assert_eq(cmd.args.x, 10)
    assert_eq(cmd.args.y, 20)
    assert_eq(cmd.args.z, 0)
    assert_eq(cmd.args.wireType, "tin_can_tripline")
    assert_eq(cmd.args.ownerId, "alice")
end)

test("missing wireType: no-op", function()
    resetAll()
    local sq = _makeSquare(10, 20, 0)
    local player = _kittedPlayer(10, 20, 0, "alice")

    Events.OnClientCommand:Fire("Deadwire", "PlaceWire", player, {
        x = 10, y = 20, z = 0
        -- wireType omitted
    })

    assert_eq(#_createdWires, 0, "createWire should NOT have been called")
    assert_nil(_findServerCmd("WirePlaced"), "WirePlaced should NOT have been sent")
end)

test("missing position: no-op", function()
    resetAll()
    local player = _kittedPlayer(10, 20, 0, "alice")

    Events.OnClientCommand:Fire("Deadwire", "PlaceWire", player, {
        wireType = "tin_can_tripline"
        -- x/y/z omitted
    })

    assert_eq(#_createdWires, 0, "createWire should NOT have been called")
end)

test("unknown wireType: no-op", function()
    resetAll()
    local sq = _makeSquare(10, 20, 0)
    local player = _kittedPlayer(10, 20, 0, "alice")

    Events.OnClientCommand:Fire("Deadwire", "PlaceWire", player, {
        x = 10, y = 20, z = 0, wireType = "definitely_not_a_wire"
    })

    assert_eq(#_createdWires, 0, "createWire should NOT have been called")
end)

test("no square at position: no-op", function()
    resetAll()
    -- Square at (99,99,0) is NOT created, so getCell():getGridSquare returns nil
    local player = _kittedPlayer(0, 0, 0, "alice")

    Events.OnClientCommand:Fire("Deadwire", "PlaceWire", player, {
        x = 99, y = 99, z = 0, wireType = "tin_can_tripline"
    })

    assert_eq(#_createdWires, 0, "createWire should NOT have been called when square is nil")
end)

test("tile already occupied: no-op", function()
    resetAll()
    local sq = _makeSquare(10, 20, 0)
    -- Pre-register a wire so the tile is occupied
    DeadwireNetwork.registerTile(10, 20, 0, 99, "tin_can_tripline", "bob")

    local player = _kittedPlayer(10, 20, 0, "alice")

    Events.OnClientCommand:Fire("Deadwire", "PlaceWire", player, {
        x = 10, y = 20, z = 0, wireType = "tin_can_tripline"
    })

    assert_eq(#_createdWires, 0, "createWire should NOT be called when tile is occupied")
    assert_nil(_findServerCmd("WirePlaced"))
end)

test("player at wire limit (WireMaxPerPlayer=1, one wire already placed): no-op", function()
    resetAll()
    -- Place one wire belonging to "alice"
    local sq1 = _makeSquare(1, 1, 0)
    DeadwireNetwork.registerTile(1, 1, 0, 1, "tin_can_tripline", "alice")

    SandboxVars.Deadwire.WireMaxPerPlayer = 1

    local sq2 = _makeSquare(2, 2, 0)
    local player = _kittedPlayer(2, 2, 0, "alice")

    Events.OnClientCommand:Fire("Deadwire", "PlaceWire", player, {
        x = 2, y = 2, z = 0, wireType = "tin_can_tripline"
    })

    assert_eq(#_createdWires, 0, "createWire should NOT be called when player is at max wire limit")
end)

test("disabled tier (EnableTier0=false, tin_can): no-op", function()
    resetAll()
    SandboxVars.Deadwire.EnableTier0 = false

    local sq = _makeSquare(10, 20, 0)
    local player = _kittedPlayer(10, 20, 0, "alice")

    Events.OnClientCommand:Fire("Deadwire", "PlaceWire", player, {
        x = 10, y = 20, z = 0, wireType = "tin_can_tripline"
    })

    assert_eq(#_createdWires, 0, "createWire should NOT be called when tier is disabled")
end)

test("EnableMod=false: no-op", function()
    resetAll()
    SandboxVars.Deadwire.EnableMod = false

    local sq = _makeSquare(10, 20, 0)
    local player = _kittedPlayer(10, 20, 0, "alice")

    Events.OnClientCommand:Fire("Deadwire", "PlaceWire", player, {
        x = 10, y = 20, z = 0, wireType = "tin_can_tripline"
    })

    assert_eq(#_createdWires, 0, "createWire should NOT be called when mod is disabled")
end)

-- #15: PlaceWire is a plain server command, so a modified client can send it
-- without ever having crafted anything. The server must check the inventory.

test("player without the kit: no-op (#15)", function()
    resetAll()
    local sq = _makeSquare(10, 20, 0)
    local player = _mockPlayer(10, 20, 0, "mallory")   -- empty-handed

    Events.OnClientCommand:Fire("Deadwire", "PlaceWire", player, {
        x = 10, y = 20, z = 0, wireType = "tin_can_tripline"
    })

    assert_eq(#_createdWires, 0, "createWire should NOT be called without a kit")
    assert_nil(_findServerCmd("WirePlaced"), "WirePlaced should NOT have been sent")
end)

test("holding the wrong kit does not authorize placement (#15)", function()
    resetAll()
    local sq = _makeSquare(10, 20, 0)
    local player = _mockPlayer(10, 20, 0, "mallory")
    _giveItem(player, DeadwireConfig.KitItems.bell_tripline)

    Events.OnClientCommand:Fire("Deadwire", "PlaceWire", player, {
        x = 10, y = 20, z = 0, wireType = "tin_can_tripline"
    })

    assert_eq(#_createdWires, 0, "a bell kit must not place a tin can wire")
end)

test("successful placement consumes exactly one kit (#15)", function()
    resetAll()
    local sq = _makeSquare(10, 20, 0)
    local player = _kittedPlayer(10, 20, 0, "alice")
    _giveItem(player, DeadwireConfig.KitItems.tin_can_tripline)   -- two in total

    Events.OnClientCommand:Fire("Deadwire", "PlaceWire", player, {
        x = 10, y = 20, z = 0, wireType = "tin_can_tripline"
    })

    assert_eq(#_createdWires, 1, "createWire should have been called")
    assert_eq(_countItems(player, DeadwireConfig.KitItems.tin_can_tripline), 1,
        "exactly one kit should have been consumed")
end)

test("failed placement consumes no kit (#15)", function()
    resetAll()
    local sq = _makeSquare(10, 20, 0)
    DeadwireNetwork.registerTile(10, 20, 0, 99, "tin_can_tripline", "bob")  -- occupied
    local player = _kittedPlayer(10, 20, 0, "alice")

    Events.OnClientCommand:Fire("Deadwire", "PlaceWire", player, {
        x = 10, y = 20, z = 0, wireType = "tin_can_tripline"
    })

    assert_eq(#_createdWires, 0, "placement should have been refused")
    assert_eq(_countItems(player, DeadwireConfig.KitItems.tin_can_tripline), 1,
        "kit must survive a refused placement")
end)

-----------------------------------------------------------------
-- RemoveWire tests
-----------------------------------------------------------------
suite("ServerCommands: RemoveWire")

test("owner removes own wire: destroyWire called, WireDestroyed sent", function()
    resetAll()
    local sq = _makeSquare(5, 5, 0)
    DeadwireNetwork.registerTile(5, 5, 0, 1, "tin_can_tripline", "alice")

    local player = _mockPlayer(5, 5, 0, "alice")

    Events.OnClientCommand:Fire("Deadwire", "RemoveWire", player, {
        x = 5, y = 5, z = 0
    })

    assert_eq(#_destroyedWires, 1, "destroyWire should have been called")
    assert_eq(_destroyedWires[1].x, 5)
    assert_eq(_destroyedWires[1].y, 5)
    assert_eq(_destroyedWires[1].z, 0)

    local cmd = _findServerCmd("WireDestroyed")
    assert_not_nil(cmd, "WireDestroyed broadcast should have been sent")
    assert_eq(cmd.args.x, 5)
    assert_eq(cmd.args.y, 5)
    assert_eq(cmd.args.z, 0)
end)

test("non-owner, non-admin cannot remove wire: no-op", function()
    resetAll()
    local sq = _makeSquare(5, 5, 0)
    DeadwireNetwork.registerTile(5, 5, 0, 1, "tin_can_tripline", "alice")

    local player = _mockPlayer(5, 5, 0, "bob")  -- not the owner, not admin

    Events.OnClientCommand:Fire("Deadwire", "RemoveWire", player, {
        x = 5, y = 5, z = 0
    })

    assert_eq(#_destroyedWires, 0, "non-owner should not be able to remove wire")
    assert_nil(_findServerCmd("WireDestroyed"))
end)

-- #14: the old check called Capability.CanBuildAnywhere, which does not exist
-- in 42.20, and called it on getRole() without a nil guard.

test("non-owner with no role is denied, not an error (#14)", function()
    resetAll()
    local sq = _makeSquare(5, 5, 0)
    DeadwireNetwork.registerTile(5, 5, 0, 1, "tin_can_tripline", "alice")

    local player = _mockRolelessPlayer(5, 5, 0, "bob")

    Events.OnClientCommand:Fire("Deadwire", "RemoveWire", player, {
        x = 5, y = 5, z = 0
    })

    assert_eq(#_destroyedWires, 0, "roleless non-owner must be denied")
end)

test("owner with no role can still remove their own wire (#14)", function()
    resetAll()
    local sq = _makeSquare(5, 5, 0)
    DeadwireNetwork.registerTile(5, 5, 0, 1, "tin_can_tripline", "alice")

    local player = _mockRolelessPlayer(5, 5, 0, "alice")

    Events.OnClientCommand:Fire("Deadwire", "RemoveWire", player, {
        x = 5, y = 5, z = 0
    })

    assert_eq(#_destroyedWires, 1, "ownership must not depend on having a role")
end)

test("admin removes any wire: destroyWire called", function()
    resetAll()
    local sq = _makeSquare(5, 5, 0)
    DeadwireNetwork.registerTile(5, 5, 0, 1, "tin_can_tripline", "alice")

    local admin = _mockAdmin(5, 5, 0, "serverop")

    Events.OnClientCommand:Fire("Deadwire", "RemoveWire", admin, {
        x = 5, y = 5, z = 0
    })

    assert_eq(#_destroyedWires, 1, "admin should be able to remove any wire")
    assert_not_nil(_findServerCmd("WireDestroyed"))
end)

test("no wire at position: no-op", function()
    resetAll()
    local sq = _makeSquare(5, 5, 0)
    -- No wire registered

    local player = _mockPlayer(5, 5, 0, "alice")

    Events.OnClientCommand:Fire("Deadwire", "RemoveWire", player, {
        x = 5, y = 5, z = 0
    })

    assert_eq(#_destroyedWires, 0, "destroyWire should NOT be called when no wire exists")
    assert_nil(_findServerCmd("WireDestroyed"))
end)

-----------------------------------------------------------------
-- WireTriggered tests
-----------------------------------------------------------------
suite("ServerCommands: WireTriggered")

test("tin_can (breakOnTrigger=true): destroyWire called, WireDestroyed sent", function()
    resetAll()
    local sq = _makeSquare(6, 6, 0)
    DeadwireNetwork.registerTile(6, 6, 0, 1, "tin_can_tripline", "alice")

    local player = _mockPlayer(6, 6, 0, "bob")

    Events.OnClientCommand:Fire("Deadwire", "WireTriggered", player, {
        x = 6, y = 6, z = 0, wireType = "tin_can_tripline"
    })

    assert_eq(#_destroyedWires, 1, "tin_can wire should be destroyed after trigger")
    assert_not_nil(_findServerCmd("WireDestroyed"), "WireDestroyed should be broadcast")

    -- WireTriggered sound command should also be sent
    local trigCmd = _findServerCmd("WireTriggered")
    assert_not_nil(trigCmd, "WireTriggered sound broadcast should be sent")
    assert_eq(trigCmd.args.x, 6)
    assert_eq(trigCmd.args.y, 6)
    assert_eq(trigCmd.args.z, 0)
    assert_not_nil(trigCmd.args.soundName)
end)

test("reinforced (breakOnTrigger=false): no destroy, cooldown set, WireTriggered sound sent", function()
    resetAll()
    local sq = _makeSquare(7, 7, 0)
    DeadwireNetwork.registerTile(7, 7, 0, 1, "reinforced_tripline", "alice")

    _setOsTime(1000)
    local player = _mockPlayer(7, 7, 0, "bob")

    Events.OnClientCommand:Fire("Deadwire", "WireTriggered", player, {
        x = 7, y = 7, z = 0, wireType = "reinforced_tripline"
    })

    assert_eq(#_destroyedWires, 0, "reinforced wire should NOT be destroyed on trigger")
    assert_nil(_findServerCmd("WireDestroyed"), "WireDestroyed should NOT be sent")

    -- Cooldown should now be active
    assert_true(DeadwireNetwork.isOnCooldown(7, 7, 0), "cooldown should be set after trigger")

    local trigCmd = _findServerCmd("WireTriggered")
    assert_not_nil(trigCmd, "WireTriggered sound broadcast should be sent")
    assert_eq(trigCmd.args.soundName, DeadwireConfig.Sounds.WIRE_RATTLE)

    -- Clients run detection against their own copy of the network, so the
    -- cooldown has to travel with the broadcast or it only exists server-side.
    assert_eq(trigCmd.args.cooldownSeconds,
        DeadwireConfig.WireDefaults.reinforced_tripline.cooldownSeconds,
        "broadcast must carry the cooldown duration for clients to mirror")
end)

test("TinCanBreakOnTrigger=false makes tin can reusable end to end", function()
    resetAll()
    SandboxVars.Deadwire.TinCanBreakOnTrigger = false
    _setOsTime(1000)
    local sq = _makeSquare(6, 6, 0)
    DeadwireNetwork.registerTile(6, 6, 0, 1, "tin_can_tripline", "alice")

    local player = _mockPlayer(6, 6, 0, "bob")

    Events.OnClientCommand:Fire("Deadwire", "WireTriggered", player, {
        x = 6, y = 6, z = 0, wireType = "tin_can_tripline"
    })

    assert_eq(#_destroyedWires, 0, "tin can should survive when the option is off")
    assert_true(DeadwireNetwork.isOnCooldown(6, 6, 0),
        "a now-reusable tin can must get a cooldown instead")
end)

-- #15: detection is necessarily client-side, so the server cannot verify that
-- a wire fired -- only that the reporter is close enough to have seen it.

test("trigger report from a distant player is rejected (#15)", function()
    resetAll()
    local sq = _makeSquare(6, 6, 0)
    _makeSquare(200, 200, 0)
    DeadwireNetwork.registerTile(6, 6, 0, 1, "tin_can_tripline", "alice")

    local mallory = _mockPlayer(200, 200, 0, "mallory")

    Events.OnClientCommand:Fire("Deadwire", "WireTriggered", mallory, {
        x = 6, y = 6, z = 0, wireType = "tin_can_tripline"
    })

    assert_eq(#_destroyedWires, 0, "a distant client must not destroy a wire")
    assert_nil(_findServerCmd("WireDestroyed"))
    assert_nil(_findServerCmd("WireTriggered"))
end)

test("trigger report from a different floor is rejected (#15)", function()
    resetAll()
    _makeSquare(6, 6, 0)
    _makeSquare(6, 6, 1)
    DeadwireNetwork.registerTile(6, 6, 0, 1, "tin_can_tripline", "alice")

    local mallory = _mockPlayer(6, 6, 1, "mallory")   -- directly above

    Events.OnClientCommand:Fire("Deadwire", "WireTriggered", mallory, {
        x = 6, y = 6, z = 0, wireType = "tin_can_tripline"
    })

    assert_eq(#_destroyedWires, 0, "z must be an exact match, not a distance")
end)

test("trigger report from an adjacent tile is accepted (#15)", function()
    resetAll()
    _makeSquare(6, 6, 0)
    _makeSquare(8, 7, 0)
    DeadwireNetwork.registerTile(6, 6, 0, 1, "tin_can_tripline", "alice")

    local player = _mockPlayer(8, 7, 0, "bob")   -- 2 tiles away, within range

    Events.OnClientCommand:Fire("Deadwire", "WireTriggered", player, {
        x = 6, y = 6, z = 0, wireType = "tin_can_tripline"
    })

    assert_eq(#_destroyedWires, 1, "a nearby player's report must still be honoured")
end)

test("camo is not degraded by a distant trigger report (#15)", function()
    resetAll()
    _makeSquare(6, 6, 0)
    _makeSquare(200, 200, 0)
    DeadwireNetwork.registerTile(6, 6, 0, 1, "reinforced_tripline", "alice")
    DeadwireNetwork.setCamouflaged(6, 6, 0, true, 100)
    SandboxVars.Deadwire.CamoTriggerDegrade = 15

    local mallory = _mockPlayer(200, 200, 0, "mallory")

    Events.OnClientCommand:Fire("Deadwire", "WireTriggered", mallory, {
        x = 6, y = 6, z = 0, wireType = "reinforced_tripline"
    })

    assert_eq(DeadwireNetwork.getTile(6, 6, 0).camoDurability, 100,
        "remote reports must not burn down camouflage")
end)

test("wire with camo (durability=100, degrade=15): durability reduced to 85, no WireCamouflaged", function()
    resetAll()
    local sq = _makeSquare(8, 8, 0)
    DeadwireNetwork.registerTile(8, 8, 0, 1, "reinforced_tripline", "alice")
    DeadwireNetwork.setCamouflaged(8, 8, 0, true, 100)
    SandboxVars.Deadwire.CamoTriggerDegrade = 15

    local player = _mockPlayer(8, 8, 0, "bob")

    Events.OnClientCommand:Fire("Deadwire", "WireTriggered", player, {
        x = 8, y = 8, z = 0, wireType = "reinforced_tripline"
    })

    local wire = DeadwireNetwork.getTile(8, 8, 0)
    assert_not_nil(wire, "wire should still exist")
    assert_eq(wire.camoDurability, 85, "camo durability should be 85 after 15-point degrade")
    assert_true(wire.camouflaged, "wire should still be camouflaged")
    assert_nil(_findServerCmd("WireCamouflaged"), "WireCamouflaged should NOT be sent (camo not removed)")
end)

test("wire with camo at durability=10 (degrade=15 -> <=0): camo removed, WireCamouflaged sent", function()
    resetAll()
    local sq = _makeSquare(9, 9, 0)
    DeadwireNetwork.registerTile(9, 9, 0, 1, "reinforced_tripline", "alice")
    DeadwireNetwork.setCamouflaged(9, 9, 0, true, 10)
    SandboxVars.Deadwire.CamoTriggerDegrade = 15

    local player = _mockPlayer(9, 9, 0, "bob")

    Events.OnClientCommand:Fire("Deadwire", "WireTriggered", player, {
        x = 9, y = 9, z = 0, wireType = "reinforced_tripline"
    })

    local wire = DeadwireNetwork.getTile(9, 9, 0)
    assert_not_nil(wire, "wire should still exist (reinforced doesn't break)")
    assert_false(wire.camouflaged, "camo should be removed when durability hits zero")

    local camoCmd = _findServerCmd("WireCamouflaged")
    assert_not_nil(camoCmd, "WireCamouflaged broadcast should be sent when camo is stripped")
    assert_false(camoCmd.args.camouflaged, "broadcast should indicate camouflaged=false")
    assert_eq(camoCmd.args.durability, 0)
    assert_eq(camoCmd.args.x, 9)
    assert_eq(camoCmd.args.y, 9)
    assert_eq(camoCmd.args.z, 0)
end)

-----------------------------------------------------------------
-- CamouflageWire tests
-----------------------------------------------------------------
suite("ServerCommands: CamouflageWire")

test("valid uncamouflaged wire: camo set, WireCamouflaged sent", function()
    resetAll()
    local sq = _makeSquare(11, 11, 0)
    DeadwireNetwork.registerTile(11, 11, 0, 1, "tin_can_tripline", "alice")
    SandboxVars.Deadwire.EnableCamouflage = true
    SandboxVars.Deadwire.CamoMaxDurability = 100

    local player = _mockPlayer(11, 11, 0, "alice")

    Events.OnClientCommand:Fire("Deadwire", "CamouflageWire", player, {
        x = 11, y = 11, z = 0
    })

    local wire = DeadwireNetwork.getTile(11, 11, 0)
    assert_not_nil(wire, "wire should still exist")
    assert_true(wire.camouflaged, "wire should be marked camouflaged")
    assert_eq(wire.camoDurability, 100)

    local cmd = _findServerCmd("WireCamouflaged")
    assert_not_nil(cmd, "WireCamouflaged broadcast should be sent")
    assert_true(cmd.args.camouflaged)
    assert_eq(cmd.args.durability, 100)
    assert_eq(cmd.args.x, 11)
    assert_eq(cmd.args.y, 11)
    assert_eq(cmd.args.z, 0)
end)

test("wire already camouflaged: no-op, WireCamouflaged NOT sent again", function()
    resetAll()
    local sq = _makeSquare(12, 12, 0)
    DeadwireNetwork.registerTile(12, 12, 0, 1, "tin_can_tripline", "alice")
    DeadwireNetwork.setCamouflaged(12, 12, 0, true, 100)
    SandboxVars.Deadwire.EnableCamouflage = true

    local player = _mockPlayer(12, 12, 0, "alice")

    Events.OnClientCommand:Fire("Deadwire", "CamouflageWire", player, {
        x = 12, y = 12, z = 0
    })

    assert_nil(_findServerCmd("WireCamouflaged"),
        "WireCamouflaged should NOT be sent when wire is already camouflaged")
end)

test("EnableCamouflage=false: no-op", function()
    resetAll()
    local sq = _makeSquare(13, 13, 0)
    DeadwireNetwork.registerTile(13, 13, 0, 1, "tin_can_tripline", "alice")
    SandboxVars.Deadwire.EnableCamouflage = false

    local player = _mockPlayer(13, 13, 0, "alice")

    Events.OnClientCommand:Fire("Deadwire", "CamouflageWire", player, {
        x = 13, y = 13, z = 0
    })

    local wire = DeadwireNetwork.getTile(13, 13, 0)
    assert_false(wire.camouflaged, "wire should NOT be camouflaged when EnableCamouflage=false")
    assert_nil(_findServerCmd("WireCamouflaged"), "WireCamouflaged should NOT be sent")
end)
