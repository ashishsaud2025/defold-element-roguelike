#!/usr/bin/env python
"""Cut a sprite out of a tile that ships with an opaque background/frame.

Tiny Creatures (Clint Bellanger, CC0) ships its 16x16 tiles with a maroon frame
and a dark backdrop. Drawn as-is in the game they look like little framed tokens,
so this tool turns the frame + backdrop into transparency.

Two modes:
  * colour key  - remove every pixel matching one of the --bg colours
  * --flood     - remove only pixels matching --bg that are connected to the
                  image border (keeps the same colours inside the creature)

Usage:
    python tools/cutout_sprite.py IN.png OUT.png --bg 63,38,49 --bg 0,0,0 --flood
    python tools/cutout_sprite.py IN.png OUT.png --bg 63,38,49 --bg 0,0,0 --bg 82,96,124

Never modifies IN.png.
"""
import argparse
import sys
from collections import deque

try:
    from PIL import Image
except ImportError:
    sys.exit("Pillow is required: pip install pillow")


def parse_colour(text):
    parts = [int(p) for p in text.split(",")]
    if len(parts) != 3:
        raise argparse.ArgumentTypeError("expected R,G,B")
    return tuple(parts)


def main(argv=None):
    ap = argparse.ArgumentParser(description="Cut a sprite out of an opaque tile background.")
    ap.add_argument("source", help="input PNG (read only)")
    ap.add_argument("output", help="output PNG (overwritten)")
    ap.add_argument("--bg", type=parse_colour, action="append", default=[],
                    help="background colour R,G,B (repeatable)")
    ap.add_argument("--flood", action="store_true",
                    help="only remove --bg colours reachable from the image border")
    ap.add_argument("--tol", type=int, default=0,
                    help="per-channel tolerance when matching --bg (default 0)")
    args = ap.parse_args(argv)

    if not args.bg:
        sys.exit("at least one --bg R,G,B is required (try --bg 0,0,0)")

    im = Image.open(args.source).convert("RGBA")
    px = im.load()
    w, h = im.size

    def matches(x, y):
        r, g, b, a = px[x, y]
        if a == 0:
            return True
        for (br, bg_, bb) in args.bg:
            if abs(r - br) <= args.tol and abs(g - bg_) <= args.tol and abs(b - bb) <= args.tol:
                return True
        return False

    if args.flood:
        seen = [[False] * w for _ in range(h)]
        q = deque()
        for x in range(w):
            for y in (0, h - 1):
                if matches(x, y) and not seen[y][x]:
                    seen[y][x] = True
                    q.append((x, y))
        for y in range(h):
            for x in (0, w - 1):
                if matches(x, y) and not seen[y][x]:
                    seen[y][x] = True
                    q.append((x, y))
        while q:
            x, y = q.popleft()
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny < h and not seen[ny][nx] and matches(nx, ny):
                    seen[ny][nx] = True
                    q.append((nx, ny))
        removed = 0
        for y in range(h):
            for x in range(w):
                if seen[y][x]:
                    r, g, b, a = px[x, y]
                    px[x, y] = (r, g, b, 0)
                    removed += 1
    else:
        removed = 0
        for y in range(h):
            for x in range(w):
                if matches(x, y):
                    r, g, b, a = px[x, y]
                    px[x, y] = (r, g, b, 0)
                    removed += 1

    im.save(args.output)
    print("%s -> %s  removed %d/%d pixels" % (args.source, args.output, removed, w * h))


if __name__ == "__main__":
    main()
