#!/usr/bin/env python3
"""Generate fx_drop.png, a white-on-alpha droplet silhouette (no external art).

The Kenney Particle Pack has no droplet/bubble shape, so this is original art.
One silhouette, one halo derived from it, so it reads as a clean droplet when
tinted water-blue on a near-black floor.

    python tools/make_drop.py [out.png] [--size 64]
"""
import argparse
import math
import os

from PIL import Image, ImageDraw, ImageFilter, ImageChops


def bezier(p0, p1, p2, steps):
    pts = []
    for i in range(steps + 1):
        t = i / steps
        x0 = (1 - t) * p0[0] + t * p1[0]
        y0 = (1 - t) * p0[1] + t * p1[1]
        x1 = (1 - t) * p1[0] + t * p2[0]
        y1 = (1 - t) * p1[1] + t * p2[1]
        pts.append(((1 - t) * x0 + t * x1, (1 - t) * y0 + t * y1))
    return pts


def make(size):
    S = 4
    W = size * S
    cx = W / 2
    body_y, body_r, apex_y = W * 0.68, W * 0.29, W * 0.10
    side_y = body_y - body_r * 0.30
    side_x = body_r * math.cos(math.radians(30))

    mask = Image.new("L", (W, W), 0)
    d = ImageDraw.Draw(mask)
    d.ellipse([cx - body_r, body_y - body_r, cx + body_r, body_y + body_r], fill=255)
    right = bezier((cx + side_x, side_y), (cx + body_r * 1.08, (side_y + apex_y) / 2 + W * 0.05), (cx, apex_y), 40)
    left = bezier((cx - side_x, side_y), (cx - body_r * 1.08, (side_y + apex_y) / 2 + W * 0.05), (cx, apex_y), 40)
    poly = ([(cx, apex_y)] + right[::-1] + [(cx + side_x * 0.55, side_y + W * 0.02),
           (cx - side_x * 0.55, side_y + W * 0.02)] + left[::-1])
    d.polygon(poly, fill=255)

    # halo derived from the silhouette (blur, keep ~35% of its strength)
    halo = mask.filter(ImageFilter.GaussianBlur(W * 0.07)).point(lambda v: int(v * 0.35))
    # inner shading: slightly darken the lower-right so the shape keeps volume
    shade = Image.new("L", (W, W), 0)
    sd = ImageDraw.Draw(shade)
    sd.ellipse([cx - body_r * 0.45, body_y - body_r * 0.25, cx + body_r * 0.85, body_y + body_r * 0.75], fill=90)
    shade = shade.filter(ImageFilter.GaussianBlur(W * 0.07))

    alpha = ImageChops.lighter(mask, halo)
    white = Image.new("RGBA", (W, W), (255, 255, 255, 255))
    dark = Image.new("RGBA", (W, W), (110, 110, 130, 255))
    rgb_image = Image.composite(dark, white, shade)
    out = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    out.paste(rgb_image, (0, 0), alpha)
    return out.resize((size, size), Image.LANCZOS)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out", nargs="?", default=os.path.join("assets", "art", "fx", "fx_drop.png"))
    ap.add_argument("--size", type=int, default=64)
    args = ap.parse_args()
    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    out = make(args.size)
    out.save(args.out)
    print("wrote", args.out, out.size, out.mode)


if __name__ == "__main__":
    main()
