# Pool infusion (v10)

Plan: `universal_pool_spell_infusion_addendum.md` (v2). Every active **Pool** infuses every
non-Pool spell (Bolt, Orbit, Spray, Nova) that overlaps it. An infused spell keeps its own
statuses, additionally applies the Pool's statuses, and deals **×1.25** damage per hit/tick,
once per hit. Pool-to-Pool out of scope. Fire Cyclone / a Combos screen were **not** built
(separate task, unapproved). No new art.

## One resolver, four deliveries
- `src/game/infusion.lua` (new): `eligible` (alive, `duration > 0`, not a trail patch, has a
  `skill_ref`), `circle_hits_pool`, `segment_hits_pool` (a frame hitch cannot skip a Pool),
  `sector_hits_pool` (asin(r/d) slack near the arc corners), `touch` / `release` / `active`
  (per-spell record keyed by the Pool table), `merge_statuses` (native first, then entries in
  entry order; `on_player` and unknown names dropped; new array), `damage(base, infused)`.
- `data.INTERACT`: `INFUSE_DAMAGE_MUL = 1.25`, `INFUSE_GRACE = 1.0` (Bolt and Orbit orbs only).
- `apply_hit` gained ONE optional trailing `infusion` parameter — the only place the ×1.25
  is applied. Callers without it behave exactly as before.
- Spray: sector-vs-Pool at cast, once per cone (split casts independently); Nova: circle-vs-Pool
  at each burst's own resolution moment — the delayed split re-tests the live Pools with its
  0.72× radius; Orbit: per-frame segment test per orb (orbs outrun a Bolt), grace per orb,
  record lives on the orb entry; Bolt: per-frame segment test (never the 0.15 s ticker).
- Visuals: one small deterministic `spawn_particle` fan per infusion start in the newest live
  Pool's colour — never the capped flipbook path (`anim_fx` / ANIM_CAP 90). Bolts and orbs tint
  head/glow/flame toward the Pool colour and restore base tints when the record empties.

## Decisions (fixed)
- `spread` passes through unchanged: an Ember Pool chain-ignites through any infused spell.
- `push` beats `pull` (a Gale Pool over a Tide spell wins the knockback). Documented, not fixed.
- Same-compound infusion allowed: no new status, still ×1.25.
- Standing in your own Pool is intended — no guard against it.
- Fire Cyclone / `spread_fire_area` / Burning Mud / Dense Cloud: untouched.

## Tests
- 742 spellcraft checks (the v9 baseline was 285) — 0 failed, 0 errors, live objects 323 → 323,
  wall clipping 0, max live one-shot anims 90/90 (cap). `ART_TEST=1` and `ART_TEST=0` PASS.
- 40-cell matrix (10 Pool compounds × Bolt/Orbit/Spray/Nova), table-driven, driven through
  `do_cast` + the update loop, with a control room per cell: merged-status union, exactly one
  ×1.25, `hide_self` never on an enemy. No cell is module-level only.
- Grace lifecycle (real path and module contract), per-orb records, Orbital Crown's extra orb,
  split_in_two orbit independence, leaves-a-trail orbit stays at base damage, Ancient Catalyst
  scales merged statuses, accent fires once per continuous infusion and never through the cap,
  Ancient Catalyst / push>pull / Mist-hide_self rows covered.
- Fail-proofs shown: `INFUSE_DAMAGE_MUL=1.0` fails exactly the 3 infusion damage checks;
  `INFUSE_GRACE=1000` fails the 4 grace-boundary checks; `segment_hits_pool → false` fails 98
  Bolt/Orbit/matrix cells; `sector_hits_pool → true` fails the 5 Spray sector checks;
  `circle_hits_pool → false` fails the 8 Nova checks.

## Bugs fixed on the way
- The infusion accent called `spawn_particle`, whose 260-particle soft cap silently dropped every
  accent particle at a full budget — and the old smoke test asserted the `infused_visual` flag,
  which is set before dispatch, so it passed anyway. `infusion_accent` now inserts directly
  (same `fx_make` + `self.particles` entry) with its own ceiling of 24 live accent particles,
  counted via an `accent` flag on the entry; `spawn_particle` is unchanged for everything else.
  New test fills `self.particles` to 260 and asserts the accent entries exist (Bolt/Spray/Nova/
  Orbit) plus the 24-particle ceiling under six infusions. Fail-proofed by reverting the fix.
- Smoke count audit: 285 baseline -> 742 (+39 B, +18 B+, +27 C, +48 D, +321 matrix); no earlier
  check was deleted or duplicated (1000 insertions, 0 deletions in the harness).
- Definition of Done item 1 was deleted and restored in the v10 doc edit (AGENTS items 43/54).

## Delivery
`Defold Games v10.zip` (in the project folder, next to `Defold Games.zip` — never overwritten).

# Spellcraft core — quirks, interactions, relics (v9)

Plan: `spellcraft_implementation_plan.md`, phases 0-5. No new elements, compounds, shapes, statuses
or relic types; Beam/Trap/Chain were **not** added (optional checkpoint, declined — scope frozen at
the five existing shapes).
Determinism preserved: recipe key, RNG call order and quirk order are unchanged, so every existing
recipe still gets the same power and quirk (`SELFCHECK OK`).

## Quirks are now real, tuned effects (`src/core/data.lua`, `src/core/skillgen.lua`)
- `QUIRK_IDS` / `QUIRK_DATA` hold every tuning number. Generated skills carry `quirk_id`; the `quirk`
  display text is unchanged.
- **Splits in two:** 2 instances at 60% strength. Bolt ±15°, pool at 60% offset / 72% radius, two
  orbits with different radii, two sweeps, burst spawns a second smaller burst after 0.3 s.
- **Leaves a trail:** short-lived patches (0.9 s, r 18, 50% power, cap 24). Bolt every 0.14 s, orbit
  every 0.5 s, pool drops 3 patches, cone/burst drop 1.
- **Repeats once:** one extra execution of the original cast after 0.25 s. Repeats never schedule
  repeats, never start a cooldown and never pay health.
- **Bigger but slower:** size ×1.30, spell delivery speed ×0.80, pool tick ×1.25. Cooldown and the
  player's own movement speed are untouched (the old ×1.5 cooldown is gone).
- **Costs 5% health:** ×1.5 power, paid once per successful player cast, refuses to cast below 1 HP
  (no cooldown, no health change), never charged for repeats or the Echo echo.

## Statuses + damage go through one path (`main/game.script`, `src/game/combat.lua`)
- `apply_statuses` and `apply_hit` are used by all five shapes, so every delivery applies the same
  damage → status → knockback trio, and knockback reads the hit's own status list.
- `status.apply(target, names, 0, duration_mul)`; `combat.new_puddle` copies the status list.
- `hide_self` (Mist) still targets the caster; repeated ticks refresh, never stack.

## Environmental interactions (`data.INTERACT`, `game.script`)
- Fire over Mud → **Burning Mud** for 3 s, then reverts; ignites once per pool (`pud.mud_ignited`).
- Wind over a fire pool → one spread pool (60% duration/strength, 80% radius), once per source pool.
- Steam + Dust → **Dense Cloud** (r 80, 2 s) that blinds and confuses inside it; ≤6 clouds.
- Areas: ≤40, aged on a 0.15 s ticker (never per frame); bolts check overlaps too.
- Interaction/area positions pass through `level_mod.free_point_near`, so nothing lands in a wall.

## Relics (`src/core/relics.lua`, reward flow, HUD)
- Inferno Heart (+15% fire power), Echoing Crystal (every 5th player cast echoes at 50%),
  Ancient Catalyst (+20% status duration), Orbital Crown (orbit +1 orb).
- At most one relic per reward screen, never a duplicate of one owned. HUD shows the relic label on
  the card and a relic line in the inventory. Relics reset with the run and never affect generation.

## Dev tools (kept on purpose: `TUNING.DEBUG` is still true)
- Keys **1-5** set slot 1's shape (bolt / pool / orbit / spray / nova), keys **6-0** set slot 2's
  shape in the same order; `Q` cycles slot 1's compound, `E` cycles slot 2's, `T` opens the
  Training Arena. All ten keys are bound in `input/game.input_binding` and covered by the smoke test.

## Bugs fixed on the way
- Interactions were only readable in the console (`print`), which failed the plan's "readable in
  combat" check. Added `announce()`: a 1.4 s HUD banner on the existing `help_text` node, an
  expanding ring + sparks at the interaction point, a flame streak for fire spread, and a brighter
  Dense Cloud. Smoke test now asserts the banner text for all three.
- Burning Mud re-ignited itself while the fire area lived (loop) → `pud.mud_ignited`.
- Splitter children / boss summons could spawn stuck inside walls → `free_point_near` in
  `spawn_wisp_at`.
- Trail puddles no longer carry `pud.color`, so 20+ trails do not drain gameplay RNG or stream embers.

## Tests
- `python tools/run_smoke_test.py` → **PASS**: spellcraft **266 checks passed, 0 failed**, 0 errors,
  live objects 323 → 323, wall clipping 0, max live one-shot anims 90/90.
  `ART_TEST=1` → PASS (flips 807/1455). `ART_TEST=0` → PASS (flips 0/0).
- New coverage: 50 combinations' fields; 10×5 compound-status matrix; 25 quirk/shape cells; health
  cost edges; each relic alone + Echo/repeat/health interactions; relic pick + reset; reward-screen
  invariants; Burning Mud / fire spread / Dense Cloud; wall boundaries; area/cloud caps; reset cleanup.
- `python tools/validate_rooms.py` → 10 rooms, 0 problems. `python tools/run_anim_test.py` → 68042
  checks, 0 failures. Editor compile endpoint → `{"success":true,"issues":[]}`.
- **Not verified:** rendering, blending, z-order, editor parsing of the new flow, and how the
  interactions/relics *feel* in play. The mock proves logic only. Max live one-shot anims sits at the
  90 cap; extras are skipped safely, so a heavier effect pass would need the cap raised.
- Dev tools kept: `TUNING.DEBUG` still true (1-5 / Q / E skill row, T for the training arena).

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
