"""Mock preview of the chosen art on the real dark floor (not the Defold renderer).

Composites tinted floor/wall tiles and the actor sprites the way main/game.script
does (tint = palette * KIND_TINT multiplier), so the art can be judged for
visibility before the human runs the game.

Usage: python tools/preview_art.py [out.png]
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ART = os.path.join(ROOT, "assets", "art")


def load(rel):
    return Image.open(os.path.join(ART, rel)).convert("RGBA")


def tint(im, rgb):
    """Multiply RGB by (r,g,b), keep alpha (same as go.set tint)."""
    px = im.load()
    out = im.copy()
    op = out.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            op[x, y] = (int(r * rgb[0]), int(g * rgb[1]), int(b * rgb[2]), a)
    return out


def main():
    out_path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "docs", "art_preview.png")
    W, H, TS = 960, 640, 48
    bg = (12, 12, 18, 255)
    canvas = Image.new("RGBA", (W, H), bg)

    floor_a = load("env/td_floor_a.png").resize((TS, TS), Image.NEAREST)
    floor_b = load("env/td_floor_b.png").resize((TS, TS), Image.NEAREST)
    wall_top = load("env/td_wall_top.png").resize((TS, TS), Image.NEAREST)
    wall_face = load("env/td_wall_face.png").resize((TS, TS), Image.NEAREST)
    pillar = load("env/td_pillar.png").resize((TS, TS), Image.NEAREST)
    torch = load("env/td_torch.png").resize((TS, TS), Image.NEAREST)

    palette = (0.30, 0.26, 0.50)          # room 1
    floor_mult = 0.90
    wall_mult = 0.75
    wall_top_mult = 0.50
    pillar_mult = 1.00

    ftint = tuple(c * floor_mult for c in palette)
    wtint = tuple(c * wall_mult for c in palette)
    wttint = tuple(c * wall_top_mult for c in palette)
    ptint = tuple(c * pillar_mult for c in palette)

    fa = tint(floor_a, ftint)
    fb = tint(floor_b, ftint)
    wt = tint(wall_top, wttint)
    wf = tint(wall_face, wtint)
    pl = tint(pillar, ptint)

    cols, rows = W // TS, H // TS
    for r in range(rows):
        for c in range(cols):
            tile = wf if r == 0 else wt
            if 0 < r and r < rows - 1 and 0 < c < cols - 1:
                tile = fb if (c * 5 + r * 3) % 7 == 0 else fa
            canvas.paste(tile, (c * TS, r * TS), tile)
    canvas.paste(torch, (6 * TS, 0), torch)
    canvas.paste(pl, (4 * TS, 4 * TS), pl)

    actors = [
        ("actors/td_player.png", 3, (6 * TS, 8 * TS)),
        ("actors/tc_wisp.png", 2, (2 * TS, 6 * TS)),
        ("actors/tc_slinger.png", 2, (10 * TS, 6 * TS)),
        ("actors/tc_charger.png", 2, (13 * TS, 8 * TS)),
        ("actors/tc_brute.png", 3, (16 * TS, 9 * TS)),
        ("actors/tc_splitter.png", 2, (8 * TS, 10 * TS)),
        ("actors/tc_boss.png", 5, (13 * TS, 2 * TS)),
    ]
    for rel, scale, (x, y) in actors:
        im = load(rel)
        im = im.resize((im.width * scale, im.height * scale), Image.NEAREST)
        canvas.paste(im, (x, y), im)

    draw = ImageDraw.Draw(canvas)
    try:
        font = ImageFont.truetype("arial.ttf", 14)
    except Exception:
        font = ImageFont.load_default()
    draw.text((8, H - 22), "mock preview: tinted Tiny Dungeon tiles + actor sprites", fill=(180, 180, 200), font=font)

    # measure visibility: mean luminance of some floor samples
    floor_px = tint(floor_a, ftint).convert("RGB")
    vals = list(floor_px.getdata())
    mean = sum(sum(p) / 3 for p in vals) / len(vals)
    print("floor mean luminance after tint: %.1f / 255" % mean)

    canvas.save(out_path)
    print("wrote", out_path)


if __name__ == "__main__":
    main()
