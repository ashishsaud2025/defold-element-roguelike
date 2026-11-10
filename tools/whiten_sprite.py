#!/usr/bin/env python3
"""Convert a Kenney Particle Pack sprite into a white-on-alpha FX sprite.

The source PNGs are white-ish art with varying brightness/alpha that becomes
invisible when tinted on a near-black floor. This whitens: RGB is forced to
255 and the brightness is encoded in alpha, so the sprite can be tinted at
runtime by any element colour.

    python tools/whiten_sprite.py SRC.png assets/art/fx/fx_name.png [--size 64]

Algorithm (per PROMPT_assets_player_enemies_spells.md 6.2):

    lum  = mean(R,G,B)/255
    eff  = lum * alpha/255
    eff  = max(eff, 0.35 * alpha/255)          # keep soft halos
    p    = 98th percentile of eff over pixels with eff > 0.02
    out  = clip(eff / p, 0, 1) ** 0.75
    result RGB = 255 (white), alpha = out * 255

The originals under the particle pack are never modified.
"""
import argparse
import os

from PIL import Image


def whiten(im, size):
    """Return a size x size white-on-alpha copy of the sprite."""
    im = im.convert("RGBA")
    if im.size != (size, size):
        im = im.resize((size, size), Image.LANCZOS)
    px = im.load()
    eff = []
    for y in range(size):
        for x in range(size):
            r, g, b, a = px[x, y]
            lum = (r + g + b) / (3 * 255)
            e = lum * a / 255
            e = max(e, 0.35 * a / 255)
            eff.append(e)
    above = sorted(e for e in eff if e > 0.02)
    if not above:
        p = 1.0
    else:
        idx = max(0, int(len(above) * 0.98) - 1)
        p = max(above[idx], 1e-6)
    out = Image.new("RGBA", (size, size), (255, 255, 255, 0))
    op = out.load()
    for y in range(size):
        for x in range(size):
            r, g, b, a = px[x, y]
            lum = (r + g + b) / (3 * 255)
            e = lum * a / 255
            e = max(e, 0.35 * a / 255)
            v = e / p
            v = min(1.0, max(0.0, v)) ** 0.75
            op[x, y] = (255, 255, 255, int(v * 255))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src", help="source sprite (never edited)")
    ap.add_argument("dst", help="output png (e.g. assets/art/fx/fx_flame.png)")
    ap.add_argument("--size", type=int, default=64)
    args = ap.parse_args()
    im = Image.open(args.src)
    out = whiten(im, args.size)
    os.makedirs(os.path.dirname(args.dst), exist_ok=True)
    out.save(args.dst)
    print("wrote", args.dst, out.size, out.mode)


if __name__ == "__main__":
    main()
