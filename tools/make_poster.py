"""Build the Workshop poster and preview image.

Deliberately plain and generated rather than drawn. mod.info has pointed at
42/poster.png since the mod was created and that file has never existed, so
the Workshop listing and the in-game mod list have both had a blank where the
thumbnail goes. A generated placeholder is a thing Rob can replace at his
leisure; a missing file is a thing that has to be noticed again.

Run:  python tools/make_poster.py
"""

import os
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MOD = os.path.join(ROOT, "Contents", "mods", "Deadwire")
TEXTURES = os.path.join(MOD, "42", "media", "textures")

BG = (18, 20, 18)
WIRE = (198, 182, 120)
TEXT = (228, 224, 210)
DIM = (128, 130, 122)


def _font(size):
    # No font file is shipped with the repo, so fall back to the bitmap default
    # rather than depending on a path that exists on this machine only.
    for name in ("segoeui.ttf", "arial.ttf", "DejaVuSans.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    return ImageFont.load_default()


def _centre(draw, text, font, y, width, fill):
    left, top, right, bottom = draw.textbbox((0, 0), text, font=font)
    draw.text(((width - (right - left)) / 2 - left, y), text, font=font, fill=fill)
    return bottom - top


def build(width, height, path, title_size, sub_size):
    img = Image.new("RGB", (width, height), BG)
    draw = ImageDraw.Draw(img)

    # A taut wire across the middle with the sag a real trip line has, and the
    # four sprites hung off it. Uses the mod's own art so the poster changes
    # when the art does.
    mid = height * 0.56
    sag = height * 0.035
    points = []
    for i in range(width + 1):
        t = i / width
        points.append((i, mid + sag * (1 - (2 * t - 1) ** 2)))
    draw.line(points, fill=WIRE, width=max(1, height // 180))

    names = ["deadwire_tincan_n", "deadwire_bell_n",
             "deadwire_reinforced_n", "deadwire_electric_n"]
    scale = height / 320.0
    for i, name in enumerate(names):
        src = os.path.join(TEXTURES, name + ".png")
        if not os.path.exists(src):
            continue
        sprite = Image.open(src).convert("RGBA")
        w = int(sprite.width * scale)
        h = int(sprite.height * scale)
        sprite = sprite.resize((w, h), Image.NEAREST)
        x = int(width * (i + 0.5) / len(names) - w / 2)
        # The art's own wire sits on the tile ground diamond at y=110 of the
        # 128px cell (measured against Tiles1x.floor.pack in Session 26), so
        # that fraction of the sprite's height is what has to land on the
        # curve. Hanging it off the top of the cell instead left every sprite
        # floating above the line, which is the same mistake the sprites
        # themselves used to make in game.
        baseline = h * (110.0 / 128.0)
        curve_y = mid + sag * (1 - (2 * (x + w / 2) / width - 1) ** 2)
        y = int(curve_y - baseline)
        img.paste(sprite, (x, y), sprite)

    _centre(draw, "DEADWIRE", _font(title_size), height * 0.12, width, TEXT)
    _centre(draw, "perimeter trip lines & electric fencing",
            _font(sub_size), height * 0.12 + title_size * 1.25, width, DIM)
    _centre(draw, "Project Zomboid B42", _font(sub_size), height * 0.86, width, DIM)

    img.save(path)
    print("wrote", path, img.size)


if __name__ == "__main__":
    build(256, 256, os.path.join(MOD, "42", "poster.png"), 34, 13)
    build(512, 512, os.path.join(ROOT, "preview.png"), 68, 26)
