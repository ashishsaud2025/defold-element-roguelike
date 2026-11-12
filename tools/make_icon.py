#!/usr/bin/env python3
"""Compose the original flat-style app icon for Element Roguelike and derive
per-platform sizes (Windows .ico, Android PNGs 36..192, HTML5 splash).
Flat polygon art: no licensed third-party artwork is used.

Usage: python tools/make_icon.py
Output: assets/icons/app_master.png (1024) + derived sizes in the same folder.
"""
import math
import os
from PIL import Image, ImageDraw

S = 1024
BG_TOP = (16, 14, 28)      # deep indigo
BG_BOT = (28, 24, 46)
POT = (26, 28, 40)
POT_RIM_T = (58, 61, 86)   # rim top face
POT_RIM_B = (35, 37, 53)   # rim body
POT_DARK = (13, 15, 24)    # opening
LIQ = (56, 230, 186)       # liquid glow (teal)
LIQ_HI = (159, 245, 221)
LIQ_LO = (34, 150, 128)
SPARK = (190, 255, 230)
ELEMENTS = [(255, 96, 32), (46, 165, 255), (205, 240, 228), (201, 138, 63)]  # fire water wind earth
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "icons")
os.makedirs(OUT, exist_ok=True)


def base():
    img = Image.new("RGB", (S, S), BG_BOT)
    d = ImageDraw.Draw(img)
    # vertical gradient
    for y in range(S):
        t = y / S
        r = int(BG_TOP[0] + (BG_BOT[0] - BG_TOP[0]) * t)
        g = int(BG_TOP[1] + (BG_BOT[1] - BG_TOP[1]) * t)
        b = int(BG_TOP[2] + (BG_BOT[2] - BG_TOP[2]) * t)
        d.line([(0, y), (S, y)], fill=(r, g, b))
    return img, d


def orb(d, cx, cy, r, color):
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=color)
    # darker ring
    d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=tuple(max(0, c - 60) for c in color), width=14)
    # specular dot
    d.ellipse([cx - r * 0.55, cy - r * 0.62, cx - r * 0.15, cy - r * 0.2], fill=(255, 255, 255))


img, d = base()
# subtle stars
for (sx, sy, s) in [(80, 90, 3), (940, 120, 2), (130, 330, 2), (920, 380, 2), (70, 600, 2), (960, 640, 3)]:
    d.ellipse([sx - s, sy - s, sx + s, sy + s], fill=(210, 214, 235))

# handles (two rings either side of the belly)
for hx in (150, 874):
    d.ellipse([hx - 62, 392 - 62, hx + 62, 392 + 62], outline=POT_RIM_B, width=34)

# belly
d.ellipse([212, 300, 812, 780], fill=POT)
# belly shading: darker lower-left crescent
d.pieslice([212, 300, 812, 780], start=100, end=290, fill=(20, 22, 33))

# rim (bar across the top of the opening): two-tone slab
d.rectangle([168, 282, 856, 336], fill=POT_RIM_B)          # rim body
d.rounded_rectangle([168, 240, 856, 300], radius=26, fill=POT_RIM_T)  # rim top face
# opening: dark ellipse inside the rim
d.ellipse([236, 262, 788, 348], fill=POT_DARK)
# liquid glow
d.ellipse([246, 272, 778, 340], fill=LIQ_LO)
d.ellipse([262, 280, 762, 336], fill=LIQ)
d.ellipse([330, 286, 694, 310], fill=LIQ_HI)

# liquid drips
for (dx, dy, dr) in [(360, 400, 14), (512, 430, 16), (660, 400, 14)]:
    d.ellipse([dx - dr, dy - dr, dx + dr, dy + dr], fill=LIQ)

# legs: three stubby flat legs
for lx in (340, 512, 684):
    d.rectangle([lx - 36, 700, lx + 36, 846], fill=POT)
    d.rectangle([lx - 36, 800, lx + 36, 846], fill=(20, 22, 33))

# rising sparks from the cauldron
for (sx, sy, s) in [(300, 180, 8), (430, 130, 6), (560, 170, 9), (700, 140, 7), (512, 90, 5)]:
    d.ellipse([sx - s, sy - s, sx + s, sy + s], fill=SPARK)

# four element orbs in an arc above the cauldron
orbres = [
    (205, 175, 46, ELEMENTS[0]),   # fire, low-left
    (381, 105, 36, ELEMENTS[2]),   # wind, high-left
    (643, 105, 36, ELEMENTS[1]),   # water, high-right
    (819, 175, 46, ELEMENTS[3]),   # earth, low-right
]
for ox, oy, r, c in orbres:
    orb(d, ox, oy, r, c)

master = os.path.join(OUT, "app_master.png")
img.save(master)
print("wrote", master)

# Derived sizes
for name, size in [("app_512.png", 512)]:
    img.resize((size, size), Image.LANCZOS).save(os.path.join(OUT, name))
for i, sz in enumerate([36, 48, 72, 96, 144, 192]):
    img.resize((sz, sz), Image.LANCZOS).save(os.path.join(OUT, "android_%d.png" % sz))

# Windows multi-resolution .ico
img.save(os.path.join(OUT, "app.ico"), format="ICO",
         sizes=[(256, 256), (128, 128), (96, 96), (64, 64), (48, 48), (32, 32), (24, 24), (16, 16)])

# HTML5 splash (same art, 512 PNG is plenty)
img.resize((512, 512), Image.LANCZOS).save(os.path.join(OUT, "splash.png"))
print("done")
