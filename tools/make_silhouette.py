#!/usr/bin/env python3
"""Turn elemental FX sprites into white-on-transparent HUD silhouettes.

The HUD tints the icons with the element colour, so they must be white.
Any coloured sprite works as input; it is reduced to its alpha shape and
re-filled white, with the darkest interior pixels dropped to ~76% brightness
so the silhouette keeps a 1-2 px inner shading and stays readable.

    python tools/make_silhouette.py assets/art/fx/fx_flame.png assets/art/icons/icon_fire.png
    python tools/make_silhouette.py --batch            # the four element icons
"""
import argparse
import os

from PIL import Image

SIZE = 64
BATCH = [
    ("fx_flame", "icon_fire"),
    ("fx_drop", "icon_water"),
    ("fx_streak", "icon_wind"),
    ("fx_debris", "icon_earth"),
]
FX = os.path.join("assets", "art", "fx")
ICONS = os.path.join("assets", "art", "icons")


def silhouette(src, dst, size=SIZE):
    im = Image.open(src).convert("RGBA")
    if im.size != (size, size):
        # nearest-neighbour when upscaling, LANCZOS when shrinking
        resample = Image.NEAREST if im.width < size else Image.LANCZOS
        im = im.resize((size, size), resample)
    px = im.load()
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    op = out.load()
    for y in range(size):
        for x in range(size):
            r, g, b, a = px[x, y]
            if a <= 5:
                continue
            lum = (r + g + b) / (3 * 255)
            # darkest interior pixels keep some shading; the rest go pure white
            bright = 0.76 + 0.24 * min(1.0, lum * (a / 255) * 1.15)
            v = min(255, int(255 * bright))
            op[x, y] = (v, v, v, a)
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    out.save(dst)
    print("wrote", dst, out.size, out.mode)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src", nargs="?")
    ap.add_argument("dst", nargs="?")
    ap.add_argument("--batch", action="store_true", help="rebuild the four element icons from assets/art/fx/")
    args = ap.parse_args()
    if args.batch:
        for fx, icon in BATCH:
            silhouette(os.path.join(FX, fx + ".png"), os.path.join(ICONS, icon + ".png"))
        return 0
    if not args.src or not args.dst:
        ap.print_help()
        return 1
    silhouette(args.src, args.dst)
    return 0


if __name__ == "__main__":
    main()
