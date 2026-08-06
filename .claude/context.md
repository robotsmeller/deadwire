# Deadwire Context

```yaml
project: Deadwire
description: PZ mod — perimeter trip lines and electric fencing for Project Zomboid (B42+)
last_session: 18
last_updated: 2026-08-06
continue_with: "#26 — regenerate 3 sprites with shorter stakes. Exact prompts are in tools/process_sprite_render.py. Then the rest of #25 (sounds, camo, rain, triggers)."
blockers: "None hard. #26 is cosmetic and well-scoped; #25's remaining steps need someone willing to sit in-game."

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

## To Resume

```
Deadwire v0.1.1, Session 19. Start from origin/main (git pull).

Session 18 was the first time this mod has EVER been confirmed running in a
game. Most of Phase 1 now has in-game evidence behind it. Three real bugs were
found and fixed in the process, one of which had silently disabled loot for
every single-player game since the mod was written.

THIS WINDOW: #26. Three sprites (tincan, bell, reinforced) have stakes that are
2-5x too tall and read as fences instead of trip lines. tanglefoot and electric
are already correct and serve as the height reference. The full working Gemini
prompt, the failure each phrase prevents, and the fix are all in the docstring
of tools/process_sprite_render.py. This is a 20-minute job, not a redesign.

THEN: the rest of #25 — sounds, camo visibility, rain degradation, and actual
trigger behaviour with a zombie. Those need the real build path, not the raw
sprite placement used in Session 18.

  cd c:/xampp/htdocs/pz-test-pilot
  python scripts/cmd.py get_status
  python scripts/cmd.py run_lua 'code=<lua>'
  (cmd.py splits each param on the FIRST '=' only, so code=<lua> is safe even
   though the Lua is full of '='.)

Harness note: `harness_dead` usually means the game is PAUSED or ALT-TABBED,
not crashed. The poll loop stops ticking when PZ loses focus. Wait a few
seconds and retry before diagnosing anything.

Before any commit touching a game name:  python scripts/verify_names.py
Run tests:                               run_tests.bat
Validate the tilesheet:                  python tools/validate_pack.py
```

## What is actually verified in-game (Session 18)

Everything below was confirmed in a running 42.20 game, not inferred.

| Check | Result |
|---|---|
| Harness IPC round-trip | works |
| Item display names | "Tin Can Trip Line Kit" etc., translated |
| All 4 kits spawn | ok |
| All 4 recipes registered | ok, and display translated |
| Item + crafting categories | both resolve |
| Sandbox options | `SandboxVars.Deadwire` populated, `getSandbox` reads through |
| Loot injection | **11/11 tables at chance 12** |
| All 10 sprites | real distinct textures, 64x128 |

**Still unverified, and this is the honest remainder of #25:** sounds, camo
visibility, camo rain degradation, and what actually happens when a zombie
walks into a wire. MP cooldowns cannot be tested in single-player at all.

## Session 18 bugs — read this before trusting any guard in this repo

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

**The auto-memory note that recorded `IGUI_CraftCategory_` as correct was
wrong.** That is the second time a wrong note in memory outlived the code
(Session 17 found the `_EN` suffix note doing the same thing). Treat
`scripts/verify_names.py` output as truth, not the notes.

### Inventory icons had opaque backgrounds

All four were 100% opaque, alpha 255 on every pixel, sitting on grey boxes in
the inventory. Rebuilt from the 1024x1024 originals with an edge flood-fill and
a premultiplied downscale. A plain white colour-key would have punched holes
through the tin cans, which is why the fill runs inward from the border.

## Sprites

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

Post height above the ground line — the open item on #26:

| sprite | above ground | verdict |
|---|---|---|
| tanglefoot | 6px | correct |
| electric | 8px | correct |
| tincan | 22px | too tall |
| bell | 30px | too tall |
| reinforced | 32px | too tall |

## Name verification: run the script, do not check by hand

```bash
python scripts/verify_names.py          # exit 0 = everything resolves
```

Resolves 109 references against the installed 42.20: `Perks.X`, `Capability.X`,
`BodyPartType.X`, `Base.X` items, `ProceduralDistributions` names, recipe
`SkillRequired`/`xpAward` perks, `Icon =` PNGs, sprite names, sandbox options,
translation **filenames**, `DisplayCategory` / recipe `category` / sandbox
`page` label keys (including the prefixes themselves), and `tiledef` id range.
`scripts/pzclass.py` is the Java `.class` reader underneath.

Read declared **fields and methods**, not the raw constant pool — a pool grep
matches any string anywhere in the class, so it passes `Perks.Foraging`.

EXISTS: `setStaggerBack`, `knockDown`, `setAlphaAndTarget`,
`getWorldSoundManager`, `PlayWorldSound`, `setOutlineHighlight(Col)`, `isAdmin`,
`BodyPartType.Foot_L`, `IsoThumpable`, `ISBuildingObject`,
`ProceduralDistributions`, `getClimateManager():getRainIntensity()`,
`Capability.UseBuildCheat`, `IsoPlayer:getRole()`, `Role:hasCapability`,
`ItemContainer:getFirstTypeRecurse`, `Faction.isInSameFaction`,
`IsoSpriteManager.instance:getSprite`, `spr:getTextureForCurrentFrame`.

DOES NOT EXIST: `Perks.Foraging` (→`PlantScavenging`), `Perks.Carpentry`
(→`Woodwork`), `Capability.CanBuildAnywhere` (→`UseBuildCheat`), the `Climate`
global (→`getClimateManager()`), `getRainStrength` (→`getRainIntensity`),
`Base.TreeBranch` (→`TreeBranch2`), any church distribution at all,
`sprite:getTextureCount()`, `getTextOrNull` for recipe display names (recipes
translate through the UI, not that call — a nil there means nothing).
There is **no electrocution system anywhere in the jar.**

**Internal name ≠ displayed name.** `Woodwork` displays as "Carpentry",
`PlantScavenging` as "Foraging".

## B42 Mod Structure (REQUIRED)

`mod.info` at root of the mod AND in `42/`, both must match. `common/` must
exist even if empty. `poster=42/poster.png`. `sandbox-options.txt` in
`42/media/`.

**Translations (42.15+) are JSON with NO `_EN` suffix** — the `EN/` directory
already says the language. `ItemName.json`, `Recipes.json`, `Sandbox.json`,
`IG_UI.json`. `zombie/core/Translator$1` holds a fixed hardcoded list of base
names; a file outside that list is never opened, with no error. Categories need
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
   features (Session 16).
8. **A missing name logs loudly.** LootDistribution warns rather than skipping
   in silence.
9. **A checker must derive, not remember.** Two checkers have now blessed bugs
   by agreeing with a hardcoded value nobody rechecked (Session 18).

## Architecture

Shared (WireNetwork, Config) → Client (Detection, UI, TriggerHandlers,
CamoVisibility, EventHandlers) → Server (ServerCommands, WireManager,
BuildActions, LootDistribution, CamoDegradation). Client `sendClientCommand` →
server validates → `sendServerCommand` broadcasts.

`ISBuildingObject:derive()` files MUST live in `server/`; load order is shared →
client → server. Cooldowns are **real seconds** (`os.time`), broadcast as a
*duration* not an absolute time because clocks are independently skewed.

## Phase Plan

| Phase | Content | Status |
|-------|---------|--------|
| 1 (MVP) | Tier 0 + Tier 1 + Camouflage + SandboxVars | Running in-game; loot/names/recipes/sprites confirmed. Sounds, camo, triggers unverified (#25). Sprite stake height (#26). |
| 2 | Pull-alarms | Not started |
| 3 | Electric fencing | #13 — art banked, mechanic decided (stagger + knockdown) |
| 4 | Advanced | Not started |

## Gates

| Gate | Command | State |
|------|---------|-------|
| Unit tests | `run_tests.bat` | 159 pass |
| Name resolution | `python scripts/verify_names.py` | 109 refs, all resolve |
| Tilesheet | `python tools/validate_pack.py` | 130 checks pass |
| In-game | PZ Test Pilot | **partially run** — see table above |
| CI | — | none configured; all gates are local-only |

## Open Issues

| # | Title | State |
|---|-------|-------|
| 26 | Sprite stake height on 3 of 5 types | **Next** — prompts written, 20 min |
| 25 | In-game smoke test | Partially done; sounds/camo/rain/triggers remain |
| 27 | Tier 1 balance: Bell health, Reinforced/Bell identical | Needs Rob |
| 28 | Delete stale repo-root mod.info | Needs Rob |
| 13 | Tier 3 electrified wire | Phase 3 — mechanic decided, art banked |
| 12 | Loot for metalworking rooms | **Injection confirmed 11/11**; needs a real container sighting to close |

## Recent sessions

### Session 18 (2026-08-06): first in-game run, three bugs, two blind checkers

The mod ran in a real game for the first time. Confirmed working: item names,
recipes, categories, sandbox options, kit spawning, all 10 sprites.

Found and fixed: the `isServer()` guard that had disabled single-player loot
forever; `IGUI_CraftCategory_` → `IGUI_CraftingCategories_`; fully opaque
inventory icons.

Both name/pack checkers were found blessing hardcoded values and now derive
them. World sprites replaced via a Gemini → `process_sprite_render.py` pipeline
that is documented in that file, including which prompt phrasings prevent which
specific failure. Stake height on 3 of 5 remains (#26).

Ten inert test `IsoObject`s were left in a throwaway test world at
x=1914-1922, y=14379/14381 — the game was closed before they could be removed.
Harmless, and irrelevant unless that save is reused.

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
