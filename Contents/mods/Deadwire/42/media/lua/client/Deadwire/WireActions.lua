-- Deadwire WireActions: timed actions for interacting with a placed wire
-- Client: queued behind luautils.walkAdj by the context menu in UI.lua
--
-- Why a timed action rather than firing the command straight from the menu:
-- the server now bounds how far a player can be from a wire they remove or
-- camouflage (#36), and a context menu can be opened on any tile on screen.
-- walkAdj queues the walk and this action runs when it finishes, so the player
-- is standing next to the wire by the time the command is sent. Sending from
-- the menu would have failed that bound for every click more than four tiles
-- out, which is most of them.
--
-- ISBaseTimedAction lives in the game's shared/ tree, and shared loads before
-- client, so deriving here at file scope is safe.

require "TimedActions/ISBaseTimedAction"
require "Deadwire/Config"
require "Deadwire/WireNetwork"
require "Deadwire/ClientCommands"

ISDeadwireWireAction = ISBaseTimedAction:derive("ISDeadwireWireAction")

-- The wire has to still be there when the walk finishes. Somebody else's zombie
-- can trip a tin can line and destroy it while the player is walking to it.
function ISDeadwireWireAction:isValid()
    local wire = DeadwireNetwork.getTile(self.wx, self.wy, self.wz)
    if not wire then return false end
    if self.command == "CamouflageWire" and wire.camouflaged then return false end
    -- The reverse of the line above (#56). Without it the action would be
    -- valid on a wire that is already plain, and the player would stand there
    -- playing the animation for nothing.
    if self.command == "UncamouflageWire" and not wire.camouflaged then return false end
    return true
end

function ISDeadwireWireAction:update()
    self.character:faceLocation(self.wx, self.wy)
end

function ISDeadwireWireAction:start()
    self:setActionAnim("Loot")
end

function ISDeadwireWireAction:stop()
    ISBaseTimedAction.stop(self)
end

-- The server validates all of this again. Nothing here is authority.
function ISDeadwireWireAction:perform()
    sendClientCommand(DeadwireConfig.MODULE, self.command, {
        x = self.wx,
        y = self.wy,
        z = self.wz,
    })
    ISBaseTimedAction.perform(self)
end

function ISDeadwireWireAction:new(character, command, x, y, z, maxTime)
    local o = ISBaseTimedAction.new(self, character)
    o.command = command
    o.wx = x
    o.wy = y
    o.wz = z
    o.stopOnWalk = true
    o.stopOnRun = true
    o.useProgressBar = true
    o.maxTime = character:isTimedActionInstant() and 1 or maxTime
    return o
end

DeadwireConfig.debugLog("WireActions initialized (client)")
