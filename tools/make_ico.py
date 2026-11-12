#!/usr/bin/env python3
"""Write a Windows .ico with pure BMP (BITMAPINFOHEADER + AND mask) entries.
PIL's PNG-compressed entries are rejected by Defold/Bob's icon replacer
("8 icon(s) not replaced ... using app.ico"), so this writer emits classic
BMP entries instead. Sizes: 16, 24, 32, 48, 64, 96, 128, 256."""
import struct
from PIL import Image

SRC = 'assets/icons/app_master.png'
DST = 'assets/icons/app.ico'
SIZES = [16, 24, 32, 48, 64, 96, 128, 256]

img = Image.open(SRC).convert('RGBA')
entries, blobs = [], []
offset = 6 + 16 * len(SIZES)  # ICONDIR header + ICONDIRENTRY array
for size in SIZES:
    layer = img.resize((size, size), Image.LANCZOS)
    px = layer.tobytes()
    # BITMAPINFOHEADER: height = 2*h (XOR + AND mask), 32bpp BGRA
    xor_size = size * size * 4
    and_stride = ((size + 31) // 32) * 4
    and_size = and_stride * size
    header = struct.pack('<IiiHHIIiiII',
                         40, size, size * 2, 1, 32, 0,
                         xor_size + and_size, 0, 0, 0, 0)
    # XOR rows bottom-up, BGRA byte order
    bgra = bytearray()
    for y in range(size - 1, -1, -1):
        for x in range(size):
            r, g, b, a = px[(y * size + x) * 4:(y * size + x) * 4 + 4]
            # premultiply-less, keep alpha; AND mask all-zero => opaque
            bgra += bytes((b, g, r, a))
    and_mask = b'\x00' * and_size
    blob = header + bgra + and_mask
    entries.append((size, len(blob), offset))
    blobs.append(blob)
    offset += len(blob)

with open(DST, 'wb') as f:
    f.write(struct.pack('<HHH', 0, 1, len(SIZES)))
    for size, length, off in entries:
        w = size if size < 256 else 0  # 0 means 256
        f.write(struct.pack('<BBBBHHII', w, w, 0, 0, 1, 32, length, off))
    for blob in blobs:
        f.write(blob)
print('wrote %s (%d entries)' % (DST, len(entries)))
