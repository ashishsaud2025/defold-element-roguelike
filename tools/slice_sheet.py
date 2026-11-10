#!/usr/bin/env python3
"""Cut a tile sheet (e.g. Kenney's Tiny Creatures tilemap.png) into single PNGs.

Usage:
    python tools/slice_sheet.py SHEET.png OUT_DIR PREFIX [tile=16] [spacing=0] [margin=0]
Example:
    python tools/slice_sheet.py downloads/tiny_creatures/tilemap_packed.png assets/art/creatures creature 16
Files are named PREFIX_000.png, PREFIX_001.png ... (row by row, left to right) and fully
transparent tiles are skipped. Open the sheet in an image viewer to see which index is which,
then rename the ones you want (witch.png, goblin.png ...) and add them with tools/add_to_atlas.py.
If the pack ships both "tilemap.png" (with 1px spacing) and "tilemap_packed.png" (no spacing),
use the packed one with spacing=0.
Needs Pillow:  pip install pillow
"""
import os, sys
from PIL import Image

def main(a):
    if len(a) < 3:
        print(__doc__); return 1
    sheet, out, prefix = a[0], a[1], a[2]
    tile = int(a[3]) if len(a) > 3 else 16
    spacing = int(a[4]) if len(a) > 4 else 0
    margin = int(a[5]) if len(a) > 5 else 0
    im = Image.open(sheet).convert("RGBA")
    os.makedirs(out, exist_ok=True)
    cols = (im.width - 2 * margin + spacing) // (tile + spacing)
    rows = (im.height - 2 * margin + spacing) // (tile + spacing)
    n = 0
    for r in range(rows):
        for c in range(cols):
            x = margin + c * (tile + spacing); y = margin + r * (tile + spacing)
            t = im.crop((x, y, x + tile, y + tile))
            if t.getbbox() is None:
                continue
            t.save(os.path.join(out, "%s_%03d.png" % (prefix, r * cols + c)))
            n += 1
    print("wrote %d tiles (%d cols x %d rows grid) to %s" % (n, cols, rows, out))
    return 0

if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
