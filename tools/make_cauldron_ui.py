#!/usr/bin/env python3
"""Generate the original pixel art for the redesigned CAULDRON screen.

Output: assets/art/ui/cd_*.png  (then run tools/add_to_atlas.py on them).
Everything is drawn here with hard-edged rectangles and a fixed random seed:
no third-party art is copied. The only third-party art on this screen is the
animated smoke puffs (fxa_smoke_a, Free Smoke Fx Pixel 2) played at runtime.

cd_bg.png is drawn at 480x320 and shown on a 960x640 node (nearest filtering
doubles every pixel), so the backdrop stays chunky and the atlas stays small.

Layout contract (design space 960x640, +y up) lives in src/ui/layout.lua; the
y constants in make_ing_panel() below must match CAULDRON.ing_* there.
"""
import math
import os
import random
from PIL import Image, ImageDraw

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "art", "ui")
os.makedirs(OUT, exist_ok=True)

GOLD_D = (112, 74, 22, 255)
GOLD = (201, 150, 48, 255)
GOLD_L = (255, 214, 110, 255)
GOLD_H = (255, 241, 178, 255)
NAVY = (20, 14, 42, 238)
NAVY_L = (36, 26, 70, 255)
PURPLE = (120, 64, 210, 255)
PURPLE_D = (62, 30, 128, 255)
PURPLE_L = (176, 120, 255, 255)
CLEAR = (0, 0, 0, 0)


def save(img, name):
    img.save(os.path.join(OUT, name))
    print("wrote assets/art/ui/%s (%dx%d)" % (name, img.width, img.height))


def chamfer_rect(d, x0, y0, x1, y1, c, fill=None, cut=3):
    """Rectangle with the four corners cut off (hard pixel chamfer)."""
    pts = [(x0 + cut, y0), (x1 - cut, y0), (x1, y0 + cut), (x1, y1 - cut),
           (x1 - cut, y1), (x0 + cut, y1), (x0, y1 - cut), (x0, y0 + cut)]
    if fill is not None:
        d.polygon(pts, fill=fill)
    d.line(pts + [pts[0]], fill=c, width=1)


def gold_frame(w, h, fill=NAVY, hot=False, cut=4, studs=True):
    """Ornate gold frame: dark outline, gold body, light inner line, corner studs."""
    img = Image.new("RGBA", (w, h), CLEAR)
    d = ImageDraw.Draw(img)
    body = GOLD_L if hot else GOLD
    chamfer_rect(d, 0, 0, w - 1, h - 1, (40, 24, 8, 255), fill=GOLD_D, cut=cut)
    chamfer_rect(d, 1, 1, w - 2, h - 2, body, fill=body, cut=cut)
    chamfer_rect(d, 3, 3, w - 4, h - 4, GOLD_D, fill=fill, cut=max(1, cut - 2))
    d.line([(cut + 1, 1), (w - cut - 2, 1)], fill=GOLD_H)
    d.line([(1, cut + 1), (1, h - cut - 2)], fill=GOLD_H)
    d.line([(5, 5), (w - 6, 5)], fill=(72, 50, 130, 255))
    if studs:
        for cx, cy in ((cut + 1, cut + 1), (w - cut - 2, cut + 1), (cut + 1, h - cut - 2), (w - cut - 2, h - cut - 2)):
            d.rectangle([cx - 1, cy - 1, cx + 1, cy + 1], fill=GOLD_H)
    return img


def diamond(d, cx, cy, r, c, outline=(40, 24, 8, 255)):
    d.polygon([(cx, cy - r), (cx + r, cy), (cx, cy + r), (cx - r, cy)], fill=c, outline=outline)


# ---------------------------------------------------------------- frames
def make_ing_panel():
    """230x470 image whose bottom-left sits at design (16, 60); image y = 530 - design y.

    Design-space y of the decor (must match layout.lua CAULDRON.ing_*):
      divider 340, SHAPES plate centre 322, footer divider 138, info badge 106.
    """
    W, H, TOP = 230, 470, 530
    img = Image.new("RGBA", (W, H), CLEAR)
    fr = gold_frame(W, 448, fill=(18, 12, 38, 240))
    img.paste(fr, (0, 22), fr)
    tab = gold_frame(150, 30, fill=(32, 22, 62, 255), cut=5)      # raised INGREDIENTS tab
    img.paste(tab, (40, 0), tab)
    d = ImageDraw.Draw(img)
    y = TOP - 340                      # element / shape divider
    d.line([(24, y), (W - 25, y)], fill=GOLD_D)
    d.line([(24, y - 1), (W - 25, y - 1)], fill=GOLD)
    diamond(d, W // 2, y, 4, GOLD_L)
    plate = gold_frame(110, 22, fill=(32, 22, 62, 255), cut=4, studs=False)   # SHAPES header
    img.paste(plate, (W // 2 - 55, TOP - 322 - 11), plate)
    d = ImageDraw.Draw(img)
    y2 = TOP - 138                     # footer divider
    d.line([(24, y2), (W - 25, y2)], fill=GOLD_D)
    d.line([(24, y2 - 1), (W - 25, y2 - 1)], fill=GOLD)
    cy = TOP - 106                     # "i" badge
    d.ellipse([22, cy - 9, 40, cy + 9], fill=(32, 22, 62, 255), outline=GOLD_L)
    d.rectangle([30, cy - 5, 31, cy - 3], fill=GOLD_H)
    d.rectangle([30, cy - 1, 31, cy + 5], fill=GOLD_H)
    save(img, "cd_ing_panel.png")


def make_title_banner():
    W, H = 340, 72
    img = Image.new("RGBA", (W, H), CLEAR)
    d = ImageDraw.Draw(img)
    body = gold_frame(236, 46, fill=(24, 16, 50, 250), cut=6)
    img.paste(body, (52, 20), body)
    d = ImageDraw.Draw(img)
    for side in (0, 1):
        for i in range(3):
            y0 = 30 + i * 6
            x0 = 8 + i * 8 if side == 0 else W - 8 - i * 8
            x1 = 52 if side == 0 else W - 52
            d.line([(x0, y0), (x1, y0)], fill=GOLD if i != 1 else GOLD_L, width=2)
        diamond(d, 14 if side == 0 else W - 15, 42, 4, GOLD_L)
    diamond(d, W // 2, 8, 8, GOLD, )
    diamond(d, W // 2, 8, 4, GOLD_H)
    d.line([(W // 2 - 26, 15), (W // 2 - 12, 15)], fill=GOLD_L)
    d.line([(W // 2 + 12, 15), (W // 2 + 26, 15)], fill=GOLD_L)
    for x in (92, 122, W - 93, W - 123):
        d.rectangle([x, 29, x + 1, 31], fill=PURPLE_L)
    save(img, "cd_title_banner.png")


def make_scroll():
    W, H = 460, 44
    img = Image.new("RGBA", (W, H), CLEAR)
    d = ImageDraw.Draw(img)
    paper = (236, 218, 170, 255)
    paper_d = (204, 180, 124, 255)
    edge = (110, 72, 34, 255)
    d.rectangle([20, 6, W - 21, H - 7], fill=paper, outline=edge)
    d.line([(21, 7), (W - 22, 7)], fill=(255, 244, 208, 255))
    d.line([(21, H - 8), (W - 22, H - 8)], fill=paper_d)
    for x0, x1 in ((2, 22), (W - 23, W - 3)):
        d.rectangle([x0, 2, x1, H - 3], fill=paper_d, outline=edge)
        d.line([(x0 + 3, 4), (x0 + 3, H - 5)], fill=(255, 244, 208, 255))
        d.line([(x1 - 4, 4), (x1 - 4, H - 5)], fill=edge)
    for cx in (34, W - 35):
        diamond(d, cx, H // 2, 3, GOLD, outline=edge)
    save(img, "cd_scroll.png")


def make_tile(hot):
    W, H = 120, 124
    img = gold_frame(W, H, fill=(22, 14, 46, 245), hot=hot, cut=5)
    d = ImageDraw.Draw(img)
    d.rectangle([16, 12, W - 17, 66], fill=(40, 26, 84, 255), outline=GOLD_D)
    for i in range(0, 54, 2):
        c = 40 + i // 3
        d.line([(17, 13 + i), (W - 18, 13 + i)], fill=(c, 26 + i // 4, 84 + i // 2, 255))
    d.rectangle([16, 12, W - 17, 66], outline=GOLD_D)
    d.rectangle([9, 72, W - 10, H - 9], fill=(14, 9, 32, 255), outline=GOLD_D)
    d.line([(10, 73), (W - 11, 73)], fill=(70, 50, 120, 255))
    save(img, "cd_tile_hot.png" if hot else "cd_tile.png")


def make_preview_panel():
    W, H = 388, 130
    img = gold_frame(W, H, fill=(20, 13, 42, 244), cut=6)
    d = ImageDraw.Draw(img)
    d.rectangle([14, 20, 98, 104], fill=(34, 22, 70, 255), outline=GOLD)
    d.rectangle([15, 21, 97, 103], outline=GOLD_D)
    for i in range(0, 80, 2):
        c = 30 + i // 3
        d.line([(16, 22 + i), (96, 22 + i)], fill=(c, 20 + i // 5, 68 + i // 2, 255))
    for cx, cy in ((14, 20), (98, 20), (14, 104), (98, 104)):
        d.rectangle([cx - 1, cy - 1, cx + 1, cy + 1], fill=GOLD_H)
    d.line([(112, 63), (W - 18, 63)], fill=GOLD_D)
    save(img, "cd_preview_panel.png")


def make_card(hot):
    W, H = 120, 114
    img = gold_frame(W, H, fill=(22, 14, 46, 245), hot=hot, cut=5)
    d = ImageDraw.Draw(img)
    d.rectangle([40, 62, W - 41, H - 12], fill=(40, 26, 84, 255), outline=GOLD_D)
    save(img, "cd_card_hot.png" if hot else "cd_card.png")


def make_done(hot):
    W, H = 300, 56
    img = Image.new("RGBA", (W, H), CLEAR)
    d = ImageDraw.Draw(img)
    edge = GOLD_L if hot else GOLD
    top = (150, 86, 236, 255) if hot else (120, 64, 210, 255)
    bot = (88, 44, 168, 255) if hot else (62, 30, 128, 255)
    chamfer_rect(d, 22, 4, W - 23, H - 5, (40, 24, 8, 255), fill=GOLD_D, cut=6)
    chamfer_rect(d, 23, 5, W - 24, H - 6, edge, fill=edge, cut=6)
    for y in range(8, H - 8):
        t = (y - 8) / (H - 17)
        c = tuple(int(top[i] * (1 - t) + bot[i] * t) for i in range(3)) + (255,)
        d.line([(27, y), (W - 28, y)], fill=c)
    d.line([(28, 8), (W - 29, 8)], fill=PURPLE_L)
    for side in (0, 1):
        for i in range(3):
            y = 14 + i * 14
            x0 = 2 + i * 3 if side == 0 else W - 3 - i * 3
            x1 = 24 if side == 0 else W - 25
            d.line([(x0, y), (x1, y)], fill=GOLD_L if i == 1 else GOLD, width=2)
        diamond(d, 8 if side == 0 else W - 9, H // 2, 4, GOLD_H)
    save(img, "cd_btn_done_hot.png" if hot else "cd_btn_done.png")


def make_small_box():
    W, H = 140, 34
    img = gold_frame(W, H, fill=(22, 14, 46, 245), cut=4, studs=False)
    save(img, "cd_small_box.png")


def make_row_hl(w, h, name):
    img = Image.new("RGBA", (w, h), CLEAR)
    d = ImageDraw.Draw(img)
    chamfer_rect(d, 0, 0, w - 1, h - 1, GOLD_L, fill=(255, 170, 50, 70), cut=3)
    chamfer_rect(d, 1, 1, w - 2, h - 2, GOLD, fill=None, cut=2)
    save(img, name)


def make_gem():
    img = Image.new("RGBA", (18, 18), CLEAR)
    d = ImageDraw.Draw(img)
    d.polygon([(9, 1), (16, 7), (9, 17), (2, 7)], fill=PURPLE, outline=(34, 14, 80, 255))
    d.polygon([(9, 1), (16, 7), (9, 7)], fill=PURPLE_L)
    d.polygon([(2, 7), (9, 7), (9, 17)], fill=PURPLE_D)
    d.line([(5, 4), (7, 3)], fill=(240, 220, 255, 255))
    save(img, "cd_gem.png")


def make_trophy():
    img = Image.new("RGBA", (18, 18), CLEAR)
    d = ImageDraw.Draw(img)
    o = (60, 36, 8, 255)
    d.polygon([(4, 2), (14, 2), (13, 9), (10, 12), (8, 12), (5, 9)], fill=GOLD_L, outline=o)
    d.rectangle([5, 3, 6, 8], fill=GOLD_H)
    d.arc([0, 3, 6, 9], 90, 270, fill=GOLD)
    d.arc([12, 3, 18, 9], 270, 90, fill=GOLD)
    d.rectangle([8, 12, 9, 14], fill=GOLD)
    d.rectangle([5, 14, 12, 16], fill=GOLD_L, outline=o)
    save(img, "cd_trophy.png")


# ---------------------------------------------------------------- backdrop
def make_bg():
    W, H = 480, 320
    rnd = random.Random(7)
    img = Image.new("RGBA", (W, H), (0, 0, 0, 255))
    px = img.load()
    d = ImageDraw.Draw(img)
    for y in range(H):                                   # base gradient
        t = y / H
        c = (int(30 - 12 * t), int(18 - 8 * t), int(58 - 24 * t))
        d.line([(0, y), (W, y)], fill=c + (255,))
    bh, bw = 14, 30                                      # stone bricks
    for row in range(0, H // bh + 1):
        off = (row % 2) * (bw // 2)
        y0 = row * bh
        for col in range(-1, W // bw + 2):
            x0 = col * bw + off
            sh = rnd.randint(-5, 5)
            base = px[min(max(x0 + 2, 0), W - 1), min(y0 + 2, H - 1)]
            c = (max(0, base[0] + sh), max(0, base[1] + sh // 2), max(0, base[2] + sh))
            d.rectangle([x0, y0, x0 + bw - 2, y0 + bh - 2], fill=c + (255,))
            d.line([(x0, y0), (x0 + bw - 2, y0)], fill=(c[0] + 6, c[1] + 4, c[2] + 10, 255))

    def shelf(x0, x1, y_top, levels, step):
        d.rectangle([x0, y_top - 6, x1, y_top + levels * step + 4], fill=(40, 24, 24, 255))
        d.rectangle([x0 + 2, y_top - 4, x1 - 2, y_top + levels * step + 2], fill=(18, 10, 18, 255))
        for lv in range(levels):
            by = y_top + lv * step + step - 3
            x = x0 + 4
            while x < x1 - 8:
                kind = rnd.random()
                if kind < 0.72:  # book
                    bw_ = rnd.randint(3, 6)
                    bh_ = rnd.randint(step - 16, step - 8)
                    col = rnd.choice([(150, 40, 52), (46, 70, 150), (40, 120, 90), (140, 100, 40),
                                      (110, 50, 150), (170, 70, 40), (60, 60, 110)])
                    d.rectangle([x, by - bh_, x + bw_, by], fill=col + (255,))
                    d.line([(x, by - bh_), (x, by)], fill=tuple(min(255, v + 40) for v in col) + (255,))
                    d.line([(x + 1, by - bh_ + 3), (x + bw_ - 1, by - bh_ + 3)], fill=(220, 190, 110, 255))
                    x += bw_ + 1
                else:  # bottle
                    col = rnd.choice([(60, 200, 110), (150, 80, 230), (220, 70, 80), (70, 150, 240)])
                    d.rectangle([x, by - 10, x + 6, by], fill=col + (255,))
                    d.rectangle([x + 2, by - 14, x + 4, by - 10], fill=(200, 200, 220, 255))
                    d.rectangle([x + 1, by - 9, x + 2, by - 3], fill=tuple(min(255, v + 70) for v in col) + (255,))
                    x += 9
            d.rectangle([x0 + 2, by + 1, x1 - 2, by + 3], fill=(88, 52, 30, 255))
    shelf(0, 66, 40, 4, 38)
    shelf(W - 76, W - 1, 60, 4, 38)
    # arched window (upper right of centre)
    wx0, wx1, wy0, wy1 = 338, 376, 38, 108
    for r in range(30, 2, -3):
        g = Image.new("RGBA", (W, H), CLEAR)
        ImageDraw.Draw(g).ellipse([(wx0 + wx1) // 2 - r * 2, wy0 + 40 - r * 2, (wx0 + wx1) // 2 + r * 2, wy0 + 40 + r * 2], fill=(90, 130, 255, 10))
        img.alpha_composite(g)
    d = ImageDraw.Draw(img)
    d.rectangle([wx0 - 3, wy0 + 18, wx1 + 3, wy1], fill=(70, 52, 40, 255))
    d.ellipse([wx0 - 3, wy0 - 2, wx1 + 3, wy0 + 40], fill=(70, 52, 40, 255))
    d.rectangle([wx0, wy0 + 20, wx1, wy1 - 3], fill=(70, 110, 220, 255))
    d.ellipse([wx0, wy0, wx1, wy0 + 40], fill=(86, 132, 240, 255))
    for y in range(wy0 + 21, wy1 - 3):
        t = (y - wy0) / (wy1 - wy0)
        d.line([(wx0 + 1, y), (wx1 - 1, y)], fill=(int(60 + 60 * (1 - t)), int(100 + 70 * (1 - t)), 230, 255))
    d.line([((wx0 + wx1) // 2, wy0 + 2), ((wx0 + wx1) // 2, wy1 - 3)], fill=(40, 30, 40, 255), width=2)
    d.line([(wx0, wy0 + 40), (wx1, wy0 + 40)], fill=(40, 30, 40, 255), width=2)
    d.line([(wx0, wy0 + 64), (wx1, wy0 + 64)], fill=(40, 30, 40, 255), width=2)
    # table + candle (right)
    d.rectangle([W - 120, 150, W - 4, 156], fill=(92, 56, 32, 255))
    d.rectangle([W - 120, 156, W - 4, 160], fill=(52, 30, 20, 255))
    d.rectangle([W - 70, 134, W - 66, 150], fill=(236, 226, 190, 255))
    d.rectangle([W - 69, 128, W - 67, 134], fill=(255, 190, 70, 255))
    d.rectangle([W - 68, 125, W - 68, 128], fill=(255, 240, 180, 255))
    for r in range(18, 2, -2):
        a = Image.new("RGBA", (W, H), CLEAR)
        ImageDraw.Draw(a).ellipse([W - 68 - r * 2, 130 - r * 2, W - 68 + r * 2, 130 + r * 2], fill=(255, 170, 60, 14))
        img.alpha_composite(a)
    d = ImageDraw.Draw(img)
    d.rectangle([0, 270, W, H], fill=(16, 10, 30, 255))   # floor
    for x in range(0, W, 40):
        d.line([(x, 270), (x - 10 + (x - 240) // 6, H)], fill=(30, 20, 56, 255))
    d.line([(0, 270), (W, 270)], fill=(58, 40, 100, 255), width=2)
    cx, cy = 240, 108                                      # cauldron glow
    for r in range(70, 0, -5):
        a = Image.new("RGBA", (W, H), CLEAR)
        ImageDraw.Draw(a).ellipse([cx - r * 2, cy - r, cx + r * 2, cy + r], fill=(150, 80, 255, 9))
        img.alpha_composite(a)
    d = ImageDraw.Draw(img)
    iron = (46, 40, 62, 255)
    iron_l = (96, 88, 124, 255)
    iron_d = (24, 20, 36, 255)
    for y in range(112, 160):                              # body (wide belly)
        t = (y - 112) / 48
        half = int(58 - 14 * (t ** 1.4)) if t > 0.15 else int(52 + 6 * (t / 0.15))
        d.line([(cx - half, y), (cx + half, y)], fill=iron)
        d.point((cx - half, y), fill=iron_d)
        d.point((cx + half, y), fill=iron_d)
        d.line([(cx - half + 3, y), (cx - half + 9, y)], fill=iron_l)
    d.line([(cx - 56, 120), (cx + 56, 120)], fill=iron_d)
    for x in range(cx - 52, cx + 53, 10):
        d.rectangle([x, 122, x + 1, 123], fill=iron_l)
    runes = [[(0, 0), (1, 1), (2, 0), (1, 2)], [(0, 0), (0, 2), (2, 1)], [(0, 1), (2, 1), (1, 0), (1, 2)],
             [(0, 2), (1, 0), (2, 2)], [(0, 0), (2, 0), (1, 1), (0, 2), (2, 2)]]
    for i, rn in enumerate(runes):
        rx = cx - 44 + i * 22
        for (dx, dy) in rn:
            d.rectangle([rx + dx * 2, 130 + dy * 2, rx + dx * 2 + 1, 130 + dy * 2 + 1], fill=(220, 150, 255, 255))
            d.rectangle([rx + dx * 2 - 1, 130 + dy * 2 - 1, rx + dx * 2 + 2, 130 + dy * 2 + 2], outline=(120, 60, 200, 255))
    d.ellipse([cx - 60, 96, cx + 60, 124], fill=iron_l, outline=iron_d)   # rim + liquid
    d.ellipse([cx - 56, 99, cx + 56, 120], fill=iron_d)
    for y in range(101, 119):
        t = (y - 101) / 18
        half = int(52 * math.sqrt(max(0, 1 - ((y - 110) / 10.0) ** 2)))
        d.line([(cx - half, y), (cx + half, y)],
               fill=(int(110 + 60 * (1 - t)), int(54 + 40 * (1 - t)), int(210 + 30 * (1 - t)), 255))
    for _ in range(14):
        bx = cx + rnd.randint(-40, 40)
        by = 110 + rnd.randint(-5, 5)
        d.rectangle([bx, by, bx + 2, by + 1], fill=(225, 190, 255, 255))
    for sgn in (-1, 1):                                    # handles
        d.ellipse([cx + sgn * 62 - 6, 112, cx + sgn * 62 + 6, 126], outline=iron_l, width=2)
    for _ in range(18):                                    # embers
        ex = cx + rnd.randint(-54, 54)
        ey = 160 + rnd.randint(-2, 8)
        d.rectangle([ex, ey, ex + 1, ey + 1], fill=(255, rnd.randint(110, 190), 50, 255))
    v = Image.new("RGBA", (W, H), CLEAR)                   # vignette
    vp = v.load()
    for y in range(H):
        for x in range(W):
            dx, dy = (x - W / 2) / (W / 2), (y - H / 2) / (H / 2)
            a = int(max(0.0, min(1.0, (dx * dx + dy * dy - 0.45) / 1.1)) * 190)
            vp[x, y] = (6, 2, 16, a)
    img.alpha_composite(v)
    img.putalpha(255)
    save(img, "cd_bg.png")


def main():
    make_bg()
    make_ing_panel()
    make_title_banner()
    make_scroll()
    make_tile(False)
    make_tile(True)
    make_preview_panel()
    make_card(False)
    make_card(True)
    make_done(False)
    make_done(True)
    make_small_box()
    make_row_hl(210, 30, "cd_row_hl.png")
    make_gem()
    make_trophy()


if __name__ == "__main__":
    main()
