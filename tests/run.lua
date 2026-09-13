-- tests/run.lua
-- Entry point for the Deadwire test suite.
-- Run from the repo root: lua tests/run.lua

-- Set up package.path so require "Deadwire/X" resolves to the mod files
local base = "Contents/mods/Deadwire/42/media/lua"
package.path = base .. "/shared/?.lua;"
             .. base .. "/client/?.lua;"
             .. base .. "/server/?.lua;"
             -- Vanilla classes the mod requires by path. The game has them in
             -- its own shared/ tree; we do not, so a require that resolves to
             -- nothing here would throw at load and kill the rest of the file.
             .. "tests/pzstub/?.lua;"
             .. package.path

-- Load stubs FIRST (defines all PZ API globals before any mod code runs)
dofile("tests/stubs.lua")

-- Load test framework
dofile("tests/runner.lua")

-- Load Deadwire modules.
--
-- ALL FOURTEEN, deliberately. Six of them used to be loaded here and the other
-- eight ran in no test at all, so a file-scope throw in one of them -- the
-- shape that hid Events.OnPlayerConnect for a whole release -- was invisible
-- until the game refused the file (#47). Requiring a module is itself a test:
-- it executes every top-level line, including the event registrations at the
-- bottom, which is where the names have to be real.
--
-- Order matters and mirrors the game's: shared, then client, then server.
require "Deadwire/Config"
require "Deadwire/WireNetwork"
require "Deadwire/Power"          -- square:haveElectricity, per-circuit
require "Deadwire/Shock"          -- what a live wire does to a body
require "Deadwire/Detection"      -- registers Events.OnZombieUpdate / OnPlayerUpdate
require "Deadwire/ClientCommands" -- sendClientCommand wrappers
require "Deadwire/WireActions"    -- ISDeadwireWireAction, derives at file scope
require "Deadwire/UI"             -- registers Events.OnFillWorldObjectContextMenu
require "Deadwire/CamoVisibility" -- registers Events.OnTick
require "Deadwire/TriggerHandlers" -- registers the eight per-type handlers
require "Deadwire/EventHandlers"  -- registers Events.OnServerCommand / OnGameStart
require "Deadwire/WireManager"    -- registers Events.OnInitGlobalModData / LoadGridsquare
require "Deadwire/ServerCommands" -- registers Events.OnClientCommand
require "Deadwire/BuildActions"   -- ISDeadwireTripLine, the real placement path
require "Deadwire/CamoDegradation" -- registers Events.EveryTenMinutes
require "Deadwire/LootDistribution" -- registers Events.OnPreDistributionMerge
require "Deadwire/FenceElectrification" -- registers Events.OnTick, the fence pulse

-- Run test files
dofile("tests/test_config.lua")
dofile("tests/test_wire_network.lua")
dofile("tests/test_detection.lua")
dofile("tests/test_wire_manager.lua")
dofile("tests/test_server_commands.lua")
dofile("tests/test_build_actions.lua")
dofile("tests/test_ui.lua")
dofile("tests/test_wire_actions.lua")
dofile("tests/test_camo_visibility.lua")
dofile("tests/test_trigger_handlers.lua")
dofile("tests/test_camo_degradation.lua")
dofile("tests/test_loot_distribution.lua")
dofile("tests/test_event_handlers.lua")
dofile("tests/test_salvage.lua")
dofile("tests/test_electric.lua")

-- Print final results (exits with code 1 if any failures)
results()
