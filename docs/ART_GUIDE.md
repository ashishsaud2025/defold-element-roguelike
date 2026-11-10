# Swapping in real art

The full, maintained guide is **README.md section 13 ("Adding art and assets")**. Quick version:

1. Put downloads **outside** the project; copy only the sprites you use into `assets/art/<tiles|actors|fx|icons>/` with unique, prefixed names.
2. `python tools/add_to_atlas.py "assets/art/tiles/td_*.png"` (quote the pattern). Sheets: `python tools/slice_sheet.py SHEET OUT_DIR PREFIX 16`.
3. Point `src/core/art.lua` at the new animation ids (`TILES`, `ACTORS`, `FX`, `ELEMENT_ICONS`); set `ENABLED = true` for player/enemy sprites.
4. Add credits to `CREDITS.md` and `src/core/credits.lua`.
5. Validate: `python tools/validate_rooms.py`, `python tools/run_smoke_test.py` (and with `ART_TEST=1`), then ask the human to reload the editor, run, and paste the console.

Suggested packs (CC0): Kenney **Tiny Dungeon** (tiles, props) and **Tiny Creatures** (player, enemies, elementals).
