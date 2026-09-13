-- Deadwire UI: Context menu for wire placement and removal
-- Client: adds right-click options on ground tiles and placed wires

require "Deadwire/Config"
require "Deadwire/WireNetwork"
require "Deadwire/WireActions"
-- ISDeadwireTripLine is a global from server/BuildActions.lua (loaded before callbacks fire)

DeadwireUI = DeadwireUI or {}

-----------------------------------------------------------
-- Helpers
-----------------------------------------------------------

-- Friendly display names for wireType keys
local wireDisplayNames = {
    tin_can_tripline    = "Tin Can Trip Line",
    reinforced_tripline = "Reinforced Trip Line",
    bell_tripline       = "Bell Trip Line",
    tanglefoot          = "Tanglefoot",
    electric_tripline   = "Electrified Deadwire",
}

-- Count how many kit items the player has
local function countKitItems(character, wireType)
    local kitItem = DeadwireConfig.KitItems[wireType]
    if not kitItem then return -1 end -- no kit required
    local items = character:getInventory():getItemsFromFullType(kitItem, true)
    return items and items:size() or 0
end

-----------------------------------------------------------
-- Placement Menu
-----------------------------------------------------------

local function onPlaceWire(worldObjects, character, wireType)
    -- wireType first, character last: the server drops non-serializable
    -- arguments when it rebuilds this in MP. See BuildActions.lua (#32).
    local tripLine = ISDeadwireTripLine:new(wireType, character)
    getCell():setDrag(tripLine, character:getPlayerNum())
end

-----------------------------------------------------------
-- Acting on a placed wire
--
-- Both of these walk the player to the wire and then run a timed action,
-- rather than firing the command from the menu. The server bounds how far away
-- the player may be (#36) and a context menu can be opened on any tile on
-- screen, so without the walk every click more than four tiles out would be
-- silently refused.
--
-- walkAdj returns false when there is no reachable adjacent tile. Queue
-- nothing in that case, the same as vanilla.
-----------------------------------------------------------

local REMOVE_TIME       = 80
local CAMOUFLAGE_TIME   = 250
-- Stripping camo back off is quicker than applying it: you are pulling grass
-- off a wire you already know the position of, not hiding one.
local UNCAMOUFLAGE_TIME = 100
local FENCE_WIRE_TIME   = 300

local function queueWireAction(character, x, y, z, command, maxTime)
    local sq = getCell():getGridSquare(x, y, z)
    if not sq then return end
    if not luautils.walkAdj(character, sq, false) then return end
    ISTimedActionQueue.add(
        ISDeadwireWireAction:new(character, command, x, y, z, maxTime))
end

local function onRemoveWire(worldObjects, character, x, y, z)
    queueWireAction(character, x, y, z, "RemoveWire", REMOVE_TIME)
end

-- Camouflage had no player-facing entry point at all until now: twelve sandbox
-- options, a visibility model and a rain-degradation model, reachable only by
-- hand-sending a client command (#42). Materials and a skill check are still
-- Sprint 4; the server applies full durability for free today.
local function onCamouflageWire(worldObjects, character, x, y, z)
    queueWireAction(character, x, y, z, "CamouflageWire", CAMOUFLAGE_TIME)
end

-- #56. Camouflage used to be one-way, so a wire you hid stayed hidden for the
-- life of the save.
local function onUncamouflageWire(worldObjects, character, x, y, z)
    queueWireAction(character, x, y, z, "UncamouflageWire", UNCAMOUFLAGE_TIME)
end

local function onElectrifyFence(worldObjects, character, x, y, z)
    queueWireAction(character, x, y, z, "ElectrifyFence", FENCE_WIRE_TIME)
end

local function onDeElectrifyFence(worldObjects, character, x, y, z)
    queueWireAction(character, x, y, z, "DeElectrifyFence", FENCE_WIRE_TIME)
end

-----------------------------------------------------------
-- Context Menu Hook
-----------------------------------------------------------

local function onFillWorldObjectContextMenu(playerNum, context, worldObjects, test)
    if test then return end
    if not DeadwireConfig.getSandbox("EnableMod", true) then return end

    local character = getSpecificPlayer(playerNum)
    if not character then return end

    -- Find the ground square from world objects
    local square = nil
    for i = 1, #worldObjects do
        local obj = worldObjects[i]
        if obj and instanceof(obj, "IsoObject") then
            square = obj:getSquare()
            if square then break end
        end
    end
    if not square then return end

    local x, y, z = square:getX(), square:getY(), square:getZ()
    local existingWire = DeadwireNetwork.getTile(x, y, z)

    if existingWire then
        -- Wire exists on this tile: show removal option
        local username = character:getUsername() or "SP"
        local isOwner = existingWire.ownerId == username
        local isAdmin = isAdmin()

        if isOwner or isAdmin then
            local friendlyName = wireDisplayNames[existingWire.wireType] or existingWire.wireType
            context:addOption("Remove " .. friendlyName,
                worldObjects, onRemoveWire, character, x, y, z)

            if DeadwireConfig.getSandbox("EnableCamouflage", true) then
                if existingWire.camouflaged then
                    -- The menu is also the only way to tell: the sprite looks
                    -- identical camouflaged or not, so which of these two
                    -- options is showing is the visual tell (#56).
                    context:addOption("Uncover " .. friendlyName,
                        worldObjects, onUncamouflageWire, character, x, y, z)
                else
                    context:addOption("Camouflage " .. friendlyName,
                        worldObjects, onCamouflageWire, character, x, y, z)
                end
            end
        end
    else
        -- A fence on this square, and not one of ours, is the farmer's half
        -- (#52). Offered before the placement submenu because a square that
        -- holds a fence is not usually a square you also want a trip line on.
        if DeadwireConfig.isTierEnabled(3) and DeadwireFences ~= nil then
            local fence = DeadwireFences.findFence(square)
            if fence then
                if DeadwireFences.isElectrified(x, y, z) then
                    context:addOption("Disconnect fence wiring",
                        worldObjects, onDeElectrifyFence, character, x, y, z)
                else
                    context:addOption("Electrify this fence",
                        worldObjects, onElectrifyFence, character, x, y, z)
                end
            end
        end

        -- No wire: show placement submenu only if player has any kits
        local wireTypes = {
            { type = DeadwireConfig.WireTypes.TIN_CAN, label = "Tin Can Trip Line", tier = 0 },
            { type = DeadwireConfig.WireTypes.REINFORCED, label = "Reinforced Trip Line", tier = 1 },
            { type = DeadwireConfig.WireTypes.BELL, label = "Bell Trip Line", tier = 1 },
            { type = DeadwireConfig.WireTypes.TANGLEFOOT, label = "Tanglefoot", tier = 1 },
            { type = DeadwireConfig.WireTypes.ELECTRIC, label = "Electrified Deadwire", tier = 3 },
        }

        -- Build list of placeable wire types (tier enabled + has kit in inventory)
        local available = {}
        for _, wire in ipairs(wireTypes) do
            if DeadwireConfig.isTierEnabled(wire.tier) then
                local kitItem = DeadwireConfig.KitItems[wire.type]
                if kitItem then
                    local count = countKitItems(character, wire.type)
                    if count > 0 then
                        available[#available + 1] = { wire = wire, count = count }
                    end
                end
            end
        end

        -- Only show submenu if player has at least one kit
        if #available > 0 then
            local placeMenu = ISContextMenu:getNew(context)
            context:addSubMenu(
                context:addOption("Place Deadwire..."),
                placeMenu
            )

            for _, entry in ipairs(available) do
                local label = entry.wire.label .. " (" .. entry.count .. ")"
                placeMenu:addOption(label, worldObjects, onPlaceWire, character, entry.wire.type)
            end
        end
    end
end

Events.OnFillWorldObjectContextMenu.Add(onFillWorldObjectContextMenu)
DeadwireConfig.debugLog("UI context menus initialized (client)")
