# Deadwire - Handoff

## Current Priority

**Fix #17 and #18, then #14/#15/#16, then finish the in-game smoke test**

#17 and #18 are one-line fixes that between them revive the entire camouflage system, which has never worked in either direction.

**Blocker for release:** world sprite *art* is placeholder. The `deadwire_01` tilesheet does ship (`.pack` + `.tiles`, both declared in mod.info), so the `construction_01_24` fallback should never fire — but that is unverified, and the 8 images in the sheet are Session 10 placeholders rather than the finished Gemini art. Source PNGs sit at repo root pending crop/resize and a tilesheet rebuild.

---

## Status

| Area | Status | Notes |
|------|--------|-------|
| Sprint 1 (Foundation) | **PASSED** | In-game, Session 6 |
| Sprint 2 (Placement) | **PASSED** | In-game, Session 8 |
| Sprint 3 (Sound+Trigger) | **Partly verified** | Items + globals confirmed in-game S16. Sprites, recipes, sounds still untested |
| Sprint 4 (Camo+Config) | **Broken** | Both halves dead: #17 and #18 |
| 42.20.2 compat | **Audited** | Six silent failures found, three fixed in 4537d2c |
| Custom world sprites | **Placeholder art** | Tilesheet ships and should load; images are S10 placeholders. Release blocker |
| Test harness | **Done** | 131 tests — `run_tests.bat` |
| pz-test-pilot harness | **Working** | Can drive the live game, see To Resume in context.md |

---

## Open Issues

| # | Title | Severity |
|---|-------|----------|
| 18 | Rain never degrades camouflage: the entire Climate API call is wrong | High |
| 17 | Camouflage skill scaling is dead: `Perks.Foraging` does not exist | High |
| 16 | Wire cooldown written in seconds, measured in game time | Medium |
| 15 | MP: server trusts client on wire triggers and kit consumption | Medium |
| 14 | Admin wire removal broken: `Capability.CanBuildAnywhere` does not exist | Medium |
| 13 | Tier 3: electrified perimeter wire (generator-powered) | Phase 3 |
| 12 | Loot distribution for metalworking rooms | Code fixed S16, needs in-game confirm |

---

## Version

- **v0.1.1** — tagged, released on GitHub. Not on Steam Workshop.
- mod.info: `modversion=0.1.1`, `pack=deadwire_01`, `tiledef=deadwire_01 200`
- `versionMin=42.0.0` is **wrong** and should be raised. The mod needs 42.13+ for namespaced tags and 42.15+ for JSON translations.

---

## Key Technical Decisions

| Decision | Rationale | Date |
|----------|-----------|------|
| No guards around unverified API names | A guard around a typo is indistinguishable from a guard around a real fallback. Cost three dead features. | 2026-08-05 |
| Verify names against the jar constant pool | Substring-matching the vanilla Lua tree gives false negatives: it passes `Perks.Foraging`. | 2026-08-05 |
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
| `Perks.Foraging` | **WRONG** — it is `Perks.PlantScavenging`. Issue #17 |
| `Climate.GetInstance():getRainStrength()` | **WRONG** on every identifier. Issue #18 |
| `Capability.CanBuildAnywhere` | **DOES NOT EXIST**. Issue #14 |
| `setOutlineHighlight` / `setOutlineHighlightCol` | Exist. Fine |
| `BodyPartType.Foot_L` | Exists. Fine |
| Issue #12 dist names | Were wrong, fixed in 4537d2c against verified vanilla names |

Still open: `sendServerCommand(player, module, cmd, args)` targeted send, used in WireNetworkSync. Verify by reconnecting in MP.

---

## Session History

### Session 16 (2026-08-05): B42.20.2 audit

Six silent failures found by reading the mod against an installed 42.20 rather than against docs. Three fixed and committed (4537d2c), three filed as #14 through #18. `pz-mod-checker scan` reported clean before and after and caught none of them, which produced pz-mod-checker#23: a spec for a `validate` command that resolves names against the real game.

Also added `Base.ElectricWire` as a trip-line binding option and widened the Tanglefoot inputs.

### Session 15 (2026-04-14): Gemini inventory icons

All 4 inventory icons generated and installed. World sprites still pending.

### Session 14 (2026-03-11): Float safety, loot guard, north orientation

`tileKey` floors coords, `isServer()` guard on loot, `north` forwarded. 131/131 tests pass.
