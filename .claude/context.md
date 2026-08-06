# Deadwire Context

```yaml
project: Deadwire
description: PZ mod — perimeter trip lines and electric fencing for Project Zomboid (B42+)
last_session: 17
last_updated: 2026-08-06
continue_with: "#25 in-game smoke test. Nothing in this mod has ever been verified running; that is now the entire Phase 1 backlog."
blockers: "#26 world sprite ART — the 8 images are Session 10 placeholders. Loading is NOT the problem (validate_pack.py 108/108, tile names match, tiledef 200 free). Needs 8 sprites drawn at 64x128 + tilesheet rebuild."

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
Deadwire v0.1.1, Session 18. main at 4f37fed.
Phase 1 code complete. ZERO open code bugs. 159 tests, 107 name refs, 108 pack
checks — all green. And NOTHING has ever been confirmed working in a running game.

THIS WINDOW: #25, the in-game smoke test. That is the whole backlog.

  cd c:/xampp/htdocs/pz-test-pilot
  python scripts/cmd.py run_lua 'code=<lua>'
  (cmd.py splits params on '=', so code MUST be passed as code=<lua>)

Start with the one-second check: open the inventory. Item names must read
"Tin Can Trip Line Kit", NOT "Deadwire_TinCanTripLineKit". All three translation
files were named *_EN.json and were never loaded by PZ. If they still read as raw
ids, the Session 17 fix did not land and nothing else is worth testing yet.

Then the other 9 steps in #25, in order — sprites, items, recipes, loot, sounds,
camo visibility, rain, sandbox options, MP cooldowns.

THEN #26 (sprite art) — but step 2 of #25 tells you whether the sheet even
registers before you spend time drawing.

Waiting on a decision from Rob: #27 (Bell health option + Reinforced/Bell are
stat-identical), #28 (delete the stale repo-root mod.info).

Before any commit touching a game name:  python scripts/verify_names.py
Run tests:                               run_tests.bat
Validate the tilesheet:                  python tools/validate_pack.py
```

## Name verification: run the script, do not check by hand

```bash
python scripts/verify_names.py          # exit 0 = everything resolves
```

Resolves 107 references against the installed 42.20: `Perks.X`, `Capability.X`,
`BodyPartType.X`, `Base.X` items, `ProceduralDistributions` names, recipe
`SkillRequired`/`xpAward` perks, `Icon =` PNGs, sprite names, sandbox options
(declared vs read vs translated), translation **filenames**, `DisplayCategory` /
recipe `category` / sandbox `page` label keys, and `tiledef` id range + collisions.
`scripts/pzclass.py` is the Java `.class` reader underneath.

**It exists because checking by hand does not hold.** Session 16 found six name bugs
manually and wrote the technique into this file without committing a tool. The very
next name written by hand — `ChurchMisc` → `ChurchStorageMisc` — was also wrong and
shipped described as "verified". A checked claim that leaves no artifact decays into
an unchecked one.

Read declared **fields and methods**, not the raw constant pool — a pool grep matches
any string anywhere in the class, so it passes `Perks.Foraging`. Note `Perks` is not a
Java enum; it is a holder class of `public static final` fields.

EXISTS: `setStaggerBack`, `knockDown`, `setAlphaAndTarget`, `getWorldSoundManager`,
`PlayWorldSound`, `setOutlineHighlight(Col)`, `isAdmin`, `BodyPartType.Foot_L`,
`IsoThumpable`, `ISBuildingObject`, `ProceduralDistributions`,
`getClimateManager():getRainIntensity()`, `Capability.UseBuildCheat`,
`IsoPlayer:getRole()`, `Role:hasCapability`, `ItemContainer:getFirstTypeRecurse`,
`Faction.isInSameFaction(IsoPlayer, String)`.

DOES NOT EXIST: `Perks.Foraging` (→`PlantScavenging`), `Perks.Carpentry` (→`Woodwork`),
`Capability.CanBuildAnywhere` (→`UseBuildCheat`), the `Climate` global
(→`getClimateManager()`), `getRainStrength` (→`getRainIntensity`), `Base.TreeBranch`
(→`TreeBranch2`), `ChurchMisc`/`ChurchStorageMisc` (**42.20 has no church distribution
at all**). There is **no electrocution system anywhere in the jar**.

**Internal name ≠ displayed name.** `Woodwork` displays as "Carpentry",
`PlantScavenging` as "Foraging". Code uses the internal name; tooltips use the
displayed one. The Sandbox tooltips saying "Carpentry 2" / "Foraging" are correct.

Rain intensity is 0.0–1.0 (vanilla `forageSystem` rounds `getPrecipitationIntensity()`
to one decimal and multiplies by it; `Bobber.lua` tests `getFogIntensity() >= 0.4`).

## B42 Mod Structure (REQUIRED)

`mod.info` at root of the mod AND in `42/`, both must match. `common/` must exist even
if empty. `poster=42/poster.png`. `sandbox-options.txt` in `42/media/`.

**Translations (42.15+) are JSON with NO `_EN` suffix** — the `EN/` directory already
says the language. `ItemName.json`, `Recipes.json`, `Sandbox.json`, `IG_UI.json`.
`zombie/core/Translator$1` holds a fixed hardcoded list of base names and opens
`Translate/<LANG>/<NAME>.json`; a file outside that list is never opened, with no error.
Session 17 found all three of this mod's translation files named `*_EN.json` (B41 `.txt`
convention carried over), so every item, recipe and sandbox label displayed as a raw id.
Categories need `IGUI_ItemCat_X` / `IGUI_CraftCategory_X` in `IG_UI.json`; the sandbox
page label needs `Sandbox_<page>` in `Sandbox.json`. `verify_names.py` checks all of it.

## Key Rules

1. **Privacy First**: no PII or credentials in commits
2. **GitHub Issues**: all tasks tracked in Issues
3. **Multiplayer First**: server-authoritative
4. **Test In-Game**: provide clear test steps
5. **Module Base** for all items; namespace tags `deadwire:tagname`
6. **Detection is CLIENT-side**: OnZombieUpdate/OnPlayerUpdate are client events
7. **No guards around unverified API names.** A guard around a typo is
   indistinguishable from a guard around a real fallback: it turns a loud error into a
   silently absent feature. Cost three dead features (Session 16).
8. **A missing name logs loudly.** LootDistribution warns rather than skipping in
   silence — every bug that file had was a nil name with a clean log.

## Architecture

Shared (WireNetwork, Config) → Client (Detection, UI, TriggerHandlers, CamoVisibility,
EventHandlers) → Server (ServerCommands, WireManager, BuildActions, LootDistribution,
CamoDegradation). Client `sendClientCommand` → server validates → `sendServerCommand`
broadcasts.

`ISBuildingObject:derive()` files MUST live in `server/`; load order is shared → client
→ server. Cooldowns are **real seconds** (`os.time`), broadcast as a *duration* not an
absolute time because server and clients have independently skewed clocks.

## Phase Plan

| Phase | Content | Status |
|-------|---------|--------|
| 1 (MVP) | Tier 0 + Tier 1 + Camouflage + SandboxVars | Code complete, no open bugs, **never run in-game** (#25), sprite art placeholder (#26) |
| 2 | Pull-alarms | Not started |
| 3 | Electric fencing | #13, API researched — no electrocution system exists in the jar |
| 4 | Advanced | Not started |

## Gates

| Gate | Command | State |
|------|---------|-------|
| Unit tests | `run_tests.bat` | 159 pass |
| Name resolution | `python scripts/verify_names.py` | 107 refs, all resolve |
| Tilesheet | `python tools/validate_pack.py` | 108 checks pass |
| In-game | PZ Test Pilot | **never run** (#25) |
| CI | — | none configured; all four gates are local-only |

## Open Issues

| # | Title | State |
|---|-------|-------|
| 25 | In-game smoke test — nothing verified running | **Next** |
| 26 | World sprite art still Session 10 placeholders | Blocker |
| 27 | Tier 1 balance: Bell health option, Reinforced/Bell identical | Needs Rob |
| 28 | Delete stale repo-root mod.info | Needs Rob |
| 13 | Tier 3 electrified wire | Phase 3 |
| 12 | Loot for metalworking rooms | Code correct + name-verified, needs in-game confirm |

## Recent sessions

### Session 17 (2026-08-05/06): eleven silent failures, six PRs

Built `scripts/verify_names.py` + `pzclass.py` **before** fixing anything, because
Session 16's hand-verification had already decayed. Closed #14–#18 and found six more
bugs on no issue at all. PRs #19–#24, all merged.

From issues: `Perks.Foraging` nil so camo was invisible to everyone forever (#17); the
entire Climate call was fiction so camo never degraded (#18); `Capability.CanBuildAnywhere`
in **three** places, not the one the issue named, plus an unguarded `getRole()` (#14); two
MP exploits — unvalidated `WireTriggered` and client-trusted kits (#15); cooldowns in game
time **and** set server-side while checked client-side, so MP cooldowns never applied at
all (#16).

Found by the verifier: `ChurchStorageMisc` does not exist; both Tier 1 recipes required
the nonexistent perk `Carpentry`; **all three translation files were named `*_EN.json` and
were never loaded**, so every item/recipe/sandbox label showed as a raw id since the mod
was written; no `IG_UI.json` existed so categories showed raw keys; four sandbox options
were declared, translated, shown to players and read by no code. Also `versionMin`
42.0.0 → 42.15.0. Tests 131 → 159. Corrected the auto-memory note that recorded the
`_EN` suffix as correct — that is why three sessions of auditing missed it.

### Session 16 (2026-08-05): B42.20.2 audit — six silent failures, three fixed

Audited the mod against an installed 42.20 rather than docs. Fixed four bad loot table
names, a kit item id typo, and `Base.TreeBranch` (made Tanglefoot uncraftable). Filed
#14–#18. `pz-mod-checker scan` reported clean before and after and caught none of it —
it is a version-keyed rule engine with no concept of whether a name resolves. Filed
pz-mod-checker#23 spec'ing a `validate` command.

### Session 15 (2026-04-14): Gemini inventory icons + pz_unpack.py

Built `pz_unpack.py` at `c:/xampp/htdocs/pz-tilesheet/`. Generated all 4 inventory icons
(32x32). World sprites left as placeholders.
