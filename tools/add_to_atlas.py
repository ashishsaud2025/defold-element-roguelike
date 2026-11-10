#!/usr/bin/env python3
"""Append PNG images to assets/art/shapes.atlas (safe, additive, idempotent).

Defold names an atlas animation after the image file (tile_floor_a.png -> "tile_floor_a"),
so after running this you can use the file name as an animation id in src/core/art.lua.

Usage (from the project root):
    python tools/add_to_atlas.py assets/art/creatures/witch.png assets/art/creatures/goblin.png
    python tools/add_to_atlas.py assets/art/creatures/*.png        (PowerShell: pass the files explicitly)
Then reopen/refresh the project in the Defold editor.
"""
import os, sys, glob

ATLAS = os.path.join("assets", "art", "shapes.atlas")

def main(argv):
    if not argv:
        print(__doc__); return 1
    files = []
    for a in argv:
        files.extend(sorted(glob.glob(a)) or [a])
    text = open(ATLAS, encoding="utf-8").read()
    added = []
    for f in files:
        f = f.replace("\\", "/")
        if not f.lower().endswith(".png") or not os.path.exists(f):
            print("skip (not an existing .png):", f); continue
        res = "/" + f.lstrip("./")
        entry = 'images {\n  image: "%s"\n}\n' % res
        if 'image: "%s"' % res in text:
            print("already in atlas:", res); continue
        marker = "extrude_borders:"
        if marker in text:
            text = text.replace(marker, entry + marker, 1)
        else:
            text += entry
        added.append(res)
    open(ATLAS, "w", encoding="utf-8", newline="\n").write(text)
    for a in added:
        print("added:", a, " -> animation id:", os.path.splitext(os.path.basename(a))[0])
    return 0

if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
