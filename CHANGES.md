# Audio / reactions / juice — P6: elemental reactions
- `src/core/reactions.lua`: data-driven reactions (Steam Burst, Shatter, Flare-up, Bog, Whirl) with per-enemy cooldowns, `check`/`update`/`consume`/`by_id` helpers.
- `main/game.script`: `apply_reaction` wired into `apply_hit` (before hit's own statuses); burn dps multiplier for Flare-up; spread radius for Flare-up; Bog converts slow to root; Whirl knockback + confuse; Steam Burst AoE; Shatter bonus damage. Reaction cooldowns ticked in enemy update.
- Smoke test: 0 errors, all P3/P4/P5 audio assertions pass.

# Audio / reactions / juice — P5: adaptive music
- `src/core/music.lua`: state-driven stem mixing (TITLE/ROOM/BOSS/CAULDRON/REWARD/WIN/DEAD), intensity-based stem gains with 0.8s fade, boss loop, stings.
- `main/game.script`: `music.set_state` on all state transitions, `music.update(dt)` in update, `music.set_intensity` tracks live enemy count.
- Smoke test: mus_title, mus_room_pad, mus_win, mus_dead all play.

# Audio / reactions / juice — P4: world audio
- `main/game.script`: player sounds (pl_hurt, pl_dash, pl_lowhp heartbeat, pl_heal, pl_die), enemy sounds (en_spawn, en_die, en_splitter_pop, en_charge_windup, en_charge, en_wall_stun, en_slinger_shot, en_brute_stomp, boss_roar/ring/charge/summon/die), UI/flow sounds (ui_pick, ui_click, ui_card, ui_craft, ui_craft_bad, ui_hover, ui_cauldron_loop, room_clear, state_title/win/dead).
- Event listeners: player_hit, dash, enemy_spawn, kill, room_clear all wired to audio.
- Smoke test: all world/UI sounds verified as played at least once.

# Audio / reactions / juice — P2: audio plumbing + 89 placeholder sounds
- `src/core/sfx.lua`: complete id manifest with per-id gain/min-gap/max-voices/pitch/loop/bus, injected backend, 16-voice global cap, pan and semitone pitch, high-level `cast`/`hit`/`status`/`quirk`/`loop_set` helpers.
- `src/core/crng.lua`: cosmetic-only RNG so pitch wobble never shifts gameplay determinism.
- `tools/make_sfx.py` (stdlib only): deterministic mono 16-bit 22050 Hz WAVs for every id, 5 ms fades, idempotent, `--force`; also rewrites `assets/sfx/SFX_MAP.md`.
- `tools/add_sounds.py`: scans `assets/sfx` + `assets/music`, prefers `.ogg`, writes `.sound` resources and regenerates `main/sfx.go`; idempotent.
- `main/sfx.go` (89 components), `sfx` instance in `main/main.collection`, additive `[sound]` limits in `game.project` (max data 128, instances 64, component count 128).
- `game.script`: injects `sound.play/stop/set_gain`, runs `sfx.update(dt)`, stops loops in `clear_world`; DEBUG audition keys `O`/`P` (previous/next), `L` (play), `K` (slot-1 cast layers).
- Smoke test: 89 ids have files + map rows, all 50 casts produce shape + element-A + signature at the exact skill pitch, hit throttle, disabled/unknown id, loop start/stop. `SFX_TEST=1` adds a missing id and must FAIL.
- Results unchanged from P1: 323 -> 323 live, 0 errors, rooms 10/0, anim 68,042/0, compile success. Mock only for playback.

# Audio / reactions / juice — P1: one choke point for hits
- New `src/game/events.lua`: synchronous event bus (`on`/`off`/`clear`/`emit`/`count`) with no listeners registered yet.
- `main/game.script`: `apply_hit` now handles all six delivery paths (bolt, puddle, orbit, cone, burst, delayed Nova echo) and burn ticks. It deliberately preserves the old quirks: the echo has no knockback, puddle/orbit ticks have no hit FX, burn ticks are silent.
- `src/core/status.lua`: `apply` returns the statuses that were newly applied (existing callers ignore it; audio will use it to avoid tick spam).
- Hooks emitted: `cast`, `hit`, `status`, `quirk`, `kill` (now carries the enemy), `player_hit`, `dash`, `room_clear`, `enemy_spawn`.
- `tools/smoke_test.lua`: asserts every hook fires at least once; `EVENT_TEST=1` adds a bogus hook and must FAIL, proving the check is live.
- Results unchanged from P0: live 323 -> 323, max 551, 0 errors, 0 wall clipping, rooms 10/0, anim 68,042/0, compile success. Mock only.

# Docs (v8)
- `AGENTS.md`: items 44-48 (render constants, test-vs-game, skipped DoD/licence TODOs, unverified letterbox assumptions, deleted deliveries), item 1 corrected for nested atlas animations, DoD item 8 added.
- `README.md`: §5.5 note, §13.1 row, §13.4 rows, new §13.5 (animated effects + letterboxing).

# Render script fix (v7)
- `letterbox.render_script` crashed every frame on Defold 1.14 (`render.STATE_DEPTH_TEST` is nil there; the constants moved
  to `graphics.*`). Every state/blend constant now resolves `graphics.X` first, then `render.X`.

# Resolution fix (v6)

- New `main/letterbox.render` + `letterbox.render_script`, set in `game.project` `[bootstrap] render`. The world is drawn
  into the largest centred 960x640 rectangle that fits the window (black bars, no stretching), at any size or maximised.
- Mouse aim is converted from window space to design space (`to_design` in `game.script`); HUD button clicks use a
  design-space rectangle test instead of `gui.pick_node`.
- Not verified here: needs a run in Defold. If aim is offset, tell me which window size; if buttons misalign, tell me which.

# Animated skill effects (v5)

- New `tools/build_fx_anim.py` (reads `downloads/`, writes `assets/art/fxa/`, the `fxa_*` animation blocks in
  `shapes.atlas`, generated `src/core/fxanim.lua`, and `docs/fx_anim_preview.png`). Re-run it after editing `COMPOUNDS`.
- Every compound has its own effect family per shape, drawn in its two elements' colours (fire orange, water blue,
  wind white, earth tan). A = alphabetically first element, B = second.
  - **Bolt**: looping flame head (A), B-coloured sparkles shed along the path, animated impact (B).
  - **Pool**: the compound's magic-circle effect pulses every 0.6 s, alternating A/B.
  - **Orbit**: orbs are flames alternating A/B, with B sparkles.
  - **Spray**: directional sweep rotated onto the aim (A + B layers).
  - **Nova**: large A burst with a smaller counter-rotated B burst inside.
  - Every cast also plays a small swirl at the caster. Steam, Mist, Dust and Mud add alpha-blended smoke puffs.
- `game.script`: `anim_fx` / `smoke_puff` / `flame_make` helpers, `self.anims` (cap 90, cleaned in `clear_world`).
  `fx_hit` and `fx_cast` take the skill. Old particles are kept underneath. `art.ANIM_FX = false` disables it all.
- `smoke_test.lua`: parses atlas animation ids; new coverage pass casts all 50 skills and asserts each plays its own
  effects, every generated animation exists in the atlas, and no two compounds share an effect set.
  Result: PASS, 0 errors, 323 -> 323 live objects, max 51 live one-shot anims.
- Not verified here: loading in the Defold editor and how it looks on screen (no engine available).

# Art pass v4 — Phase 4 (spell art)

## 6.1 Skills describe their elements
- `skillgen.makeSkill` now returns `elements = { a, b }` (the two element names, sorted) and `shape_key`
  (the internal shape key, e.g. `projectile`). Generation order is untouched — the golden vectors still pass
  (`SELFCHECK OK`). `selfcheck.lua` now also asserts the two new fields.

## 6.2 New element FX sprites (`assets/art/fx/`, 64 px, white-on-alpha)
- New `tools/whiten_sprite.py` implements the spec's exact algorithm (lum×alpha, halo floor, 98th-percentile
  normalise, gamma 0.75). Inputs from the Kenney Particle Pack, originals untouched:
  `fx_flame`←flame_05, `fx_scorch`←scorch_01, `fx_spark`←star_06, `fx_splash`←light_02, `fx_bubble`←circle_03,
  `fx_streak`←scratch_01, `fx_swirl`←twirl_03, `fx_debris`←dirt_02.
- `fx_drop`←generated droplet (`tools/make_drop.py`, original art; the pack has no droplet). First attempt
  rendered as a broken "padlock" shape and was rewritten as a single silhouette + derived halo.
- All nine were viewed tinted fire/water/wind/earth/white on near-black before acceptance: all clearly visible.
- All nine added to `shapes.atlas` via `tools/add_to_atlas.py` (50 images total).

## 6.3 Per-element effect styles
- `art.lua` gained `ELEMENT_FX` (fire/water/wind/earth × trail/hit/rise/spoke) + `ELEMENT_FALLBACK`.
- `game.script`: **Bolt** — trail particles use element A's `trail` (rotated onto the flight direction for the
  wind streak), wall/enemy hit burst uses element B's `hit`; **Pool** — rising embers/bubbles use A's `rise`,
  drifting upward; **Orbit** — sparks use A's `trail`; **Spray (cone)** — the fan alternates A's and B's trail
  sprites; **Nova** — spokes use B's `spoke`. `spawn_particle` gained an optional `rot`; `fx_hit` gained an
  optional `hit_art`. Sizes, counts, caps and the skill-colour tinting are unchanged. Bolt heads stay radially
  symmetric circles; directional read comes from the rotated wind streaks.
- Bolt trail and spray streaks rotate onto the aim direction (cosmetic only, `go.set_rotation`).

## 6.4 Element icons: game-icons.net set KEPT (user preference)
- First pass generated CC0 silhouettes from the FX art (`tools/make_silhouette.py`: `icon_fire`←`fx_flame`,
  `icon_water`←`fx_drop`, `icon_wind`←`fx_streak`, `icon_earth`←`fx_debris`). After seeing them, the user
  preferred the previous icons, so those four were restored **in place** from the official white-on-transparent
  PNG archive (resized 512→64 LANCZOS, same ids): `icon_fire`←sbed/fire, `icon_water`←lorc/drop,
  `icon_wind`←lorc/air-zigzag, `icon_earth`←lorc/rock. They are CC BY 3.0, credited in `CREDITS.md`/`credits.lua`.
- `tools/make_silhouette.py` is kept but unused (documented by this note).

## 6.5 Shape glyphs: skipped
- Needs hand-written `main/hud.gui` node edits (skill cards carry only element dots); the spec permits skipping.

## DEBUG row enabled for skill testing (user request)
- `src/core/data.lua`: `TUNING.DEBUG = true` — enables keys 1-5 (slot 1 shape) and Q/E (cycle slot 1/2 compound).
  Input bindings already exist. **Set back to `false` for release builds.**

## Tests / verification
- Smoke test + `ART_TEST=1` / `ART_TEST=0`: PASS, 0 errors (mock only). Anim test 68,042/0. Rooms 9/0.
- `skillgen` selfcheck: OK (golden vectors unchanged). All atlas ids referenced by code exist.
- Editor `/command/compile`: `{"success":true,"issues":[]}`. **Not verified:** rendering/blending/z-order/filters —
  human checkpoint required. A Project → Reload is needed (atlas and in-place icon files changed).
- **Not verified:** whether the wind-streak trail rotation reads well in motion; spray fan mix; per-palette
  readability on all nine room palettes during combat.

---

# New downloaded effect packs → fire + wind spell FX

## What was used
- Surveyed the 8 packs in `downloads/` and extracted them to `defold_downloads/effects_packs/`.
- **Usable (license on disk):**
  - `pixel_fire_asset_pack` (devkidd) — free for personal/commercial, attribution appreciated.
  - `pixel_holy_effects_pack01` (Sentient Dream Studio) — free for personal/commercial, attribution appreciated.
- **NOT used (no license file on disk; AGENTS.md requires CC0/CC BY):** `Effect and Bullet 16x16`,
  `Effect and FX Pixel All Free`, `Free Smoke Fx Pixel 2`, `Pixel Holy Spell Effect 32x32 Pack 3`, `RPG Effect All Free`.
  Web search was unavailable (HTTP 402), so their licenses could not be confirmed.

## Implementation (replaces the Kenney art behind the same atlas ids)
- **Fire** (`fx_flame`, `fx_scorch`, `fx_spark`) ← devkidd Pixel fire asset pack, white variant, frames
  Group 4-1 / 6-1 / 7-1, whitened to white-on-alpha (`tools/whiten_sprite.py`, 64 px).
- **Wind** (`fx_streak`, `fx_swirl`) ← Sentient Dream Studio Pixel Holy Effects Pack 01
  (`HolySlash_C_02`, `HeavensFury_04` — picked by measured alpha coverage because animation frame 01 is nearly
  empty in most of these packs). Whitened to white-on-alpha.
- **Water** (`fx_drop`, `fx_splash`, `fx_bubble`) and **earth** (`fx_debris`) stay on the Kenney Particle Pack art.
- `ELEMENT_FX` ids are unchanged, so `game.script`/`art.lua` needed no code change; old art backed up to
  `defold_downloads/effects_packs/kenney_fx_backup/` and is regenerable from the Kenney pack anyway.
- `CREDITS.md` + `credits.lua` gained the two new packs (plus a per-sprite provenance note).

## Verification
- New sprites measured: 24–43 % alpha coverage, pure white (tintable), streaks/swirls no longer near-empty.
- Smoke / ART_TEST=1 / ART_TEST=0: PASS, 0 errors. Anim 68,042/0. Rooms 10/0. Editor compile `{"success":true,"issues":[]}`.
- **Not verified:** how the new fire/wind FX read in motion and on every palette — human checkpoint required.
  **Not used:** the five unlicensed packs (need license confirmation).

# Training Arena + dummy enemy (practice target for skill testing)

- New room 10 **Training Arena** (`src/levels/rooms.lua`): three `d` dummies and pillars, wide open floor.
  Validates: `10 room(s), 0 problem(s)`.
- New enemy type **`dummy`** (`src/game/enemies.lua`): HP 9999 (inert; `immortal = true`), speed 0 (never moves),
  contact damage 0 (never harms you). `src/game/combat.lua apply_damage` honours `immortal` — HP never drops,
  but `flash_timer` and the hit scale-pop still fire so you get full feedback for testing combos.
- Dummy spawns use the new **`target_dummy`** bullseye sprite (`assets/art/actors/target_dummy.png`, generated by
  `tools/make_target.py` — original art, no credit needed), registered in `shapes.atlas` and
  `art.ACTORS.dummy` (scale 3). Normal enemies are untouched.
- New room/legend key **`d`** (`src/game/level.lua`; `validate_rooms.py` updated).
- **`T`** (debug key, `TUNING.DEBUG`) toggles the Training Arena: press `T` to jump in from anywhere, `T` again to
  return to the title screen (`reset_run`). Input binding added.
- Contact-damage block in `game.script` now skips zero-damage enemies entirely (fixes "dummy touches player → HP 100 spam + flash").
- Smoke-test pathing stays on rooms 1-9 (dummies never move, so they would fail the "reached" assertion); the dummy
  mechanics were verified with a throwaway harness: room parses, 3 dummies spawn, `apply_damage(99999)` returns false
  and keeps HP at 9999, wisp still dies normally, `target_dummy` is in the atlas, art manifest resolves.
- Editor `/command/compile`: `{"success":true,"issues":[]}`. Rooms valid, smoke/anim suites pass (mock only).
- Confirmed in the running game by the human: Training Arena works — dummies take full hit feedback and never die.
- **Debug key list (DEBUG on):** 1-5 slot-1 shape, Q/E cycle slot 1/2 compounds, T training arena toggle.

# Fix pass: obstacle visibility

## Root cause
The floor and walls used the **same grey-blue brick texture** (tiles 36/38/40/14/39 from Kenney Tiny Dungeon), so
walls were invisible against the floor — the only cue was the 2 px blue accent line on `wall_face` cells. `wall_top`
cells (stacked walls) had no cue at all, so they were effectively invisible.

## Fix
- Replaced `td_floor_a`/`td_floor_b` (grey brick, tiles 36/38) with Kenney's actual **warm-tan floor** tiles
  (tiles 48/49). Floors are now warm tan tinted by the room palette; walls stay grey-blue brick, so the two read
  as distinct materials at a glance.
- Updated `assets/art/actors/MAPPING.md` (floor_a → tile 48, floor_b → tile 49) and regenerated
  `docs/art_preview.png`.
- `KIND_TINT` left unchanged (floor 0.90 / wall_face 0.75 / wall_top 0.50 / pillar 1.00); the contrast now comes
  from the art itself, not just the multiplier.

## Tests
- Smoke test + ART_TEST=1/0: PASS (mock only), 0 errors.
- Editor `/command/compile`: `{"success":true,"issues":[]}`.
- Confirmed in the running game by the human: warm-tan floor vs grey-blue brick walls — obstacles now read clearly.

## Art in the game
- Player is the purple wizard from Kenney Tiny Dungeon (`td_player`, 16 px art at scale 3); enemies are six Tiny
  Creatures sprites (wisp, slinger, charger, brute, splitter, boss) cut out of the packed sheet and trimmed with
  `tools/cutout_sprite.py`. Mapping: `assets/art/actors/MAPPING.md`.
- Environment tiles switched to Tiny Dungeon (`td_floor_a/b`, `td_wall_face/top`, `td_pillar`, `td_torch`) at scale 3
  with higher palette multipliers (`KIND_TINT` floor 0.90 / wall_face 0.75 / wall_top 0.50 / pillar 1.00) so the
  textured tiles read on the dark floor.
- New `src/game/anim.lua` (pure, unit-tested): idle bob, run squash, dash stretch + lean, per-enemy motion
  (wisp float, slinger recoil/retreat, charger wind-up shake + charge lean, brute stomp, splitter jelly, boss
  breathing + pre-attack swell). It only ever changes sprite scale, sprite offset and rotation.
- Facing: `faces` in the manifest is honoured (`"right"` today; `"left"` starts mirrored). The mirror is applied with
  `sprite.set_hflip` — **never** a negative scale component (see the fixed bug below).
- Pixel-perfect: `[graphics] default_texture_min_filter/mag_filter = nearest` in `game.project` (needs an editor
  restart to take effect).
- Hit flash still pops (folded into `base_scale * anim * hit_pop`) and restores on every spawn path, including
  splitter children and boss summons.

## Fixed at checkpoint 5.5
- **Per-frame `Vector passed to go.set_scale contains components that are below or equal to zero` (game.script:269).**
  Facing was implemented by multiplying the x scale by `-1`; Defold 1.14 rejects any scale component `<= 0`, so the
  error flooded the console whenever the player aimed left (and `sync_enemy_visual` did the same whenever an enemy was
  to the player's right). Both now call `sprite.set_hflip(url, mirror)` and keep the scale strictly positive; the
  rotation still takes the `-1` so the lean points the right way after mirroring. The mirror is cached per actor
  (`self.player_mirror`, `e.mirror`) and initialised on both spawn paths.
- `tools/smoke_test.lua` now fails on a non-positive `go.set_scale` component and stubs `sprite.set_hflip` (validating
  the url and the boolean), so this class of bug is caught headlessly. It also counts both mirror directions and the
  runner asserts both occurred (516 mirrored / 683 normal in the reference run).

## Tests / tooling
- New `tools/test_anim.lua` + `tools/run_anim_test.py` (68,042 checks: no NaN, scales 0.5-1.6, deterministic,
  spec values such as dash 1.30/0.80 and brute stomp y≈0.9).
- `tools/smoke_test.lua` now reads the valid animation ids from `assets/art/shapes.atlas`, asserts every
  `art.ACTORS[*].anim` exists, and supports `ART_TEST=0` for the shape fallback (previously `ART_TEST=1` faked art
  with circles).
- Reference run after the fix: smoke / `ART_TEST=1` / `ART_TEST=0` all `PASS (mock only)`, 0 errors, baseline 323 = after
  323, max 503 sprites, 0 wall clipping; anim 68,042/0; rooms 9/0 problems; editor `/command/compile`
  `{"success":true,"issues":[]}`.
- **Not verified here:** rendering, blending, z-order, texture-filter appearance and the editor's file parsing — the
  human must confirm in the running game.

---

# Fix pass: visuals + feel

## Why the particles did not render
1. The Kenney PNGs were dim grey with low alpha (avg brightness ~0.2). Tinting them with a colour on a near-black floor made them invisible. They are now white with boosted alpha.
2. They were drawn at 10-30 px, with normal alpha blending. Glows now use an additive sprite (`main/fx.*`) and are 40-200 px.
3. The projectile head used a thin lens-flare sprite as a "ball". It is now a bright core + soft glow orb + a spark trail.

## Environment
Stone-tile floor with per-room colour palette (9 palettes), dark frame with glowing inner edge, flickering corner torches, rotating centre sigil, drifting motes, vignette. Removed the stray (6,5) offset on visual.go.

## Feel / fun
- Hold the mouse button to keep casting (cooldown-gated). SPACE dash (invulnerable, afterimages).
- Reticle at the aim point + wand tip glow, player glow takes the slot-1 skill colour, blink while invulnerable.
- Hit sparks, kill rings + stars, Nova ring + spokes, Spray particle fan, Pool bubbles, Orbit sparks.
- Enemies push each other apart (no more single blob). Slingers keep their distance. Chargers wind up (pulse) before dashing. Charger = diamond, Brute = square.
- 8 rooms + boss (was 4 + boss). Room n spends 3+2n points; newest enemy always appears. +25 HP when a room is cleared.
- Bugs fixed: enemies stayed red after the first hit; enemies lost their colour after a status ended; telegraph/ring double delete; burst visuals leaked on reset; delayed Nova echo created visuals after the room ended; DEBUG keys off (TUNING.DEBUG).

## Tuning knobs (src/core/data.lua)
ROOM_COUNT, DASH_SPEED, DASH_TIME, DASH_COOLDOWN, HEAL_ON_CLEAR, DEBUG.

---
# Level pass
- 9 authored rooms (`src/levels/rooms.lua`), 20x13 tile grid (48px), two enemy waves per room.
- Walls and pillars block the player, dash, enemies, bolts and puddles (`src/game/level.lua`).
- Enemies path around walls (line-of-sight + BFS flow field). Chargers that slam into a wall are stunned.
- Per-room palettes; wall faces get a glowing accent line; wall torches flicker.
- `src/core/art.lua` manifest + `tools/add_to_atlas.py` + `tools/slice_sheet.py` + `docs/ART_GUIDE.md` for real art.
- Fixes: telegraph ring double delete, room-clear timer reset, slingers only hold distance with a clear line.

---
# Docs + tooling pass (2026-11-10)
- `AGENTS.md`: added Part B (assistant mistakes 23-37), Definition of Done, asset quick reference; reorganised into Parts A/B/C.
- `README.md`: corrected the atlas section, added capacity limits, additive sprite, smoke test, failure modes 15-26, and section 13 (asset pipeline).
- `src/core/art.lua` is now the single source of art ids: `FX` roles and `ELEMENT_ICONS` (HUD and `data.ART` read from it); player art + facing supported.
- Fixed: splitter children / boss summons used the wrong scale after a hit flash (`spawn_wisp_at` now sets `base_scale`).
- New tools: `tools/validate_rooms.py`, `tools/run_smoke_test.py` (wraps `tools/smoke_test.lua`; modes: default, `ART_TEST=1`, `SPRITE_MAX=n`).
