#!/usr/bin/env python
"""Build a labelled contact sheet for sprite picking.

Every PNG in a folder (or matching a glob) is drawn scaled with nearest-neighbour
on a dark background, with its index number underneath. The index -> file name
mapping is printed (and written next to the sheet as <sheet>.txt), so a reader who
cannot see the image can still pick by index.

Usage:
    python tools/make_picker.py <input glob or folder> <output.png> [options]

Options:
    --cols N        columns in the grid (default 10)
    --scale N       integer upscale factor (default 4)
    --max N         cap the drawn size in pixels (downscales huge sprites; default 0 = no cap)
    --bg R,G,B      background colour (default 32,34,42)
    --label-size N  label font size (default 14)

Examples:
    python tools/make_picker.py "downloads/tiny-creatures/tiny-creatures/Tiles" docs/sprite_picker_tiny_creatures.png
    python tools/make_picker.py "downloads/particle-pack/PNG (White background)" docs/particle_picker.png

Never writes into the download folder; only the output PNG + its .txt legend.
"""
import argparse
import glob
import os
import sys

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    sys.exit("Pillow is required: pip install pillow")


def collect(pattern):
    if os.path.isdir(pattern):
        files = glob.glob(os.path.join(pattern, "*.png"))
    else:
        files = glob.glob(pattern)
    files = [f for f in files if f.lower().endswith(".png")]
    return sorted(files, key=lambda p: os.path.basename(p).lower())


def parse_colour(text):
    parts = [int(p) for p in text.split(",")]
    if len(parts) != 3:
        raise argparse.ArgumentTypeError("expected R,G,B")
    return tuple(parts)


def main(argv=None):
    ap = argparse.ArgumentParser(description="Build a labelled sprite contact sheet.")
    ap.add_argument("input", help="folder or glob of PNG files")
    ap.add_argument("output", help="output PNG path")
    ap.add_argument("--cols", type=int, default=10)
    ap.add_argument("--scale", type=int, default=4)
    ap.add_argument("--max", type=int, default=0, dest="max_size",
                    help="cap the drawn sprite size in pixels (0 = no cap)")
    ap.add_argument("--bg", type=parse_colour, default=(32, 34, 42))
    ap.add_argument("--label-size", type=int, default=14)
    args = ap.parse_args(argv)

    files = collect(args.input)
    if not files:
        sys.exit("no PNG files found for: " + args.input)
    if args.cols < 1 or args.scale < 1:
        sys.exit("--cols and --scale must be >= 1")

    # Cell = biggest scaled sprite, plus room for the index label.
    max_w = max_h = 0
    sizes = {}
    for path in files:
        with Image.open(path) as im:
            sizes[path] = im.size
            w, h = im.width * args.scale, im.height * args.scale
            if args.max_size > 0:
                w, h = min(w, args.max_size), min(h, args.max_size)
            max_w = max(max_w, w)
            max_h = max(max_h, h)
    cell_w = max_w + 12
    cell_h = max_h + args.label_size + 14

    rows = (len(files) + args.cols - 1) // args.cols
    sheet = Image.new("RGB", (cell_w * args.cols, cell_h * rows), args.bg)
    draw = ImageDraw.Draw(sheet)
    try:
        font = ImageFont.truetype("arial.ttf", args.label_size)
    except Exception:
        font = ImageFont.load_default()

    for i, path in enumerate(files):
        col = i % args.cols
        row = i // args.cols
        x0 = col * cell_w
        y0 = row * cell_h
        with Image.open(path) as im:
            im = im.convert("RGBA")
            nw, nh = im.width * args.scale, im.height * args.scale
            if args.max_size > 0:
                nw, nh = min(nw, args.max_size), min(nh, args.max_size)
            im = im.resize((nw, nh), Image.NEAREST if nw >= im.width else Image.LANCZOS)
            # checkered-ish faint pad so transparent sprites are visible
            px = x0 + (cell_w - im.width) // 2
            py = y0 + (max_h - im.height) // 2 + 6
            sheet.paste(im, (px, py), im)
        label = str(i)
        tw = draw.textlength(label, font=font)
        draw.text((x0 + (cell_w - tw) / 2, y0 + max_h + 8), label,
                  fill=(210, 214, 225), font=font)

    out_dir = os.path.dirname(os.path.abspath(args.output))
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)
    sheet.save(args.output)

    legend = os.path.splitext(args.output)[0] + ".txt"
    with open(legend, "w", encoding="utf-8") as f:
        for i, path in enumerate(files):
            w, h = sizes[path]
            f.write("%d\t%s\t%dx%d\n" % (i, os.path.basename(path), w, h))

    print("wrote %s  (%d sprites, %dx%d)" % (args.output, len(files), sheet.width, sheet.height))
    print("legend: %s" % legend)
    for i, path in enumerate(files):
        print("%3d  %s" % (i, os.path.basename(path)))


if __name__ == "__main__":
    main()
