# Archived session write-ups

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

Moved out of `.claude/context.md` by `.claude/hooks/context-prune.cjs`, which keeps
the newest three in the live file. Nothing loads this file; it is here because why
a thing was done a certain way is worth keeping and is worth nothing on every turn.

Read it when a decision looks arbitrary and you want to know what it cost.

---

## Art and sprite pipeline (sessions 15, 18, 19)


`tools/process_sprite_render.py` is the whole pipeline: hue-key the magenta,
erode the blend ring, area-average down to 64 wide, anchor to the tile's ground
edge, mirror east into north. Its docstring holds the working Gemini prompts.

**The geometry rule that matters:** in PZ's projection both facings are
diagonal and mirrored about the vertical axis. There is no flat-horizontal
orientation. The Session 10 placeholders drew north flat, which is why they
looked wrong rather than merely crude. Verified against vanilla `fencing_01`
sprites extracted with `pz_unpack.py`.

**Index hazard:** `pz_tilesheet.py` globs `deadwire_*.png` alphabetically.
A new sprite that sorts earlier renumbers everything after it, and
`DeadwireConfig.Sprites` holds those indices by hand. Adding `electric` in
Session 18 moved reinforced/tanglefoot/tincan from 2,4,6 to 4,6,8.

```
0/1 bell      2/3 electric (banked for #13, absent from Sprites on purpose)
4/5 reinforced   6/7 tanglefoot   8/9 tincan
```

Stake height above the ground line, after the Session 19 replacement:

| sprite | above ground |
|---|---|
| tincan, bell, reinforced, electric | 18px |
| tanglefoot | 6px |

Previously these ranged 22 to 32 and the tall ones read as fences rather than
trip lines.

**At 32px, silhouette contrast beats object identity.** An icon pass that shrank
the pale wire coil to enlarge the cans produced a brown blob on a dark
inventory panel. The coil is not filler, it is the high-contrast shape that
makes the item findable in a list. Tanglefoot is the clearest case the other
way: it reads instantly at 1x purely because the whole coil is rust-coloured.

**A local ComfyUI pipeline was built and abandoned.** SDXL with a pixel-art
LoRA holds composition once the hanging objects are drawn into the ControlNet
skeleton, but it renders thin and washed out at this scale and lost every
comparison against the existing art. The models are installed at C:/ai/ComfyUI
if anyone wants them; the generation half is not worth rebuilding.


---

## Session 18 bugs, in full


### `isServer()` is FALSE in single-player

`LootDistribution.lua` opened with `if not isServer() then return end`, so the
merge returned immediately and **no Deadwire loot has ever spawned in any
single-player game**. Not bells, not kits, not once.

In PZ single-player, `isServer()` and `isClient()` are **both false**.
`isServer()` is true only on a dedicated server. The correct guard for "the
authoritative side" is:

```lua
if isClient() then return end   -- runs in SP and on the dedicated server
```

`TriggerHandlers.lua` already used `if not isClient()` correctly, with a comment
explaining it. The knowledge was in the repo; the loot file just never got it.

### The crafting category key was wrong, and the checker agreed with it

The mod shipped `IGUI_CraftCategory_Deadwire`. B42 uses
**`IGUI_CraftingCategories_Deadwire`**. The sidebar rendered the raw key.

`verify_names.py` had the wrong prefix hardcoded and had been reporting it
green. A checker that encodes a remembered fact rather than a checked
relationship is worse than no checker: it converts an unverified belief into a
green tick. It now derives both category prefixes from the game's own
`IG_UI.json` and fails loudly if neither is found. Same fix applied to
`validate_pack.py`, which hardcoded "8 sprites" and failed the moment a
legitimate 9th and 10th were added.

The wrong prefix lived in exactly two places, the mod's `IG_UI.json` and
`verify_names.py`, and they agreed with each other. Nothing else in the repo or
in auto-memory recorded it, so there was no third source to catch the
disagreement. That is the shape to watch for: a checker and its subject sharing
one unverified assumption looks identical to a passing test.

### Inventory icons had opaque backgrounds

All four were 100% opaque, alpha 255 on every pixel, sitting on grey boxes in
the inventory. Rebuilt from the 1024x1024 originals with an edge flood-fill and
a premultiplied downscale. A plain white colour-key would have punched holes
through the tin cans, which is why the fill runs inward from the border.


---

### Session 17 (2026-08-05/06): eleven silent failures, six PRs

Built `scripts/verify_names.py` + `pzclass.py` **before** fixing anything.
Closed #14–#18 and found six more bugs on no issue at all. PRs #19–#24.

`Perks.Foraging` nil so camo was invisible forever (#17); the entire Climate
call was fiction so camo never degraded (#18); `Capability.CanBuildAnywhere` in
three places (#14); two MP exploits (#15); cooldowns in game time and checked on
the wrong side (#16). Found by the verifier: `ChurchStorageMisc` does not exist;
both Tier 1 recipes required the nonexistent perk `Carpentry`; **all three
translation files were named `*_EN.json` and were never loaded**; no
`IG_UI.json` existed; four sandbox options were read by no code.

### Session 16 (2026-08-05): B42.20.2 audit — six silent failures, three fixed

Audited against an installed 42.20 rather than docs. Fixed four bad loot table
names, a kit item id typo, and `Base.TreeBranch`. Filed #14–#18.
`pz-mod-checker scan` reported clean before and after and caught none of it.

### Session 15 (2026-04-14): Gemini inventory icons + pz_unpack.py

Built `pz_unpack.py` at `c:/xampp/htdocs/pz-tilesheet/`. Generated all 4
inventory icons — on opaque white backgrounds, which Session 18 had to fix.

---

### Session 20 (2026-09-06): the review

A Fable agent read all 2,136 lines against the installed jar with `javap`, not
inference. Fourteen findings, eleven confirmed, filed as #31 to #43. Report in
`docs/REVIEW-30.md`. Established the five run-mode facts above, and found two of
PLAN.md's own "expected behaviour" lines were fiction.

### Session 21 (2026-09-06): the review executed, and the checkers made honest

Ten issues closed across three commits. The mod's core feature works again.

**The four that broke it (df281ce).** Trip lines only fired when a player was
already within 3 tiles, because the server checked the *reporter's* distance
rather than where the zombie was; it now re-derives from `getMovingObjects()` on
a 3x3 around the wire. Wire placement failed entirely on a dedicated server
because `new(character, wireType)` put a non-serializable IsoPlayer first.
`Events.OnPlayerConnect` does not exist, so the join sync never ran once —
replaced with a client `OnGameStart` request and a targeted reply. Camouflage
was never written to the save.

**Correctness (0295d6b).** `CamoDegradation` and the wire load were running on
multiplayer clients; the uncamouflage alpha reset moved into
`WireNetwork.setCamouflaged` so it runs in single player at all; tanglefoot
stopped inheriting the 36-second Tier 1 cooldown; Detection stopped leaking one
modData key per tile crossed; `FALLBACK_SPRITE` deleted.

**The checkers (ee2393b).** `verify_names.py` went from 109 references to 271:
event names, sound names, the binary `.tiles`, and Java method existence and
arity. `tests/stubs.lua` no longer invents event names — the allow-list is
generated from the jar. Deleted `deadwire_01.tiles.txt`, which the game never
read and which this checker had been verifying instead of the real file. Fixed
`tools/pz-tilesheet` writing the tiledef id into the tileset-number field.

Older sessions (20 and earlier) are in `.claude/archive/sessions.md`.

### Session 22 (2026-09-08): the paper work finished, and a test plan

Five issues closed in three commits, and the mod stopped being a thing with
known holes in it. It is now a thing nobody has watched.

**Authority and the way in (de322da).** `PlaceWire` is gone: a server command
that trusted whatever coordinates it was handed, with no proximity check, that
nothing ever called. Deleting it took the per-player wire cap and the placement
log with it, which `verify_names` caught on its own -- two options came back as
declared-but-unread within a minute (now Key Rule 13). Both moved to
`ISDeadwireTripLine:create`, the path the engine actually uses. `CamouflageWire`
gained the owner check it never had, `RemoveWire` gained a distance bound, and
camouflage gained a context menu, which it had never had at all. Both menu
options walk the player to the wire and run a timed action, because a context
menu opens on any tile on screen and the new bound would have refused most
clicks -- which would have been #31 all over again.

**Text and outline (4e84ef2, 062101e).** `maxSpan` and `proneDuration` deleted:
declared per type, read by nothing, and promising spans and prone timers in the
tooltips. 76 orphan label lines gone from `Sandbox.json`, and `verify_names` now
refuses a label with no option as well as an option with no label. The rain
tooltip said "per hour" and the code runs every ten in-game minutes, found while
writing the test plan -- which is worth noting as a method, since prose a person
will act on has to bottom out in the code. `PLAN.md` carries a banner naming
every place it disagrees with the mod. Owner outline (#29) walks every wire now,
coloured per type.

**The tests grew where the risk was.** 187 to 201. `ISDeadwireTripLine` had no
tests at all before this, which is exactly why the moved gates could have gone
missing quietly. Six mutations, all six bit.

### Session 23 (2026-09-08): watched it work, for the first time

Parts A and B of `docs/TEST-PLAN.md` run live against a real 42.20.4 game,
24/24 checks pass. `createWire`'s actual path watched for the first time --
Session 18 only ever placed raw `IsoObject`s standing in for it.

**The harness had no loadstring.** `run_lua` throws "loadstring unavailable"
on this build, contradicting pz-test-pilot's own CLAUDE.md, which claims it
works -- that repo's note is stale. Worked around it by adding two registered
command handlers (`deadwire_smoke_a`/`deadwire_smoke_b`) directly to the
harness mod rather than sending code over the wire, since `call_function`
cannot pass live objects (player, grid squares) across the JSON boundary
either. Cost one full relaunch to register -- Init.lua's requires run once at
process boot, a reloaded save does not re-run them.

**What that proved.** All 8 mod-load log lines, all 10 Deadwire globals, loot
still injected into `FarmerTools`/`MetalShopTools` after Session 22's changes,
`ISDeadwireTripLine:create` placing a real `IsoThumpable` with the right
sprite for all four wire types, exactly one kit consumed per placement, the
canPassThrough/blockAllTheSquare/isThumpable flags all correct, a door beside
a wire still opens (#8 holds), the context menu correctly gates on carried
kits, and the save/reload round trip (`loadAll` + `reconnectSquare`) rebuilding
all four wires with world objects relinked.

**What Rob found live that no script would have caught.** The owner-outline
box is sized to the object's engine bounds, not the sprite art (#48) --
visible only by looking at it. Tin can's single-use trigger fired correctly
when Rob walked over it by accident (confirming part of Part C nobody meant to
test yet), but the alert sound was so quiet it defeats the wire's entire
purpose (#49). Measured all three sound assets with ffmpeg: `bell_ring.ogg`
and `wire_rattle.ogg` had real unused headroom and got gain-boosted (+4dB,
+10dB, mono preserved, no clipping); `tin_can_rattle.ogg` was already at its
0dB ceiling, so it needs a mastering pass, not a gain knob. A destroyed
single-use wire leaves nothing behind, which reads as a bug rather than a
mechanic (#50). The wire sprite draws in front of the character model, a
tiles/sprite anchor problem with no Lua-side cause (#51).

**Four issues filed, one commented with full results (#25).** Ends with 11
open, tree clean except the two boosted `.ogg` files.
