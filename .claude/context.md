# Deadwire Context

```yaml
project: Deadwire
description: PZ mod — perimeter trip lines and electric fencing for Project Zomboid (B42+)
last_session: 17
last_updated: 2026-08-05
continue_with: "In-game smoke test: sprites load, recipes registered, loot reachable, sounds play, camo now visible/degrading. All five code bugs (#14-#18) are fixed and merged."
blockers: "World sprite ART is placeholder — the 8 images in deadwire_01 are Session 10 placeholders, not finished art. Loading is no longer the suspected problem: validate_pack.py passes 108/108, the 8 tile names match what Config.Sprites asks for, and tiledef id 200 collides with nothing (vanilla is all below 100; no installed mod declares one). That is still an inference from file structure, not an observation of PZ registering the sheet."

tech:
  stack: pz-lua-mod
  tools: [Lua 5.1 (Kahlua2), Project Zomboid B42.20.2, Git, GitHub]

paths:
  mod_root: Contents/mods/Deadwire/42/
  shared: Contents/mods/Deadwire/42/media/lua/shared/Deadwire/
  client: Contents/mods/Deadwire/42/media/lua/client/Deadwire/
  server: Contents/mods/Deadwire/42/media/lua/server/Deadwire/
  scripts: Contents/mods/Deadwire/42/media/scripts/
  rules: .claude/rules/
  docs: docs/

workflow:
  tracking: GitHub Issues
  phases: 4 (MVP → Pull-Alarms → Electric Fencing → Advanced)
  current_phase: 1
```

## B42 Mod Structure (REQUIRED)

`mod.info` at root AND in `42/`, both must match. `common/` must exist even if empty. `poster=42/poster.png`. `sandbox-options.txt` in `42/media/`.

Translation files are JSON since 42.15, in `42/media/lua/shared/Translate/EN/`, and the
filenames carry **no `_EN` suffix** — the `EN/` directory already says the language.
`ItemName.json`, `Recipes.json`, `Sandbox.json`. `zombie/core/Translator$1` holds a fixed
hardcoded list of base names and builds `Translate/<LANG>/<NAME>.json`; a file outside
that list is never opened, with no error. Session 17 found all three of this mod's
translation files were named `*_EN.json` (B41 `.txt` convention carried over), so every
item, recipe and sandbox label displayed as a raw id. `verify_names.py` checks this now.

## Key Rules

1. **Privacy First**: No PII or credentials in commits
2. **GitHub Issues**: All tasks tracked in Issues
3. **Multiplayer First**: Server-authoritative
4. **Test In-Game**: Provide clear test steps
5. **Module Base**: `module Base` for all items
6. **Namespace Tags**: `deadwire:tagname`
7. **Detection is CLIENT-side**: OnZombieUpdate/OnPlayerUpdate are client events
8. **No guards around unverified API names.** A guard around a typo is indistinguishable from a guard around a real fallback: it turns a loud error into a silently absent feature. This cost three dead features, found in Session 16.

## Name verification: run the script, do not check by hand

```bash
python scripts/verify_names.py          # exit 0 = every name resolves
```

`scripts/verify_names.py` resolves every game name the mod references against the
installed 42.20 install: `Perks.X`, `Capability.X`, `BodyPartType.X`, `Base.X` item
ids in both Lua and scripts, `ProceduralDistributions` names, recipe
`SkillRequired`/`xpAward` perks, `Icon =` PNG existence, sprite names against the
mod's own tilesheet, and root-vs-42 `mod.info` agreement. 67 references at present.
`scripts/pzclass.py` is the Java `.class` reader underneath it.

**This exists because checking by hand does not hold.** Session 16 found six name
bugs manually and wrote the technique into this file without committing a tool. The
very next name written by hand — `ChurchMisc` → `ChurchStorageMisc` — was also wrong
and was committed described as "verified against vanilla ProceduralDistributions.lua
on 42.20". Session 17 found it in seconds with the script. A checked claim that
leaves no artifact decays into an unchecked one.

Read declared **fields and methods**, not the raw constant pool. A constant-pool
grep matches any string anywhere in the class, so it passes `Perks.Foraging`.
Note also that `Perks` is not a Java enum: it is a holder class of
`public static final` fields, so an ACC_ENUM-only check finds nothing there.

Confirmed to EXIST: `setStaggerBack`, `knockDown`, `setAlphaAndTarget`,
`getWorldSoundManager`, `PlayWorldSound`, `IsoObject:setOutlineHighlight`,
`setOutlineHighlightCol`, `isAdmin`, `BodyPartType.Foot_L`, `IsoThumpable`,
`ISBuildingObject`, `ProceduralDistributions`, `IsoGridSquare:isGeneratorPoweringSquare`,
`getClimateManager():getRainIntensity()`, `Capability.UseBuildCheat`,
`IsoPlayer:getRole()`, `Role:hasCapability`, `ItemContainer:getFirstTypeRecurse`.

Confirmed NOT to exist: `Perks.Foraging` (it is `PlantScavenging`), `Perks.Carpentry`
(it is `Woodwork`), `Capability.CanBuildAnywhere` (it is `UseBuildCheat`), the
`Climate` global (it is `getClimateManager()`), `getRainStrength` (it is
`getRainIntensity`), `Base.TreeBranch` (it is `TreeBranch2`), `ChurchMisc` /
`ChurchStorageMisc` (**42.20 has no church distribution at all**). There is **no
electrocution system anywhere in the jar**.

**Internal name ≠ displayed name.** `Woodwork` displays as "Carpentry" and
`PlantScavenging` displays as "Foraging" (`IGUI_perks_*` / `Sandbox_*` in the vanilla
EN translations). Mod code must use the internal name; player-facing tooltips must
use the displayed one. The Sandbox_EN tooltips saying "Carpentry 2" and "Foraging"
are therefore correct and were deliberately left alone.

Rain intensity is normalised 0.0-1.0: vanilla `forageSystem` rounds
`getPrecipitationIntensity()` to one decimal and multiplies chances by it, and
`Bobber.lua` tests `getFogIntensity() >= 0.4`. `STORM_THRESHOLD = 0.8` relies on this.

## Architecture

Shared (WireNetwork, Config) → Client (Detection, UI, TriggerHandlers, CamoVisibility) → Server (ServerCommands, WireManager, BuildActions, LootDistribution, CamoDegradation). Client `sendClientCommand` → server validates → `sendServerCommand` broadcasts.

`ISBuildingObject:derive()` files MUST live in `server/`; load order is shared → client → server.

## Phase Plan

| Phase | Content | Status |
|-------|---------|--------|
| 1 (MVP) | Tier 0 + Tier 1 + Camouflage + SandboxVars | Code complete, no open bugs, untested in-game, sprite art placeholder |
| 2 | Pull-alarms | Not started |
| 3 | Electric fencing | Issue #13, API researched |
| 4 | Advanced | Not started |

## Recent Changes

### Session 17 (2026-08-05): every open code bug fixed, plus a name verifier

Built `scripts/verify_names.py` + `scripts/pzclass.py` first, then fixed what it
found. 67 references now resolve; 143/143 tests pass (was 131).

Closed #14 through #18:

- **#17** `Perks.Foraging` → `Perks.PlantScavenging`. Camouflaged wires were
  invisible to every player forever, because the nil perk made `getPerkLevel`
  return 0 for everyone.
- **#18** the whole Climate call was fiction (`Climate.GetInstance():getRainStrength()`
  — no such global, no such method). Now `getClimateManager():getRainIntensity()`.
  Camouflage had never degraded from weather.
- **#14** `Capability.CanBuildAnywhere` → `UseBuildCheat`, in all **three** places
  (the issue named one), plus a nil guard on `getRole()`, which threw in SP.
- **#15** two MP exploits closed: `WireTriggered` now requires the reporter to be
  within 3 tiles and on the same floor, and `PlaceWire` verifies and consumes the
  kit server-side instead of trusting the client.
- **#16** cooldowns moved from game time to real seconds. Also fixed a bug the issue
  did not mention: the server set the cooldown while detection checks it on the
  *client*, so in MP the cooldown never applied at all. `WireTriggered` now
  broadcasts the duration (not an absolute time — clock skew) and clients mirror it.
  The broadcast is no longer gated on `soundName`, so silent Tanglefoot gets one too;
  the client no longer substitutes a default sound when `soundName` is absent, which
  would have made Tanglefoot audible.

Two bugs found that were not on any issue: `ChurchStorageMisc` did not exist (bells
silently absent from that table) and both Tier 1 recipes required `Carpentry`, which
is not a perk — `Woodwork` is. Recipes were likely uncraftable.

Unverified in-game still: sprites render, recipes register, loot reachable, sounds
play. Nothing here was tested against a running game.

### Session 16 (2026-08-05): B42.20.2 audit — six silent failures, three fixed

Audited the whole mod against an installed 42.20 rather than against docs. `pz-mod-checker scan` reported clean both before and after and found none of it: it is a version-keyed rule engine with no concept of "does this name resolve".

Fixed and committed (4537d2c): four loot table names that do not exist (`FarmTools`, `ChurchMisc`, `MetalFabrication`, `MetalFabricationStorage`), a kit item id typo'd against the mod's own item, and `Base.TreeBranch` which made Tanglefoot uncraftable. Also added `Base.ElectricWire` to both trip-line bindings at count 2, widened the Tanglefoot wood input to five items, `tags=` → `Tags=`, `Type=` → `ItemType=base:normal`. All 17 `Base.*` references now resolve.

Filed #14 through #18. #17 and #18 are the serious ones: `Perks.Foraging` and the entire Climate call are wrong, so camouflaged wires are invisible to everyone forever AND never degrade. The camouflage system has never worked in either direction.

Smoke test via pz-test-pilot confirmed the mod loads, all five globals initialise, and all four items exist (validating the `ItemType` change). Sprites, recipes and loot tables remain unverified; the run was interrupted by an urgent bug in the sibling HeadForTheHills mod.

Filed pz-mod-checker#23: spec for a `validate` command resolving every name a mod uses against the installed game. Six of seven bugs found today were one shape and it would have caught all of them.

### Session 15 (2026-04-14): Gemini inventory icons + pz_unpack.py

Built `pz_unpack.py` at `c:/xampp/htdocs/pz-tilesheet/`. Generated all 4 inventory icons (32x32) via Gemini. World sprites still in progress; full-size source PNGs sit at repo root pending crop/resize and a tilesheet rebuild.

### Session 14 (2026-03-11): Float safety, loot guard, north orientation

`tileKey` floors all coords. `LootDistribution` gained an `isServer()` guard. `north` forwarded through Client/ServerCommands. 131/131 tests pass.

## To Resume

```
Deadwire v0.1.1, Session 18. Phase 1 code complete, ZERO open code bugs,
but nothing has ever been confirmed working in a running game.

Everything left needs PZ actually running. That is the whole remaining list.

THIS WINDOW:

1. Smoke test. Harness: PZ running with PZ Test Pilot enabled, then
     cd c:/xampp/htdocs/pz-test-pilot
     python scripts/cmd.py run_lua 'code=<lua>'
   cmd.py splits params on '=', so the code MUST be passed as code=<lua>.
   Check, in order:
     a. getSprite("deadwire_01_0") .. _7 all non-nil  -> tilesheet actually loaded
     b. getScriptManager():getItem("Base.Deadwire_TinCanTripLineKit") non-nil
     c. all four craftRecipes registered (Woodwork:2 now, was the bogus Carpentry:2)
     d. ProceduralDistributions.list.JanitorMisc contains Base.Bell after world load
     e. place a wire, walk a zombie into it, hear the sound
     f. camouflage a wire, check a low-skill character cannot see it and a
        PlantScavenging 7 character can -- this path has NEVER worked before now
     g. confirm getRainIntensity() really is 0-1 in a live storm (STORM_THRESHOLD=0.8)

2. Then the blocker: world sprite ART. The 8 images in deadwire_01 are Session 10
   placeholders. Source PNGs at repo root need crop/resize to 64x128 and a
   tilesheet rebuild. Step 1a tells you whether the sheet loads at all before you
   spend time on art.

3. Parked for Rob: delete the stale repo-root mod.info (0.1.0, poster=poster.png).
   It sits outside Contents/ so PZ never reads it, but it reads like the manifest
   and is not one. Session 17 misread it as such.

Before any commit that touches names:  python scripts/verify_names.py
Run tests anytime:                     run_tests.bat   (143 tests)
```
