#!/usr/bin/env python3
"""Generate the original UI pixel art for the Lantern Hall feature.

Everything here is drawn with hard-edged rectangles (the project uses nearest-neighbour
rendering), no randomness, and no copied assets. Output: assets/art/ui/<name>.png.

Sizes are chosen for the 960x640 design space: a 68x68 slot frame (64px slot + 2px
border), a 240x24 health bar, a 56x56 portrait, 48x48 door and 48x64 altar art.
"""
import os
from PIL import Image, ImageDraw

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "art", "ui")
os.makedirs(OUT, exist_ok=True)


def px(img, x, y, color):
    img.putpixel((x, y), color)


def save(img, name):
    img.save(os.path.join(OUT, name))
    print("wrote assets/art/ui/%s (%dx%d)" % (name, img.width, img.height))


def slot_frame(ready=False):
    S = 68
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    outer = (57, 50, 62, 255)
    bevel_hi = (74, 74, 88, 255)
    bevel_lo = (19, 18, 26, 255)
    if ready:
        outer = (99, 78, 35, 255)
        bevel_hi = (255, 216, 99, 255)
        bevel_lo = (179, 98, 34, 255)
    # outer 2px frame
    d.rectangle([0, 0, S - 1, S - 1], outline=outer, width=2)
    # inner bevel: light line top-left, dark line bottom-right
    d.line([(3, 3), (S - 4, 3)], fill=bevel_hi)
    d.line([(3, 3), (3, S - 4)], fill=bevel_hi)
    d.line([(S - 4, 3), (S - 4, S - 4)], fill=bevel_lo)
    d.line([(3, S - 4), (S - 4, S - 4)], fill=bevel_lo)
    if ready:
        stud = (255, 230, 122, 255)
        for cx, cy in ((1, 1), (S - 4, 1), (1, S - 4), (S - 4, S - 4)):
            d.rectangle([cx, cy, cx + 3, cy + 3], fill=stud)
    save(img, "slot_frame_ready.png" if ready else "slot_frame.png")


LETTERS = {
    "Q": ["01110", "10001", "10001", "10001", "10101", "10010", "01101"],
    "R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
}


def keycap(kind):
    S = 24
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cap = (214, 209, 190, 255)
    shade_lo = (161, 157, 139, 255)
    shade_hi = (242, 240, 226, 255)
    outline = (38, 35, 45, 255)
    # outer body
    d.rectangle([1, 1, S - 2, S - 2], fill=cap)
    d.rectangle([1, 1, S - 2, S - 2], outline=outline)
    # bevel: highlight across the top, shade across the bottom
    d.line([(2, 3), (S - 3, 3)], fill=shade_hi)
    d.line([(2, S - 4), (S - 3, S - 4)], fill=shade_lo)
    if kind == "mouse":
        # mouse glyph: tall rounded body, split line, scroll wheel dot
        body = (62, 60, 74, 255)
        d.rectangle([7, 5, 16, 18], fill=body)
        d.rectangle([8, 4, 15, 19], fill=body)
        d.rectangle([11, 7, 12, 9], fill=cap)  # wheel strip
        d.line([(11, 5), (12, 5)], fill=shade_hi)
        d.line([(11, 9), (11, 13)], fill=cap)   # centre split
        d.line([(12, 9), (12, 13)], fill=cap)
    else:
        glyph = LETTERS[kind]
        sx, sy = 6, 5
        px_size = 2
        fg = (38, 35, 45, 255)
        for r, row in enumerate(glyph):
            for c, ch in enumerate(row):
                if ch == "1":
                    d.rectangle([sx + c * px_size, sy + r * px_size,
                                 sx + c * px_size + px_size - 1, sy + r * px_size + px_size - 1],
                                fill=fg)
    save(img, "keycap_%s.png" % kind)


def portrait():
    S = 56
    img = Image.new("RGBA", (S, S), (10, 8, 12, 255))
    d = ImageDraw.Draw(img)
    # faint moonlit gradient backdrop behind the figure
    for y in range(0, S):
        v = max(10, 26 - int(6 * (abs(y - 8) / 8.0)))
        d.line([(0, y), (S - 1, y)], fill=(v, v, v + 4))
    hood_shadow = (26, 26, 36, 255)
    hood_mid = (43, 47, 64, 255)
    hood_hi = (64, 69, 92, 255)
    face = (8, 7, 11, 255)
    robe_dark = (29, 43, 52, 255)
    robe_mid = (44, 66, 78, 255)
    eye = (242, 204, 96, 255)
    # robe: widening trapezoid
    for y in range(34, S):
        half = 10 + (y - 34) // 2
        d.rectangle([S // 2 - half, y, S // 2 + half, y], fill=robe_dark)
    for y in range(38, S):
        half = 7 + (y - 38) // 2
        d.rectangle([S // 2 - half, y, S // 2 + half, y], fill=robe_mid)
    # hood rim (arch above the face void)
    d.rectangle([15, 8, 40, 12], fill=hood_shadow)
    d.rectangle([11, 12, 44, 26], fill=hood_shadow)
    d.rectangle([11, 12, 44, 14], fill=hood_hi)   # moonlit crown line
    # hood sides descending to the shoulders
    d.rectangle([9, 14, 13, 34], fill=hood_shadow)
    d.rectangle([42, 14, 46, 34], fill=hood_shadow)
    d.line([(11, 13), (11, 34)], fill=hood_mid)
    d.line([(44, 13), (44, 34)], fill=hood_mid)
    # face void
    d.rectangle([15, 14, 40, 30], fill=face)
    d.rectangle([17, 12, 38, 33], outline=hood_shadow)
    # eye glints
    d.rectangle([20, 21, 22, 22], fill=eye)
    d.rectangle([33, 21, 35, 22], fill=eye)
    save(img, "portrait.png")


def bar_fill(label):
    W, H = 240, 24
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    bg = (17, 16, 24, 255)
    bevel_hi = (43, 37, 55, 255)
    bevel_lo = (7, 6, 12, 255)
    d.rectangle([0, 0, W - 1, H - 1], fill=bg)
    d.line([(0, 0), (W - 1, 0)], fill=bevel_hi)
    d.line([(0, H - 1), (W - 1, H - 1)], fill=bevel_lo)
    reds = [(217, 74, 82, 255)] * 6 + [(168, 50, 62, 255)]
    seg_w = 24
    x = 2
    while x < W - 2:
        i = (x // seg_w) % 8
        d.rectangle([x, 4, x + seg_w - 3, H - 5], fill=reds[i % len(reds)])
        if i == 0 or i == 4:
            d.rectangle([x, 4, x + 2, H - 5], fill=(255, 135, 140, 255))  # sheen on segment starts
        x += seg_w
    # inner separators every 24 px (chunks)
    for sx in range(2 + seg_w, W - 2, seg_w):
        d.line([(sx - 1, 4), (sx - 1, H - 5)], fill=(30, 10, 14, 255))
    save(img, "%s.png" % label)


def dash_bar(label):
    W, H = 240, 6
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    if label == "dash_bg":
        d.rectangle([0, 0, W - 1, H - 1], fill=(11, 10, 17, 255))
        d.line([(0, 0), (W - 1, 0)], fill=(30, 34, 46, 255))
        d.line([(0, H - 1), (W - 1, H - 1)], fill=(5, 5, 9, 255))
    else:
        d.rectangle([0, 0, W - 1, H - 1], fill=(38, 188, 170, 255))
        d.line([(0, 0), (W - 1, 0)], fill=(160, 255, 233, 255))
        d.line([(0, H - 1), (W - 1, H - 1)], fill=(14, 89, 79, 255))
    save(img, "%s.png" % label)


def altar():
    W, H = 48, 64
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    stone = (46, 44, 54, 255)
    stone_hi = (79, 77, 92, 255)
    stone_lo = (22, 21, 28, 255)
    stone_dark = (30, 29, 37, 255)
    bowl = (60, 52, 43, 255)
    bowl_hi = (110, 97, 78, 255)
    flame_out = (242, 152, 60, 255)
    flame_mid = (255, 204, 84, 255)
    flame_core = (255, 239, 176, 255)
    # base plinth (overhangs the body)
    d.rectangle([1, 52, 46, 62], fill=stone)
    d.rectangle([1, 52, 46, 53], fill=stone_hi)
    d.line([(1, 61), (46, 61)], fill=stone_lo)
    # upper base under the cup
    d.rectangle([7, 44, 40, 52], fill=stone_dark)
    d.line([(7, 44), (40, 44)], fill=stone_hi)
    # pedestal body (tapered)
    d.polygon([(9, 44), (39, 44), (34, 46), (14, 46)], fill=stone)
    d.rectangle([14, 46, 34, 48], fill=stone)
    # bowl cup
    d.rectangle([13, 36, 35, 44], fill=bowl)
    d.line([(13, 36), (35, 36)], fill=bowl_hi)
    d.line([(13, 43), (35, 43)], fill=stone_lo)
    # flame over the bowl (chunky teardrop)
    d.rectangle([21, 26, 27, 37], fill=flame_out)
    d.rectangle([22, 20, 26, 29], fill=flame_out)
    d.rectangle([23, 16, 25, 22], fill=flame_out)
    d.rectangle([22, 29, 26, 36], fill=flame_mid)
    d.rectangle([23, 26, 25, 29], fill=flame_mid)
    d.rectangle([23, 33, 25, 36], fill=flame_core)
    save(img, "altar.png")


def door():
    W = H = 48
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    frame = (49, 45, 57, 255)
    frame_hi = (87, 82, 100, 255)
    frame_lo = (24, 22, 30, 255)
    wood = (49, 33, 20, 255)
    wood_dark = (32, 21, 13, 255)
    wood_mid = (66, 46, 28, 255)
    knob = (236, 190, 79, 255)
    knob_lo = (150, 108, 30, 255)
    # arched stone frame around the door fill
    d.rectangle([0, 0, W - 1, H - 1], fill=frame)
    d.line([(0, 0), (W - 1, 0)], fill=frame_hi)
    d.rectangle([2, 2, W - 3, H - 3], outline=frame_hi)
    d.rectangle([3, 3, W - 4, H - 4], outline=frame_lo)
    # the door fill (arched top implied by the frame corners)
    d.rectangle([7, 8, W - 8, H - 7], fill=wood)
    # plank lines
    for x in (16, 24, 32):
        d.line([(x, 9), (x, H - 8)], fill=wood_dark)
    d.line([(8, 18), (W - 9, 18)], fill=wood_dark)
    d.line([(8, 32), (W - 9, 32)], fill=wood_dark)
    # highlight on the middle plank
    d.line([(28, 9), (28, H - 8)], fill=wood_mid)
    d.rectangle([8, 12, W - 9, 13], fill=wood_mid)
    # gold handle
    d.rectangle([30, 26, 34, 30], fill=knob)
    d.rectangle([30, 30, 34, 31], fill=knob_lo)
    save(img, "door.png")


slot_frame(False)
slot_frame(True)
keycap("Q")
keycap("R")
keycap("mouse")
portrait()
bar_fill("bar_fill")
dash_bar("dash_bg")
dash_bar("dash_fill")


def bar_bg():
    W, H = 240, 24
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, W - 1, H - 1], fill=(17, 16, 24, 255))
    d.line([(0, 0), (W - 1, 0)], fill=(43, 37, 55, 255))
    d.line([(0, H - 1), (W - 1, H - 1)], fill=(7, 6, 12, 255))
    save(img, "bar_bg.png")


bar_bg()
altar()
door()
