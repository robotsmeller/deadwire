-- Deadwire Power: is this run of wire live?
-- Shared: the trigger path runs client-side, the fence pulse runs server-side,
-- and both ask the same question, so the answer lives in one place.
--
-- The model is one call, square:haveElectricity(), and deliberately nothing
-- more. It returns true for grid power and for a generator, so any power mod
-- that energises a square through the vanilla API satisfies this for free --
-- GeneratorNetwork_42, already installed here, does exactly that. We never ask
-- a wire tile about generators, radii or fuel, which is what keeps the whole
-- feature compatible with mods nobody here has read.
--
-- Session 25 measured the real generator radius live at 40 tiles, not the 20
-- the Generator Range mod hardcodes. That number is not written down anywhere
-- in this file on purpose: asking the square means never needing to know it.
--
-- WHAT THIS DOES NOT HAVE, and why: there is no separate energiser object. A
-- run is live when any tile of it stands on a powered square. The design
-- (#13) describes an energiser as the one object that asks about power, which
-- is the better long-term shape, but it needs a new placeable, its own item,
-- recipe, sprite and build action before a single wire can be tested. This is
-- the reversible half of that: the power question is already isolated behind
-- isCircuitLive, so adding a real energiser later changes which square gets
-- asked and nothing else. Logged as a session-28 decision.

require "Deadwire/Config"
require "Deadwire/WireNetwork"

DeadwirePower = DeadwirePower or {}

-----------------------------------------------------------
-- One square
-----------------------------------------------------------

-- Vanilla pairs haveElectricity() with the AllowExteriorGenerator sandbox
-- check whenever the square is outdoors (ISVehicleMenu.lua:1088 is the
-- example this follows). Without that pairing an outdoor run would draw from
-- a generator on a server that has exterior generators switched off.
function DeadwirePower.isSquareLive(sq)
    if not sq then return false end
    if not sq:haveElectricity() then return false end

    if sq:isOutside() and not DeadwirePower.exteriorGeneratorsAllowed() then
        -- Grid power still counts outdoors; it is only the generator that the
        -- sandbox option gates. hasGridPower answers that directly.
        return sq:hasGridPower() and true or false
    end

    return true
end

function DeadwirePower.exteriorGeneratorsAllowed()
    -- Vanilla's own option, not one of ours, so it is read straight off
    -- SandboxVars rather than through DeadwireConfig.getSandbox (which looks
    -- under SandboxVars.Deadwire). Default true, matching the game default.
    if SandboxVars == nil then return true end
    local v = SandboxVars.AllowExteriorGenerator
    if v == nil then return true end
    return v and true or false
end

-----------------------------------------------------------
-- A run of wire
-----------------------------------------------------------

-- True when any tile of this wire's circuit stands on a live square.
--
-- The circuit is precomputed at place and remove time (#53), so this is a walk
-- over one run rather than a search of the map, and the trigger path pays only
-- for the length of the fence it is actually standing on.
function DeadwirePower.isCircuitLive(x, y, z)
    local tiles = DeadwireNetwork.getCircuitTiles(x, y, z)
    if #tiles == 0 then return false end

    local cell = getCell and getCell() or nil
    if not cell then return false end

    for _, tile in ipairs(tiles) do
        local sq = cell:getGridSquare(tile.x, tile.y, tile.z)
        if DeadwirePower.isSquareLive(sq) then
            return true
        end
    end
    return false
end

-----------------------------------------------------------
-- Generator draw
--
-- IsoGenerator carries a per-appliance consumption table and sums it in
-- getTotalPowerUsing(); SandboxVars.GeneratorFuelConsumption scales the burn.
-- Adding our draw to that total and subtracting it again on removal inherits
-- vanilla's entire fuel loop, so gas-barrel and solar mods keep working
-- because we never touch fuel ourselves.
--
-- #54 flagged this as unverified and load-bearing: IsoGenerator also has
-- updateGenerator and checkObjectPowered, and if it recomputes its own total
-- from a scan each update then our addition is wiped. That has still not been
-- watched in a running game, so this is written to be harmless either way --
-- it adjusts the total if the methods are there and does nothing if they are
-- not, and no other part of the feature depends on the draw landing. The
-- fence works whether or not the generator ever notices it. Part J of
-- docs/TEST-PLAN.md is the check.
-----------------------------------------------------------

function DeadwirePower.drawPerCircuit()
    return DeadwireConfig.getSandbox("ElectricPowerDraw", 20)
end

function DeadwirePower.adjustGeneratorDraw(sq, delta)
    if not sq or delta == 0 then return false end
    local gen = sq:getGenerator()
    if not gen then return false end
    if not gen.getTotalPowerUsing or not gen.setTotalPowerUsing then return false end

    local current = gen:getTotalPowerUsing() or 0
    local wanted = current + delta
    if wanted < 0 then wanted = 0 end
    gen:setTotalPowerUsing(wanted)
    DeadwireConfig.debugLog("Generator draw " .. current .. " -> " .. wanted)
    return true
end

DeadwireConfig.debugLog("Power initialized")
