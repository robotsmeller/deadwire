# Deadwire Context

```yaml
project: Deadwire
description: PZ mod — perimeter trip lines and electric fencing for Project Zomboid (B42+)
last_session: 29
last_updated: 2026-09-17
continue_with: "Rob decides on the posts-and-line redesign (#58). If yes, the first job is a one-session spike: draw one test line between two world points and have Rob look at it at two zoom levels and behind a wall. If no, finish testing: docs/TEST-PLAN.md Parts J, K, L (electric wire, electric fence, uncover camo), then C-G (#25)."
blockers: "#58 needs Rob's yes/no before any more visual or placement work, because it would replace the sprite model outright. #27 and #45 still need his decision too, and #58 answers most of #45."
```

## To Resume

```
Deadwire v0.1.1, Session 30. Start from origin/main. 9 issues open.

Session 29 was the first testing session and it changed direction. The mod
WORKS: sound, crossing vs walking beside, diagonal crossing, stand-still, all
confirmed live. But Rob judged the UX weak -- too many visual glitches and
workarounds -- and asked for a better model. My recommendation, written up in
full on #58: posts centred on tiles plus a coloured line we draw ourselves,
owner-visible, crossing detected as segment geometry. Nothing is built.

FIRST: ask Rob whether #58 goes ahead. Do not start the rewrite without a
yes. The spike (one test line drawn in-world) comes before the rewrite.

Small and independent of #58: #59, the alarm goes quiet for 36s after one
trip. Split the sound gap (~2s) from the effect cooldown.

TALK TO ROB IN PLAIN WORDS, no issue numbers, no labels only we understand.

HARNESS: cd c:/xampp/htdocs/pz-test-pilot, python scripts/cmd.py get_status.
"harness_dead / heartbeat stale" means the game is paused or unfocused, not
crashed -- ask Rob to click back in. The PumpsHavePropane-transplant stack
trace on right-click is that mod's, not ours. set_sandbox_var sets the Lua
SandboxVars table and takes effect live (LogWireTriggers=true is how trip
events get into console.txt). Setup probes for Parts J/K are in the Session
28 notes in git history (6beae16).

Gates: run_tests.bat 398 pass (PowerShell: cmd /c .\run_tests.bat),
verify_names.py all resolve, validate_pack.py 130 checks.
```

## How PZ actually loads and routes mod Lua

0. **In single player, `isServer()` and `isClient()` are BOTH false.** The
   authoritative-side guard is `if isClient() then return end`.
1. **A game client runs `shared/`, `client/` AND `server/` Lua.** `server/`
   means "loaded last", not "server only".
2. **A dedicated server runs `shared/` and `server/` only.**
3. **`sendServerCommand` does nothing except on a real dedicated server.**
4. **`sendClientCommand` in single player is asynchronous.**
5. **In multiplayer the server rebuilds the build object from scratch** via
   `BuildAction.parse`, by parameter name. IsoPlayer args are dropped (#32).
6. **Script files (`media/scripts/*.txt`) only strip `/* */` comments.**
   `ScriptParser.stripComments`, read from the 42.20 jar in Session 29. A `//`
   line stays as text and becomes the next block's header, and a block whose
   header is not `module` is skipped with no error. This silenced every sound
   and hid the electric recipe. verify_names.py now refuses `//` in scripts.

## What is actually verified in a running game

Session 18: IPC, item names, kits, recipes, categories, sandbox vars, loot
injection, sprites. Session 23: TEST-PLAN Parts A and B. Session 29: Part H
(all four sounds register and play; tin can rattle heard on a real crossing)
and Part I1-I5 (beside = silent, across both ways fires, standing still fires
once, diagonal fires both posts). NOT yet seen: the electric recipe in the
crafting menu, Parts C-G, J, K, L, and I6 (old saves).

## Sprites

**Index hazard:** `pz_tilesheet.py` globs `deadwire_*.png` alphabetically and
`DeadwireConfig.Sprites` holds the indices by hand: 0/1 bell, 2/3 electric,
4/5 reinforced, 6/7 tanglefoot, 8/9 tincan. Geometry (Session 26): an edge
sprite occupies one 32px tile edge, bottom-anchored on the ground diamond;
`tools/fix_sprite_geometry.py` re-seats art, never hand-edit. All of this is
moot if #58 lands.

## Name verification

`python scripts/verify_names.py` (exit 0 = everything resolves) checks perks,
items, distributions, icons, sprites, sandbox options both ways, translation
filenames, events, sounds, Java method arity, and now `//` in script files.
DOES NOT EXIST: `Perks.Foraging` (`PlantScavenging`), `Perks.Carpentry`
(`Woodwork`), `Capability.CanBuildAnywhere`, the `Climate` global,
`getRainStrength`, `Base.TreeBranch`, `Events.OnPlayerConnect`,
`sprite:getTextureCount()`. No electrocution system in the jar.

## B42 Mod Structure

`mod.info` at root AND in `42/`. `common/` must exist. `poster=42/poster.png`.
`sandbox-options.txt` in `42/media/`. Translations are JSON with NO `_EN`
suffix, from the fixed list in `Translator$1`.

## Key Rules

1. Privacy first. 2. All tasks in GitHub Issues. 3. Multiplayer first.
4. Test in game. 5. `module Base`, tags `deadwire:tagname`. 6. Detection is
client-side. 7. No guards around unverified API names. 8. A missing name logs
loudly. 9. **A checker must derive, not remember** -- verify_names stripped
`//` as a comment, so it checked a file the game never reads (Session 29).
10. `server/` is load order, not a guard. 11. Validate the reported thing,
not the reporter. 12. **Green tests are not evidence**; put the bug back.
13. Dead code is still somewhere things live.

## Architecture

Shared (WireNetwork, Config) → Client (Detection, UI, WireActions,
TriggerHandlers, CamoVisibility, EventHandlers) → Server (ServerCommands,
WireManager, BuildActions, LootDistribution, CamoDegradation). Cooldowns are
real seconds (`os.time`), per wire type, no fallback. Placement is
`ISDeadwireTripLine` only.

## Open Issues (9)

- **Decision:** #58 posts-and-line redesign (recommended). #27 bell vs
  reinforced. #45 damage and spans (mostly answered by #58).
- **Bugs:** #59 alarm silent 36s after one trip. #60 rail draws over the
  character. #48 outline floats -- Rob called it launch-blocking; #58
  dissolves #48 and #60.
- **Testing:** #25 Parts C-G. #12 one real container sighting.
- **Enhancement:** #46 camouflage costs materials.
- **Parked by Rob:** placement is one right-click per tile; folded into #58.

## Recent sessions

### Session 29 (2026-09-17): first real test, and a change of direction

Part H found all four sounds unregistered. The cause, read from the jar: the
script parser strips only `/* */`, and last session's `//` comments swallowed
the sound module and the electric recipe. My own goal from Session 28, and
the checker had blessed it by stripping `//` itself. Fixed both files, made
verify_names refuse `//` (mutation-checked), sound confirmed by ear. Part I
passed live (five extra-looking trips traced to repositioning with a
controlled single crossing). #49 closed. Rob then saw the floating outline
and the rail over his legs, and said the alarm going quiet for 36 seconds
defeats an early warning system. He asked for an audit and best practice.
Found: every visual bug comes from drawing a line on a tile edge in an engine
that only knows whole-tile objects. Recommended posts plus a self-drawn
owner-visible line (engine support confirmed: `IsoUtils.XToScreen`,
`SpriteRenderer.renderline`, foraging overlays; precedent 7 Days to Die fence
posts). Filed #58, #59, #60.

### Session 28 (2026-09-13): built the whole electric tier, verified none of it

Edge-crossing detection (#55), circuit adjacency (#53), electrified wire (#13)
and fence (#52) via `square:haveElectricity()` with no separate energiser,
un-camouflage (#56), Workshop packaging. All merged in PR #57 on green tests.
The `//` comments that broke sound and the electric recipe landed here.

### Session 27 (2026-09-10): live-verified the sprite geometry fix

Plain sprites sit correctly on tile edges. Found three bugs by looking: the
outline floats (#48), detection was direction-blind (#55), camouflage could
not be undone (#56).
