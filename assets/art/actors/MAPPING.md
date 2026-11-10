# Actor and environment sprite mapping

Chosen from the packs listed in `assets/third_party/`. "Index" is the cell
number in `docs/sprite_picker_<pack>.png` (the number drawn under the sprite).
Facing: these packs draw front-facing characters; the game mirrors the sprite
with the x scale so `faces = "right"` is used for all of them, and mirroring is
purely cosmetic (the sprites are symmetric).

## Actors (`assets/art/actors/`)

| Role | Pack | Index | Project file | Atlas id | Faces | Scale | Source cell |
| --- | --- | --- | --- | --- | --- | --- | --- |
| player   | Kenney Tiny Dungeon | 84  | `td_player.png`   | `td_player`   | right | 3 | `Tiles/tile_0084.png` (purple wizard) |
| wisp     | Tiny Creatures      | 43  | `tc_wisp.png`     | `tc_wisp`     | right | 2 | `Tilemap/tilemap_packed.png` cell 43 (white ghost) |
| slinger  | Tiny Creatures      | 67  | `tc_slinger.png`  | `tc_slinger`  | right | 2 | cell 67 (robed caster with staff) |
| charger  | Tiny Creatures      | 20  | `tc_charger.png`  | `tc_charger`  | right | 2 | cell 20 (brown boar) |
| brute    | Tiny Creatures      | 127 | `tc_brute.png`    | `tc_brute`    | right | 3 | cell 127 (grey stone golem) |
| splitter | Tiny Creatures      | 46  | `tc_splitter.png` | `tc_splitter` | right | 2 | cell 46 (blue slime) |
| boss     | Tiny Creatures      | 31  | `tc_boss.png`     | `tc_boss`     | right | 5 | cell 31 (blue dragon) |

**Why the packed sheet and not `Tiles/tile_XXXX.png`:** the individual Tiny
Creatures PNGs are exported with an opaque maroon frame + dark backdrop (they
are map tiles, not cut-outs). `Tilemap/tilemap_packed.png` has the same RGB
pixels with an alpha channel, and `tools/cutout_sprite.py` removes the frame and
backdrop (`--bg 63,38,49 --bg 0,0,0 --bg 82,96,124 --flood`). Index mapping is
row-major, 10 columns, cell `i` = column `i % 10`, row `i // 10`; cell `i`
corresponds to `Tiles/tile_(i+1).png` (verified pixel-for-pixel).

## Environment (`assets/art/env/`)

| Role | Pack | Index | Project file | Atlas id | Tint | Scale |
| --- | --- | --- | --- | --- | --- | --- |
| floor_a   | Kenney Tiny Dungeon | 48 | `td_floor_a.png`   | `td_floor_a`   | yes (room palette) | 3 (16px -> 48px) |
| floor_b   | Kenney Tiny Dungeon | 49 | `td_floor_b.png`   | `td_floor_b`   | yes | 3 |
| wall_face | Kenney Tiny Dungeon | 40 | `td_wall_face.png` | `td_wall_face` | yes | 3 |
| wall_top  | Kenney Tiny Dungeon | 14 | `td_wall_top.png`  | `td_wall_top`  | yes | 3 |
| pillar    | Kenney Tiny Dungeon | 39 | `td_pillar.png`    | `td_pillar`    | yes | 3 |
| torch     | Kenney Tiny Dungeon | 29 | `td_torch.png`     | `td_torch`     | no (coloured art) | 3 |

The floor tiles are now warm tan (Kenney's actual floor art, tiles 48-49) so they read
distinctly against the grey-blue wall tiles; the per-room palette still recolours them
(`art.TILES.*.tint = true`). The torch is drawn in its own warm colours
(`tint = false`); the flickering light is a separate additive glow.

The previous generated placeholder tiles (`tile_floor_a` … `tile_torch`) stay in
`assets/art/tiles/` and in the atlas as a known-good fallback; they are not
drawn when `M.TILES` points at the `td_*` ids.

## Preview

`docs/art_preview.png` (regenerate with `python tools/preview_art.py`) shows the
tinted tiles plus every actor at its in-game scale on the real dark background.
