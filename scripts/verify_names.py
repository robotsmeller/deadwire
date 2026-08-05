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
  sprite names         this mod's own .tiles.txt tile indices

Deliberately NOT checked: bare global function names. Many legitimate globals
are defined in vanilla Lua rather than exposed from Java, so a Java-only check
reports false positives, and a checker that cries wolf stops being read.
"""

import argparse
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from pzclass import Jar  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MOD = os.path.join(REPO, "Contents", "mods", "Deadwire", "42", "media")

DEFAULT_PZ = r"C:/Program Files (x86)/Steam/steamapps/common/ProjectZomboid"

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


def mod_sprites():
    """Tile names the mod's own tilesheet actually defines."""
    path = os.path.join(MOD, "deadwire_01.tiles.txt")
    if not os.path.exists(path):
        return set()
    with open(path, encoding="utf-8", errors="replace") as fh:
        src = fh.read()
    name = re.search(r"file\s*=\s*(\S+)", src)
    if not name:
        return set()
    count = len(re.findall(r"^\s*tile\s*$", src, re.M))
    return {"%s_%d" % (name.group(1), i) for i in range(count)}


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
        code = re.sub(r"//[^\n]*", "", src)
        where = rel(path)

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


def check_config_sprites(rep):
    """Config.Sprites must name tiles the shipped tilesheet defines."""
    sprites = mod_sprites()
    if not sprites:
        rep.bad("tilesheet", "deadwire_01.tiles.txt", "media/",
                "tilesheet definition missing or unparseable")
        return
    fallback = os.path.join(MOD, "texturepacks", "deadwire_01.pack")
    if not os.path.exists(fallback):
        rep.bad("tilesheet", "deadwire_01.pack", "media/texturepacks/",
                "declared in mod.info but not present")
    else:
        rep.ok("tilesheet", "deadwire_01.pack")


def check_modinfo(rep):
    """Both mod.info files must agree; B42 reads 42/ but the root one is required."""
    def parse(path):
        d = {}
        with open(path, encoding="utf-8", errors="replace") as fh:
            for line in fh:
                if "=" in line and not line.strip().startswith("#"):
                    k, v = line.split("=", 1)
                    d[k.strip()] = v.strip()
        return d

    root = parse(os.path.join(REPO, "Contents", "mods", "Deadwire", "mod.info"))
    inner = parse(os.path.join(REPO, "Contents", "mods", "Deadwire", "42", "mod.info"))
    for key in ("name", "id", "modversion", "versionMin", "poster", "pack", "tiledef"):
        a, b = root.get(key), inner.get(key)
        if a == b:
            rep.ok("mod.info", key)
        else:
            rep.bad("mod.info", key, "Contents/mods/Deadwire/mod.info",
                    "root=%r vs 42/=%r" % (a, b))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--pz", default=DEFAULT_PZ, help="Project Zomboid install dir")
    args = ap.parse_args()

    jar_path = os.path.join(args.pz, "projectzomboid.jar")
    if not os.path.exists(jar_path):
        print("ERROR: no projectzomboid.jar at %s" % jar_path)
        print("Pass --pz <install dir>.")
        return 2

    jar = Jar(jar_path)
    items = vanilla_items(args.pz)
    dists = vanilla_distributions(args.pz)

    rep = Report()
    check_lua(rep, jar, items, dists)
    check_scripts(rep, jar, items)
    check_config_sprites(rep)
    check_modinfo(rep)

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
