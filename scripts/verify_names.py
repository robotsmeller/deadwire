"""Resolve every game name Deadwire references against the installed game.

Run:  python scripts/verify_names.py [--pz <ProjectZomboid dir>]

Exit code 0 if every name resolves, 1 otherwise.

This exists because the whole class of bug that has cost this project the most
is a name that looks right and silently does not exist: Perks.Foraging,
Capability.CanBuildAnywhere, Base.TreeBranch, ChurchStorageMisc. None of them
error at load. The feature just never happens. `pz-mod-checker scan` does not
catch these -- it is a version-keyed rule engine with no concept of whether a
name resolves.

Checked categories (each has hard ground truth in the install):
  Perks.X              PerkFactory$Perks static fields
  Capability.X         Capability enum constants
  BodyPartType.X       BodyPartType enum constants
  Base.X               vanilla generated item scripts + this mod's own items
  distribution names   ProceduralDistributions.list keys
  SkillRequired/xpAward  perk names inside craftRecipe blocks
  Icon = X             media/textures/Item_X.png must exist
  event names          zombie/Lua/LuaEventManager's registry
  sprite names         the binary .tiles the game actually loads
  .tiles header        magic, version, tileset number and tile count bounds
  sound names          a sound block in the mod's script, with the ogg on disk
  Java calls           method exists on the receiver's class chain, with an
                       overload that takes that many arguments
  tiledef id           in range, and not colliding with a vanilla tilesheet
  sandbox options      every option declared is read, every key read is declared,
                       and every declared option has an EN label

Deliberately NOT checked: bare global function names. Many legitimate globals
are defined in vanilla Lua rather than exposed from Java, so a Java-only check
reports false positives, and a checker that cries wolf stops being read.
"""

import argparse
import glob
import json
import os
import re
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from pzclass import Jar  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MOD = os.path.join(REPO, "Contents", "mods", "Deadwire", "42", "media")

DEFAULT_PZ = r"C:/Program Files (x86)/Steam/steamapps/common/ProjectZomboid"

# Where PZ loads local (non-Workshop) mods from. Used only for tiledef collision
# checking, and skipped without complaint if it is not there.
MODS_DIR = os.path.join(os.path.expanduser("~"), "Zomboid", "mods")

TRANSLATE_EN = os.path.join(
    "Contents", "mods", "Deadwire", "42", "media",
    "lua", "shared", "Translate", "EN")
TRANSLATE_EN = os.path.join(os.path.dirname(os.path.dirname(
    os.path.abspath(__file__))), TRANSLATE_EN)

# Translator loads a FIXED list of base names and builds the path
# "<root>/media/lua/shared/Translate/<LANG>/<NAME>.json". The names live in
# zombie/core/Translator$1. A file outside this set is never opened -- no error,
# no warning, just untranslated raw keys shown to the player.
#
# The B41 convention was ItemName_EN.txt with a matching table name, and the _EN
# suffix carried over into this project's JSON files by habit. It was wrong for
# all three of them, and every item, recipe and sandbox option in the mod
# displayed as a raw id until Session 17.
# Attribute names the JVM itself writes into every constant pool. Fixed by the
# class file spec (JVMS 4.7), not by anything Project Zomboid chose, so removing
# them is not the same as hardcoding the list we are trying to derive.
JVM_ATTRIBUTE_NAMES = {
    "AnnotationDefault", "BootstrapMethods", "Code", "ConstantValue",
    "Deprecated", "EnclosingMethod", "Exceptions", "InnerClasses",
    "LineNumberTable", "LocalVariableTable", "LocalVariableTypeTable",
    "MethodParameters", "Module", "ModuleMainClass", "ModulePackages",
    "NestHost", "NestMembers", "PermittedSubclasses", "Record",
    "RuntimeInvisibleAnnotations", "RuntimeInvisibleParameterAnnotations",
    "RuntimeInvisibleTypeAnnotations", "RuntimeVisibleAnnotations",
    "RuntimeVisibleParameterAnnotations", "RuntimeVisibleTypeAnnotations",
    "Signature", "SourceDebugExtension", "SourceFile", "StackMapTable",
    "Synthetic",
}


def translator_base_names(jar):
    """The file names Translator will actually open, read from the game.

    This used to be a hardcoded set of 29 names, which is the same shape as
    every checker this project has had to fix: a belief, agreeing with itself.
    Translator builds <root>/media/lua/shared/Translate/<LANG>/<NAME>.json from
    a fixed map in zombie/core/Translator$1, and a file outside it is simply
    never opened -- no error, no warning, raw ids on screen. Reading the map's
    own keys means a future build that adds one is picked up for free.
    """
    k = jar.klass("zombie/core/Translator$1")
    pool = {v for v in k.pool if isinstance(v, str)}
    return {v for v in pool
            if re.fullmatch(r"[A-Z][A-Za-z0-9_]*", v)
            and v not in JVM_ATTRIBUTE_NAMES}

# Item ids referenced with a module prefix this checker cannot resolve are
# skipped rather than reported; only Base.* has a single unambiguous source.
ITEM_RE = re.compile(r"\bBase\.([A-Za-z_][A-Za-z0-9_]*)")


class Report:
    def __init__(self):
        self.problems = []
        self.checked = 0

    def ok(self, _category, _name):
        self.checked += 1

    def bad(self, category, name, where, hint=""):
        self.checked += 1
        self.problems.append((category, name, where, hint))

    def check(self, category, name, valid, where, universe=None):
        if name in valid:
            self.ok(category, name)
        else:
            self.bad(category, name, where, near(name, universe or valid))


def near(name, universe):
    """Cheap nearest-name hint: same prefix, or same lowercase spelling."""
    low = name.lower()
    exact = [c for c in universe if c.lower() == low]
    if exact:
        return "did you mean %s" % exact[0]
    pre = sorted(c for c in universe if c.lower().startswith(low[:4]))[:4]
    return ("closest: " + ", ".join(pre)) if pre else ""


# ---------------------------------------------------------------- ground truth

def vanilla_items(pz):
    """Every `item X` declared inside `module Base` in the generated scripts."""
    items = set()
    root = os.path.join(pz, "media", "scripts")
    for dirpath, _dirs, files in os.walk(root):
        for fn in files:
            if not fn.endswith(".txt"):
                continue
            path = os.path.join(dirpath, fn)
            with open(path, encoding="utf-8", errors="replace") as fh:
                src = fh.read()
            for m in re.finditer(r"^\s*item\s+([A-Za-z_][A-Za-z0-9_]*)\s*$",
                                 src, re.M):
                items.add(m.group(1))
    return items


def vanilla_distributions(pz):
    path = os.path.join(pz, "media", "lua", "server", "Items",
                        "ProceduralDistributions.lua")
    with open(path, encoding="utf-8", errors="replace") as fh:
        src = fh.read()
    return set(re.findall(r"^\t([A-Za-z_][A-Za-z0-9_]*)\s*=\s*\{", src, re.M))


def mod_items():
    path = os.path.join(MOD, "scripts", "deadwire_items.txt")
    with open(path, encoding="utf-8", errors="replace") as fh:
        src = fh.read()
    return set(re.findall(r"^\s*item\s+([A-Za-z_][A-Za-z0-9_]*)\s*$", src, re.M))


TILES_PATH = os.path.join(MOD, "deadwire_01.tiles")

# Bounds enforced by IsoWorld.LoadTileDefinitions, read from the 42.20.4
# bytecode. The limits are 1024 when the tiledef fileNumber is exactly 1 and
# 512 otherwise, and a mod's fileNumber is its mod.info tiledef id, so 512 is
# always the number that applies to us.
TILESETS_PER_FILE = 512
TILES_PER_TILESET = 512


def parse_tiles(path):
    """Read the binary tile definitions the game actually loads.

    Layout, confirmed against all seven vanilla .tiles files and the bytecode
    of IsoWorld.LoadTileDefinitions:

        "tdef" | version u32 | tileset_count u32
        per tileset: name\n | image\n | cols u32 | rows u32
                     tileset_number u32 | tile_count u32
        per tile:    prop_count u32 | (key\n value\n) * prop_count

    Note what the fifth field is NOT. pz-tilesheet's README calls it "id" and
    says it must match the mod.info tiledef number. It is the tileset number,
    LoadTileDefinitions rejects anything outside 1..512, and the tiledef number
    is passed separately as fileNumber. Following that README and picking a
    tiledef id above 512 to dodge a collision produces a file the game refuses,
    and every world sprite silently disappears (#40).
    """
    with open(path, "rb") as fh:
        blob = fh.read()
    pos = [0]

    def raw(n):
        out = blob[pos[0]:pos[0] + n]
        if len(out) != n:
            raise ValueError("truncated at byte %d" % pos[0])
        pos[0] += n
        return out

    def u32():
        return struct.unpack("<I", raw(4))[0]

    def line():
        end = blob.find(b"\n", pos[0])
        if end < 0:
            raise ValueError("unterminated string at byte %d" % pos[0])
        out = blob[pos[0]:end].decode("utf-8", "replace").strip()
        pos[0] = end + 1
        return out

    magic = raw(4)
    if magic != b"tdef":
        raise ValueError("bad magic %r, expected b'tdef'" % magic)

    out = {"version": u32(), "tilesets": []}
    for _ in range(u32()):
        ts = {"name": line(), "image": line(), "cols": u32(), "rows": u32(),
              "tileset_number": u32(), "tile_count": u32()}
        for _t in range(ts["tile_count"]):
            for _prop in range(u32()):
                line()
                line()
        out["tilesets"].append(ts)
    out["trailing"] = len(blob) - pos[0]
    return out


def mod_sprites():
    """Tile names the mod's own tilesheet actually defines.

    Read from the binary, not the .tiles.txt beside it. The game builds
    media/<name>.tiles and never looks at the text form -- the string
    ".tiles.txt" occurs in no class in the jar -- so checking the text file
    verified a file the game ignores, while the one it loads was verified by
    nothing. Both are written from the same inputs, so they agreed by
    construction: the same blind-checker shape as the crafting category prefix.
    """
    if not os.path.exists(TILES_PATH):
        return set()
    try:
        tiles = parse_tiles(TILES_PATH)
    except (ValueError, OSError):
        return set()
    names = set()
    for ts in tiles["tilesets"]:
        names |= {"%s_%d" % (ts["name"], i) for i in range(ts["tile_count"])}
    return names


def lua_files():
    out = []
    for dirpath, _dirs, files in os.walk(os.path.join(MOD, "lua")):
        for fn in files:
            if fn.endswith(".lua"):
                out.append(os.path.join(dirpath, fn))
    return sorted(out)


def script_files():
    d = os.path.join(MOD, "scripts")
    return sorted(os.path.join(d, f) for f in os.listdir(d) if f.endswith(".txt"))


def rel(path):
    return os.path.relpath(path, REPO).replace("\\", "/")


# ---------------------------------------------------------------------- checks

def check_lua(rep, jar, items, dists):
    perks = jar.klass("zombie/characters/skills/PerkFactory$Perks").constants()
    caps = jar.klass("zombie/characters/Capability").constants()
    bodyparts = jar.klass("zombie/characters/BodyDamage/BodyPartType").constants()
    sprites = mod_sprites()
    # The mod's own items are declared in `module Base` too, so Base.Deadwire_*
    # is legitimate: resolve against vanilla plus this mod's declarations.
    items = items | mod_items()

    for path in lua_files():
        with open(path, encoding="utf-8", errors="replace") as fh:
            src = fh.read()
        # Comments carry dead example names on purpose; strip them first.
        code = re.sub(r"--[^\n]*", "", src)
        where = rel(path)

        for name in set(re.findall(r"\bPerks\.([A-Za-z_][A-Za-z0-9_]*)", code)):
            rep.check("Perks", name, perks, where)
        for name in set(re.findall(r"\bCapability\.([A-Za-z_][A-Za-z0-9_]*)", code)):
            rep.check("Capability", name, caps, where)
        for name in set(re.findall(r"\bBodyPartType\.([A-Za-z_][A-Za-z0-9_]*)", code)):
            rep.check("BodyPartType", name, bodyparts, where)
        for name in set(ITEM_RE.findall(code)):
            rep.check("item", "Base." + name, {"Base." + i for i in items}, where,
                      universe=items)
        for name in set(re.findall(r'"(deadwire_01_\d+)"', code)):
            rep.check("sprite", name, sprites, where)

        # Distribution names live in `local <x>Dists = { "A", "B" }` tables.
        for block in re.findall(r"local\s+\w*[Dd]ists\s*=\s*\{(.*?)\}", code, re.S):
            for name in re.findall(r'"([A-Za-z_][A-Za-z0-9_]*)"', block):
                rep.check("distribution", name, dists, where)


def check_scripts(rep, jar, items):
    perks = jar.klass("zombie/characters/skills/PerkFactory$Perks").constants()
    all_items = items | mod_items()

    for path in script_files():
        with open(path, encoding="utf-8", errors="replace") as fh:
            src = fh.read()
        where = rel(path)
        # Strip exactly what ScriptParser.stripComments strips: /* */ and
        # nothing else. A // line is left in as text and becomes part of the
        # next block's header, so the game skips that whole block without a
        # word. Stripping // here, as this once did, checked a file the game
        # never reads. All four sounds and the electric recipe, session 29.
        code = re.sub(r"/\*.*?\*/", "", src, flags=re.S)
        for n, line in enumerate(code.split("\n"), 1):
            if "//" in line:
                rep.bad("script comment", "//", "%s line %d" % (where, n),
                        "the game only strips /* */; this line hides the "
                        "block after it")

        for name in set(ITEM_RE.findall(code)):
            rep.check("item", "Base." + name,
                      {"Base." + i for i in all_items}, where, universe=all_items)

        # SkillRequired = Perk:Level;Perk:Level  (same grammar for xpAward)
        for field in ("SkillRequired", "xpAward"):
            for m in re.finditer(field + r"\s*=\s*([^,\n}]+)", code):
                for pair in m.group(1).split(";"):
                    pair = pair.strip()
                    if not pair:
                        continue
                    perk = pair.split(":")[0].strip()
                    if perk:
                        rep.check("recipe skill", perk, perks, where)

        for name in set(re.findall(r"^\s*Icon\s*=\s*([A-Za-z0-9_]+)", code, re.M)):
            png = os.path.join(MOD, "textures", "Item_%s.png" % name)
            if os.path.exists(png):
                rep.ok("icon", name)
            else:
                rep.bad("icon", name, where,
                        "expected media/textures/Item_%s.png" % name)


# Options whose key is built at runtime rather than written as a literal, so the
# literal scan below cannot see them. Each must be justified by a real call site.
DYNAMIC_SANDBOX_KEYS = {
    "EnableTier0": "Config.isTierEnabled builds the key from the tier number",
    "EnableTier1": "Config.isTierEnabled",
    "EnableTier2": "Config.isTierEnabled",
    "EnableTier3": "Config.isTierEnabled",
    "EnableTier4": "Config.isTierEnabled",
    "WireAffectsZombies": "Detection.detectEntity picks the key by entity type",
    "WireAffectsPlayers": "Detection.detectEntity",
    "TripLineHealth": "Config.getWireHealth looks it up via healthOptions",
    "ReinforcedHealth": "Config.getWireHealth via healthOptions",
}

# Read by Lua and deliberately NOT declared, with a reason. isTierEnabled asks
# about tiers 2-4, which are Phases 2-4 and have no wire types yet; getSandbox
# returns the `true` default, which gates nothing because those tiers are empty.
# Declaring them now would put knobs for absent features on the settings screen.
# Each must gain a real option as its phase lands.
UNDECLARED_BY_DESIGN = {
    "EnableTier2": "Phase 2 (pull-alarms) not implemented",
    "EnableTier3": "Phase 3 (electric fencing) not implemented, Issue #13",
    "EnableTier4": "Phase 4 (advanced) not implemented",
}


def check_sandbox_options(rep):
    """Every option offered to players must be read, and vice versa.

    A key the Lua reads but sandbox-options.txt does not declare is stuck on its
    hardcoded default forever. A key declared but never read is a knob on the
    server settings screen that silently does nothing -- which is what
    TinCanBreakOnTrigger, TripLineHealth and ReinforcedHealth were until
    Session 17.
    """
    used = set()
    for path in lua_files():
        with open(path, encoding="utf-8", errors="replace") as fh:
            code = re.sub(r"--[^\n]*", "", fh.read())
        used |= set(re.findall(r'getSandbox\(\s*"([A-Za-z0-9_]+)"', code))
    used |= set(DYNAMIC_SANDBOX_KEYS)

    opts_path = os.path.join(MOD, "sandbox-options.txt")
    with open(opts_path, encoding="utf-8", errors="replace") as fh:
        declared = set(re.findall(r"^\s*option\s+Deadwire\.([A-Za-z0-9_]+)",
                                  fh.read(), re.M))

    for key in sorted(used - declared - set(UNDECLARED_BY_DESIGN)):
        rep.bad("sandbox option", key, "sandbox-options.txt",
                "read by Lua but not declared -- permanently stuck on its default")
    for key in sorted(declared - used):
        rep.bad("sandbox option", key, "sandbox-options.txt",
                "declared but never read -- a knob that does nothing")
    for key in sorted(used & declared):
        rep.ok("sandbox option", key)

    # Every declared option needs an EN label or the settings screen shows the key.
    tr_path = os.path.join(TRANSLATE_EN, "Sandbox.json")
    with open(tr_path, encoding="utf-8") as fh:
        data = json.load(fh)
    table = data.get("Sandbox_EN", data)
    translated = {k[len("Sandbox_Deadwire_"):] for k in table
                  if k.startswith("Sandbox_Deadwire_")
                  and not k.endswith("_tooltip") and "_option" not in k}
    for key in sorted(declared - translated):
        rep.bad("sandbox translation", key, "Translate/EN/Sandbox.json",
                "declared option has no EN label")

    # And the other direction. Thirty-odd labels outlived the options they
    # described -- WireDecay, TanglefootSize, CamoDisarm, the MaxSpans -- so the
    # file read like a feature list for a mod that does not exist (#44). Harmless
    # in game, which is exactly why nothing caught it for six sessions.
    for key in sorted(translated - declared):
        rep.bad("sandbox translation", key, "Translate/EN/Sandbox.json",
                "label for an option sandbox-options.txt does not declare")
    for key in sorted(translated & declared):
        rep.ok("sandbox translation", key)


def _load_translation(name):
    path = os.path.join(TRANSLATE_EN, name + ".json")
    if not os.path.exists(path):
        return {}
    with open(path, encoding="utf-8") as fh:
        data = json.load(fh)
    return data.get(name, data)


ITEM_CAT_PREFIX = "IGUI_ItemCat_"
RECIPE_CAT_PREFIX = "IGUI_CraftingCategories_"


def _vanilla_ig_ui(pz):
    path = os.path.join(pz, "media", "lua", "shared", "Translate", "EN",
                        "IG_UI.json")
    if not os.path.exists(path):
        return {}
    with open(path, encoding="utf-8", errors="replace") as fh:
        try:
            return json.load(fh)
        except ValueError:
            return {}


def check_categories(rep, pz):
    """Item and recipe categories need IGUI_ keys or the UI shows the raw key.

    `DisplayCategory = X` on an item resolves through IGUI_ItemCat_X, and
    `category = X` on a craftRecipe through IGUI_CraftingCategories_X -- both
    in IG_UI.json, which this mod did not have at all until Session 17.

    The recipe prefix is IGUI_CraftingCategories_, NOT IGUI_CraftCategory_.
    Session 17 guessed the latter, wrote it into both the mod and this checker,
    and the checker then reported the bug as resolved for a full session: the
    crafting sidebar rendered the raw key `CraftingCategories_Deadwire` the
    whole time. Both prefixes below are taken from the game's own
    media/lua/shared/Translate/EN/IG_UI.json, not from memory.
    """
    ig = _load_translation("IG_UI")

    # Check the prefixes themselves against the game before using them. A
    # hardcoded prefix is a belief, and this checker has already shipped a
    # wrong one; if a future build renames these, the assertion fails loudly
    # instead of the checker silently blessing keys nothing reads.
    vanilla_ig = _vanilla_ig_ui(pz)
    for prefix in (ITEM_CAT_PREFIX, RECIPE_CAT_PREFIX):
        if any(k.startswith(prefix) for k in vanilla_ig):
            rep.ok("category prefix", prefix)
        else:
            rep.bad("category prefix", prefix + "*",
                    "media/lua/shared/Translate/EN/IG_UI.json",
                    "no key with this prefix in the game's own IG_UI.json")

    def collect(pattern, fname):
        path = os.path.join(MOD, "scripts", fname)
        if not os.path.exists(path):
            return set()
        with open(path, encoding="utf-8", errors="replace") as fh:
            code = re.sub(r"//[^\n]*", "", fh.read())
        return set(re.findall(pattern, code, re.M))

    for cat in sorted(collect(r"^\s*DisplayCategory\s*=\s*([A-Za-z0-9_]+)",
                              "deadwire_items.txt")):
        rep.check("item category", ITEM_CAT_PREFIX + cat, ig,
                  "Translate/EN/IG_UI.json")
    for cat in sorted(collect(r"^\s*category\s*=\s*([A-Za-z0-9_]+)",
                              "deadwire_recipes.txt")):
        rep.check("recipe category", RECIPE_CAT_PREFIX + cat, ig,
                  "Translate/EN/IG_UI.json")

    # The sandbox page label lives in Sandbox.json, not IG_UI.json.
    sb = _load_translation("Sandbox")
    opts = os.path.join(MOD, "sandbox-options.txt")
    with open(opts, encoding="utf-8", errors="replace") as fh:
        pages = set(re.findall(r"^\s*page\s*=\s*([A-Za-z0-9_]+)", fh.read(), re.M))
    for page in sorted(pages):
        rep.check("sandbox page", "Sandbox_" + page, sb,
                  "Translate/EN/Sandbox.json")


def check_translation_filenames(rep, base_names):
    """A translation file PZ does not ask for by name is simply never read."""
    if not os.path.isdir(TRANSLATE_EN):
        rep.bad("translations", "Translate/EN", "media/lua/shared/",
                "directory missing")
        return
    for fn in sorted(os.listdir(TRANSLATE_EN)):
        if not fn.endswith(".json"):
            continue
        base = fn[:-len(".json")]
        if base in base_names:
            rep.ok("translation file", fn)
        else:
            hint = ""
            if base.endswith("_EN") and base[:-3] in base_names:
                hint = ("drop the _EN suffix -- it is already in EN/; "
                        "should be %s.json" % base[:-3])
            else:
                hint = "not a name Translator loads; the file is never opened"
            rep.bad("translation file", fn, "Translate/EN/", hint)


def pack_page_names(path):
    """Page names inside a .pack atlas: "PZPK" | mask i32 | pages u32, then a
    length-prefixed name per page. Only the names are needed here."""
    with open(path, "rb") as fh:
        blob = fh.read()
    if blob[:4] != b"PZPK":
        raise ValueError("bad magic %r, expected b'PZPK'" % blob[:4])
    pages = struct.unpack_from("<I", blob, 8)[0]
    pos = 12
    names = []
    for _ in range(min(pages, 64)):
        n = struct.unpack_from("<I", blob, pos)[0]
        pos += 4
        names.append(blob[pos:pos + n].decode("utf-8", "replace"))
        break   # one page per sheet here; reading further needs the image blob
    return names


def check_config_sprites(rep):
    """The tilesheet the game loads must define the tiles Config.Sprites names.

    Everything here reads the binary .tiles. The text .tiles.txt beside it was
    what this checker used to read, and the game never opens it (#40).
    """
    if not os.path.exists(TILES_PATH):
        rep.bad("tilesheet", "deadwire_01.tiles", "media/",
                "the file the game loads is missing")
        return
    try:
        tiles = parse_tiles(TILES_PATH)
    except (ValueError, OSError) as exc:
        rep.bad("tilesheet", "deadwire_01.tiles", "media/",
                "unparseable: %s" % exc)
        return

    if tiles["version"] == 1:
        rep.ok("tilesheet", "version")
    else:
        rep.bad("tilesheet", "version %d" % tiles["version"], "media/deadwire_01.tiles",
                "LoadTileDefinitions accepts version 1 only")

    if tiles["trailing"] == 0:
        rep.ok("tilesheet", "byte length")
    else:
        rep.bad("tilesheet", "byte length", "media/deadwire_01.tiles",
                "%d bytes left over after parsing -- the layout is not what we "
                "think it is" % tiles["trailing"])

    if not tiles["tilesets"]:
        rep.bad("tilesheet", "tilesets", "media/deadwire_01.tiles",
                "no tilesets declared, so no world sprite can resolve")
        return

    for ts in tiles["tilesets"]:
        num = ts["tileset_number"]
        if 1 <= num <= TILESETS_PER_FILE:
            rep.ok("tilesheet", "tileset number")
        else:
            rep.bad("tilesheet", "tileset number %d" % num,
                    "media/deadwire_01.tiles",
                    "must be 1..%d or the game refuses the whole file and every "
                    "world sprite vanishes. This is NOT the mod.info tiledef id, "
                    "whatever pz-tilesheet's README says" % TILESETS_PER_FILE)

        if 0 <= ts["tile_count"] <= TILES_PER_TILESET:
            rep.ok("tilesheet", "tile count")
        else:
            rep.bad("tilesheet", "tile count %d" % ts["tile_count"],
                    "media/deadwire_01.tiles",
                    "must be 0..%d" % TILES_PER_TILESET)

        expected = ts["cols"] * ts["rows"]
        if ts["tile_count"] == expected:
            rep.ok("tilesheet", "grid")
        else:
            rep.bad("tilesheet", "grid %dx%d" % (ts["cols"], ts["rows"]),
                    "media/deadwire_01.tiles",
                    "declares %d tiles but the grid holds %d"
                    % (ts["tile_count"], expected))

    # Config.Sprites indexes into this sheet by hand, so the highest index it
    # names has to exist. Adding a PNG that sorts earlier renumbers everything
    # after it silently, which is the hazard recorded in context.md.
    highest = -1
    for path in lua_files():
        with open(path, encoding="utf-8", errors="replace") as fh:
            code = re.sub(r"--[^\n]*", "", fh.read())
        for idx in re.findall(r'"deadwire_01_(\d+)"', code):
            highest = max(highest, int(idx))
    total = sum(ts["tile_count"] for ts in tiles["tilesets"])
    if highest < total:
        rep.ok("tilesheet", "sprite indices")
    else:
        rep.bad("tilesheet", "deadwire_01_%d" % highest, "media/deadwire_01.tiles",
                "the sheet defines %d tiles, so index %d does not exist"
                % (total, highest))

    pack = os.path.join(MOD, "texturepacks", "deadwire_01.pack")
    if not os.path.exists(pack):
        rep.bad("tilesheet", "deadwire_01.pack", "media/texturepacks/",
                "declared in mod.info but not present")
        return
    rep.ok("tilesheet", "deadwire_01.pack")

    # The tile definitions name an image; the atlas has to be the page that
    # supplies it, or every tile resolves to nothing.
    try:
        pages = pack_page_names(pack)
    except (ValueError, OSError, struct.error) as exc:
        rep.bad("tilesheet", "deadwire_01.pack", "media/texturepacks/",
                "unparseable: %s" % exc)
        return
    wanted = tiles["tilesets"][0]["name"]
    if any(page == wanted or page == wanted + "0" for page in pages):
        rep.ok("tilesheet", "pack page")
    else:
        rep.bad("tilesheet", "pack page", "media/texturepacks/deadwire_01.pack",
                "tiles name %r but the atlas page is %r" % (wanted, pages))


# --------------------------------------------------------------- event names

def pz_event_names(jar):
    """Every event name the game's own event manager knows about.

    Deliberately a superset: this is the identifier-shaped part of
    zombie/Lua/LuaEventManager's constant pool with the JVM's own attribute
    names removed, so a handful of Java member names ("get", "size") come along
    too. That direction is safe. A subset would mean reporting real events as
    missing, and a checker that cries wolf stops being read; a superset can only
    fail to flag a typo that happens to collide with a Java identifier, and it
    still catches the case that actually bit us -- Events.OnPlayerConnect, a
    name that appears nowhere in the jar at all (#33).
    """
    k = jar.klass("zombie/Lua/LuaEventManager")
    pool = {v for v in k.pool if isinstance(v, str)}
    return {v for v in pool
            if re.fullmatch(r"[A-Za-z][A-Za-z0-9_]*", v)
            and v not in JVM_ATTRIBUTE_NAMES}


def check_events(rep, jar):
    """Events.X.Add(...) on a name the game does not have throws at load.

    It throws "attempt to index a nil value" the moment the file is read, in
    every run mode, and everything below that line in the file never registers.
    Nothing in the test suite caught it, because tests/stubs.lua invented any
    event name it was asked for -- 159 tests passed over a dead handler for a
    whole release.
    """
    known = pz_event_names(jar)
    for path in lua_files():
        with open(path, encoding="utf-8", errors="replace") as fh:
            code = re.sub(r"--[^\n]*", "", fh.read())
        for name in sorted(set(re.findall(r"\bEvents\.([A-Za-z_][A-Za-z0-9_]*)", code))):
            rep.check("event", name, known, rel(path))


EVENTS_CACHE = os.path.join(REPO, "tests", "pz_events.lua")


def write_events_cache(jar):
    names = sorted(pz_event_names(jar))
    lines = [
        "-- GENERATED by scripts/verify_names.py --update-events. Do not edit.",
        "--",
        "-- Every event name in zombie/Lua/LuaEventManager's constant pool.",
        "-- tests/stubs.lua reads this so an Events.X the game does not have",
        "-- fails the test suite instead of being invented on demand, which is",
        "-- how Events.OnPlayerConnect passed 159 tests (#33, #43).",
        "--",
        "-- verify_names.py fails if this file disagrees with the installed jar,",
        "-- so it cannot quietly go stale.",
        "return {",
    ]
    lines += ['    ["%s"] = true,' % n for n in names]
    lines.append("}")
    with open(EVENTS_CACHE, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(lines) + "\n")
    return len(names)


def check_events_cache(rep, jar):
    """The stub allow-list is a cache of the jar, and must still match it.

    The test suite has to run without the game installed, so the list is
    committed. A committed list is a remembered one, and this project's whole
    bug history is remembered values that stopped being true -- hence the gate.
    """
    if not os.path.exists(EVENTS_CACHE):
        rep.bad("event cache", "tests/pz_events.lua", "tests/",
                "missing -- run python scripts/verify_names.py --update-events")
        return
    with open(EVENTS_CACHE, encoding="utf-8") as fh:
        cached = set(re.findall(r'\["([^"]+)"\]\s*=\s*true', fh.read()))
    live = pz_event_names(jar)
    if cached == live:
        rep.ok("event cache", "tests/pz_events.lua")
        return
    missing = len(live - cached)
    extra = len(cached - live)
    rep.bad("event cache", "tests/pz_events.lua", "tests/",
            "out of date against the installed jar (%d new, %d gone) -- run "
            "python scripts/verify_names.py --update-events" % (missing, extra))


# --------------------------------------------------------------- sound names

def check_sounds(rep):
    """A sound name with no script block plays nothing, silently.

    PZ logs "no GameSound" only for some paths; a name that reaches
    PlayWorldSound with no matching `sound X {}` block simply makes no noise,
    which on an alarm mod is the entire feature failing with no symptom.
    """
    script = os.path.join(MOD, "scripts", "deadwire_sounds.txt")
    if not os.path.exists(script):
        rep.bad("sound", "deadwire_sounds.txt", "media/scripts/", "missing")
        return
    with open(script, encoding="utf-8", errors="replace") as fh:
        src = re.sub(r"//[^\n]*", "", fh.read())

    declared = set(re.findall(r"^\s*sound\s+([A-Za-z0-9_]+)", src, re.M))
    for block in declared:
        rep.ok("sound block", block)

    # Every clip has to point at a file that is actually shipped.
    for clip in set(re.findall(r"file\s*=\s*([^,\s]+)", src)):
        # Paths are relative to the mod's 42/ directory.
        disk = os.path.join(os.path.dirname(MOD), clip.replace("/", os.sep))
        if os.path.exists(disk):
            rep.ok("sound file", clip)
        else:
            rep.bad("sound file", clip, "media/scripts/deadwire_sounds.txt",
                    "declared in a clip but not on disk")

    used = set()
    for path in lua_files():
        with open(path, encoding="utf-8", errors="replace") as fh:
            code = re.sub(r"--[^\n]*", "", fh.read())
        used |= set(re.findall(r'PlayWorldSound\(\s*"([A-Za-z0-9_]+)"', code))
        if path.endswith("Config.lua"):
            block = re.search(r"DeadwireConfig\.Sounds\s*=\s*\{(.*?)\}", code, re.S)
            if block:
                used |= set(re.findall(r'"([A-Za-z0-9_]+)"', block.group(1)))

    for name in sorted(used):
        rep.check("sound", name, declared, "media/scripts/deadwire_sounds.txt")


# ---------------------------------------------------------------- Java calls

# Receiver variable -> the class it holds, for the colon-call check below. Only
# names whose type is unambiguous everywhere in this codebase are listed; any
# other receiver is skipped rather than guessed at. Method lookup walks the
# superclass chain, so IsoThumpable finds setAlphaAndTarget on IsoObject.
RECEIVER_TYPES = {
    "sq": "zombie/iso/IsoGridSquare",
    "psq": "zombie/iso/IsoGridSquare",
    "square": "zombie/iso/IsoGridSquare",
    "cell": "zombie/iso/IsoCell",
    "obj": "zombie/iso/objects/IsoThumpable",
    "isoObject": "zombie/iso/objects/IsoThumpable",
    "player": "zombie/characters/IsoPlayer",
    "character": "zombie/characters/IsoPlayer",
    "zombie": "zombie/characters/IsoZombie",
    "inv": "zombie/inventory/ItemContainer",
    "role": "zombie/characters/Role",
    "climate": "zombie/iso/weather/ClimateManager",
    "part": "zombie/characters/BodyDamage/BodyPart",
    "bodyDamage": "zombie/characters/BodyDamage/BodyDamage",
}

# Receivers that legitimately hold either a zombie or a player.
UNION_RECEIVERS = {
    "entity": ("zombie/characters/IsoZombie", "zombie/characters/IsoPlayer"),
}

# Global getters whose return type is fixed. BaseSoundManager is at
# zombie/BaseSoundManager, not zombie/audio/.
GLOBAL_GETTER_TYPES = {
    "getSoundManager": "zombie/BaseSoundManager",
    "getWorldSoundManager": "zombie/WorldSoundManager",
}


def _lua_arg_count(code, open_paren):
    """Arguments in the Lua call whose "(" is at open_paren, or None.

    Returns None when the call cannot be counted honestly: unbalanced, varargs,
    or running off the end. Reporting nothing beats reporting a guess.
    """
    depth = 0
    args = 0
    seen = False
    i = open_paren
    while i < len(code):
        c = code[i]
        if c in "\"'":
            quote = c
            i += 1
            while i < len(code) and code[i] != quote:
                i += 2 if code[i] == "\\" else 1
            seen = True
        elif c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
            if depth == 0:
                return args + 1 if seen else 0
        elif c == "," and depth == 1:
            args += 1
        elif c == "." and code[i:i + 3] == "...":
            return None
        elif not c.isspace():
            seen = True
        i += 1
    return None


def check_java_calls(rep, jar):
    """Does this method exist on that class, and does it take that many args?

    The bugs that have cost this project most were names that look right and do
    not exist: getRainStrength for getRainIntensity, Climate for
    getClimateManager(). Nothing errors; the feature just never happens. The
    receiver map above is small on purpose -- an unknown receiver is skipped.
    """
    tables = {}
    for name, path in list(RECEIVER_TYPES.items()) + list(GLOBAL_GETTER_TYPES.items()):
        if not jar.has_class(path):
            rep.bad("receiver class", path, "scripts/verify_names.py",
                    "not in this build -- the checks for '%s' would silently "
                    "pass on anything" % name)
            continue
        tables[name] = jar.methods_deep(path)
    for name, paths in UNION_RECEIVERS.items():
        merged = {}
        for path in paths:
            if not jar.has_class(path):
                rep.bad("receiver class", path, "scripts/verify_names.py",
                        "not in this build")
                continue
            for meth, arities in jar.methods_deep(path).items():
                merged.setdefault(meth, set()).update(arities)
        tables[name] = merged

    call_re = re.compile(r"\b([A-Za-z_][A-Za-z0-9_]*)\s*(\(\s*\))?\s*:\s*"
                         r"([A-Za-z_][A-Za-z0-9_]*)\s*\(")
    for path in lua_files():
        with open(path, encoding="utf-8", errors="replace") as fh:
            code = re.sub(r"--[^\n]*", "", fh.read())
        where = rel(path)
        for m in call_re.finditer(code):
            recv, called, method = m.group(1), m.group(2), m.group(3)
            if called and recv not in GLOBAL_GETTER_TYPES:
                continue                    # some other function's return value
            if not called and recv in GLOBAL_GETTER_TYPES:
                continue                    # not the getter, just a variable
            table = tables.get(recv)
            if table is None:
                continue                    # receiver type not established
            if method not in table:
                rep.bad("java method", "%s:%s" % (recv, method), where,
                        near(method, set(table)))
                continue
            n = _lua_arg_count(code, m.end() - 1)
            if n is None or n in table[method]:
                rep.ok("java method", method)
            else:
                rep.bad("java method", "%s:%s/%d" % (recv, method, n), where,
                        "no overload takes %d argument(s); valid: %s"
                        % (n, ", ".join(str(a) for a in sorted(table[method]))))


def _parse_modinfo(path):
    d = {}
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            if "=" in line and not line.strip().startswith("#"):
                k, v = line.split("=", 1)
                d[k.strip()] = v.strip()
    return d


def check_modinfo(rep, pz):
    """Both mod.info files must agree; B42 reads 42/ but the root one is required."""
    root = _parse_modinfo(os.path.join(REPO, "Contents", "mods", "Deadwire", "mod.info"))
    inner = _parse_modinfo(os.path.join(REPO, "Contents", "mods", "Deadwire", "42", "mod.info"))
    for key in ("name", "id", "modversion", "versionMin", "poster", "pack", "tiledef"):
        a, b = root.get(key), inner.get(key)
        if a == b:
            rep.ok("mod.info", key)
        else:
            rep.bad("mod.info", key, "Contents/mods/Deadwire/mod.info",
                    "root=%r vs 42/=%r" % (a, b))

    # A tiledef ID collision silently breaks every world sprite: the later
    # tilesheet wins and Deadwire's tiles resolve to someone else's art.
    tiledef = inner.get("tiledef", "")
    parts = tiledef.split()
    if len(parts) != 2 or not parts[1].isdigit():
        rep.bad("tiledef", tiledef or "(missing)", "42/mod.info",
                "expected '<name> <id>' with a numeric id")
        return
    ours = int(parts[1])
    if not 100 <= ours <= 8190:
        rep.bad("tiledef", str(ours), "42/mod.info", "id must be in 100-8190")
        return

    # Vanilla currently sits entirely below 100, so in practice the collision
    # that can actually happen is with another installed mod. Both are checked.
    taken = {}
    for tiles_txt in glob.glob(os.path.join(pz, "media", "*.tiles.txt")):
        with open(tiles_txt, encoding="utf-8", errors="replace") as fh:
            m = re.search(r"^\s*id\s*=\s*(\d+)", fh.read(), re.M)
        if m:
            taken.setdefault(int(m.group(1)), "vanilla " + os.path.basename(tiles_txt))

    for mod_info in glob.glob(os.path.join(MODS_DIR, "*", "mod.info")):
        other = _parse_modinfo(mod_info)
        if other.get("id") == "Deadwire":
            continue
        bits = other.get("tiledef", "").split()
        if len(bits) == 2 and bits[1].isdigit():
            taken.setdefault(int(bits[1]),
                             "mod " + (other.get("id") or os.path.basename(mod_info)))

    if ours in taken:
        rep.bad("tiledef", str(ours), "42/mod.info",
                "collides with %s -- every Deadwire world sprite would resolve "
                "to the other sheet's art" % taken[ours])
    else:
        rep.ok("tiledef", str(ours))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--pz", default=DEFAULT_PZ, help="Project Zomboid install dir")
    ap.add_argument("--update-events", action="store_true",
                    help="rewrite tests/pz_events.lua from the installed jar")
    args = ap.parse_args()

    jar_path = os.path.join(args.pz, "projectzomboid.jar")
    if not os.path.exists(jar_path):
        print("ERROR: no projectzomboid.jar at %s" % jar_path)
        print("Pass --pz <install dir>.")
        return 2

    jar = Jar(jar_path)

    if args.update_events:
        n = write_events_cache(jar)
        print("wrote tests/pz_events.lua: %d event names" % n)
        return 0

    items = vanilla_items(args.pz)
    dists = vanilla_distributions(args.pz)

    rep = Report()
    check_lua(rep, jar, items, dists)
    check_scripts(rep, jar, items)
    check_sandbox_options(rep)
    check_translation_filenames(rep, translator_base_names(jar))
    check_categories(rep, args.pz)
    check_config_sprites(rep)
    check_modinfo(rep, args.pz)
    check_events(rep, jar)
    check_events_cache(rep, jar)
    check_sounds(rep)
    check_java_calls(rep, jar)

    print("verify_names: %d references checked against %s"
          % (rep.checked, os.path.basename(args.pz)))
    print("  vanilla items: %d   distributions: %d" % (len(items), len(dists)))

    if not rep.problems:
        print("\nAll names resolve.")
        return 0

    print("\n%d UNRESOLVED:\n" % len(rep.problems))
    width = max(len(c) for c, _n, _w, _h in rep.problems)
    for category, name, where, hint in rep.problems:
        print("  %-*s  %-34s %s" % (width, category, name, where))
        if hint:
            print("  %-*s  %s" % (width, "", hint))
    return 1


if __name__ == "__main__":
    sys.exit(main())
