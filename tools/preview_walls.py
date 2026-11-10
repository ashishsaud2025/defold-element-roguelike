#!/usr/bin/env python3
"""Compare tile mappings for obstacle readability (mock, not the Defold renderer).

Renders one real room (default: room 5, Slime Pits) at the game's 48 px cell size
for several candidate tile mappings, using the same tint maths as
apply_palette() in main/game.script, and writes a 2x2 comparison sheet.

    python tools/preview_walls.py [room_index] [out.png]
"""
import os
import re
import sys

from PIL import Image, ImageDraw, ImageFont, ImageOps

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TILES = os.path.join(ROOT, "assets", "art", "env")
RAW_TILES = os.path.join(os.path.dirname(ROOT), "defold_downloads", "tiny-dungeon", "Tiles")
ACTORS = os.path.join(ROOT, "assets", "art", "actors")
TS = 48
COLS, ROWS = 20, 13
SOLID = set("#OT")
ENEMY_ART = {"w": "tc_wisp", "s": "tc_slinger", "c": "tc_charger",
             "b": "tc_brute", "p": "tc_splitter", "W": "tc_wisp",
             "S": "tc_slinger", "C": "tc_charger", "B": "tc_brute",
             "Q": "tc_splitter", "X": "tc_boss"}
ENEMY_SCALE = {"tc_wisp": 2, "tc_slinger": 2, "tc_charger": 2,
               "tc_brute": 3, "tc_splitter": 2, "tc_boss": 5}
PALETTES = [
    ((0.30, 0.26, 0.50), (0.60, 0.45, 1.00)),
    ((0.20, 0.36, 0.42), (0.30, 0.90, 0.95)),
    ((0.44, 0.22, 0.26), (1.00, 0.40, 0.35)),
    ((0.24, 0.40, 0.26), (0.50, 1.00, 0.50)),
    ((0.24, 0.30, 0.50), (0.45, 0.65, 1.00)),
    ((0.46, 0.34, 0.20), (1.00, 0.75, 0.30)),
    ((0.44, 0.22, 0.44), (1.00, 0.45, 0.95)),
    ((0.30, 0.34, 0.40), (0.75, 0.90, 1.00)),
    ((0.30, 0.12, 0.16), (1.00, 0.25, 0.30)),
]


def load_room(path, index):
    src = open(path, encoding="utf-8").read()
    rooms = [(m.group(1), re.findall(r'"([^"]*)"', m.group(2)))
             for m in re.finditer(r'name\s*=\s*"([^"]+)",\s*rows\s*=\s*\{(.*?)\}', src, re.S)]
    return rooms[max(0, min(index - 1, len(rooms) - 1))]


def tile(index):
    im = Image.open(os.path.join(RAW_TILES, "tile_%04d.png" % index)).convert("RGBA")
    return im.resize((TS, TS), Image.NEAREST)


def mul(im, rgb, alpha=1.0):
    """Multiply RGB by rgb (Defold sprite tint), keep/scale alpha."""
    px = im.load()
    out = Image.new("RGBA", im.size)
    op = out.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            op[x, y] = (min(255, int(r * rgb[0])), min(255, int(g * rgb[1])),
                        min(255, int(b * rgb[2])), int(a * alpha))
    return out


def grey(im):
    """Brightness-preserving desaturate (keeps shading, drops the warm hue)."""
    g = ImageOps.grayscale(im)
    out = Image.new("RGBA", im.size)
    out.paste(g.convert("RGBA"))
    return out


def make_tiles(spec, palette):
    """Resolve a mapping spec into ready tinted 48 px tiles."""
    def resolve(key):
        idx = spec[key]
        if isinstance(idx, tuple):
            idx = idx[0]
        return load_image("tile_%04d" % idx)

    def load_image(name):
        im = Image.open(os.path.join(RAW_TILES, name + ".png")).convert("RGBA")
        return im.resize((TS, TS), Image.NEAREST)

    out = {}
    f = palette
    if spec.get("desaturate_floor"):
        floor = grey(resolve("floor"))
        out["floor_a"] = mul(floor, tuple(c * spec["floor_m"] * 1.55 for c in f))
        out["floor_b"] = mul(floor, tuple(c * spec["floor_m"] * 1.35 for c in f))
    elif spec.get("floor_tint") == "palette":
        floor = resolve("floor")
        out["floor_a"] = mul(floor, tuple(c * spec["floor_m"] for c in f))
        out["floor_b"] = mul(floor, tuple(c * spec["floor_m"] * 0.88 for c in f))
    else:
        floor = resolve("floor")
        out["floor_a"] = mul(floor, spec.get("floor_mul", (1, 1, 1)))
        out["floor_b"] = mul(floor, tuple(c * 0.9 for c in spec.get("floor_mul", (1, 1, 1))))

    face = resolve("face")
    top = resolve("top")
    if spec.get("wall_tint") == "palette":
        out["face"] = mul(face, tuple(c * spec["face_m"] for c in f))
        out["top"] = mul(top, tuple(c * spec["top_m"] for c in f))
    else:
        out["face"] = mul(face, spec.get("face_mul", (1, 1, 1)))
        out["top"] = mul(top, spec.get("top_mul", (1, 1, 1)))
    out["pillar"] = mul(resolve("pillar"), spec.get("pillar_mul", (1, 1, 1)))
    return out


def render(name, rows, spec, palette, accent):
    idx = spec["floor"][1] if isinstance(spec["floor"], tuple) else spec["floor"]
    spec = dict(spec)
    spec["floor"] = spec["floor"][1] if isinstance(spec["floor"], tuple) else spec["floor"]
    tiles = make_tiles(spec, palette)
    W, H = COLS * TS, ROWS * TS
    canvas = Image.new("RGBA", (W, H), (10, 10, 16, 255))

    def solid(r, c):
        return 0 <= r < ROWS and 0 <= c < COLS and rows[r][c] in SOLID

    for r in range(ROWS):
        for c in range(COLS):
            x, y = c * TS, r * TS
            ch = rows[r][c]
            if ch in SOLID:
                floor_below = not solid(r + 1, c)
                canvas.paste(tiles["face"] if floor_below else tiles["top"], (x, y), tiles["face"] if floor_below else tiles["top"])
                if floor_below and spec.get("accent", True):
                    line = Image.new("RGBA", (TS, 2), (int(accent[0] * 255), int(accent[1] * 255), int(accent[2] * 255), 128))
                    canvas.alpha_composite(line, (x, y + TS - 3))
            else:
                canvas.paste(tiles["floor_b"] if (c * 5 + r * 3) % 7 == 0 else tiles["floor_a"], (x, y))

    # actors + torches on top (game z-order)
    for r in range(ROWS):
        for c in range(COLS):
            ch = rows[r][c]
            x, y = c * TS, r * TS
            if ch == "T":
                t = Image.open(os.path.join(RAW_TILES, "tile_0029.png")).convert("RGBA").resize((TS, TS), Image.NEAREST)
                canvas.alpha_composite(t, (x, y - 2))
            elif ch == "O":
                canvas.alpha_composite(tiles["pillar"], (x, y))
            elif ch == "@":
                a = Image.open(os.path.join(ACTORS, "td_player.png")).convert("RGBA")
                a = a.resize((a.width * 3, a.height * 3), Image.NEAREST)
                canvas.alpha_composite(a, (x - 8, y - 8))
            elif ch in ENEMY_ART:
                art = ENEMY_ART[ch]
                s = ENEMY_SCALE[art]
                a = Image.open(os.path.join(ACTORS, art + ".png")).convert("RGBA")
                a = a.resize((a.width * s, a.height * s), Image.NEAREST)
                canvas.alpha_composite(a, (x + TS // 2 - a.width // 2, y + TS // 2 - a.height // 2))

    draw = ImageDraw.Draw(canvas)
    try:
        font = ImageFont.truetype("arial.ttf", 22)
    except Exception:
        font = ImageFont.load_default()
    label = name
    draw.rectangle((0, 0, 8 * len(label) + 16, 30), fill=(0, 0, 0, 170))
    draw.text((8, 4), label, fill=(240, 240, 250), font=font)
    return canvas


def main():
    room_index = int(sys.argv[1]) if len(sys.argv) > 1 else 5
    out_path = sys.argv[2] if len(sys.argv) > 2 else os.path.join(
        os.environ.get("TEMP", "."), "wall_compare.png")
    name, rows = load_room(os.path.join(ROOT, "src", "levels", "rooms.lua"), room_index)
    palette, accent = PALETTES[room_index - 1]

    variants = [
        ("A  current: wall planks as floor", dict(
            floor=(36, 38), face=40, top=14, pillar=39,
            floor_tint="palette", floor_m=0.90, face_m=0.75, top_m=0.50, pillar_m=1.0, wall_tint="palette")),
        ("B  real roles, warm floor", dict(
            floor=(48, 49), face=40, top=37, pillar=57,
            floor_mul=(1.0, 1.0, 1.0), face_mul=(0.82, 0.86, 0.95), top_mul=(0.78, 0.82, 0.92),
            pillar_mul=(0.95, 0.97, 1.05))),
        ("C  real roles, darker walls", dict(
            floor=(48, 49), face=40, top=37, pillar=57,
            floor_mul=(1.05, 1.02, 1.0), face_mul=(0.62, 0.66, 0.76), top_mul=(0.55, 0.59, 0.70),
            pillar_mul=(1.0, 0.98, 1.0))),
        ("D  real roles, palette-tinted floor", dict(
            floor=(48, 49), face=40, top=37, pillar=57, desaturate_floor=True,
            floor_m=1.0, face_m=0.70, top_m=0.55, pillar_m=1.0, wall_tint="palette")),
    ]

    images = [render(n, rows, s, palette, accent) for n, s in variants]
    w, h = images[0].size
    sheet = Image.new("RGBA", (w * 2 + 12, h * 2 + 12), (8, 8, 12, 255))
    for i, im in enumerate(images):
        sheet.paste(im, ((i % 2) * (w + 12), (i // 2) * (h + 12)))
    sheet.save(out_path)
    print("room %d (%s) -> %s  (%dx%d)" % (room_index, name, out_path, sheet.width, sheet.height))


if __name__ == "__main__":
    main()
