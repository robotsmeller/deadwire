"""Turn a Gemini trip-line render into a Deadwire 64x128 world sprite.

Keying is by HUE, not by value: anything where red and blue both sit well above
green is the magenta family. That takes the #FF00FF background and the
semi-transparent white sparkle watermark in one pass, since the watermark is
just a lightened version of the same background. Rust (#8A5A32) has a big
red-green gap but almost no blue, and the grey tones have no gap at all, so
neither is touched.

Target geometry comes from the sprites already in the mod: content spans the
full 64px width and its bottom sits at y=96, which is the low end of the tile's
2:1 ground edge running (0,64) -> (63,96).

Usage:
    python tools/process_sprite_render.py <render.png> <outdir> <kind>

Produces deadwire_<kind>_e.png and deadwire_<kind>_n.png. North is the mirror
of east: in PZ's projection both facings are diagonal and mirrored, and there
is no flat-horizontal orientation. The Session 10 placeholders drew north flat,
which is why they read as wrong in-world rather than merely crude.

Then rebuild the pack (see docs, Part C) and re-run tools/validate_pack.py.

WARNING: pz_tilesheet.py globs media/textures/deadwire_*.png in ALPHABETICAL
order, so a new sprite whose name sorts before an existing one silently
renumbers every index after it. DeadwireConfig.Sprites holds those indices by
hand. Adding "electric" in Session 18 pushed reinforced/tanglefoot/tincan from
2,4,6 to 4,6,8.

--------------------------------------------------------------------------
The Gemini prompt that produced the current art, kept because getting the
isometric angle right took several tries and the working phrasing is not
obvious. Attach a vanilla PZ fence sprite as a style reference (extract one
with pz_unpack.py from the game's Tiles1x.pack).

  Pixel art sprite for the game Project Zomboid, matching the attached
  reference for palette and perspective.

  Subject: <see per-type line below>

  GEOMETRY, follow exactly: the line runs corner to corner across the image on
  a 2:1 isometric diagonal, starting at the upper left and descending to the
  lower right, dropping exactly half as much vertically as it travels
  horizontally. A stake stands at each end. Nothing is horizontal and nothing
  is at 45 degrees.

  RENDERING: true chunky pixel art on a coarse grid, about 64 pixels wide of
  actual detail, every pixel a large flat square block of solid colour. No
  anti-aliasing, no gradients, no dithering, no blur, no glow. Twelve colours
  maximum. Every object carries a one-block near-black outline. If a detail
  cannot survive being one or two blocks wide, leave it out.

  PALETTE: timber #3A2E1F #6B5334 #8F7146, wire #6E6E63 #A7A792, rust #5A3A20
  #8A5A32, outline #14140F. Nothing brighter than #C0C0B1. (Sampled from the
  game's own fencing_01 sprites -- vanilla's white picket fence is #A7A792,
  NOT #FFFFFF, which is why the Session 10 near-white strand glared.)

  Solid pure magenta #FF00FF background. No shadow, no ground, no grass, no
  text, no border.

Per type, and the failure each phrasing was written to prevent:
  tincan     ...a trip line of thin wire with three small dented tin cans
             hanging from it, each can about six blocks tall.
  bell       ...a trip line of thin wire with one small brass bell hanging at
             its midpoint, the bell about eight blocks tall.
  reinforced ...a single heavy doubled strand of thick barbed wire strung tight
             between two stakes, the two wires running close together and
             twisting around each other along their length. No ladder rungs. No
             evenly spaced perpendicular crosspieces.
             (Without those bans it returns a ladder. Every time.)
  tanglefoot ...three or four loose strands of rusted barbed wire sagging and
             crossing in a loose snarl, strung low between short stakes barely
             taller than the wire. Keep it sparse and open with plenty of empty
             space, not a dense mass.
             (Without "sparse" it returns an unreadable blob.)
  electric   ...a single taut steel wire between two stakes, each stake capped
             with a small off-white porcelain insulator the wire threads
             through, and a small metal warning tag hanging from the middle. No
             sparks, no lightning bolts, no glow.

OUTSTANDING (issue #26): tincan, bell and reinforced have stakes 22, 30 and
32px above the ground line. tanglefoot (6px) and electric (8px) are correct and
are the ones that look right in-game; the other three read as fences rather
than trip lines. Regenerate those three with the tanglefoot render attached as
a height reference plus:

  The stakes are very short, driven low into the ground, rising only about as
  high above the wire as the stakes in the second attached image. Ankle height
  on a person. These are trip line stakes, not fence posts.
"""
import os
import sys

from PIL import Image, ImageOps

W, H = 64, 128
CONTENT_BOTTOM = 96


def is_magenta(r, g, b):
    """Magenta family at ANY brightness.

    The first pass used r > 140, which passed the flat background but missed
    the blend pixels between the background and each object's near-black
    outline -- those land near (128, 20, 128) and survived as a purple fringe
    around every post and can. The hue gap is what identifies the background;
    brightness is not. Rust (138,90,50) has the red gap but no blue, timber
    (107,83,52) has neither, so nothing in the artwork matches.
    """
    return r > 55 and b > 55 and (r - g) > 30 and (b - g) > 30


def key_magenta(im):
    im = im.convert("RGBA")
    px = im.load()
    w, h = im.size
    for y in range(h):
        for x in range(w):
            r, g, b, _ = px[x, y]
            if is_magenta(r, g, b):
                px[x, y] = (0, 0, 0, 0)

    # Erode the alpha by two source pixels. The blend ring is a couple of
    # pixels wide at 1024; at the 16:1 downscale that is an eighth of a final
    # pixel of real artwork lost, against a fringe that is plainly visible.
    a = im.getchannel("A")
    ap = a.load()
    keep = Image.new("L", im.size, 0)
    kp = keep.load()
    for y in range(h):
        for x in range(w):
            if ap[x, y] == 0:
                continue
            solid = True
            for dy in (-2, -1, 0, 1, 2):
                for dx in (-2, -1, 0, 1, 2):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < w and 0 <= ny < h and ap[nx, ny] == 0:
                        solid = False
                        break
                if not solid:
                    break
            kp[x, y] = 255 if solid else 0
    im.putalpha(keep)
    return im


def despill(im):
    """Kill any magenta fringe left on surviving edge pixels."""
    px = im.load()
    w, h = im.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            if (r - g) > 18 and (b - g) > 18:
                px[x, y] = (g, g, g, a)      # collapse the tint to neutral
    return im


def to_sprite(im, width=W):
    im = im.crop(im.getchannel("A").getbbox())
    ratio = width / im.size[0]
    new_h = max(1, round(im.size[1] * ratio))

    r, g, b, a = im.split()
    prem = Image.composite(Image.merge("RGB", (r, g, b)),
                           Image.new("RGB", im.size, (0, 0, 0)), a)
    prem = prem.resize((width, new_h), Image.BOX)
    a_s = a.resize((width, new_h), Image.BOX)

    small = Image.new("RGBA", (width, new_h))
    sp, ap, dp = prem.load(), a_s.load(), small.load()
    for y in range(new_h):
        for x in range(width):
            av = ap[x, y]
            if av < 24:                      # drop near-transparent lint
                dp[x, y] = (0, 0, 0, 0)
                continue
            pr, pg, pb = sp[x, y]
            s = 255.0 / av
            dp[x, y] = (min(255, int(pr * s)), min(255, int(pg * s)),
                        min(255, int(pb * s)), 255)

    canvas = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    canvas.alpha_composite(small, (0, CONTENT_BOTTOM - new_h))
    return canvas


def main():
    src, outdir, name = sys.argv[1], sys.argv[2], sys.argv[3]
    os.makedirs(outdir, exist_ok=True)

    im = Image.open(src)
    im = despill(key_magenta(im))
    east = to_sprite(im)
    east.save(os.path.join(outdir, "deadwire_%s_e.png" % name))
    ImageOps.mirror(east).save(os.path.join(outdir, "deadwire_%s_n.png" % name))

    bb = east.getchannel("A").getbbox()
    vals = list(east.getchannel("A").getdata())
    print("%s  bbox=%s  clear=%.0f%%"
          % (name, bb, 100 * sum(1 for v in vals if v == 0) / len(vals)))


if __name__ == "__main__":
    main()
