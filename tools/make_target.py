#!/usr/bin/env python3
"""Generate the 16x16 training-dummy bullseye sprite (original art, no external assets).

Reads as an archery target on a dark floor: white/red concentric rings.
Used for the "dummy" enemy type (a practice target that never attacks and never dies).

    python tools/make_target.py [out.png]
"""
import argparse
import os

from PIL import Image, ImageDraw

PX = 16
C = 7.5                     # centre (pixel units, 0..15)


def circle(d, r, outline, fill=None):
    d.ellipse([C - r, C - r, C + r, C + r], outline=outline, fill=fill)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out", nargs="?", default=os.path.join("assets", "art", "actors", "target_dummy.png"))
    args = ap.parse_args()
    im = Image.new("RGBA", (PX, PX), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)

    # Outer dark rim, then white/red/white/red bullseye (16px is tiny: go simple)
    circle(d, 7, (24, 20, 24, 255), fill=(24, 20, 24, 255))
    circle(d, 6, (228, 226, 228, 255), fill=(228, 226, 228, 255))
    circle(d, 4, (196, 56, 44, 255), fill=(196, 56, 44, 255))
    circle(d, 2, (228, 226, 228, 255), fill=(228, 226, 228, 255))
    circle(d, 1, (196, 56, 44, 255), fill=(196, 56, 44, 255))

    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    im.save(args.out)
    print("wrote", args.out, im.size, im.mode)


if __name__ == "__main__":
    main()
