# Deadwire Context

```yaml
project: Deadwire
description: PZ mod — perimeter trip lines and electric fencing for Project Zomboid (B42+)
last_session: 16
last_updated: 2026-08-05
continue_with: "Fix #17 and #18 (one-liners, revives the whole camouflage system), then #14/#15/#16, then finish the in-game smoke test"
blockers: "World sprite ART is placeholder. The deadwire_01 tilesheet ships and is declared in mod.info, so sprites should load, but the 8 images are Session 10 placeholders, not the finished Gemini art. Whether they render at all is still unverified in-game."

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

`mod.info` at root AND in `42/`, both must match. `common/` must exist even if empty. `poster=42/poster.png`. `sandbox-options.txt` in `42/media/`. Translation files are JSON since 42.15, in `42/media/lua/shared/Translate/EN/`.

## Key Rules

1. **Privacy First**: No PII or credentials in commits
2. **GitHub Issues**: All tasks tracked in Issues
3. **Multiplayer First**: Server-authoritative
4. **Test In-Game**: Provide clear test steps
5. **Module Base**: `module Base` for all items
6. **Namespace Tags**: `deadwire:tagname`
7. **Detection is CLIENT-side**: OnZombieUpdate/OnPlayerUpdate are client events
8. **No guards around unverified API names.** A guard around a typo is indistinguishable from a guard around a real fallback: it turns a loud error into a silently absent feature. This cost three dead features, found in Session 16.

## Verified against the installed 42.20 jar (Session 16)

Confirmed to EXIST: `setStaggerBack`, `knockDown`, `setAlphaAndTarget`, `getWorldSoundManager`, `PlayWorldSound`, `IsoObject:setOutlineHighlight`, `setOutlineHighlightCol`, `isAdmin`, `BodyPartType.Foot_L`, `IsoThumpable`, `ISBuildingObject`, `ProceduralDistributions`, `IsoGridSquare:isGeneratorPoweringSquare`.

Confirmed NOT to exist: `Perks.Foraging` (it is `PlantScavenging`), `Perks.Carpentry` (it is `Woodwork`), `Capability.CanBuildAnywhere` (nearest real: `UseBuildCheat`), the `Climate` global (it is `getClimateManager()`), `getRainStrength` (it is `getRainIntensity`), `Base.TreeBranch` (it is `TreeBranch2`). There is **no electrocution system anywhere in the jar**.

Technique: parse the constant pool of each `.class` in `projectzomboid.jar` — zip read, walk the pool, take tag-1 UTF8 entries. ~142k identifiers in seconds. Do NOT substring-match against the vanilla Lua tree: that passes `Perks.Foraging` as valid because the word appears elsewhere.

## Architecture

Shared (WireNetwork, Config) → Client (Detection, UI, TriggerHandlers, CamoVisibility) → Server (ServerCommands, WireManager, BuildActions, LootDistribution, CamoDegradation). Client `sendClientCommand` → server validates → `sendServerCommand` broadcasts.

`ISBuildingObject:derive()` files MUST live in `server/`; load order is shared → client → server.

## Phase Plan

| Phase | Content | Status |
|-------|---------|--------|
| 1 (MVP) | Tier 0 + Tier 1 + Camouflage + SandboxVars | Code complete, 5 open bugs, sprites incomplete |
| 2 | Pull-alarms | Not started |
| 3 | Electric fencing | Issue #13, API researched |
| 4 | Advanced | Not started |

## Recent Changes

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
Deadwire v0.1.1, Session 17. Phase 1 code complete but NOT shippable.

THIS WINDOW, in order:

1. #17: CamoVisibility.lua:73, Perks.Foraging -> Perks.PlantScavenging. One word.
2. #18: CamoDegradation.lua:22, replace getRainStrength's body with
     local cm = getClimateManager()
     if not cm then return 0 end
     return cm:getRainIntensity() or 0
   Confirm in-game whether getRainIntensity is normalised 0-1; STORM_THRESHOLD=0.8 assumes it.
3. #14: ServerCommands.lua:126, Capability.CanBuildAnywhere -> Capability.UseBuildCheat,
   and nil-guard getRole().
4. #16: cooldown is written in seconds but measured in game time, so 36 "seconds" is about
   1.5 real seconds. Decide real-time (preferred) vs renaming the field.
5. #15: PlaceWire never checks the player holds a kit, and WireTriggered accepts any client's
   claim for any coordinate. Both MP-only exploits.
6. Finish the smoke test. Harness works: PZ running with PZ Test Pilot enabled, then
     cd c:/xampp/htdocs/pz-test-pilot
     python scripts/cmd.py run_lua 'code=<lua>'
   cmd.py splits params on '=', so the code MUST be passed as code=<lua>.
   Still unverified: sprites load, recipes registered, loot tables reachable, sounds play.

THEN the blocker: world sprite ART. The deadwire_01 tilesheet ships (.pack + .tiles, both
declared in mod.info) so the sprites should load and the construction_01_24 fallback should
never fire — but that is UNVERIFIED, and the 8 images in it are Session 10 placeholders.
Source PNGs at repo root need crop/resize to 64x128 and a tilesheet rebuild.
Check which is true first: getSprite("deadwire_01_0") through _7 via the harness.

Run tests anytime: run_tests.bat
```
