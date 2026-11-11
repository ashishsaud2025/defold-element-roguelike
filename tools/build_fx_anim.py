#!/usr/bin/env python3
"""Build the animated spell-effect flipbooks from the packs in downloads/.

    pip install pillow numpy
    python tools/build_fx_anim.py            # run from the project root

What it does (idempotent, safe to re-run):
  1. Extracts the needed zips from downloads/ into .fx_cache/ (once).
  2. Slices effect sheets into 64px frames, picks the colour row that matches each
     element (fire = red/orange, water = blue, wind = white, earth = tan), trims empty
     borders (centred, so the effect stays centred), and subsamples long animations.
  3. Writes the frames to assets/art/fxa/ and (re)writes every `fxa_*` animation block
     in assets/art/shapes.atlas. Frames are only referenced from animation blocks, so no
     extra auto-generated single-frame animations appear.
  4. Writes src/core/fxanim.lua (animation lengths, sizes, facing, per-compound styles).
  5. Writes docs/fx_anim_preview.png so you can eyeball every family.

To change which effect a skill uses: edit COMPOUNDS below (numbers are the file numbers
inside "Effect and FX Pixel All Free" / "RPG Effect All Free", see docs/fx_catalog_*.png
if present), re-run, reload the Defold project.

Packs used: "Effect and FX Pixel All Free", "RPG Effect All Free", "Pixel fire asset pack v1.2",
"Free Smoke Fx Pixel 2". See CREDITS.md.
"""
import glob
import math
import os
import re
import sys
import zipfile

import numpy as np
from PIL import Image, ImageDraw

ROOT = os.getcwd()
DL = os.path.join(ROOT, "downloads")
CACHE = os.path.join(ROOT, ".fx_cache")
OUT_DIR = os.path.join(ROOT, "assets", "art", "fxa")
ATLAS = os.path.join(ROOT, "assets", "art", "shapes.atlas")
LUA_OUT = os.path.join(ROOT, "src", "core", "fxanim.lua")
PREVIEW = os.path.join(ROOT, "docs", "fx_anim_preview.png")

ZIPS = [
    "Effect and FX Pixel All Free.zip",
    "RPG Effect All Free.zip",
    "Pixel fire asset pack v1.2.zip",
    "Free Smoke Fx Pixel 2.zip",
]

# Colour row inside every 64px effect sheet (9 colour variants per effect).
ELEM_ROW = {"fire": 0, "water": 2, "wind": 5, "earth": 4}
# Fire-pack flame colours per element.
ELEM_FLAME = {"fire": "red", "water": "blue", "wind": "white", "earth": "yellow"}

# Role -> (duration in seconds, max frames kept)
ROLE = {
    "hit":   (0.38, 9),
    "pool":  (0.95, 10),
    "spray": (0.50, 9),
    "nova":  (0.60, 10),
    "cast":  (0.40, 8),
    "puff":  (0.45, 8),
}

# One entry per compound (see src/core/data.lua COMPOUNDS). `el` = the two element names,
# sorted alphabetically exactly like skillgen does. The numbers pick an effect from the packs.
# `smoke` (optional) = alpha-blended smoke tint r,g,b; those skills also emit smoke puffs.
COMPOUNDS = {
    "Inferno": dict(el=("fire", "fire"),   hit=230,  pool=186,  spray=1012, nova=766),
    "Tide":    dict(el=("water", "water"), hit=273,  pool=712,  spray=6,    nova=1114),
    "Gale":    dict(el=("wind", "wind"),   hit=314,  pool=176,  spray=1013, nova=3),
    "Quake":   dict(el=("earth", "earth"), hit=1031, pool=703,  spray=124,  nova=1032),
    "Steam":   dict(el=("fire", "water"),  hit=293,  pool=185,  spray=1101, nova=835,  smoke=(0.92, 0.92, 0.97)),
    "Ember":   dict(el=("fire", "wind"),   hit=63,   pool=16,   spray=123,  nova=125),
    "Magma":   dict(el=("earth", "fire"),  hit=1033, pool=674,  spray=126,  nova=135),
    "Mist":    dict(el=("water", "wind"),  hit=232,  pool=26,   spray=233,  nova=77,   smoke=(0.72, 0.88, 1.00)),
    "Mud":     dict(el=("earth", "water"), hit=702,  pool=1054, spray=114,  nova=71,   smoke=(0.46, 0.34, 0.22)),
    "Dust":    dict(el=("earth", "wind"),  hit=324,  pool=3,    spray=76,    nova=115,  smoke=(0.82, 0.70, 0.46)),
}
CAST_FX = 13     # small swirl at the caster's hands
PUFF_FX = 273    # tiny second-element sparkle (bolt trails, orbit sparks)

# Looping flames from the fire pack: bolt head (tall flame) and orbit orb (round flame).
FLAME_HEAD = "4 - 4"
FLAME_ORB = "4 - 5"
FLAME_FPS = 12

# Smoke sheet: (png number, row) -> family name. White, hard edged, tinted at runtime.
SMOKE = {"smoke_a": ("06", 7), "smoke_b": ("06", 8)}


def log(*a):
    print(*a, flush=True)


# ------------------------------------------------------------------ extraction
def ensure_cache():
    os.makedirs(CACHE, exist_ok=True)
    for z in ZIPS:
        src = os.path.join(DL, z)
        dst = os.path.join(CACHE, z[:-4])
        if os.path.isdir(dst):
            continue
        if not os.path.exists(src):
            sys.exit("missing pack: %s (put it in downloads/)" % src)
        log("extracting", z)
        with zipfile.ZipFile(src) as zf:
            zf.extractall(dst)


_big_index = None


def big_file(num):
    global _big_index
    if _big_index is None:
        _big_index = {}
        for pack in ("Effect and FX Pixel All Free", "RPG Effect All Free"):
            for p in glob.glob(os.path.join(CACHE, pack, "**", "*.png"), recursive=True):
                b = os.path.basename(p)[:-4]
                if b.isdigit():
                    _big_index[int(b)] = p
    if num not in _big_index:
        sys.exit("effect #%d not found in the big packs" % num)
    return _big_index[num]


# ------------------------------------------------------------------ frame helpers
def sheet_frames(path, row, cell=64):
    """Frames of one colour row, trailing empty frames removed."""
    im = Image.open(path).convert("RGBA")
    n = im.width // cell
    fr = [im.crop((i * cell, row * cell, (i + 1) * cell, (row + 1) * cell)) for i in range(n)]
    used = [i for i, f in enumerate(fr) if f.getchannel("A").getbbox()]
    if not used:
        sys.exit("empty row %d in %s" % (row, path))
    return fr[: used[-1] + 1]


def subsample(frames, maxf):
    if len(frames) <= maxf:
        return frames
    idx = [int(round(i * (len(frames) - 1) / (maxf - 1))) for i in range(maxf)]
    return [frames[i] for i in idx]


def half_extent(frames, cell=64):
    """Largest distance from the cell centre to any non-transparent pixel."""
    c = cell / 2.0
    h = 0
    for f in frames:
        bb = f.getchannel("A").getbbox()
        if bb:
            h = max(h, c - bb[0], bb[2] - c, c - bb[1], bb[3] - c)
    return int(math.ceil(h)) + 1


def face_angle(frames, cell=64):
    """Direction (radians, y up) the effect 'points' towards, or None if it is symmetric."""
    best, best_mass = None, -1
    for f in frames:
        a = np.array(f.getchannel("A")).astype(float)
        m = a.sum()
        if m > best_mass:
            best, best_mass = a, m
    if best is None or best_mass <= 0:
        return None
    ys, xs = np.mgrid[0:best.shape[0], 0:best.shape[1]]
    cx = (best * xs).sum() / best_mass - (cell - 1) / 2.0
    cy = (cell - 1) / 2.0 - (best * ys).sum() / best_mass   # y up
    if math.hypot(cx, cy) >= 3.0:
        return math.atan2(cy, cx)
    # symmetric about the centre: use the long axis if the shape is elongated
    dx, dy = xs - (cell - 1) / 2.0 - cx, ((cell - 1) / 2.0 - ys) - cy
    cxx = (best * dx * dx).sum() / best_mass
    cyy = (best * dy * dy).sum() / best_mass
    cxy = (best * dx * dy).sum() / best_mass
    tr, det = cxx + cyy, cxx * cyy - cxy * cxy
    disc = math.sqrt(max(0.0, tr * tr / 4 - det))
    l1, l2 = tr / 2 + disc, tr / 2 - disc
    if l2 > 0 and l1 / l2 > 2.2:
        return 0.5 * math.atan2(2 * cxy, cxx - cyy)
    return None


def crop_centered(f, half, cell=64):
    c = cell // 2
    return f.crop((c - half, c - half, c + half, c + half))


# ------------------------------------------------------------------ build
anims = {}      # atlas id -> dict(frames=[paths], playback, fps, n, dur, size)
fams = {}       # family -> dict(size, face)


def save_set(name, frames, playback, fps, size):
    paths = []
    for i, f in enumerate(frames):
        fn = "%s_%02d.png" % (name, i)
        f.save(os.path.join(OUT_DIR, fn))
        paths.append("/assets/art/fxa/" + fn)
    anims[name] = dict(frames=paths, playback=playback, fps=fps, n=len(frames),
                       dur=round(len(frames) / float(fps), 3), size=size)


def build_big(role, num, elems):
    fam = "%s%d" % (role, num)
    dur, maxf = ROLE[role]
    src = big_file(num)
    per = {e: subsample(sheet_frames(src, ELEM_ROW[e]), maxf) for e in elems}
    half = max(half_extent(fr) for fr in per.values())
    half = max(half, 6)
    face = face_angle(per[elems[0]])
    for e, fr in per.items():
        n = len(fr)
        fps = max(4, int(round(n / dur)))
        save_set("fxa_%s_%s" % (fam, e), [crop_centered(f, half) for f in fr],
                 "PLAYBACK_ONCE_FORWARD", fps, half * 2)
    fams[fam] = dict(size=half * 2, face=face)


def build_flames():
    base = os.path.join(CACHE, "Pixel fire asset pack v1.2", "Pixel fire asset pack v1.2",
                        "Pixel Fire Asset Pack Colored")
    for fam, grp in (("headflame", FLAME_HEAD), ("orbflame", FLAME_ORB)):
        size = 0
        for e, colour in ELEM_FLAME.items():
            p = os.path.join(base, "fire asset %s" % colour, "Group %s" % grp, "Group %s.png" % grp)
            im = Image.open(p).convert("RGBA")
            h = im.height
            n = im.width // 32
            fr = [im.crop((i * 32, 0, (i + 1) * 32, h)) for i in range(n)]
            # keep the flame's own anchor: pad to a square so scaling/rotation use one number
            side = max(32, h)
            sq = []
            for f in fr:
                canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
                canvas.alpha_composite(f, ((side - 32) // 2, side - h))
                sq.append(canvas)
            save_set("fxa_%s_%s" % (fam, e), sq, "PLAYBACK_LOOP_FORWARD", FLAME_FPS, side)
            size = side
        fams[fam] = dict(size=size, face=math.pi / 2)      # flame tip points up


def build_smoke():
    for fam, (num, row) in SMOKE.items():
        p = os.path.join(CACHE, "Free Smoke Fx Pixel 2", "Free Smoke Fx  Pixel %s.png" % num)
        fr = subsample(sheet_frames(p, row), 10)
        half = max(half_extent(fr), 6)
        save_set("fxa_%s" % fam, [crop_centered(f, half) for f in fr],
                 "PLAYBACK_ONCE_FORWARD", max(4, int(round(len(fr) / 0.7))), half * 2)
        fams[fam] = dict(size=half * 2, face=None)


def write_atlas():
    text = open(ATLAS, encoding="utf-8").read()
    text = re.sub(r'animations \{\n  id: "fxa_.*?\n\}\n', "", text, flags=re.S)
    blocks = []
    for name in sorted(anims):
        a = anims[name]
        b = 'animations {\n  id: "%s"\n' % name
        for p in a["frames"]:
            b += '  images {\n    image: "%s"\n  }\n' % p
        b += "  playback: %s\n  fps: %d\n  flip_horizontal: 0\n  flip_vertical: 0\n}\n" % (a["playback"], a["fps"])
        blocks.append(b)
    marker = "extrude_borders:"
    block_text = "".join(blocks)
    if marker in text:
        text = text.replace(marker, block_text + marker, 1)
    else:
        text += block_text
    open(ATLAS, "w", encoding="utf-8", newline="\n").write(text)


def lua_key(k):
    return '["%s"]' % k


def write_lua():
    L = ["-- /src/core/fxanim.lua",
         "-- GENERATED by tools/build_fx_anim.py - do not edit by hand; edit COMPOUNDS in the tool and re-run.",
         "-- ANIMS : atlas animation id -> { n = frames, dur = seconds for one play-through, size = px of a frame }",
         "-- FAM   : effect family -> { size = px, face = direction the art points (radians, y up) or nil }",
         "-- COMPOUND : compound name -> which family each shape uses, plus optional smoke tint.",
         "local M = {}", "", "M.ANIMS = {"]
    for name in sorted(anims):
        a = anims[name]
        L.append("    %s = { n = %d, dur = %.3f, size = %d }," % (lua_key(name), a["n"], a["dur"], a["size"]))
    L += ["}", "", "M.FAM = {"]
    for name in sorted(fams):
        f = fams[name]
        face = ("%.4f" % f["face"]) if f["face"] is not None else "nil"
        L.append("    %s = { size = %d, face = %s }," % (lua_key(name), f["size"], face))
    L += ["}", "", "M.COMPOUND = {"]
    for cname, c in COMPOUNDS.items():
        s = ('smoke = { %.2f, %.2f, %.2f }' % c["smoke"]) if "smoke" in c else "smoke = nil"
        L.append('    %s = { hit = "hit%d", pool = "pool%d", spray = "spray%d", nova = "nova%d", %s },'
                 % (lua_key(cname), c["hit"], c["pool"], c["spray"], c["nova"], s))
    L += ["}", "", 'M.CAST = "cast%d"' % CAST_FX, 'M.PUFF = "puff%d"' % PUFF_FX, "", "return M", ""]
    open(LUA_OUT, "w", encoding="utf-8", newline="\n").write("\n".join(L))


def write_preview():
    """One row per family; element colours stacked; first/mid/last frames."""
    names = sorted(a for a in anims)
    cell = 64
    rows = len(names)
    sheet = Image.new("RGBA", (6 * cell + 230, rows * cell), (14, 14, 22, 255))
    d = ImageDraw.Draw(sheet)
    for r, n in enumerate(names):
        a = anims[n]
        d.text((4, r * cell + 4), "%s\n%d frames @%dfps\nsize %d" % (n, a["n"], a["fps"], a["size"]), fill=(255, 255, 0, 255))
        for j in range(6):
            i = int(round(j * (a["n"] - 1) / 5.0))
            im = Image.open(os.path.join(ROOT, a["frames"][i].lstrip("/"))).convert("RGBA")
            if im.width > cell or im.height > cell:
                s = min(cell / float(im.width), cell / float(im.height))
                im = im.resize((max(1, int(im.width * s)), max(1, int(im.height * s))), Image.NEAREST)
            sheet.alpha_composite(im, (230 + j * cell + (cell - im.width) // 2, r * cell + (cell - im.height) // 2))
    os.makedirs(os.path.dirname(PREVIEW), exist_ok=True)
    # split into a few images so it stays viewable
    sheet.convert("RGB").save(PREVIEW)


def main():
    ensure_cache()
    os.makedirs(OUT_DIR, exist_ok=True)
    for old in glob.glob(os.path.join(OUT_DIR, "fxa_*.png")):
        os.remove(old)
    # which (family, element) pairs are really used
    need = {}
    for c in COMPOUNDS.values():
        for role in ("hit", "pool", "spray", "nova"):
            need.setdefault((role, c[role]), set()).update(c["el"])
    need.setdefault(("cast", CAST_FX), set()).update(ELEM_ROW.keys())
    need.setdefault(("puff", PUFF_FX), set()).update(ELEM_ROW.keys())
    order = ["fire", "water", "wind", "earth"]
    for (role, num), els in sorted(need.items()):
        build_big(role, num, [e for e in order if e in els])
    build_flames()
    build_smoke()
    write_atlas()
    write_lua()
    write_preview()
    total = sum(a["n"] for a in anims.values())
    log("animations: %d  frames: %d  families: %d" % (len(anims), total, len(fams)))
    log("wrote", os.path.relpath(LUA_OUT, ROOT), os.path.relpath(ATLAS, ROOT), os.path.relpath(PREVIEW, ROOT))


if __name__ == "__main__":
    main()
