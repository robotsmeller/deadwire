# Deadwire Context

```yaml
project: Deadwire
description: PZ mod — perimeter trip lines and electric fencing for Project Zomboid (B42+)
last_session: 28
last_updated: 2026-09-13
continue_with: "IN-GAME TESTING, and only that. Session 28 built a lot and verified none of it in a running game. Work docs/TEST-PLAN.md Parts H through L in order: H audio (#49), I crossing vs walking beside (#55), J the electrified deadwire (#13), K the electrified fence (#52, and K5 is the one that could still sink its design), L uncovering camouflage (#56). Then Parts C-G, which have never been run at all (#25)."
blockers: "Nothing blocks the testing. #27 (bell vs reinforced are stat-identical) and #45 (wire damage and spans) still need a decision from Rob and nothing else. The Workshop upload needs Rob at the Steam uploader; workshop.txt, preview.png and the poster are all in place now."
```

## To Resume

```
Deadwire v0.1.1, Session 29. Start from origin/main. Tree clean, 7 issues open.

Session 28 was a BUILD session and nothing in it has been watched running.
Five issues closed on green tests alone, which per Rule 12 is not evidence.
The single job of session 29 is to look at it in a game.

What landed, all merged to main in PR #57:

- Wires now fire on the EDGE they were crossed, not the tile they sit on
  (#55). Walking the length of your own perimeter no longer sets off every
  wire in it. Two behaviour changes fall out of this: standing still on a
  wire no longer re-triggers it, and entities carry three more modData keys.
- Circuit adjacency (#53): a run is a connected component over orthogonally
  adjacent tiles, recomputed whole at place and remove time.
- Electrified deadwire (#13) and electrified fencing (#52). One power call,
  square:haveElectricity(), paired with AllowExteriorGenerator outdoors.
  There is NO separate energiser object: a run is live if any tile of it
  stands on a powered square. That was a deliberate scope call, logged in
  .claude/afk-log.md, and it is reversible -- the power question is isolated
  behind DeadwirePower.isCircuitLive.
- Camouflage can be undone (#56), and which menu option shows is the only
  visual tell there is.
- Workshop packaging: poster.png (generated, placeholder), workshop.txt,
  preview.png. mod.info had pointed at a poster that never existed.
- Audio (#49): the sound script declared its blocks at file scope. All 150
  vanilla sound scripts wrap them in `module Base { }`. Fixed, NOT verified,
  issue deliberately left open.

TALK TO ROB IN PLAIN WORDS, no issue numbers, no labels only we understand.

HARNESS: cd c:/xampp/htdocs/pz-test-pilot, scripts/cmd.py get_status.
loadstring is off so run_lua always throws. cmd.py can't pass a real JSON
array through args=; call _ipc.send_command from a short Python script for a
list. teleportTo(x,y,z) is a real, verified IsoGameCharacter method.

`deadwire_probe_setup` (step=teleport, then step=build) teleports to a fixed
outdoor site (8504,9414,0) and builds a real activated generator + StickFence.
A generator left running for days burns its tank dry; remove_object + rebuild
before trusting a power reading, and advance_time past ElecShutModifier
BEFORE building, not after.

NEW in session 28:
  `deadwire_probe_audio  step=check`   is the sound registered at all
  `deadwire_probe_audio  step=play`    play it three ways, say which you heard
  `deadwire_probe_electric step=report` READ-ONLY power readings, run first
  `deadwire_probe_electric step=wires`  lay a four-tile electric run
  `deadwire_probe_electric step=fence`  electrify the StickFence
  `deadwire_probe_electric step=cross`  position for the crossing test

Gates: run_tests.bat 398 pass over 17 files, verify_names.py 392 refs,
validate_pack.py 130 checks. PowerShell, not Git Bash.
```

## How PZ actually loads and routes mod Lua

Read from bytecode in Session 20. Half of Sessions 20 and 21 only make sense
with these, and every guard written before them was written blind.

0. **In single player, `isServer()` and `isClient()` are BOTH false.**
   `isServer()` is true only on a dedicated server. The guard for "the
   authoritative side" is `if isClient() then return end`, which runs in single
   player and on the dedicated server. Getting this backwards meant no Deadwire
   loot ever spawned in any single-player game, silently, for the mod's whole
   life (Session 18).
1. **A game client runs `shared/`, `client/` AND `server/` Lua.** `GameWindow`
   loads shared and client at boot; `GameLoadingState` loads `server` whenever a
   world loads. `server/` does not mean "server only". It means "loaded last".
2. **A dedicated server runs `shared/` and `server/` only.** `GameServer` calls
   `LoadDirBase("client", true)`, which checksums without executing. No
   `client/` code of ours can ever run there.
3. **`sendServerCommand` does nothing except on a real dedicated server.** Both
   overloads are `if (GameServer.server) ...; return;`. Everything in
   `client/EventHandlers.lua` is dead in single player; the mod works there only
   because both halves share one `tileIndex` in memory.
4. **`sendClientCommand` in single player is asynchronous**, arriving on the
   next net pass, not the same frame.
5. **In multiplayer the server rebuilds the build object from scratch.**
   `BuildAction.parse` reads the class name from the metatable and calls
   `<Type>:new(...)` with values harvested **by parameter name**. Only String,
   Double, Boolean, table, InventoryItem, IsoDirections and IsoDeadBody survive.
   An IsoPlayer argument is silently dropped, which was #32.

Corollary: **`server/` is the wrong place to put a guard.** If a file must not
run on a multiplayer client, write `if isClient() then return end` inside it.

## What is actually verified in a running game

Session 18, in a real 42.20 game: harness IPC, item display names, all 4 kits
spawning, all 4 recipes registered and translated, item and crafting categories
resolving, `SandboxVars.Deadwire` via `getSandbox`, loot injection at **11/11
tables, chance 12**, and all 10 sprites as distinct 64x128 textures. Session 23
added Parts A and B of `docs/TEST-PLAN.md`, 24/24, including `createWire`'s real
path. Parts C to G are still unrun and are the list of what that leaves.

## Sprites

Art is finished. What remains here is only what breaks if you touch it.

**Index hazard:** `pz_tilesheet.py` globs `deadwire_*.png` alphabetically, and
`DeadwireConfig.Sprites` holds those indices by hand. A new sprite that sorts
earlier renumbers everything after it, silently.

```
0/1 bell      2/3 electric (in use since Session 28, #13)
4/5 reinforced   6/7 tanglefoot   8/9 tincan
```

**Geometry, corrected Session 26 (#51):** an edge sprite occupies ONE 32px
tile edge, not the full 64px cell width, and sits bottom-anchored on the tile
ground diamond -- N(32,96) E(64,112) S(32,128) W(0,112) in a 64x128 cell,
derived from Tiles1x.floor.pack, not from our own prior art. North-facing art
descends left to right into x 30..62; west-facing ascends into x 1..33; both
baseline y=110, matching fencing_01_5/_4 exactly. The old target ("spans the
full 64px, bottom at y=96") was measured from our own sprites and agreed with
itself, which is how a wire ended up floating above and across the whole tile,
covering a character next door.

Facings were also swapped: every _n file held ascending (west-shaped) art and
every _e file held descending (north-shaped) art, so a north-edge wire drew
the west sprite. tools/fix_sprite_geometry.py re-seats and re-swaps existing
art and refuses to write if a file measured slope disagrees with its name --
run it, do not hand-edit the PNGs. Sprites are now half their old width;
detail was traded away because the source renders were not kept, so a
faithful redraw needs a new render pass, not a fix to this pipeline.
tools/process_sprite_render.py carries the corrected target and prompt.

**The `.tiles` file:** `42/media/deadwire_01.tiles` is what the game loads;
there is no `.tiles.txt` any more, the game never opened it. The fifth
per-tileset field is the **tileset number**, bounded 1..512 by
`LoadTileDefinitions`, NOT the mod.info tiledef id whose range is 100..8190.
`tools/pz-tilesheet` used to write the tiledef id there, so a future id above
512 would have made the game refuse the file and every world sprite vanish with
no error. Fixed to write 1; our shipped file says 200, legal and loads.

## Name verification: run the script, do not check by hand

```bash
python scripts/verify_names.py          # exit 0 = everything resolves
```

Resolves **322** references against the installed 42.20.4: perks, capabilities,
body parts, `Base.X` items, distributions, icon PNGs, sprite names, sandbox
options **in both directions**, translation filenames, category and page label
keys, the tiledef id range, event and sound names, the binary `.tiles` header,
and Java method existence and arity. `scripts/pzclass.py` is the `.class` reader
underneath and walks the superclass chain.

`--update-events` regenerates `tests/pz_events.lua`, the allow-list
`tests/stubs.lua` uses to refuse an event name the game does not have. The gate
fails if that committed copy drifts from the jar.

The script proves what exists. The traps live here. DOES NOT EXIST:
`Perks.Foraging` (it is `PlantScavenging`), `Perks.Carpentry` (`Woodwork`),
`Capability.CanBuildAnywhere` (`UseBuildCheat`), the `Climate` global
(`getClimateManager()`), `getRainStrength` (`getRainIntensity`),
`Base.TreeBranch` (`TreeBranch2`), `Events.OnPlayerConnect`, any church
distribution, `sprite:getTextureCount()`, and `getTextOrNull` for recipe display
names. There is **no electrocution system anywhere in the jar.**

**Internal name ≠ displayed name.** `Woodwork` displays as "Carpentry",
`PlantScavenging` as "Foraging".

## B42 Mod Structure (REQUIRED)

`mod.info` at root of the mod AND in `42/`, both must match. `common/` must
exist even if empty. `poster=42/poster.png`. `sandbox-options.txt` in
`42/media/`.

**Translations (42.15+) are JSON with NO `_EN` suffix** — the `EN/` directory
already says the language. `zombie/core/Translator$1` holds a fixed list of base
names; a file outside it is never opened, with no error. verify_names now reads
that list from the jar rather than remembering it. Categories need
`IGUI_ItemCat_X` and `IGUI_CraftingCategories_X` in `IG_UI.json`; the sandbox
page label needs `Sandbox_<page>` in `Sandbox.json`.

## Key Rules

1. **Privacy First**: no PII or credentials in commits
2. **GitHub Issues**: all tasks tracked in Issues
3. **Multiplayer First**: server-authoritative
4. **Test In-Game**: provide clear test steps
5. **Module Base** for all items; namespace tags `deadwire:tagname`
6. **Detection is CLIENT-side**: OnZombieUpdate/OnPlayerUpdate are client events
7. **No guards around unverified API names.** A guard around a typo is
   indistinguishable from a guard around a real fallback. Cost three dead
   features (Session 16) and one invisible fallback sprite (#39).
8. **A missing name logs loudly.** Never substitute a default for it.
9. **A checker must derive, not remember.** Four checkers have now blessed bugs
   by agreeing with a hardcoded value nobody rechecked. A checker that supplies
   whatever it is asked for cannot detect an absence.
10. **`server/` is a load-order directory, not a guard** (see run modes above).
11. **Validate the reported thing, not the reporter.** The trigger gate checked
    how far away the reporting player was, when the question was where the
    zombie is. Re-derive from world state server-side (#31).
12. **Green tests are not evidence.** Put the bug back and confirm they fail.
    Every fix in Sessions 21 and 22 was checked that way, and two of the checks
    that looked fine did not bite until the mutation was made faithful.
13. **Dead code is still somewhere things live.** "Nothing calls it" is a
    complete answer to the wrong question. Deleting the uncalled `PlaceWire`
    handler also deleted the only reader of `WireMaxPerPlayer` and
    `LogWirePlacements`. Before deleting a path, ask what it is the only place
    for. verify_names caught this one; it will not always be there.

## Architecture

Shared (WireNetwork, Config) → Client (Detection, UI, WireActions,
TriggerHandlers, CamoVisibility, EventHandlers) → Server (ServerCommands,
WireManager, BuildActions, LootDistribution, CamoDegradation). Client
`sendClientCommand`, server validates, `sendServerCommand` broadcasts.
`ISBuildingObject:derive()` files MUST live in `server/`. Cooldowns are **real
seconds** (`os.time`), broadcast as a *duration* because clocks are
independently skewed, and declared per wire type with no fallback.

Placement is `ISDeadwireTripLine` only; there is no PlaceWire command. Acting on
a placed wire goes through `luautils.walkAdj` plus `ISDeadwireWireAction`, so
the player is standing next to it when the server's four-tile bound is checked.

## Gates

All local, no CI. `run_tests.bat` compiles **all 17** mod `.lua` files
(`tests/syntax_check.lua`) and stops there on failure, then runs the suite,
**398 pass**. PowerShell, not Git Bash -- `cmd //c` fails on the path, not the
tests. `python scripts/verify_names.py` **392 refs**. `python
tools/validate_pack.py` **130 checks**.

The syntax gate enumerates the tree rather than carrying a file list, and
finding zero files is a failure, not a pass. It compiles without executing, so
a file-scope call that throws at runtime gets past it; requiring all seventeen
in `tests/run.lua` is what catches that.

## Open Issues

Seven open. #13, #52, #53, #55 and #56 all closed in Session 28 by PR #57 --
on green tests, which is not the same as working, and Parts H-L of the test
plan are what would make them real.

- **Next, in game, and this is the whole job:** Parts H-L of
  docs/TEST-PLAN.md cover everything Session 28 built. Then #49 the tin can
  audio, #25 Parts C-G, #12 one real container sighting.
- **Needs a decision from Rob:** #27 bell and reinforced are the same wire
  with a different noise. #45 wire damage, spans, tanglefoot wear.
- **Art:** #48 the owner/camo outline box is drawn off the object's engine
  bounds rather than the sprite art, a separate draw path from the #51 fix.
  tin_can_rattle.ogg needs mastering. The sprites themselves are still
  placeholder-grade, and workshop.txt now asks Workshop users for help.
- **Deliberately not done:** the electrified deadwire kit is craft-only and
  is not in any loot table. Tier 3 gated behind Electricity 3 should not be
  lying in a toolbox.

## Recent sessions

### Session 28 (2026-09-13): built the whole electric tier, verified none of it

Rob asked what was really blocking launch, then said to do everything
possible out of game and stop when it was ready to test. Five issues closed,
three commits, one PR merged, and not one line of it watched in a game.

**The launch answer, which was smaller than expected.** Almost nothing
technical was blocking. Two missing files stopped a Workshop upload:
mod.info pointed at 42/poster.png, which had never existed, and there was no
workshop.txt or preview image. Both made this session. The real risk was
that a zombie tripping a wire had never been observed, but zombies and
players share one detection function and the player half was confirmed in
Session 27, so that is a look-once job rather than an unknown.

**#55 was the one that would have earned bad reviews.** Detection fired on
tile occupancy, so a wire went off when you walked ALONG it. The facing was
being thrown away the instant the object was built, even though the sprite
and the IsoThumpable were both constructed from it. Now recorded, persisted,
broadcast, and recovered off the object's own getNorth() for older saves. The
edge convention that makes the arithmetic honest: the boundary between
(x,y-1) and (x,y) is the NORTH edge of (x,y). Diagonals are credited to both
components deliberately, because a wire dodgeable at 45 degrees would be
worse than the bug.

**The audio, diagnosed by measurement rather than by listening again.** Ruled
out first, each with evidence: all four oggs are mono 44.1kHz peaking at full
scale, so neither stereo nor silent; category = Item is the most-used
category in the game's own scripts, 1521 blocks of it; is3D and clip.file are
both real fields on GameSound and GameSoundClip in the 42.20 jar; and
PlayWorldSound's 6-arg overload exists with the types we pass. What was left:
all 150 vanilla sound scripts wrap their blocks in a module and ours did not.
Rob offered to record louder sounds and the measurement is what said not to
bother. Unverified, so #49 stays open.

**Tier 3, both halves.** The power model is one call and deliberately nothing
more, so any power mod that energises a square the vanilla way works for
free. The scope call worth knowing: there is no separate energiser object. A
run is live when any tile of it stands on a powered square. The design asks
for a real energiser and that is the better shape, but it needs an item, a
recipe, a sprite and a build action before one wire could be tested. The
power question is isolated behind isCircuitLive, so adding it later changes
which square gets asked and nothing else.

For the fence, the register of live fences is kept in OUR GlobalModData
rather than as modData on the fence object. #52 flagged foreign-object
modData surviving a reload as load-bearing and unverified; keeping our own
list turns that into a cosmetic unknown. Part K5 of the test plan is still
the check that could sink it.

**Two own goals worth keeping.** The direction tests failed on first run
because the mock entities were seeded with an arrival history, which made the
step under test a two-tile jump -- a test-harness bug wearing a code bug's
clothes, and I nearly went looking in the wrong file. And I wrote "every
other mod on this machine wraps its sound blocks in a module" into two files
before checking; no other installed mod ships a sound script at all, so
vanilla was the whole comparison set. Corrected both before committing.

Eleven mutations confirmed biting across the two features, plus a no-op
control that stayed green, which is the check that the suite is not failing
for unrelated reasons.

### Session 27 (2026-09-10): live-verified #51, found three bugs it was never going to fix

Rob restarted PZ and looked. The harness (deadwire_smoke_b) placed one wire of
each type at his feet rather than hand-building through the crafting menu --
faster, and it exercises the same createWire path the real UI does.

**Confirmed: plain sprites are fixed.** All four wire types sit on the ground
along a tile edge, correct length, no longer floating over him as he walked
past. First live confirmation since #51 landed in Session 26 -- the code fix
alone was explicitly not counted as done until someone looked at it running.

**Three real bugs, found looking rather than testing for them:**

- The owner/camo glow outline (#48, already open) still floats exactly like
  the old sprite bug, on wires whose plain sprite is now correct. Traced it:
  CamoVisibility.lua's setOutline() calls obj:setOutlineHighlight(true), an
  engine-drawn box keyed to the IsoObject's own collision bounds, not to the
  sprite bitmap #51 fixed. Two unrelated draw paths sharing one symptom --
  updated #48 with this, did not touch the code.
- Trigger detection is direction-blind (#55, new). Reinforced knocks the
  player back walking parallel to the wire, same as crossing it; tin can
  breaks the same way. TriggerHandlers.lua only checks tile occupancy, no
  comparison against the wire's own orientation.
- Camouflage cannot be undone and carries no visual tell (#56, new).
  WireActions.lua's isValid() refuses CamouflageWire once already camouflaged,
  and no reverse command exists. The sprite looks identical camouflaged or not,
  so the owner has no way to check whether it worked.

One near-miss on the session's own method: my first read of "wires always sit
on the top-left of the tile, never the right side" looked like a fourth bug.
It was not -- deadwire_smoke_b hardcodes north=false for every placement, so
all four test wires shared one facing. Caught before filing anything, but it
is the same shape as the journal's stale-context trap: a tool's own
convenience default read as a finding about the mod.

A stack trace also showed in the console during testing -- checked and it is
PumpsHavePropane-transplant throwing in its own OnContextMenu handler,
nothing to do with Deadwire.

Rob's call for next session: attempt a real art pass on the sprites (the
geometry is now confirmed correct, so a redraw has something solid to sit on)
rather than another fix to this pipeline.

### Session 26 (2026-09-10): the wire sprite was drawn wrong, in two ways at once

Rob asked whether #51 (wire draws over the character) had ever actually been
fixed. It had not -- the issue body says it needs the tilesheet touched, not
Lua, and nothing had touched the tilesheet.

**Every sprite floated above and across its own tile.** A PZ tile sprite is a
64x128 cell; the ground it occupies is a diamond in the bottom quarter,
derived from measuring Tiles1x.floor.pack rather than assumed: every floor
tile is a 63x32 image pasted at offset (0,96), giving N(32,96) E(64,112)
S(32,128) W(0,112). Our art spanned the full 64px width and bottomed out at
y=96 -- the edge of a diamond that does not exist on this engine. That target
was written into tools/process_sprite_render.py and said outright it came
from the sprites already in the mod, so the art was checked against itself
and passed. Measured against vanilla instead: fencing_01_5 (WallN) occupies
x 30..62, y 59..110, half the cell width, well inside the real diamond.

**Second bug, found only because vanilla was measured to confirm the first.**
Every _n (north) sprite file held art that ascends left to right, and every
_e file held art that descends -- backwards. Vanilla's own WallN tiles
(fencing_01_5/_17/_21) all descend; its WallW tiles (fencing_01_4/_16/_20)
all ascend, six for six. So a wire built on a north edge has been drawing the
west-shaped sprite for the mod's entire life.

Ruled out along the way: draw ordering (IsoCell bytecode draws every object
on a square before any character on it -- cannot explain covering a
neighbour) and vanilla's WallN/WallW flags (they also set collideN/collideW,
which would break zombie pass-through, the whole point of a trip wire).

**Fix is tools/fix_sprite_geometry.py.** Halves each sprite (nearest
neighbour, keeps the 2:1 diagonal, costs pixel detail -- accepted, since the
source renders were never kept) and re-seats it on the correct edge, swapping
art between _n/_e files where the measured slope disagrees with the filename.
Refuses to write if a slope cannot be resolved. Rebuilt the pack and .tiles
from tools/pz-tilesheet/pz_tilesheet.py, corrected the geometry target and
Gemini prompt in process_sprite_render.py. 346 tests, 322 names, 130 pack
checks, all green.

**Not yet confirmed live.** Rob's call, made explicitly: ship with
placeholder-grade art rather than block launch on a redraw, and ask Workshop
users if anyone wants to help with better sprites. The geometry fix stands
regardless of art quality, but nobody has stood next to a wire in-game since
it landed -- that is the first thing next session does, and per Rule 12
(green tests are not evidence) it does not count as done until someone has
looked at it running.

### Session 25 (2026-09-08): four unknowns answered, and two false readings caught before they shipped

All four Tier 3 probes from #54 run live -- full results on #54, #13, #52.

**`deadwire_probe_setup` builds a real generator and real fence from Lua**,
no hand-built base needed: the generator via vanilla's own
`MOGenerator.lua` construction path, the fence via `ISBuildIsoEntity` with
build cheat flipped on, the same path the F2 debug entity panel uses. Two
bugs before it worked, both needing a relaunch to catch since the fix lives
in code loaded at process boot: `setInfo()` reads `self.player`, unset
outside the normal drag-to-place flow, threw deep in perk-level lookup; and
the fence's `nSprite=1` (west layout) disagreed with a hardcoded `north=true`
passed to `create()`, which would have built the fence with its collision on
the wrong edge -- exactly what the vault probe measures.

**Two false power-radius readings before the real one.** Day 1's city grid
was still live, so `haveElectricity()` read true everywhere regardless of the
generator -- looked like a huge radius, meant nothing. Jumped the clock past
`ElecShutModifier` (instant, no real-time cost) to kill grid power, which
surfaced a second false reading: the generator, "on" for the whole jump, had
burned its tank dry and read unpowered everywhere including its own square.
Neither was a probe bug, both were artifacts of skipping simulated time
instead of living through it. Rebuilt the generator fresh post-jump; real
reading was 40 tiles, not the Generator Range mod's hardcoded 20. Repeated on
a second save after Rob's first corrupted -- same trap, same fix, so it's the
process, not the save.

**No registered handler could spawn a zombie**, and `SendCommandToServer`
routed through `call_function` ran with no error and no effect either --
fire-and-forget gives no way to tell permissions gate from silent parse
failure. What worked: right-click ground with `-debug` running gives a real
Debug > Add Zombie option, a real player action instead of a scripted one.

**One cosmetic casualty left alone:** right-clicking the directly-built
generator throws a stack error, some field a normal placement wires up that
`IsoGenerator.new` alone doesn't. Throwaway test code, not the mod.

### Session 24 (2026-09-08): eight dark files lit, and Tier 3 designed

Three commits here plus one in pz-test-pilot, and the mod stopped carrying code
nobody had ever executed.

**All fourteen files now load in the suite (e436ee6, #47).** Eight ran in no
test at all. `run_tests.bat` compiles every mod `.lua` first, then runs the
suite; 201 tests became 330 across seven new files. Twenty mutations, all
caught. The real find was in the suite itself: `test_detection.lua` nils handler
entries per test and never restored them, so once TriggerHandlers loaded, every
file after it silently ran against zero registered handlers.

**A destroyed wire leaves its parts (1fb8faf, #50).** One roll per wire over its
durable parts; a wire taken up by hand returns the whole kit with no roll. Cord
is never salvaged, which dissolved the design knot -- the recipes accept any of
three cords, the kit records none, and the cord is what snapped. 330 to 346.
Mutation testing caught two stubs that had blessed real bugs: `ZombRand`
answered the same number forever, hiding one-roll-per-part, and accepted a
bound below 1, hiding a range computed backwards.

**Tier 3 designed and split (#13, #52, #53, #54).** Rob's framing: a farmer and
a survivalist are different people. A pasture fence is meant to be seen, since
visibility is the deterrent; an electrified deadwire is meant not to be. Two
API claims in the old #13 body were wrong and would each have cost a session --
`isGeneratorPoweringSquare()` is on `IsoChunk`, not `IsoGridSquare`, and
`setGeneratorRange` takes zero arguments. The power model is one
`square:haveElectricity()` call on the energiser's square, which is
radius-agnostic and so satisfied by any power mod energising a square the
vanilla way. `GeneratorNetwork_42` in Rob's own mods folder does exactly that,
so the compatibility claim has a working example rather than a hope.

**pz-test-pilot pushed (cb03c49).** Session 23's smoke handlers had sat
uncommitted for a session. Four `deadwire_probe_*` handlers added for #54.
Corrected that repo's CLAUDE.md, which claimed `loadstring()` works; it does
not, and that sentence sent Session 23 down a blind alley.

Session 23's write-up (watched `createWire` run live for the first time,
filed #48-#51) is in `.claude/archive/sessions.md`.
