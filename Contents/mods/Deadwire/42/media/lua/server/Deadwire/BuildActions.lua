-- Deadwire BuildActions: ISBuildingObject derivative for wire placement
-- Server: ISBuildingObject and derivatives must be in server/ (PZ load order)
-- create() runs server-side in MP via PZ's ISBuildAction:perform

require "Deadwire/Config"
require "Deadwire/WireNetwork"
require "Deadwire/WireManager"

-----------------------------------------------------------
-- ISDeadwireTripLine: Buildable wire object
-----------------------------------------------------------

ISDeadwireTripLine = ISBuildingObject:derive("ISDeadwireTripLine")

function ISDeadwireTripLine:create(x, y, z, north, sprite)
    local sq = getWorld():getCell():getGridSquare(x, y, z)
    if not sq then return end

    -- Both paths set self.character: ISBuildAction:perform in single player,
    -- shared/ActionManager.lua in multiplayer. If neither did, say so rather
    -- than erroring three lines down on a nil index.
    if not self.character then
        DeadwireConfig.log("BuildActions: create with no character, aborting")
        return
    end

    local wireType = self.wireType or DeadwireConfig.WireTypes.TIN_CAN
    local username = self.character:getUsername() or "SP"

    -- The tier gate and the wire cap used to live in the PlaceWire server
    -- command, which #36 deleted as an unchecked second placement path. They
    -- belong here, on the path that actually places wires: this create() runs
    -- server-side in multiplayer, so a client that never opened our context
    -- menu still passes through it.
    local defaults = DeadwireConfig.WireDefaults[wireType]
    if not defaults then
        DeadwireConfig.log("BuildActions: unknown wire type " .. tostring(wireType))
        return
    end
    if not DeadwireConfig.isTierEnabled(defaults.tier) then
        DeadwireConfig.debugLog("BuildActions: tier " .. defaults.tier .. " disabled")
        return
    end

    local maxWires = DeadwireConfig.getSandbox("WireMaxPerPlayer", 50)
    if DeadwireNetwork.getPlayerTileCount(username) >= maxWires then
        DeadwireConfig.log("BuildActions: " .. username .. " at wire limit (" .. maxWires .. ")")
        return
    end

    local networkId = DeadwireNetwork.generateNetworkId()

    -- Verify kit item exists before attempting placement (consume only after success)
    local kitItem = DeadwireConfig.KitItems[wireType]
    local kitItemObj = nil
    if kitItem then
        kitItemObj = self.character:getInventory():getFirstTypeRecurse(kitItem)
        if not kitItemObj then
            DeadwireConfig.debugLog("BuildActions: missing kit " .. kitItem)
            return
        end
    end

    local obj = DeadwireWireManager.createWire(sq, wireType, username, networkId, north)
    if not obj then return end

    -- Consume kit only after wire placement confirmed
    if kitItemObj then
        self.character:getInventory():Remove(kitItemObj)
    end

    if DeadwireConfig.getSandbox("LogWirePlacements", true) then
        DeadwireConfig.log("Wire placed: " .. wireType .. " at "
            .. x .. "," .. y .. "," .. z .. " by " .. username)
    end

    sendServerCommand(DeadwireConfig.MODULE, "WirePlaced", {
        x = x,
        y = y,
        z = z,
        networkId = networkId,
        wireType = wireType,
        ownerId = username,
        north = north and true or false,
    })
end

-- Argument order matters, and character MUST come last (#32).
--
-- In multiplayer ISBuildAction:perform returns before create(). The server
-- rebuilds this object from scratch in zombie.core.BuildAction.parse, which
-- harvests values from the client instance BY PARAMETER NAME and calls
-- <Type>:new(...) positionally. Only String, Double, Boolean, table,
-- InventoryItem, IsoDirections and IsoDeadBody survive that trip; an IsoPlayer
-- is silently dropped. With character first, the server was calling
-- new("tin_can_tripline") -- character got the string, wireType went nil, every
-- wire defaulted to tin can and getPlayerNum() threw on a string.
--
-- Vanilla's own convention says the same thing: ISLightSource:new(sprite,
-- northSprite, character) and ISNaturalFloor:new(sprite, northSprite, item,
-- character) both put character last and tolerate nil.
function ISDeadwireTripLine:new(wireType, character)
    local o = {}
    setmetatable(o, self)
    self.__index = self
    o:init()

    -- Per-type sprites, with nothing substituted for a missing one (#39).
    local wt = wireType or DeadwireConfig.WireTypes.TIN_CAN
    local sprites = DeadwireConfig.Sprites[wt]
    if not sprites then
        DeadwireConfig.log("BuildActions: no sprites declared for " .. tostring(wt))
    end
    o:setSprite(sprites and sprites.east)
    o:setNorthSprite(sprites and sprites.north)

    -- character is nil on the server's rebuild; ActionManager sets it before
    -- create() runs. Note the server also assigns an IsoPlayer to o.player in
    -- parse, so never treat self.player as a number outside this function.
    o.character = character
    o.player = character and character:getPlayerNum() or 0
    o.wireType = wt
    o.name = "Trip Wire"
    o.canBeAlwaysPlaced = true
    o.noNeedHammer = true
    o.canPassThrough = true
    o.isWallLike = false
    o.actionAnim = "Loot"
    o.buildLow = true
    return o
end

function ISDeadwireTripLine:isValid(square)
    if not square then return false end
    local x, y, z = square:getX(), square:getY(), square:getZ()
    if DeadwireNetwork.getTile(x, y, z) then return false end
    if square:isVehicleIntersecting() then return false end
    if not square:isFreeOrMidair(true) then return false end
    return true
end

function ISDeadwireTripLine:render(x, y, z, square)
    ISBuildingObject.render(self, x, y, z, square)
end
