# Deadwire - Handoff

## Current Priority

**In-game smoke test. Everything that remains needs PZ actually running.**

All five open code bugs (#14 through #18) are fixed, tested and merged. There are no
open code bugs. What there is instead is a mod that has never been confirmed working:
sprites, recipes, loot tables, sounds and the whole camouflage path are unverified in
a live game. The camouflage path in particular has never worked in either direction
until now, so it has no history of behaving at all.

Run `python scripts/verify_names.py` before any commit that touches a game name. It
resolves all 67 references against the installed 42.20 and is the reason two bugs
nobody had filed turned up in Session 17.

**Blocker for release:** world sprite *art* is placeholder. The `deadwire_01` tilesheet
ships (`.pack` + `.tiles`, both declared in mod.info) and its 8 tile indices provably
match the names `Config.Sprites` asks for, so the `construction_01_24` fallback should
never fire — but that is still unverified in-game, and the 8 images are Session 10
placeholders rather than the finished Gemini art. Source PNGs sit at repo root pending
crop/resize and a tilesheet rebuild.

---

## Status

| Area | Status | Notes |
|------|--------|-------|
| Sprint 1 (Foundation) | **PASSED** | In-game, Session 6 |
| Sprint 2 (Placement) | **PASSED** | In-game, Session 8 |
| Sprint 3 (Sound+Trigger) | **Partly verified** | Items + globals confirmed in-game S16. Sprites, recipes, sounds still untested |
| Sprint 4 (Camo+Config) | **Fixed, untested** | #17 + #18 closed S17. Never worked before, so no prior behaviour to compare against |
| 42.20.2 compat | **Audited + tooled** | 8 silent failures total. `scripts/verify_names.py` now checks all 67 names |
| MP hardening | **Done, untested** | #15 closed S17: trigger proximity + server-side kit consumption |
| Custom world sprites | **Placeholder art** | Tilesheet ships, names provably match. Images are S10 placeholders. Release blocker |
| Test harness | **Done** | 143 tests — `run_tests.bat` |
| pz-test-pilot harness | **Working** | Can drive the live game, see To Resume in context.md |

---

## Open Issues

| # | Title | Severity |
|---|-------|----------|
| 13 | Tier 3: electrified perimeter wire (generator-powered) | Phase 3 |
| 12 | Loot distribution for metalworking rooms | Code correct + name-verified, needs in-game confirm |

Closed in Session 17: #14, #15, #16, #17, #18.

---

## Version

- **v0.1.1** — tagged, released on GitHub. Not on Steam Workshop.
- mod.info: `modversion=0.1.1`, `pack=deadwire_01`, `tiledef=deadwire_01 200`
- `versionMin` raised `42.0.0` → **`42.15.0`** in Session 17. 42.15 is the floor the mod
  demonstrably cannot go below (JSON translations landed there; namespaced tags need
  42.13). It is not a tested claim — everything has only ever been checked against
  42.20 — but 42.20 would lock out users the mod very likely works for, and 42.0.0 was
  simply false. Lower it only with evidence, raise it if 42.15 turns out to break.

### Tilesheet: loads-or-not is now answered as far as static checking can

- `python tools/validate_pack.py` → **108/108 pass**. The shipped `.pack` is structurally
  valid, all 8 sprite names are present at the correct 64×128 regions in a 512×128 sheet,
  and the header/page/entry layout matches vanilla `Tiles2x.pack`.
- `tiledef` id 200 is free: vanilla sits entirely below 100 (ids 1, 13, 68, 88) and none
  of the 6 installed mods declares a tiledef. `verify_names.py` now checks this.
- So the remaining sprite risk is **art quality, not loading** — with the caveat that
  "should load" is still an inference from file structure, not an observation of PZ
  registering the sheet. Confirm with `getSprite("deadwire_01_0")` in the live game.

---

## Key Technical Decisions

| Decision | Rationale | Date |
|----------|-----------|------|
| Name checking is a committed script, not a technique | S16 verified by hand and wrote the method into context.md. The next hand-written name (`ChurchStorageMisc`) was wrong and shipped labelled "verified". A checked claim with no artifact decays to an unchecked one. | 2026-08-05 |
| Read declared fields/methods, not the constant pool | A pool grep matches any string anywhere in the class, so it passes `Perks.Foraging`. Also: `Perks` is not an enum, it is a holder of public static final fields. | 2026-08-05 |
| A missing loot distribution logs a warning | The existence check was silently skipping. Every bug this file had was a nil name with a clean log. | 2026-08-05 |
| Cooldowns in real seconds, broadcast as a duration | Game time made the same config number mean a different real duration per server. Duration not absolute time, because server and clients are different machines with skewed clocks. | 2026-08-05 |
| No guards around unverified API names | A guard around a typo is indistinguishable from a guard around a real fallback. Cost three dead features. | 2026-08-05 |
| Loot uses `.items` flat pairs | Matches vanilla on 42.20. The 42.16 `weightChance` rule applies to `procList`, not `.items`. | 2026-08-05 |
| Explicit item lists over `tags[...]` for Tanglefoot | A recipe line is an item list or a tags list, never both, and Stake carries `tentpeg` not `woodhandle`. | 2026-08-05 |
| No RecalcAllWithNeighbours on wire place | Trip wires must be pathfinding-transparent. Recalc only on removal. Fixes #8. | 2026-03-11 |
| CamoVisibility on OnTick + 60-tick throttle | Visibility needs ~1s responsiveness. Visual-only, no game logic. | 2026-03-11 |
| Detection.lua in **client/** | OnZombieUpdate/OnPlayerUpdate are client-only events. | 2026-02-20 |
| BuildActions.lua in **server/** | `ISBuildingObject` lives in server/ and derive() runs at file-load time. | 2026-02-21 |
| Dedup via `os.time()` | Real-time seconds. Game-hours at 60x gave a ~1 frame window. | 2026-03-11 |
| Sound: SP local, MP broadcast | Prevents double-play. | 2026-03-11 |
| Player stagger via `setBumpType` | `setSlowFactor`/`setSlowTimer` do not exist in B42. | 2026-03-11 |
| Mono OGG requirement | PZ `is3D` audio fails silently on stereo. | 2026-02-22 |

---

## Resolved from the old "Needs Verification" list

All checked against the installed 42.20 jar in Session 16. This table used to carry six unknowns; four are now answered and two became bugs.

| Item | Verdict |
|------|---------|
| `Perks.Foraging` | **WRONG** — it is `Perks.PlantScavenging`. Fixed S17, #17 |
| `Climate.GetInstance():getRainStrength()` | **WRONG** on every identifier — it is `getClimateManager():getRainIntensity()`. Fixed S17, #18 |
| `Capability.CanBuildAnywhere` | **DOES NOT EXIST** — it is `UseBuildCheat`. Fixed S17 in all 3 places, #14 |
| `ChurchStorageMisc` | **DOES NOT EXIST** — 42.20 has no church distribution at all. Found and fixed S17 |
| Recipe `SkillRequired = Carpentry` | **NOT A PERK** — it is `Woodwork`. Found and fixed S17 |
| Rain intensity range | **0.0-1.0**, from vanilla's own use of the sibling intensity getters |
| `Woodwork` / `PlantScavenging` display names | Show as "Carpentry" / "Foraging". Existing tooltips are correct, deliberately unchanged |
| `setOutlineHighlight` / `setOutlineHighlightCol` | Exist. Fine |
| `BodyPartType.Foot_L` | Exists. Fine |

Still open: `sendServerCommand(player, module, cmd, args)` targeted send, used in WireNetworkSync. Verify by reconnecting in MP.

---

## Session History

### Session 17 (2026-08-05): all five code bugs closed, name verifier built

Built `scripts/verify_names.py` + `scripts/pzclass.py` *before* fixing anything, on the
grounds that S16's hand-verification had already decayed — and it immediately found two
bugs nobody had filed (`ChurchStorageMisc`, and `Carpentry` in both Tier 1 recipes).

Closed #14/#15/#16/#17/#18. Two of them were larger than the issue said: #14 named one
`CanBuildAnywhere` site and there were three, and #16's real damage was that the server
set cooldowns while the client checked them, so MP cooldowns never applied at all.

Tests 131 → 143. The five new #15 tests were confirmed to fail with the guards removed,
so they are not vacuous. Nothing was tested against a running game.

### Session 16 (2026-08-05): B42.20.2 audit

Six silent failures found by reading the mod against an installed 42.20 rather than against docs. Three fixed and committed (4537d2c), three filed as #14 through #18. `pz-mod-checker scan` reported clean before and after and caught none of them, which produced pz-mod-checker#23: a spec for a `validate` command that resolves names against the real game.

Also added `Base.ElectricWire` as a trip-line binding option and widened the Tanglefoot inputs.

### Session 15 (2026-04-14): Gemini inventory icons

All 4 inventory icons generated and installed. World sprites still pending.

### Session 14 (2026-03-11): Float safety, loot guard, north orientation

`tileKey` floors coords, `isServer()` guard on loot, `north` forwarded. 131/131 tests pass.
