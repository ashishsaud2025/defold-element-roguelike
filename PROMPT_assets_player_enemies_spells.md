# PROMPT: Download and implement player, enemy and spell art (Defold element roguelike)

> Paste this whole file into your coding agent as one message. The project is the Defold game in the current folder
> (Defold 1.14.0, Windows, PowerShell). You have network access; the human runs the Defold editor.

---

## 0. Mission

Replace the placeholder circles/squares with real, **properly credited, openly licensed** art, and make it feel good:

1. **Download the art packs yourself** (section 3), verify their licenses, record sources and credits.
2. **Player and enemy sprites** (section 5) with code-driven animation (the packs are static sprites).
3. **Spell art** (section 6): per-element effects, directional bolts, element icons for the HUD.
4. Keep the game fully playable at every step. `art.ENABLED = false` must still give the old shapes.

You are **done** only when section 9 (Definition of Done) passes and the human has confirmed in the running game.

---

## 1. Read first (mandatory, before touching anything)

1. `AGENTS.md` - **every item.** Part A is mistakes already made by a previous agent, Part B is mistakes made by the assistant that
   wrote the earlier prompts and patches. Do not repeat any of them. Where `README.md` and `AGENTS.md` disagree, `AGENTS.md` wins.
2. `README.md` sections 0, 5.5 (atlas), 9 (failure modes) and **13 (adding art and assets)**.
3. `src/core/art.lua` (the manifest), `src/core/data.lua` (`TUNING`, `ART`), `src/game/enemies.lua` (enemy ids and radii),
   `src/core/skillgen.lua`, `src/core/credits.lua`, `CREDITS.md`, `main/game.script` (search for `art_mod`, `FX.`, `fx_make`, `spawn_particle`, `sync_player`).

### Non-negotiables (these exist because they already broke the project)
- Lua 5.1 only: no `goto`, no `//`, no bit operators (use the `bit` module). No Defold physics. No tilemap component.
- You **cannot run the game**. The human does. After each phase stop, give them a test checklist, and read the **first** console error, not the flood after it.
- Atlas: **no `animations { }` blocks.** Add images only with `python tools/add_to_atlas.py "<glob>"`. Animation id = image file name without `.png`; names must be unique across folders.
- Never edit a PNG in place. Originals stay **outside** the project. Generated/derived PNGs are produced by a script in `tools/` and noted in `CREDITS.md`.
- Never write resource files with `Set-Content -Encoding UTF8` (BOM). Edit `.collection`, `.go`, `.gui`, `game.project` additively.
- Do not add sprites without a budget: `[sprite] max_count = 2048` today, about 330 are used by the arena. Particles are capped at 260. Check the count after each phase.
- Spell effect art is **tinted** by the skill's element colour: it must be WHITE / light grey with brightness in the alpha channel. Never paint colour into spell art.
- Only **CC0 or CC BY** licenses. No CC BY-SA, NC, ND, "all rights reserved", or unknown. If a page does not state a license, do not use the asset.
- Version every delivery (`CHANGES.md` entry, zip name `..._v3.zip`, etc.). Say what you could **not** verify.

---

## 2. Phase 0 - Preflight (no art yet)

1. Confirm tools: `python --version` (or `py --version`), `pip show pillow lupa` (install with `pip install pillow lupa` if missing).
2. Run the baseline and record the numbers in your first reply:
   - `python tools/validate_rooms.py` -> `0 problem(s)`
   - `python tools/run_smoke_test.py` and `ART_TEST=1 python tools/run_smoke_test.py` -> `RESULT: PASS (mock only)`
   - baseline object count printed by the smoke test (currently 323) and `[sprite] max_count` in `game.project`.
3. Make a working branch/copy note in `CHANGES.md` ("assets pass started"). Do not change code yet.
4. Reply in at most 6 lines with your plan and anything blocking. Then continue.

---

## 3. Phase 1 - Download the assets yourself

Create a downloads folder **outside** the project, next to it: `..\defold_downloads\` (create it if missing). Use PowerShell
`Invoke-WebRequest -UseBasicParsing` (or `curl.exe`; in PowerShell `curl` is an alias for something else). Never put downloads inside the project folder.

### 3.1 Packs to fetch

| Pack | Author | Expected license | Pages (verify before use) | Use for |
| --- | --- | --- | --- | --- |
| **Tiny Dungeon** | Kenney | CC0 | https://kenney.nl/assets/tiny-dungeon , mirror https://opengameart.org/content/tiny-dungeon | player candidates (characters), items, optional tiles later |
| **Tiny Creatures** | Clint Bellanger | CC0 | https://opengameart.org/content/tiny-creatures , https://clintbellanger.itch.io/tiny-creatures | enemies, bosses, the four elementals |
| **Particle Pack** (full original) | Kenney | CC0 | https://kenney.nl/assets/particle-pack | more spell effect sprites (a brightened subset is already in `assets/art/particles/`) |
| *(optional)* **game-icons.net** icons | various | CC BY 3.0 (credit each author) | https://game-icons.net | only if the CC0 silhouette route in 6.4 is not good enough |

### 3.2 How to download
1. Fetch the pack's page HTML and **read the license text on the page.** Record the exact license name you read.
2. Find the download link in the HTML: for Kenney look for an `href` ending in `.zip` (path contains `/media/pages/assets/`); for OpenGameArt look for `href` values containing `/sites/default/files/`.
   Example:
   ```powershell
   $html = (Invoke-WebRequest -UseBasicParsing "https://kenney.nl/assets/tiny-dungeon").Content
   [regex]::Matches($html, 'href="([^"]+\.zip)"') | ForEach-Object { $_.Groups[1].Value }
   ```
   Make relative links absolute. Download with `Invoke-WebRequest -UseBasicParsing -Uri <url> -OutFile <file>`, then `Expand-Archive`.
3. Verify the zip really opened and contains PNGs. Compute SHA-256 (`Get-FileHash`).
4. For each pack create `assets/third_party/<pack-slug>/` and put there: the pack's license file if it ships one, and a `SOURCE.txt`:
   ```
   pack:    Tiny Creatures
   author:  Clint Bellanger
   url:     <page url>
   file:    <downloaded file url>
   license: CC0 1.0 (as stated on the page, read on <date>)
   sha256:  <hash>
   ```
   Do **not** copy the whole pack into the project; only the PNGs you actually use go to `assets/art/...` (section 4).
5. **Stop and ask the human** (do not scrape around it) if: the page needs a JS button/login/captcha, the license is missing or unclear, the download is not a zip/PNG,
   or the network is blocked. Give them the exact page URL and the exact folder to put the file in (`..\defold_downloads\<pack>.zip`), then continue when it is there.

---

## 4. Phase 2 - Inspect, slice, and pick sprites

1. Open each sheet with Pillow and print its size. Work out tile size and spacing: tile is normally 16 px; if `width = cols*16 + (cols-1)*spacing` fits with spacing 1, the sheet has 1 px gaps.
   Prefer a "packed"/no-spacing variant if the pack ships both. Use `python tools/slice_sheet.py SHEET OUT_DIR PREFIX 16 [spacing] [margin]`.
   If a pack already ships individual PNGs, use those directly.
2. Build a **labelled contact sheet** for every pack (new tool `tools/make_picker.py`): all sliced tiles scaled 4x on a dark grey background, with their index drawn under each one, saved as
   `docs/sprite_picker_<pack>.png`. Also one for the Kenney particle sprites: `docs/particle_picker.png`.
3. **Choose sprites.** If you can see images, view the pickers and choose yourself. If you cannot see images, stop and ask the human to pick indices, and give them this reply template:
   ```
   player=<index in picker X>
   wisp=<idx> slinger=<idx> charger=<idx> brute=<idx> splitter=<idx> boss=<idx>
   elemental_fire=<idx> elemental_water=<idx> elemental_wind=<idx> elemental_earth=<idx>
   ```
4. Selection criteria (all must hold):

| Role | Look for | Notes |
| --- | --- | --- |
| player | a wizard / witch / dark wizard / mage | must read clearly at 32-48 px |
| wisp | will-o-wisp, ghost, spirit | |
| slinger (ranged) | goblin, skeleton, dark mage, archer | |
| charger | boar, wolf, minotaur, charging beast | |
| brute | golem, ogre, large armoured creature | |
| splitter | slime / jelly | it splits, so a slime reads perfectly |
| boss | lich, dragon, hydra, treant, large creature | draw it big |
| 4 elementals | fire, water, wind (air), earth elementals/sprites | used for HUD icons in Phase 4 |

   Transparent background, same style/palette family, distinct silhouettes (an enemy must be recognisable from its outline). Record the chosen indices in `assets/art/actors/MAPPING.md`
   (role -> pack -> source index -> file name -> which way it faces: left or right).
5. Copy **only the chosen sprites** to `assets/art/actors/` as `tc_<role>.png` (Tiny Creatures) or `td_<role>.png` (Tiny Dungeon), and elementals to `assets/art/actors/elemental_<element>.png`.
   Delete every unused slice. Run `python tools/add_to_atlas.py "assets/art/actors/*.png"`.

---

## 5. Phase 3 - Player and enemy sprites in the game

### 5.1 Manifest
Fill `src/core/art.lua`:
```lua
M.ENABLED = true
M.ACTORS = {
    player   = { anim = "td_player",   scale = 3, faces = "right" },
    wisp     = { anim = "tc_wisp",     scale = 2, faces = "right" },
    slinger  = { anim = "tc_slinger",  scale = 2, faces = "right" },
    charger  = { anim = "tc_charger",  scale = 2, faces = "right" },
    brute    = { anim = "tc_brute",    scale = 3, faces = "right" },
    splitter = { anim = "tc_splitter", scale = 2, faces = "right" },
    boss     = { anim = "tc_boss",     scale = 6, faces = "right" },
}
```
Add support for `faces = "left"` (the code currently assumes right: flip logic in `sync_player` and for enemies must multiply by `-1` when the art faces left).
Rules: **integer scales only** (pixel art; 16 px x 2 = 32 px, x 3 = 48 px). Art should be about `2 x collision radius` wide: wisp/slinger/splitter radius 12, charger 14, brute 18, boss 32.
Splitter children and boss summons spawn as **wisps** (`spawn_wisp_at`), so they use the `wisp` art; make sure that path sets `base_scale`, `base_tint` and the facing state like every other spawn path (AGENTS B31).

### 5.2 Pixel-perfect rendering
Find the correct `game.project` keys for texture filtering (check https://defold.com/manuals/project-settings/ or the editor's project settings view; do not guess) and set the default min/mag filter to **nearest**, additively.
Tell the human it requires an editor reload.

### 5.3 Animation by code (visual only)
The art is static. Create `src/game/anim.lua`: **pure functions**, no `go.*` calls, so they can be unit tested:
```lua
-- returns scale_x_mult, scale_y_mult, y_offset_px, rotation_radians
M.player(state, t)     -- idle bob; squash when moving; stretch along the dash; tiny lean toward the aim
M.enemy(kind, e, t)    -- per kind, see table
```
| Entity | Motion |
| --- | --- |
| player | idle bob (about 2 px, 1.2 Hz); move squash (x 1.08 / y 0.92 at speed); dash stretch (x 1.3 / y 0.8 for the dash time); flips to face the aim |
| wisp | floating bob plus a slow wobble |
| slinger | recoil (quick scale pop backwards) when it fires; leans away when retreating |
| charger | wind-up shake while `e.windup > 0`; leans into the charge direction while `e.charging` |
| brute | slow stomp: periodic squash (y 0.9) every ~0.7 s while walking |
| splitter | jelly wobble (x and y out of phase) |
| boss | slow breathing pulse; stronger pulse before a charge or summon |

Hard rules: animation changes **only** sprite scale, the sprite's visual y offset, and rotation. It must **never** modify `e.x`, `e.y`, radius or any value used by collision, AI or pathing.
Final scale = `base_scale * anim_scale * hit_pop` (the existing hit-flash pop must keep working and must restore the correct size). Facing: flip the sprite's x scale (negative) by movement/aim direction (use `faces`).
Add unit tests for `anim.lua` (pure Lua, run under LuaJIT through the smoke test harness or a small `tools/test_anim.lua`): no NaN, scales stay within 0.5-1.6, same inputs give same outputs.

### 5.4 Nice-to-have if the sprite budget allows
- A soft blob shadow under each actor (a generated `shadow.png` white/black ellipse, normal blend, z `-0.3`). It doubles per-actor sprites, so check the budget and the cap first.
- A brief squash-and-fade on death before the existing kill burst.

### 5.5 Stop and report (Phase 3 checkpoint)
Human test checklist to give them:
1. Reload the project in the editor; run; the console shows `SELFCHECK OK` and no `ERROR:` lines (paste the first error if any).
2. The player is the wizard sprite, faces the mouse, bobs when idle, squashes when moving, stretches on a SPACE dash, blinks when hit.
3. Each enemy type looks like its sprite (rooms 1-9), animates as in 5.3, flashes/pops when hit, and is clickable-sized correctly (collision still feels fair).
4. Splitter children and boss-summoned wisps look right and do not change size after being hit.
5. Pixels look crisp (no blur).
Wait for the human's confirmation before Phase 4.

---

## 6. Phase 4 - Spell art

### 6.1 Make skills describe their elements
`src/core/skillgen.lua` returns `key`, `compound`, `shape`... but not the elements. Add `elements = { a, b }` (the two element names, sorted) and `shape_key` to the returned table.
This must **not** change the deterministic output: the golden vectors in the selfcheck (`Steam Bolt, power 7, "repeats once"` etc.) must still pass. Add an assertion for the new fields.

### 6.2 More effect sprites from the Kenney Particle Pack
1. From the downloaded full Particle Pack pick additional sprites you need (flame, droplet/bubble, wind streak, rock chips/debris, smoke puffs, sparkles, ring, slash). Create `docs/particle_picker.png` first and choose from it.
2. Make white-on-alpha versions with a new script `tools/whiten_sprite.py` (do **not** edit the originals). Algorithm (this is what already made the current particles visible):
   ```
   lum  = mean(R,G,B)/255
   eff  = lum * alpha/255
   eff  = max(eff, 0.35 * alpha/255)          # keep soft halos
   p    = 98th percentile of eff over pixels with eff > 0.02
   out  = clip(eff / p, 0, 1) ** 0.75
   result RGB = 255 (white), alpha = out * 255
   ```
   Output to `assets/art/fx/fx_<name>.png`, 64-128 px, then `python tools/add_to_atlas.py "assets/art/fx/*.png"`. View them tinted fire-red on a near-black background before accepting (they must be clearly visible).

### 6.3 Per-element effect styles
Add to `src/core/art.lua`:
```lua
M.ELEMENT_FX = {
    fire  = { trail = "fx_flame", hit = "fx_scorch", rise = "fx_flame",  spoke = "fx_spark" },
    water = { trail = "fx_drop",  hit = "fx_splash", rise = "fx_bubble", spoke = "fx_drop"  },
    wind  = { trail = "fx_streak",hit = "fx_swirl",  rise = "fx_swirl",  spoke = "fx_streak"},
    earth = { trail = "fx_debris",hit = "fx_scorch", rise = "fx_debris", spoke = "fx_debris"},
}
```
(Example ids; use the sprites you actually produced. Every id must exist in the atlas. Every missing entry falls back to the generic `FX` role.)
Use them in `main/game.script` (`do_cast` and the per-frame effect code):
- **Bolt:** trail particles use element **A's** `trail`; hit burst uses element **B's** `hit`. If the head sprite is directional (a streak or flare), rotate it to the flight direction (`go.set_rotation(vmath.quat_rotation_z(angle), id)`).
- **Pool:** rising bubbles/embers use A's `rise`, drifting upward.
- **Orbit:** the sparks use A's `trail`.
- **Spray (cone):** the fan alternates A's and B's sprites.
- **Nova:** the spokes use B's `spoke`.
- A double element (Fire + Fire) simply uses the same element for both.
Keep all of it **tinted** by the skill colour (the blended element colour) and drawn with the additive fx factory. Sizes and counts stay where they are spawned (`fx_hit`, `fx_cast`, `do_cast` branches).
Respect the particle cap (260) and the sprite budget.

### 6.4 Element icons for the HUD
The HUD tints icons with the element colour, so icons must be **white silhouettes**.
- Preferred (CC0, no extra credit needed): write `tools/make_silhouette.py` that turns the chosen elemental sprites into white-on-transparent, 64 px icons (nearest-neighbour upscale; fill every pixel with alpha > 0 white, keep a 1-2 px inner shading by lowering brightness on the darkest pixels so the shape stays readable).
  Output `assets/art/icons/icon_fire.png`, `icon_water.png`, `icon_wind.png`, `icon_earth.png` (same ids the manifest already uses, so `ELEMENT_ICONS` needs no change). Back up nothing inside the project; the old icons are gone from the atlas only if the file names are reused, so check `git`/zip history first and mention it in `CHANGES.md`.
- Only if that looks bad: use game-icons.net white PNGs (CC BY 3.0). Then credit **every author** in `CREDITS.md` and `src/core/credits.lua` (format: `Icon "<name>" by <author> (game-icons.net, CC BY 3.0)`).

### 6.5 Shape glyphs (optional)
Generate five tiny white pictograms with Pillow (bolt, pool, orbit, spray, nova) as your own work (no credit needed) and show them on the skill slot cards if `main/hud.gui_script` can do it with a few lines (`gui.play_flipbook`). Skip if it needs hand-written `.gui` node edits.

### 6.6 Stop and report (Phase 4 checkpoint)
Human test checklist:
1. Run the game, cast every shape with several element pairs (the debug keys are off by default; set `TUNING.DEBUG = true` in `src/core/data.lua` to use 1-5 / Q / E).
2. Fire trails look like fire, water like drops/bubbles, wind like streaks, earth like debris; mixed skills visibly mix.
3. Directional bolts point where they fly. Effects are bright and readable on every room palette.
4. HUD/reward icons are crisp silhouettes tinted with the element colour.
5. No `ERROR:` lines; frame rate fine during a Gauntlet fight (room 8).

---

## 7. Tooling and tests you must add or extend

1. `tools/check_art.py` (new): parse `src/core/art.lua` for every animation id (`anim = "..."`, `FX`, `ELEMENT_FX`, `ELEMENT_ICONS`, `TILES`, `ACTORS`) and fail if any id is not an image in `assets/art/shapes.atlas` (basename without `.png`), if any atlas image file is missing on disk, or if an `assets/third_party/<pack>/` folder has no matching line in `CREDITS.md`.
2. `tools/smoke_test.lua`: replace the hard-coded `VALID_ANIM` list with ids **parsed from the atlas file** so an unknown id fails the test. In `ART_TEST=1` mode use the **real** `ACTORS` from `art.lua` instead of the fake `circle` mapping.
3. `tools/make_picker.py`, `tools/whiten_sprite.py`, `tools/make_silhouette.py` (new). Each prints usage with `-h`, works on Windows paths, never overwrites an original.
4. Update `README.md` section 13 (new roles, new tools, per-element FX, `faces`), `docs/ART_GUIDE.md` pointer, `CREDITS.md`, `src/core/credits.lua`, `CHANGES.md`.
5. If you make a mistake, add it to `AGENTS.md` as the next numbered item (what happened / why / rule).

---

## 8. Reporting format (after each phase)

```
PHASE <n> DONE
Downloaded: <pack, url, license read, sha256 short> or "none"
Files created: ...
Files changed: ...
Atlas: <n> images; sprite budget: <used> of 2048
Tests: validate_rooms=<result> | smoke=<result> | ART_TEST=<result> | check_art=<result>
How to test: <numbered steps for the human>
Expected console: <what should print; what must not appear>
Not verified: <what you could not run (rendering, blending, z-order, editor parsing)>
Credits added: <lines>
```

---

## 9. Definition of Done

- All three Definition-of-Done checks in `AGENTS.md` pass, and `python tools/check_art.py` reports no problems.
- Every pack used has: `assets/third_party/<pack>/SOURCE.txt`, a credit line in `CREDITS.md` **and** `src/core/credits.lua`, and its license read from the page (not assumed).
- Player and all 6 enemy ids render as sprites with code animation; with `art.ENABLED = false` the game still runs with shapes.
- Spell effects are element-specific, tinted, additive, capped; icons are white silhouettes (or credited game-icons).
- The human has confirmed both checkpoints (5.5 and 6.6) in the running game.
- Delivery is versioned and `CHANGES.md` lists what changed.

## 10. Do NOT

- Download anything outside section 3.1 without asking; bypass a captcha/login/JS-only download; use unlicensed or unclear art.
- Put downloads, original packs, or unused sprites inside the project.
- Hand-write `animations {}` in the atlas, a tilemap, physics, or a custom render script.
- Tint coloured art or paint colour into spell art.
- Change collision, AI, pathing, golden skill vectors, or room layouts as part of this task.
- Claim "no errors": say what you ran and what you could not.

**Begin with Phase 0.** Reply with the baseline numbers and a plan of at most 6 lines, then start Phase 1.
