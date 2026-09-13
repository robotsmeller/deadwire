# Deadwire in-game test plan

Written at the end of Session 22, when the mod became believed-correct on paper
and stopped being anything more than that.

**Nothing below has ever been watched working.** Session 18 confirmed the mod
loads, the items exist, the recipes register and the sprites are real textures.
It never placed one of the mod's own wires. Everything else in here is reasoning
about a game nobody ran.

Run it in single player. Anything needing two players is at the bottom, unrun.

---

## Before you start

1. Launch Project Zomboid. Enable **Deadwire** in the mod list.
2. Start a **new sandbox game**. In the settings, find the **Deadwire** page
   (one page, 33 options) and leave everything at its default.
3. Set **Zombies → Population → None** for parts A to F. Part C turns them back
   on. A wandering horde during the visual checks wastes your time.
4. Pick any spawn. An open field beats a house: you need bare ground to place on
   and clear sightlines for the outline checks.
5. The log is `C:\Users\roban\Zomboid\console.txt`. Leave it open in an editor
   that reloads on change, or tell me and I will read it for you.

**Leave debug logging off.** `DeadwireConfig.DEBUG` is `false` and should stay
that way for a first run: it logs a line per tile registration and is most of
the log volume, and nothing in Parts A to G needs it. Every check below names a
line that prints without it.

If something fails and the plain log does not say why, turn it on then, for that
one check:

```
scripts/cmd.py run_lua 'code=DeadwireConfig.DEBUG = true'
```

---

## Part A: does it load at all

Search `console.txt` for `[Deadwire]`. You should find all of these, once each:

```
[Deadwire] LootDistribution: bells→...  kits→...  tables (chance=12)
[Deadwire] WireManager: loaded 0 wires from save (nextId=1)
[Deadwire] WireManager initialized (server)
[Deadwire] ServerCommands initialized
[Deadwire] TriggerHandlers initialized (client)
[Deadwire] CamoVisibility initialized (client)
[Deadwire] CamoDegradation initialized (server)
[Deadwire] Client EventHandlers initialized
```

**A1.** All eight present → the mod loaded in every one of its three parts.

**A2.** Any line missing, or any Lua error naming a Deadwire file → stop and
tell me which. A file that throws stops loading at that line and everything
below it in that file never runs, silently.

**A3.** Two new files this session, `WireActions.lua` and the rewritten
`CamoVisibility.lua`, are the ones most likely to throw. `WireActions` derives
from a vanilla class at load time; if that name is wrong the error names the
file.

`WireActions.lua` prints nothing with debug logging off, so absence of a line
proves nothing about it. The check that does is whether the global it defines
exists:

```
scripts/cmd.py run_lua 'code=print("[Deadwire] WireActions loaded: " .. tostring(ISDeadwireWireAction ~= nil))'
```

`false` means the file threw before its last line. The smoke script does this
for you.

---

## Part B: placing a wire

This is the path Session 18 never exercised. Everything else depends on it.

**B1.** Give yourself a kit. Debug menu → item spawner → search `Deadwire`.
Take one of each: tin can, reinforced, bell, tanglefoot.

**B2.** Right-click bare ground. A **Place Deadwire...** submenu appears,
listing only the kits you are carrying, each with a count in brackets.

- Nothing appears → the menu never fired. Check the log for a Lua error at
  right-click time.
- Types you are not carrying appear → wrong, tell me.

**B3.** Pick **Tin Can Trip Line (1)**. You get a ghost object on the cursor.
Move it around: it should refuse to place on walls, in water, or inside a
vehicle, and accept bare ground.

**B4.** Click to place. Expect, on screen: a trip line sprite on that tile,
drawn diagonally, standing about 18 pixels above the ground line.

Expect in the log:

```
[Deadwire] Wire placed: tin_can_tripline at <x>,<y>,<z> by SP
```

**B5.** Check the kit left your inventory. Exactly one.

**B6.** Walk through the tile the wire is on. You should pass straight through,
not be blocked. This is what `setCanPassThrough(true)` is for and it has never
been watched either.

**B7.** Place the other three types on separate tiles. Each gets its own sprite.
Tanglefoot sits much lower, about 6 pixels up, and is deliberately hard to see
on grass. Part E is what fixes that.

**B8.** Place a wire directly next to a door, then open and close the door. It
must not be blocked. That was #8 and the fix is untested.

**B9.** Save and quit to the main menu, then load the same save. Expect:

```
[Deadwire] WireManager: loaded 4 wires from save (nextId=5)
```

and all four wires still on the ground where you left them.

---

## Part C: does a zombie set one off

Turn zombie population back to normal, or spawn one from the debug menu next to
a wire.

**C1.** Stand back, out of earshot is fine, and let a zombie walk onto the
**tin can** wire. Expect:

- a rattle you can hear
- the wire disappears (tin can is single-use by default)
- in the log: `[Deadwire] Wire triggered: tin_can_tripline at ...` (needs
  `LogWireTriggers` on in the sandbox settings, which is off by default, so
  turn it on for this run)
- other zombies in earshot turn and come towards the noise

**C2.** Same on the **reinforced** wire. Different sound, wire survives, and it
will not fire again for 36 real seconds. Walk a second zombie in immediately to
confirm the silence, then again after a minute to confirm it re-arms.

**C3.** Same on the **bell** wire. Loudest of the three, radius 60 tiles.

**C4.** Walk a zombie into **tanglefoot** repeatedly. About 4 in 10 should fall
over. No sound at all: it is a silent trap. Crawlers are ignored by default.

**C5. The one that matters.** Stand 30 or more tiles from a wire, out of sight,
and let a zombie hit it. It must still fire. Until this session the server
checked how far away *you* were rather than where the zombie was, so trip lines
only worked when you were already within three tiles, which is the mod's whole
point not working. This check is the fix.

**C6.** Walk into a wire yourself. Trip lines make noise. Tanglefoot staggers
you and takes 5 points of foot damage. Trip lines do **not** damage you.

---

## Part D: the new context menu

**D1.** Right-click a wire you placed, from **across the screen**, ten or more
tiles away. The menu offers **Remove <name>** and **Camouflage <name>**.

**D2.** Click **Remove**. Your character should **walk to the wire first**, then
play a short action, then the wire vanishes. It must not happen instantly from
where you stand, and it must not fail silently.

- Nothing happens and no walk starts → the wire is probably somewhere your
  character cannot path to. Try one on open ground.
- The character walks but nothing is removed → check the log for
  `RemoveWire: SP too far from x,y,z`. That means the walk finished further out
  than the server's four-tile bound, and I have the number wrong.

**D3.** Place a wire, then right-click it and choose **Camouflage**. Longer
action than removal, roughly three times. The wire should visibly fade out when
it completes.

Camouflage costs nothing today. Materials and a skill check are Sprint 4.

**D4.** Right-click the camouflaged wire again. **Camouflage** is gone from the
menu, **Remove** is still there.

**D5.** Interrupt yourself: start a Camouflage, then walk away before the bar
fills. Nothing should happen to the wire.

---

## Part E: the owner outline (new this session)

**E1.** With `OwnerWireOutline` on (the default), every wire you placed should be
drawn with a coloured outline, from up to 20 tiles away, on your floor only.

Colours are per type, so a perimeter is readable without walking it:

| Wire | Outline |
|---|---|
| Tin can | pale yellow |
| Reinforced | steel blue |
| Bell | brass |
| Tanglefoot | green |

**E2.** The tanglefoot one is the point of the feature. Stand back and confirm
you can now find a tanglefoot tile on grass, which you could not in B7.

**E3.** Walk more than 20 tiles away and back. The outline should come and go.

**E4.** Camouflage a wire. It fades, and the outline stays, because you are the
one who put it there.

**E5.** Turn `OwnerWireOutline` off in the sandbox settings and start a fresh
save. No outlines on anything.

**E6.** Timing: the outline updates once a second, not every frame. A one-second
lag after placing is expected, not a bug.

---

## Part F: camouflage visibility and weather

Camouflage hides a wire from everyone whose Foraging is too low. In single
player you are the owner of every wire, and the owner sees through camouflage by
default, so you have to turn that off to see the effect at all.

**F1.** In the sandbox settings, turn **`CamoVisibleToOwner` off**. New save,
place a wire, camouflage it.

**F2.** At Foraging 0 the wire should be **completely invisible**. Walk over it
and it should still trigger. Blind and armed is the intended state.

**F3.** Raise Foraging with the debug menu. At **3** it should be a faint
shimmer within 3 tiles. At **5**, semi-transparent within 8. At **7**, clear
with an **orange** outline within 15 tiles.

That orange is deliberately not one of the four owner colours in Part E: orange
means somebody else's wire that you spotted.

**F4.** Turn `CamoVisibleToOwner` back on. Your own camouflaged wire is fully
visible again regardless of skill.

**F5. Rain.** Camouflage a wire, then force rain from the debug weather panel
and let it run.

The check runs every ten in-game minutes while it is raining, and takes
`5 x how hard it is raining` off a starting 100, rounded down. Heavy rain at
0.8 or above counts as a storm and takes 10 flat. So a storm strips a wire in
about a hundred in-game minutes and light drizzle may take a whole day. Speed
up time if you are watching it.

Expect the wire to become visible on its own, and the log to say:

```
[Deadwire] CamoDegradation: N wire(s) lost camouflage from rain (intensity=...)
```

Very light rain takes nothing at all: at intensity below 0.2 the per-tick loss
rounds down to zero. That is the code working as written, not a stall.

**F6. Wear from triggers.** Camouflage a wire and let zombies set it off seven
times. Each trigger costs 15 durability, so the seventh should strip it.

**F7.** Camouflage a wire, save, quit to menu, reload. It must **still be
camouflaged**. This was broken until Session 21: camo was written to the live
network and never to the save, so every reload stripped it.

---

## Part G: the authority gates

These are the #36 fixes. Single player can only reach one of them honestly,
because you own everything and you are always an admin.

**G1.** From the debug console, try to remove a wire from far away without
walking:

```
sendClientCommand("Deadwire", "RemoveWire", {x = <wire x>, y = <wire y>, z = 0})
```

with your character 30 tiles off. Expect nothing to happen and the log to say
`RemoveWire: SP too far from ...`. That is the gate working.

**G2.** Same shape for camouflage:

```
sendClientCommand("Deadwire", "CamouflageWire", {x = ..., y = ..., z = 0})
```

Same refusal.

**G3.** Try the command that no longer exists:

```
sendClientCommand("Deadwire", "PlaceWire", {x = ..., y = ..., z = 0, wireType = "bell_tripline"})
```

Expect `[Deadwire] Unknown command: PlaceWire` and no wire. Placement now only
happens through the build action, which the game validates for us.

**G4.** Wire cap. Set `WireMaxPerPlayer` to its minimum of **5**, spawn seven
kits, place six. The sixth should refuse, with
`[Deadwire] BuildActions: SP at wire limit (5)`, and keep its kit.

---

## Part H: does the audio work at all (#49)

Rob heard nothing when a tin can wire broke, and nobody knew whether the sound
name never registered or registered and played too quietly. Those need opposite
fixes, so this measures the registration before it plays anything.

What was ruled out first, by measurement rather than by listening again: all
four oggs are mono 44.1kHz and peak at full scale, so they are neither stereo
nor silent; `category = Item` is the most-used category in the game's own sound
scripts, 1521 blocks of it; `is3D` and `clip.file` are both real fields on
`GameSound` and `GameSoundClip` in the 42.20 jar; and `PlayWorldSound`'s 6-arg
overload exists with the types we pass.

What was left is that `deadwire_sounds.txt` declared its `sound` blocks at file
scope. All 150 vanilla sound scripts wrap them in `module Base { }`, without
exception. Ours was the only file that did not. No other mod installed here
ships a sound script at all, so vanilla is the entire comparison set and this
is a strong lead rather than a proven cause. That is now fixed, and Part H is
what decides whether it was the cause.

**H1.** With the game running and a save loaded:

```
cd c:/xampp/htdocs/pz-test-pilot
python scripts/cmd.py deadwire_probe_audio step=check
```

Silent, safe any time. Four `AU1.*` lines, one per sound. Each one is `PASS` if
`getGameSound` returns something and `FAIL` with "the script block did not
parse" if it returns nil. This is the whole question: a nil here means no volume
change and no playback change could ever have helped.

**H2.** Then, with your speakers up:

```
python scripts/cmd.py deadwire_probe_audio step=play
```

Each registered sound is played three ways in a row: the mod's own
`PlayWorldSound` call (`a`), the character's emitter (`b`), and
`character:playSound` (`c`). Say which of the three you heard. If only `b` and
`c` are audible, the fix is to change the mod's playback call, not the audio.

**H3.** Only once H1 and H2 are green, do it for real: walk into a tin can wire
and listen. That is the check #49 is actually about; H1 and H2 exist so that a
failure here has a known cause.

---

## What single player cannot test

Say the word and I will write the dedicated-server version of this, but none of
it can be checked from one machine:

- **The join sync.** A second player's wire list arrives from the server on
  connect. The event this used to hang off did not exist, so it never ran once.
- **The multiplayer rebuild.** The server rebuilds the placement object from
  scratch and drops any argument that is not a plain value. Wire placement
  failed completely on a dedicated server until Session 21.
- **Faction outlines.** Part E's outline extends to anyone in your faction.
  There are no factions in single player.
- **Cooldown mirroring.** Each client keeps its own copy of a wire's cooldown.
- **Somebody else's wire.** Every authority check in Part G is about a player
  who is not the owner, and in single player there is no such player.

## What is deliberately not built

Not bugs, and not on this plan:

- Nothing damages a wire. Zombies walk through rather than attack, and no code
  path reduces a wire's health. Issue #45.
- A wire is one tile. Multi-tile runs between anchors were designed and never
  built. Issue #45.
- Tanglefoot has no prone timer and never wears out. Issue #45.
- Camouflage costs no materials and needs no skill. Sprint 4.
- Rain degradation is per ten in-game minutes, not per hour. The tooltip used
  to say per hour; the text was corrected, the timing was not changed.
- Step over and disarm were designed and never built.
