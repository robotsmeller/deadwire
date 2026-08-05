-- tests/test_wire_network.lua
-- Tests for DeadwireNetwork (WireNetwork.lua)
-- Modules are already require'd by run.lua. Stubs are already loaded.


suite("DeadwireNetwork.tileKey")

test("produces correct comma-separated format", function()
    assert_eq(DeadwireNetwork.tileKey(1, 2, 3), "1,2,3")
end)

test("handles zero coordinates", function()
    assert_eq(DeadwireNetwork.tileKey(0, 0, 0), "0,0,0")
end)

test("handles large coordinates", function()
    assert_eq(DeadwireNetwork.tileKey(9999, 8888, 1), "9999,8888,1")
end)

test("different coordinates produce different keys", function()
    assert_ne(DeadwireNetwork.tileKey(1, 2, 3), DeadwireNetwork.tileKey(3, 2, 1))
end)


suite("DeadwireNetwork.parseKey")

test("round-trips tileKey correctly", function()
    local key = DeadwireNetwork.tileKey(10, 20, 1)
    local x, y, z = DeadwireNetwork.parseKey(key)
    assert_eq(x, 10, "x")
    assert_eq(y, 20, "y")
    assert_eq(z, 1,  "z")
end)

test("round-trips zero coordinates", function()
    local key = DeadwireNetwork.tileKey(0, 0, 0)
    local x, y, z = DeadwireNetwork.parseKey(key)
    assert_eq(x, 0, "x")
    assert_eq(y, 0, "y")
    assert_eq(z, 0, "z")
end)

test("returns numbers (not strings)", function()
    local x, y, z = DeadwireNetwork.parseKey("5,6,7")
    assert_eq(type(x), "number")
    assert_eq(type(y), "number")
    assert_eq(type(z), "number")
end)


suite("DeadwireNetwork.registerTile and getTile")

test("registerTile creates an entry with correct fields", function()
    _reset()
    local entry = DeadwireNetwork.registerTile(1, 2, 0, 1, "tin_can_tripline", "player1")
    assert_not_nil(entry, "entry should exist")
    assert_eq(entry.x, 1)
    assert_eq(entry.y, 2)
    assert_eq(entry.z, 0)
    assert_eq(entry.networkId, 1)
    assert_eq(entry.wireType, "tin_can_tripline")
    assert_eq(entry.ownerId, "player1")
    assert_true(entry.active, "entry should be active")
end)

test("registerTile initializes camouflage fields to defaults", function()
    _reset()
    local entry = DeadwireNetwork.registerTile(1, 2, 0, 1, "tin_can_tripline", "player1")
    assert_false(entry.camouflaged, "should start uncamouflaged")
    assert_eq(entry.camoDurability, 0)
    assert_eq(entry.cooldownUntil, 0)
    assert_nil(entry.isoObject)
end)

test("getTile returns the registered entry", function()
    _reset()
    DeadwireNetwork.registerTile(5, 10, 1, 1, "bell_tripline", "owner")
    local entry = DeadwireNetwork.getTile(5, 10, 1)
    assert_not_nil(entry)
    assert_eq(entry.wireType, "bell_tripline")
end)

test("getTile returns nil for unregistered tile", function()
    _reset()
    assert_nil(DeadwireNetwork.getTile(99, 99, 99))
end)

test("getTile returns nil after clear", function()
    _reset()
    DeadwireNetwork.registerTile(1, 1, 0, 1, "tin_can_tripline", "p1")
    DeadwireNetwork.clear()
    assert_nil(DeadwireNetwork.getTile(1, 1, 0))
end)


suite("DeadwireNetwork.registerTile idempotency")

test("second registerTile call updates fields, not duplicate network entry", function()
    _reset()
    -- Register once
    DeadwireNetwork.registerTile(3, 4, 0, 1, "tin_can_tripline", "playerA")
    -- Register again at same coords with updated fields
    DeadwireNetwork.registerTile(3, 4, 0, 1, "bell_tripline", "playerB")

    -- Fields should be updated
    local entry = DeadwireNetwork.getTile(3, 4, 0)
    assert_eq(entry.wireType, "bell_tripline", "wireType should update")
    assert_eq(entry.ownerId, "playerB", "ownerId should update")

    -- Network tiles list should not have a duplicate
    local network = DeadwireNetwork.getNetwork(1)
    assert_not_nil(network)
    assert_eq(#network.tiles, 1, "network.tiles should not duplicate")
end)

test("registerTile on different coords creates separate entries", function()
    _reset()
    DeadwireNetwork.registerTile(0, 0, 0, 1, "tin_can_tripline", "p1")
    DeadwireNetwork.registerTile(1, 0, 0, 1, "tin_can_tripline", "p1")
    local network = DeadwireNetwork.getNetwork(1)
    assert_eq(#network.tiles, 2, "network should have 2 tiles")
end)


suite("DeadwireNetwork.unregisterTile")

test("removes the tile entry", function()
    _reset()
    DeadwireNetwork.registerTile(2, 3, 0, 1, "tin_can_tripline", "p1")
    DeadwireNetwork.unregisterTile(2, 3, 0)
    assert_nil(DeadwireNetwork.getTile(2, 3, 0))
end)

test("removes the key from network.tiles", function()
    _reset()
    DeadwireNetwork.registerTile(2, 3, 0, 1, "tin_can_tripline", "p1")
    DeadwireNetwork.unregisterTile(2, 3, 0)
    local network = DeadwireNetwork.getNetwork(1)
    -- Network should be nil (last tile gone) or have 0 tiles
    if network ~= nil then
        assert_eq(#network.tiles, 0, "network.tiles should be empty")
    end
end)

test("removes network entirely when last tile is unregistered", function()
    _reset()
    DeadwireNetwork.registerTile(2, 3, 0, 1, "tin_can_tripline", "p1")
    DeadwireNetwork.unregisterTile(2, 3, 0)
    assert_nil(DeadwireNetwork.getNetwork(1), "network should be deleted when empty")
end)

test("network survives when other tiles remain", function()
    _reset()
    DeadwireNetwork.registerTile(0, 0, 0, 1, "tin_can_tripline", "p1")
    DeadwireNetwork.registerTile(1, 0, 0, 1, "tin_can_tripline", "p1")
    DeadwireNetwork.unregisterTile(0, 0, 0)
    local network = DeadwireNetwork.getNetwork(1)
    assert_not_nil(network, "network should still exist")
    assert_eq(#network.tiles, 1)
end)

test("unregisterTile on nonexistent tile is a no-op", function()
    _reset()
    -- Should not throw
    DeadwireNetwork.unregisterTile(99, 99, 99)
end)


suite("DeadwireNetwork.generateNetworkId")

test("generateNetworkId increments on each call", function()
    _reset()
    local id1 = DeadwireNetwork.generateNetworkId()
    local id2 = DeadwireNetwork.generateNetworkId()
    local id3 = DeadwireNetwork.generateNetworkId()
    assert_true(id2 > id1, "id2 should be greater than id1")
    assert_true(id3 > id2, "id3 should be greater than id2")
end)

test("generateNetworkId returns 1 after clear", function()
    _reset()
    DeadwireNetwork.generateNetworkId()
    DeadwireNetwork.generateNetworkId()
    DeadwireNetwork.clear()
    local id = DeadwireNetwork.generateNetworkId()
    assert_eq(id, 1)
end)

test("setNextNetworkId then generateNetworkId resumes from correct ID", function()
    _reset()
    DeadwireNetwork.setNextNetworkId(100)
    local id = DeadwireNetwork.generateNetworkId()
    assert_eq(id, 100)
    local id2 = DeadwireNetwork.generateNetworkId()
    assert_eq(id2, 101)
end)


suite("DeadwireNetwork.clear")

test("clear removes all registered tiles", function()
    _reset()
    DeadwireNetwork.registerTile(1, 1, 0, 1, "tin_can_tripline", "p1")
    DeadwireNetwork.registerTile(2, 2, 0, 2, "bell_tripline", "p2")
    DeadwireNetwork.clear()
    assert_nil(DeadwireNetwork.getTile(1, 1, 0))
    assert_nil(DeadwireNetwork.getTile(2, 2, 0))
end)

test("clear removes all networks", function()
    _reset()
    DeadwireNetwork.registerTile(1, 1, 0, 1, "tin_can_tripline", "p1")
    DeadwireNetwork.clear()
    assert_nil(DeadwireNetwork.getNetwork(1))
end)

test("clear resets nextNetworkId to 1", function()
    _reset()
    DeadwireNetwork.generateNetworkId()
    DeadwireNetwork.generateNetworkId()
    DeadwireNetwork.clear()
    assert_eq(DeadwireNetwork.generateNetworkId(), 1)
end)

test("getAllTiles returns empty table after clear", function()
    _reset()
    DeadwireNetwork.registerTile(1, 1, 0, 1, "tin_can_tripline", "p1")
    DeadwireNetwork.clear()
    local count = 0
    for _ in pairs(DeadwireNetwork.getAllTiles()) do count = count + 1 end
    assert_eq(count, 0)
end)


suite("DeadwireNetwork camouflage")

test("setCamouflaged marks tile as camouflaged", function()
    _reset()
    DeadwireNetwork.registerTile(5, 5, 0, 1, "tin_can_tripline", "p1")
    DeadwireNetwork.setCamouflaged(5, 5, 0, true, 80)
    local entry = DeadwireNetwork.getTile(5, 5, 0)
    assert_true(entry.camouflaged)
    assert_eq(entry.camoDurability, 80)
end)

test("getCamoTiles includes camouflaged tiles", function()
    _reset()
    DeadwireNetwork.registerTile(5, 5, 0, 1, "tin_can_tripline", "p1")
    DeadwireNetwork.setCamouflaged(5, 5, 0, true, 80)
    local camo = DeadwireNetwork.getCamoTiles()
    local key = DeadwireNetwork.tileKey(5, 5, 0)
    assert_not_nil(camo[key], "camouflaged tile should appear in getCamoTiles")
end)

test("getCamoTiles excludes non-camouflaged tiles", function()
    _reset()
    DeadwireNetwork.registerTile(1, 1, 0, 1, "tin_can_tripline", "p1")
    -- Do not set camouflaged
    local camo = DeadwireNetwork.getCamoTiles()
    local key = DeadwireNetwork.tileKey(1, 1, 0)
    assert_nil(camo[key], "uncamouflaged tile should not appear in getCamoTiles")
end)

test("setCamouflaged false removes tile from camoTiles", function()
    _reset()
    DeadwireNetwork.registerTile(5, 5, 0, 1, "tin_can_tripline", "p1")
    DeadwireNetwork.setCamouflaged(5, 5, 0, true, 80)
    DeadwireNetwork.setCamouflaged(5, 5, 0, false, 0)
    local camo = DeadwireNetwork.getCamoTiles()
    local key = DeadwireNetwork.tileKey(5, 5, 0)
    assert_nil(camo[key], "de-camouflaged tile should be removed from getCamoTiles")
    local entry = DeadwireNetwork.getTile(5, 5, 0)
    assert_false(entry.camouflaged)
end)

test("setCamouflaged on nonexistent tile is a no-op (no crash)", function()
    _reset()
    -- Should not throw
    DeadwireNetwork.setCamouflaged(99, 99, 99, true, 100)
end)

test("multiple tiles tracked in camoTiles independently", function()
    _reset()
    DeadwireNetwork.registerTile(1, 0, 0, 1, "tin_can_tripline", "p1")
    DeadwireNetwork.registerTile(2, 0, 0, 1, "tin_can_tripline", "p1")
    DeadwireNetwork.setCamouflaged(1, 0, 0, true, 50)
    DeadwireNetwork.setCamouflaged(2, 0, 0, true, 70)
    local camo = DeadwireNetwork.getCamoTiles()
    local count = 0
    for _ in pairs(camo) do count = count + 1 end
    assert_eq(count, 2)
end)


suite("DeadwireNetwork cooldown")

-- Cooldowns are measured in REAL seconds (os.time), not game hours -- see #16.
-- These tests drive _setOsTime, not _setWorldAge; advancing world age must have
-- no effect at all on a cooldown.

test("isOnCooldown returns false when no cooldown set", function()
    _reset()
    _setOsTime(0)
    DeadwireNetwork.registerTile(1, 1, 0, 1, "tin_can_tripline", "p1")
    assert_false(DeadwireNetwork.isOnCooldown(1, 1, 0))
end)

test("isOnCooldown returns false for unregistered tile", function()
    _reset()
    assert_false(DeadwireNetwork.isOnCooldown(99, 99, 99))
end)

test("setCooldown then isOnCooldown returns true within window", function()
    _reset()
    _setOsTime(1000)
    DeadwireNetwork.registerTile(1, 1, 0, 1, "tin_can_tripline", "p1")
    DeadwireNetwork.setCooldown(1, 1, 0, 36)   -- expires at t=1036
    _setOsTime(1035)
    assert_true(DeadwireNetwork.isOnCooldown(1, 1, 0))
end)

test("isOnCooldown returns false after time advances past cooldown", function()
    _reset()
    _setOsTime(1000)
    DeadwireNetwork.registerTile(1, 1, 0, 1, "tin_can_tripline", "p1")
    DeadwireNetwork.setCooldown(1, 1, 0, 36)   -- expires at t=1036
    _setOsTime(1100)
    assert_false(DeadwireNetwork.isOnCooldown(1, 1, 0))
end)

test("isOnCooldown returns false exactly at expiry boundary", function()
    _reset()
    _setOsTime(1000)
    DeadwireNetwork.registerTile(1, 1, 0, 1, "tin_can_tripline", "p1")
    DeadwireNetwork.setCooldown(1, 1, 0, 36)   -- cooldownUntil = 1036
    _setOsTime(1036)                            -- 1036 < 1036 is false
    assert_false(DeadwireNetwork.isOnCooldown(1, 1, 0))
end)

test("cooldown ignores game time entirely (regression: #16)", function()
    _reset()
    _setOsTime(1000)
    _setWorldAge(10)
    DeadwireNetwork.registerTile(1, 1, 0, 1, "reinforced_tripline", "p1")
    DeadwireNetwork.setCooldown(1, 1, 0, 36)
    _setWorldAge(9999)   -- centuries of game time, no real seconds elapsed
    assert_true(DeadwireNetwork.isOnCooldown(1, 1, 0),
        "world age must not expire a real-time cooldown")
end)

test("setCooldown returns the duration applied", function()
    _reset()
    _setOsTime(500)
    DeadwireNetwork.registerTile(1, 1, 0, 1, "reinforced_tripline", "p1")
    assert_eq(DeadwireNetwork.setCooldown(1, 1, 0, 36), 36)
end)

test("setCooldown on nonexistent tile is a no-op returning nil", function()
    _reset()
    assert_eq(DeadwireNetwork.setCooldown(99, 99, 99, 5), nil)
end)


suite("DeadwireNetwork.getPlayerTileCount")

test("returns 0 when no tiles registered", function()
    _reset()
    assert_eq(DeadwireNetwork.getPlayerTileCount("player1"), 0)
end)

test("returns correct count for one owner", function()
    _reset()
    DeadwireNetwork.registerTile(0, 0, 0, 1, "tin_can_tripline", "player1")
    DeadwireNetwork.registerTile(1, 0, 0, 1, "tin_can_tripline", "player1")
    DeadwireNetwork.registerTile(2, 0, 0, 1, "tin_can_tripline", "player1")
    assert_eq(DeadwireNetwork.getPlayerTileCount("player1"), 3)
end)

test("counts only the specified owner", function()
    _reset()
    DeadwireNetwork.registerTile(0, 0, 0, 1, "tin_can_tripline", "player1")
    DeadwireNetwork.registerTile(1, 0, 0, 2, "tin_can_tripline", "player2")
    DeadwireNetwork.registerTile(2, 0, 0, 2, "tin_can_tripline", "player2")
    assert_eq(DeadwireNetwork.getPlayerTileCount("player1"), 1)
    assert_eq(DeadwireNetwork.getPlayerTileCount("player2"), 2)
end)

test("decreases after unregisterTile", function()
    _reset()
    DeadwireNetwork.registerTile(0, 0, 0, 1, "tin_can_tripline", "player1")
    DeadwireNetwork.registerTile(1, 0, 0, 1, "tin_can_tripline", "player1")
    DeadwireNetwork.unregisterTile(0, 0, 0)
    assert_eq(DeadwireNetwork.getPlayerTileCount("player1"), 1)
end)


suite("DeadwireNetwork.getNetworkTiles")

test("returns empty table for unknown networkId", function()
    _reset()
    local tiles = DeadwireNetwork.getNetworkTiles(999)
    assert_not_nil(tiles)
    assert_eq(#tiles, 0)
end)

test("returns all tiles for a network", function()
    _reset()
    DeadwireNetwork.registerTile(0, 0, 0, 1, "tin_can_tripline", "p1")
    DeadwireNetwork.registerTile(1, 0, 0, 1, "tin_can_tripline", "p1")
    DeadwireNetwork.registerTile(2, 0, 0, 1, "tin_can_tripline", "p1")
    local tiles = DeadwireNetwork.getNetworkTiles(1)
    assert_eq(#tiles, 3)
end)

test("returns entry objects with correct coordinates", function()
    _reset()
    DeadwireNetwork.registerTile(10, 20, 1, 1, "bell_tripline", "p1")
    local tiles = DeadwireNetwork.getNetworkTiles(1)
    assert_eq(#tiles, 1)
    assert_eq(tiles[1].x, 10)
    assert_eq(tiles[1].y, 20)
    assert_eq(tiles[1].z, 1)
end)

test("does not include tiles from a different network", function()
    _reset()
    DeadwireNetwork.registerTile(0, 0, 0, 1, "tin_can_tripline", "p1")
    DeadwireNetwork.registerTile(1, 0, 0, 2, "tin_can_tripline", "p2")
    local net1tiles = DeadwireNetwork.getNetworkTiles(1)
    local net2tiles = DeadwireNetwork.getNetworkTiles(2)
    assert_eq(#net1tiles, 1)
    assert_eq(#net2tiles, 1)
end)

test("returns fewer tiles after unregister", function()
    _reset()
    DeadwireNetwork.registerTile(0, 0, 0, 1, "tin_can_tripline", "p1")
    DeadwireNetwork.registerTile(1, 0, 0, 1, "tin_can_tripline", "p1")
    DeadwireNetwork.unregisterTile(0, 0, 0)
    local tiles = DeadwireNetwork.getNetworkTiles(1)
    assert_eq(#tiles, 1)
end)


suite("DeadwireNetwork.setIsoObject")

test("setIsoObject stores object retrievable via getTile", function()
    _reset()
    DeadwireNetwork.registerTile(3, 3, 0, 1, "tin_can_tripline", "p1")
    local fakeObj = { _name = "mock_iso_object" }
    DeadwireNetwork.setIsoObject(3, 3, 0, fakeObj)
    local entry = DeadwireNetwork.getTile(3, 3, 0)
    assert_not_nil(entry.isoObject, "isoObject should be set")
    assert_eq(entry.isoObject, fakeObj)
end)

test("setIsoObject on nonexistent tile is a no-op", function()
    _reset()
    local fakeObj = { _name = "ghost" }
    -- Should not throw
    DeadwireNetwork.setIsoObject(99, 99, 99, fakeObj)
end)

test("setIsoObject can be updated", function()
    _reset()
    DeadwireNetwork.registerTile(3, 3, 0, 1, "tin_can_tripline", "p1")
    local obj1 = { id = 1 }
    local obj2 = { id = 2 }
    DeadwireNetwork.setIsoObject(3, 3, 0, obj1)
    DeadwireNetwork.setIsoObject(3, 3, 0, obj2)
    local entry = DeadwireNetwork.getTile(3, 3, 0)
    assert_eq(entry.isoObject.id, 2, "isoObject should reflect the latest assignment")
end)


suite("DeadwireNetwork.getAllTiles")

test("getAllTiles returns all registered tiles", function()
    _reset()
    DeadwireNetwork.registerTile(0, 0, 0, 1, "tin_can_tripline", "p1")
    DeadwireNetwork.registerTile(1, 1, 0, 2, "bell_tripline", "p2")
    local all = DeadwireNetwork.getAllTiles()
    local count = 0
    for _ in pairs(all) do count = count + 1 end
    assert_eq(count, 2)
end)

test("getAllTiles keys match tileKey format", function()
    _reset()
    DeadwireNetwork.registerTile(7, 8, 0, 1, "tin_can_tripline", "p1")
    local all = DeadwireNetwork.getAllTiles()
    local expected_key = DeadwireNetwork.tileKey(7, 8, 0)
    assert_not_nil(all[expected_key], "getAllTiles should use tileKey format")
end)
