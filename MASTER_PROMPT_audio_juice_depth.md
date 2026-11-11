# MASTER PROMPT: Audio, Combos, Juice and Depth (Defold Element Roguelike)

> **For the human (Ash):** put this file in the project root next to `AGENTS.md`, then start opencode in the project folder and send:
> `Read MASTER_PROMPT_audio_juice_depth.md completely, then AGENTS.md, then follow the prompt. Begin with Phase P0.`
> The agent works in phases, stops after each one, and keeps `PROGRESS_SUMMARY.md` up to date. To let it run several phases without stopping, say "continue through P5".

---

## 0. Your role and ground rules

You are the coding agent that extends an existing, working Defold 1.14.0 game on Windows. You are **not** starting from scratch. The game already has: 4 elements, 10 compounds, 5 shapes (50 deterministic skills), 9 authored rooms, 6 enemy types, a boss, a cauldron, animated spell FX, a letterboxed 960x640 view, a headless smoke test, and a Training Arena debug room.

**Goal of this work:** (1) add a complete, layered **sound system** for every skill, status, quirk, enemy, UI action and music state; (2) add **elemental reactions and combos** so mixing elements matters; (3) add **juice**; (4) add **depth** (enemy affinities, environment, grimoire, relics); (5) leave a clear written record of everything you did.

Rules that are not negotiable:

1. **Read first, in this order:** this file, `AGENTS.md` (every item: these are real bugs already made in this project), `CHANGES.md`, `README.md` sections 3, 4, 7, 13, then `src/core/art.lua`, `src/core/data.lua`, `src/core/skillgen.lua`, `src/core/status.lua`, `src/game/combat.lua`, `src/game/enemies.lua`, and the structure of `main/game.script` (about 2,200 lines: use `rg`/`Select-String` for `fx_cast`, `fx_hit`, `fx_kill`, `fx_player_hit`, `do_cast`, `apply_damage`). Where `README.md` and `AGENTS.md` disagree, **AGENTS.md wins**.
2. **You cannot run the Defold engine.** You can edit files, run Python, and run the headless tests (`pip install lupa`, then `python tools\run_smoke_test.py`, also with `$env:ART_TEST=1` and `$env:ART_TEST=0`; also `python tools\validate_rooms.py`, and `tools\run_anim_test.py`). If the Defold editor is open and its HTTP `/command/compile` endpoint is reachable (see `CHANGES.md`, earlier agents used it; the port/token are in `.internal/`, which you may read but never edit), run a compile check after each phase. If it is not reachable, write "compile: not verified". **Never claim something works in the engine.** Say "mock only" for the headless tests and list what the human must check in the running game.
3. **Lua 5.1 / LuaJIT only.** No `goto`, no `//`, no integer types, no `continue`. Use `require "bit"` for bit ops. Module boilerplate: every module starts with `local M = {}` and ends with `return M`.
4. **Pure logic goes in modules** under `src/` (no `go.*`, `gui.*`, `sound.*` inside them except through an injected backend). `game.script` applies results to the engine. GUI scripts cannot use `go.*`; the game script cannot use `gui.*`. They talk by `msg.post`.
5. **Skill determinism is sacred.** Never change `hash.lua`, `rng.lua`, or the order of RNG calls in `skillgen.lua`. `SELFCHECK OK` and the golden vectors must keep passing. Anything new that depends on a skill (pitch, mastery, reroll) is computed **outside** `makeSkill`, from `skill.key`.
6. **Do not spend gameplay RNG on cosmetics** (AGENTS #38). Pitch variation, shake direction, decal placement use a separate cosmetic RNG (`src/core/crng.lua`, a tiny xorshift32 seeded by a constant, never `math.random`).
7. **Never reverse earlier decisions or delete earlier work** (AGENTS #30, #41, #48): do not disable the user's debug tools, do not overwrite user assets in place, do not delete earlier delivery files. `TUNING.DEBUG` stays `true` during development; tell the human to set it `false` before release, do not do it yourself.
8. **Resource files: additive and minimal.** Edit `.collection`, `.go`, `.gui`, `game.project`, `*.input_binding`, `shapes.atlas` additively. Prefer standalone component files over `embedded_components`. When you must write a protobuf-text file for a type you have not seen in this project (for example `.sound`), **first find an existing example or the official Defold manual page; if you are still unsure, stop and ask the human to create one in the editor and paste its text** (AGENTS #32). Do not invent APIs.
9. **Windows file hygiene:** write files as UTF-8 **without BOM** (AGENTS #20). Prefer Python for file generation (`open(path, "w", encoding="utf-8", newline="\n")`). Resource paths in project files use `/` and a leading `/`.
10. **Respect capacity limits:** `[sprite] max_count = 2048`, `[collection] max_instances = 4096`. Any new persistent visual (decals, numbers) must be capped and cleaned in `clear_world`. The smoke test already checks live sprite counts and leaks: keep it green.
11. **Licensing:** only CC0 or CC BY assets, with the licence text in `assets/third_party/<pack>/` and a line in **both** `CREDITS.md` and `src/core/credits.lua`. Do **not** download third-party audio yourself unless the human asks. Everything you generate yourself (placeholder sounds, glyphs) is original and needs no credit, but say so in `CREDITS.md` ("Placeholder audio generated by tools/make_sfx.py").
12. **Every new feature must have a fallback.** The game must still run if every audio file is removed (silent), and must still run if a feature flag is turned off. Each feature gets a flag in `TUNING` (or its own manifest `ENABLED`), documented in the summary.
13. **Verify before you claim** (AGENTS #24, #35, #46, #47). Run the tests after every phase. Report failures and unverified assumptions honestly. If a test fails for a reason you did not expect, find the real reason before changing the test (AGENTS #45).
14. **Stop after every phase.** Use the report format in section 2, wait for the human, and do not start the next phase until they confirm. Every phase must leave the game runnable.

---

## 1. Facts about the project you must not get wrong

- Entry: `game.project` -> `main/main.collection` -> instances `game` (`main/game.go`: components `script`, `visual_factory`, `fx_factory`) and `hud` (`main/hud.go`, `hud.gui`, `hud.gui_script`).
- State machine in `game.script`: `TITLE -> PICK_START -> ROOM -> REWARD -> CAULDRON -> ROOM ... -> boss -> WIN`, plus `DEAD` and `CREDITS`. The debug key `T` toggles the Training Arena.
- Skills come from `skillgen.makeSkill(a, b, shape, name)` and carry: `key`, `compound`, `shape` (display name, e.g. "Bolt"), `shape_key` (`projectile|puddle|orbit|cone|burst`), `elements = {A, B}` (sorted alphabetically), `power`, `quirk`, `color`, `cooldown`, `radius`, `duration`, `statuses`.
- Established visual language: **element A = cast / trail / flame head, element B = impact**. Sound must follow the same rule.
- Cast path: `do_cast(self, slot, is_repeat)` -> `fx_cast`. Hit paths: bolts (about line 1442), puddles (about 1501), orbits (about 1564), cone (about 2027), burst (about 2081) and the delayed burst echo (about 2135). **These five blocks are near-identical copies** (apply damage, apply statuses, push/pull knockback, hit FX). Other hook functions: `fx_hit`, `fx_kill`, `fx_player_hit`, `fx_cast`.
- Enemy types (`src/game/enemies.lua`): wisp, slinger, charger, brute, splitter, dummy (immortal), boss. Statuses (`src/core/status.lua`): burn, slow, stun, root, blind, confuse, push, pull, hide_self, spread.
- GUI/world coordinates both start at the **bottom-left** (AGENTS #21, #22). Facing uses `sprite.set_hflip`, **never** a negative scale (AGENTS #40).
- `tools/` is Python + Pillow (one file uses numpy). Tests use `lupa`. Keep new tools dependency-light: **`tools/make_sfx.py` must use only the Python standard library** (`wave`, `struct`, `math`, `random`).

---

## 2. Reporting (mandatory)

### 2.1 `PROGRESS_SUMMARY.md` (project root, you create it in P0, update it at the end of every phase)

Structure, in this order:

1. **Overall summary** (rewritten each phase, max 25 lines): what the game now does that it did not before, what the human must verify in the running game, how to turn each feature off, current known issues.
2. **Phase status table:** `Phase | Title | Status (todo / done / blocked / skipped) | Date`.
3. **Per-phase entries, newest last, never deleted.** Each entry uses the template in 2.2.
4. **Tuning knobs:** every new `TUNING` key / manifest flag with default and meaning.
5. **Sound map pointer:** link to `assets/sfx/SFX_MAP.md`.
6. **Decisions and deviations:** anything you did differently from this prompt and why.
7. **Mistakes made and fixed** (also appended to `AGENTS.md`, see 2.3).

### 2.2 Per-phase report (paste it in the chat **and** append it to `PROGRESS_SUMMARY.md`)

```
PHASE <Pn> DONE: <title>
Files created: ...
Files changed: ... (one line each: what changed)
Wiring: <which .go/.collection/game.project/input lines connect it>
How to test (human, in the Defold editor): <numbered steps, exact keys/rooms>
Expected console: <what should print; what must NOT appear>
Automated results: smoke / ART_TEST=1 / ART_TEST=0 / anim / rooms / selfcheck / compile -> PASS|FAIL|not verified, with the numbers
Not verified (human must check): ...
Decisions / deviations: ...
Known gaps: ...
Credits added: <asset, author, licence> or "none"
```

### 2.3 Other files you must keep in sync

- `CHANGES.md`: add a short entry at the **top** per phase, in the existing style.
- `AGENTS.md`: if you make a mistake, hit a surprise, or the editor rejects something, append a new numbered item under a new **Part D (mistakes by the extension agent)**, in the existing format (what happened, root cause, rule). Do this **when it happens**, not at the end (AGENTS #46).
- `assets/sfx/SFX_MAP.md`: one row per sound id: `id | file | what it should sound like | where it plays | status (placeholder/final)`. The human uses it to swap in real sounds by file name.

---

## 3. Phases

Do them in order. **Tier A** is the core (audio, reactions, juice, UI). **Tier B** is depth. **Tier C** changes run structure and needs the human's explicit OK before each phase starts.

| Tier | Phases |
|---|---|
| A | P0 Baseline, P1 Hit refactor, P2 Audio plumbing, P3 Spell audio, P4 World audio, P5 Music, P6 Reactions, P7 Fusion + combo streak, P8 Juice, P9 UI + settings |
| B | P10 Enemy affinities, P11 New enemies + boss phases, P12 Environment + decals |
| C | P13 M8 extras (name seed, quirk reroll, magic fading), P14 Grimoire + mastery, P15 Relics + shrines + shop, P16 Meta + daily seed |

---

### P0: Baseline (no gameplay changes)

1. Read everything listed in rule 1. Check that `git status` is clean or note what is dirty (if the project is a git repo; if not, copy `main/game.script` to `main/game.script.bak_P0` once, and say so).
2. Run: `python tools\run_smoke_test.py`, with `ART_TEST=1`, with `ART_TEST=0`, `python tools\validate_rooms.py`, `python tools\run_anim_test.py`. Record the exact numbers as the **baseline** in `PROGRESS_SUMMARY.md` (results, live objects, max sprites, rooms, anim checks).
3. Create `PROGRESS_SUMMARY.md` (structure 2.1) and `assets/sfx/SFX_MAP.md` (empty table).
4. Write a **map of hook points** into the summary: for each of cast, hit (6 blocks), kill, player hit, dash, status apply, quirk, room clear, state change, boss patterns: file + line + function. This is the contract for P2-P4.
5. Report. Nothing else changes in P0.

### P1: One choke point for hits (refactor, zero behaviour change)

Problem: the "apply damage, apply statuses, knockback, hit FX" code is copy-pasted six times in `game.script`. Audio, reactions, damage numbers, hit-stop and affinities all need one place.

1. Add `local function apply_hit(self, e, damage, statuses, src)` in `game.script` (or a new `src/game/hitflow.lua` with an injected effects table if it can stay pure). `src` = `{ skill = skill, kind = "bolt"|"puddle"|"orbit"|"cone"|"burst"|"echo"|"burn"|"spread", x = , y = }`. It must do exactly what the six blocks do today, in the same order: `combat_mod.apply_damage`, `status_mod.apply`, push/pull knockback away from / toward `src`, `fx_hit`, and returns `died`. Burn ticks (line about 1106) use the same function with `kind = "burn"` and **must not** play hit FX, matching today's behaviour.
2. Replace the six blocks with calls. Keep every variable the surrounding code uses (kill handling, `splitter` children, boss death).
3. Add a hook table `self.hooks` (or module `src/game/events.lua`) that `apply_hit`, `do_cast`, `fx_kill`, `fx_player_hit` call as `events.emit(name, ctx)`. In P1 it has no listeners. Later phases register listeners for audio, reactions, juice.
4. Tests must be identical to the P0 baseline (same results, same counts within noise). If numbers change, you changed behaviour: find out why before continuing.

### P2: Audio plumbing and placeholder sounds

#### 2.1 Read the Defold sound docs first
Open the Defold manual (Sound) and the `sound` API reference. Expected, **to be verified before use**: a `.sound` component per clip (fields for sound file, looping, group, gain, pan, speed), `sound.play(url, [props], [complete])` with props such as `delay`, `gain`, `pan`, `speed`; `sound.stop(url)`; `sound.set_group_gain(group, gain)`; component properties `gain`/`pan`/`speed` that can be set and animated with `go.set`/`go.animate`; `[sound] max_sound_instances` and `max_sound_buffers` in `game.project`; WAV and OGG supported. If any of this differs from what you can confirm, follow the docs and write the difference into `AGENTS.md`. If you cannot confirm the `.sound` file text format, stop and ask the human to create one sound component in the editor and paste it.

#### 2.2 Sound ids and the manifest: `src/core/sfx.lua`
Mirror `art.lua`: a manifest, a silent fallback, and an injected backend so it is testable headless.

```lua
local M = {}
M.ENABLED = true
M.BUS = { master = 1.0, sfx = 1.0, music = 0.7 }
-- id -> { gain, min_gap (s), max_voices, pitch_var (fraction), loop (bool), bus }
M.SOUNDS = { cast_bolt = { gain = 0.8, min_gap = 0.03, max_voices = 3, pitch_var = 0.05, bus = "sfx" }, ... }
M.backend = nil          -- function(id, props) set by game.script; tests set a recorder
function M.play(id, opts) end    -- opts: gain, pan, speed, delay; applies throttle + bus gain + pitch_var via crng
function M.stop(id) end
function M.update(dt) end        -- advances the internal clock, fades loops, frees voice slots
function M.set_bus(name, gain) end
```

Rules: unknown id -> do nothing, return false, **never error** (log once). Per-id `min_gap` and `max_voices` throttles; a global cap of simultaneous voices (default 16, below `max_sound_instances`). Pan = `(x - 480) / 480 * 0.6`, clamped to +-0.6, for world sounds. Pitch is the Defold `speed` property: semitone shift `s` -> `speed = 2^(s/12)`.

High-level event helpers in the same module (pure: they only call `M.play`):

| Helper | Plays |
|---|---|
| `sfx.cast(skill, x)` | shape gesture `cast_<shape_key>` + element A layer `el_<A>_cast` (gain 0.6) + compound signature `sig_<compound lowercase>` (delay 0.02). All three use `speed` from the **skill pitch** (below) |
| `sfx.hit(skill, x, strength)` | `el_<B>_hit`, gain scaled by `strength` (0.5-1.0). One per frame per element |
| `sfx.status(name, x)` | `st_<name>` (min_gap 0.15 globally, so a nova hitting 10 enemies is one sound) |
| `sfx.quirk(quirk)` | `qk_split`, `qk_repeat`, `qk_trail`, `qk_big`, `qk_cost` |
| `sfx.loop_set(kind, count)` | start/stop `loop_pool`, `loop_orbit`, gain scaled by active count |

**Skill pitch:** `semitones = (hash(skill.key) % 5) - 2` (-2..+2), computed with `src/core/hash.lua` on the key **outside** `makeSkill`. The same recipe always sounds the same; a different recipe sounds slightly different. Document it.

#### 2.3 Placeholder generator: `tools/make_sfx.py` (standard library only)
Generates **every** id in `SFX_MAP.md` as a mono 16-bit **22050 Hz WAV** into `assets/sfx/` (music into `assets/music/`). Deterministic (seeded `random`), idempotent, never overwrites a file whose name already exists unless `--force` (the human may have swapped real sounds in), prints a table of what it wrote/skipped. Synthesis building blocks (implement once, reuse): sine/saw/square/triangle oscillators, white noise, one-pole low-pass/high-pass, a band-pass sweep, ADSR/exponential envelopes, short feedback delay, soft clip, 5 ms fade in/out on every file to avoid clicks.

Recipes (keep them simple; they are placeholders, and the human will replace them):
- **Element roots (pitch language):** fire = D4, water = F4, wind = A4, earth = C4. A compound signature is a two-note chord made of **both elements' roots** plus a fifth, 0.35-0.6 s, so Steam sounds different from Magma and the sound literally mixes the two elements. Doubles (Inferno = fire+fire) use the root and its octave.
- **Shape gestures:** Bolt = 0.15 s noise band-pass sweep up (zip); Pool = 0.5 s low thump + rising shimmer; Orbit = 0.4 s bell cluster; Spray = 0.35 s breathy noise sweep down-up; Nova = 0.2 s riser then 0.5 s boom (low sine drop + noise burst).
- **Element cast layers:** fire = crackle (random clicks + hiss), water = bloop (sine with exponential rise) x2, wind = filtered-noise gust with slow LFO, earth = 50-70 Hz rumble + dull noise.
- **Element hits:** short (80-150 ms) versions of the same timbres: fire = sizzle pop, water = splash tick, wind = whoosh snip, earth = thud.
- **Status cues (150-400 ms):** burn = ignite whoosh, slow = descending sine + low-pass close, stun = high ring + thump, root = low creak, blind = static burst, confuse = warbling detuned pair, push/pull = short pitch-up / pitch-down whoosh.
- **Quirks:** split = two rapid clicks, repeat = a soft echo tap, trail = hiss, big = pitch-dropped thump, cost = heartbeat double-thump.
- **Loops (must loop seamlessly, 1.0-2.0 s, start and end at zero crossing):** pool = bubbling hum, orbit = airy shimmer, heartbeat (`pl_lowhp`) = lub-dub, cauldron bubbling.
- **Music stems:** 8 bars, 100 BPM, same key, **same length** so they layer. `mus_room_pad` (slow sustained chord, pentatonic), `mus_room_rhythm` (soft kick + noise hat), `mus_room_lead` (sparse arpeggio), `mus_boss` (faster, minor, all layers in one), `mus_title` (pad + bell), plus non-looping `mus_win`, `mus_dead` (about 3-5 s). Mono 22050 Hz is fine for placeholders (about 5 MB in total).

Complete id list (every id must exist in `M.SOUNDS`, in `SFX_MAP.md`, and as a generated file):

- Shapes: `cast_projectile`, `cast_puddle`, `cast_orbit`, `cast_cone`, `cast_burst`.
- Element layers: `el_fire_cast`, `el_water_cast`, `el_wind_cast`, `el_earth_cast`, `el_fire_hit`, `el_water_hit`, `el_wind_hit`, `el_earth_hit`.
- Compounds (10): `sig_inferno`, `sig_tide`, `sig_gale`, `sig_quake`, `sig_steam`, `sig_ember`, `sig_magma`, `sig_mist`, `sig_mud`, `sig_dust`.
- Status (8): `st_burn`, `st_slow`, `st_stun`, `st_root`, `st_blind`, `st_confuse`, `st_push`, `st_pull`; plus `st_hide`.
- Quirks (5): `qk_split`, `qk_repeat`, `qk_trail`, `qk_big`, `qk_cost`.
- Loops: `loop_pool`, `loop_orbit`.
- Player: `pl_hurt`, `pl_dash`, `pl_lowhp` (loop), `pl_die`, `pl_heal`.
- Enemies: `en_spawn`, `en_hit`, `en_die`, `en_charge_windup`, `en_charge`, `en_slinger_shot`, `en_brute_stomp`, `en_splitter_pop`, `en_wall_stun`, `boss_roar`, `boss_ring`, `boss_charge`, `boss_summon`, `boss_die`.
- UI / flow: `ui_hover`, `ui_click`, `ui_card`, `ui_pick`, `ui_craft`, `ui_craft_bad`, `ui_cauldron_loop`, `room_clear`, `state_win`, `state_dead`, `state_title`.
- Later phases: `rx_steam`, `rx_shatter`, `rx_flare`, `rx_bog`, `rx_whirl`, `combo_up`, `fusion`, `hit_weak`, `hit_resist`, `crit_streak`, `relic_get`, `shrine`, `shop_buy`. (Generate them in P2 too, so later phases only wire them.)

#### 2.4 Engine wiring: `tools/add_sounds.py` and `main/sfx.go`
- `tools/add_sounds.py` scans `assets/sfx/` and `assets/music/`, and for each `<id>.ogg` (preferred) or `<id>.wav` writes `<id>.sound` next to it (standalone resource, correct fields from the verified format; loop flag from the manifest; group per bus), then writes `main/sfx.go` with **one `components { id: "<id>" component: "/assets/sfx/<id>.sound" }` per sound** (standalone references, no `embedded_components`). It is idempotent and prints what changed.
- Add the `sfx` instance to `main/main.collection` **additively** (`instances { id: "sfx" prototype: "/main/sfx.go" }`). Addresses are then `"/sfx#<id>"`.
- Add `[sound]` limits to `game.project` additively (for example `max_sound_instances`, `max_sound_buffers`) with values you verified in the docs.
- Because the human can swap real files in by name, re-running `add_sounds.py` after replacing `assets/sfx/cast_bolt.wav` with `cast_bolt.ogg` must keep working (prefer `.ogg` if both exist).

#### 2.5 Hook-up in `game.script`
- In `init`: `sfx.backend = function(id, props) sound.play("/sfx#" .. id, props) end` (adapt to the verified API; stop through `sound.stop`). `sfx.update(dt)` in `update`. Everything routes through `sfx.*`; **no direct `sound.play` elsewhere**.
- **Debug sound test (under `TUNING.DEBUG`):** new input actions (additive to `game.input_binding`) so the human can audition: `O`/`P` previous/next sound id, `L` play it, `K` play the current slot-1 skill's full cast layers. Show the current id in the console (and on the HUD if easy).

#### 2.6 Tests
Extend `tools/smoke_test.lua` (mock `sound.play`/`sound.stop`, or use the recorder backend):
- every id in `M.SOUNDS` has a file in `assets/sfx` or `assets/music` (WAV or OGG) **and** a row in `SFX_MAP.md`;
- all 50 skills: a cast produces `cast_<shape>` + `el_<A>_cast` + `sig_<compound>`, with a `speed` inside 2^(-2/12)..2^(2/12) (times pitch_var);
- throttle: 20 `sfx.hit` calls in one frame produce at most `max_voices` plays;
- with `sfx.ENABLED = false` or all files missing the whole smoke run still passes;
- unknown id: no error.

### P3: Spell audio (all skills, combos, statuses, quirks)

1. **Cast:** in `do_cast` (and every repeat), call `sfx.cast(skill, sx)`. For `repeats once` the second cast plays a quieter copy (gain x0.6) so the echo is audible but not doubled-loud.
2. **Hit:** register an `apply_hit` listener: `sfx.hit(src.skill, e.x, strength)` where strength = `min(1, damage / skill.power)` clamped to 0.5-1. Burn ticks and puddle ticks are **silent** (use `st_burn` only on the first application). Kill gets `en_die` (P4).
3. **Statuses:** `sfx.status(name, e.x)` only on a **fresh** application (the status was not present before), so a puddle ticking every 0.5 s does not spam. `hide_self` on the player plays `st_hide`.
4. **Quirks:** `sfx.quirk` at cast time: split, trail, bigger (`qk_big` plus the cast pitched -2 semitones extra), cost (`qk_cost` and `pl_hurt` quietly).
5. **Loops:** Pool and Orbit use `loop_pool` / `loop_orbit` loops; count active ones each frame and call `sfx.loop_set` (one loop per type, gain = `min(1, 0.4 + 0.2 * count)`, stop when count reaches 0 and in `clear_world` / `reset_run`).
6. **Training Arena check:** all 50 skills audible and distinguishable by ear is a human check: list 10 recipes for the human to compare (Inferno Bolt vs Tide Bolt vs Steam Nova ...).
7. Fill `SFX_MAP.md` rows for everything wired in this phase.

### P4: World audio (player, enemies, UI, states)

- **Player:** `pl_hurt` in `fx_player_hit`; `pl_dash` on dash start; `pl_lowhp` heartbeat loop while HP < 30% and room active (stop on heal, death, state change); `pl_heal` on room clear heal; `pl_die` on death.
- **Enemies:** `en_spawn` when a telegraph resolves into an enemy (throttled); `en_hit` is replaced by the element hit (do not double-play: `en_hit` only for enemy bolts hitting the player); `en_die` on kill; charger: `en_charge_windup` at telegraph, `en_charge` at dash start, `en_wall_stun` when it slams a wall; slinger `en_slinger_shot`; brute `en_brute_stomp` (matching the existing stomp animation phase); splitter `en_splitter_pop` on split; boss: `boss_roar` on spawn/phase, `boss_ring` for the 12-bullet ring, `boss_charge`, `boss_summon`, `boss_die`.
- **UI / flow (`hud.gui_script` posts messages to game or plays through the game script; GUI scripts must not call `go.*`):** `ui_hover` (throttled), `ui_click`, `ui_card` on reward card show, `ui_pick`, `ui_craft` on a successful craft (and play that compound's `sig_*` at gain 0.9 so the player *hears what they made*), `ui_craft_bad` on an invalid cauldron attempt, `ui_cauldron_loop` while in CAULDRON, `room_clear`, `state_title`, `state_win`, `state_dead`.
- Spatial: world sounds use pan from x; UI sounds are centred.
- Update `SFX_MAP.md`. Tests: a scripted run (the existing smoke harness) must assert that each of these events produced its id at least once.

### P5: Adaptive music

- `src/core/music.lua` (pure state logic, backend injected like sfx): states `TITLE`, `ROOM`, `BOSS`, `WIN`, `DEAD`, `CAULDRON/REWARD` (calm: pad only).
- In ROOM, the three stems (`mus_room_pad`, `_rhythm`, `_lead`) **start together** (same length) and are mixed by **intensity** = clamp(enemies alive / 8, 0, 1) blended with a low pass over time: pad always on; rhythm gain rises above intensity 0.25; lead above 0.6. Gain changes are faded (about 0.8 s) by `go.animate` on the sound component's `gain` property (verify it works for `.sound` components in the docs) or by stepping gain each frame in `music.update`.
- Boss uses `mus_boss` (crossfade 1.0 s from the room stems). WIN/DEAD stop the loops and play the sting.
- Optional layer per owned element (only if easy): a tiny tonal tick in the element's root note that gets louder the more of that element the player owns; skip if it complicates P5, record in the summary.
- Music bus volume comes from `sfx.BUS.music`. Restarting a run must not stack loops (leak test: loop-start count equals loop-stop count after a full smoke run).

### P6: Elemental reactions (gameplay + audio + VFX)

Currently statuses do not interact. Add data-driven reactions so the element mixing has consequences.

`src/core/reactions.lua` (pure): a list of

```lua
{ id = "steam_burst", name = "Steam Burst",
  needs = { "burn" },              -- enemy must have ANY of these statuses
  element = "water",               -- the incoming skill must contain this element
  consume = { "burn" },            -- removed from the enemy
  effect = "aoe", radius = 60, damage_mul = 0.6, min_damage = 4, apply = { "blind" }, apply_time = 1.0,
  sound = "rx_steam", fx_family = "steam" }
```

`reactions.check(enemy, skill) -> list of reactions` (evaluated **before** the new hit applies its own statuses; each enemy has a per-reaction cooldown of 0.5 s; at most 3 reactions per frame; AoE reactions cannot chain into AoE reactions on the same frame).

Initial set (tune in `data.lua`/`TUNING`):

| Reaction | Needs (status) + incoming element | Effect |
|---|---|---|
| **Steam Burst** | burn + water | consumes burn; 60 px AoE, 0.6x power (min 4), blinds 1 s |
| **Shatter** | stun or root + earth | consumes it; +0.75x power bonus damage; crack FX |
| **Flare-up** | burn + wind | burn dps x2 for 3 s and spread radius 60 px |
| **Bog** | slow + earth | converts slow into root for 2 s |
| **Whirl** | blind + wind | knocks the enemy back 140 px and confuses it for 2 s |

Wiring: `apply_hit` (P1) calls `reactions.check` and applies results through one `apply_reaction(self, e, r, src)` function: damage via the normal path (so kills, splitters, affinities, damage numbers all work), a floating label of the reaction's name in the skill's element colour (HUD message, see P8), `rx_*` sound, and FX (reuse existing flipbooks: steam/smoke puffs, hit anims, scorch; **no new art is required**; if you want a new effect use `tools/build_fx_anim.py` conventions and keep the sprite cap).

Tests: pure unit tests for `reactions.check` (each reaction triggers, cooldown works, wrong element does not trigger); a smoke scenario in the Training Arena room (burn a dummy with Inferno, then hit it with a water skill, expect `steam_burst`); the reaction sound ids are played. Immortal dummies **do** take reactions (their feedback still fires, HP stays).

### P7: Cross-slot fusion and combo streak

- **Fusion ("Resonance"):** if the player casts slot 1 and slot 2 within `TUNING.FUSION_WINDOW` (1.5 s) and the two skills have **different shapes**, the second cast gets `+TUNING.FUSION_POWER` (default +25%) and emits a ring FX at the player; if the two skills also **share an element**, the first skill's remaining cooldown is reduced by 0.5 s. Plays `fusion` with `speed` rising by one semitone per consecutive fusion (cap +5). Pure logic in `src/game/combo.lua`; flag `TUNING.FUSION_ENABLED`.
- **Combo streak:** `combo.count` increases on each kill or reaction and decays to 0 after `TUNING.COMBO_WINDOW` (2.0 s) of nothing. Each step plays `combo_up` at `speed = 2^(min(count, 12)/12)`, so a streak is a rising scale. Streak thresholds (5, 10, 20) play `crit_streak` and show a HUD banner. The HUD shows the current count and a shrinking timer bar.
- Reward: at thresholds heal 2 HP and shave 0.3 s off both cooldowns (tunable; set to 0 to disable).
- Tests: unit tests for window logic, decay, cap, and determinism (no RNG).

### P8: Juice

Each item has a `TUNING` flag and obeys the **accessibility toggles** from P9 (screenshake, flashes).

1. **Hit-stop:** `self.time_scale` multiplies the simulation `dt`. On kills of strong enemies and on boss hits freeze to 0.05x for 0.04-0.08 s (real time). It must never stall timers that use real time (`room_clear_timer` uses sim time: check that rooms still clear). Tune: normal kill 0.04, brute 0.06, boss phase change 0.12.
2. **Screen shake:** the world is drawn by `main/letterbox.render_script`. Add a minimal `shake` message (`{ amp, time }`) that offsets the **view translation only** while shaking, decaying linearly, direction from `crng`. **Read the whole render script first.** Defold 1.14 moved render constants to `graphics.*` (AGENTS #44): follow the existing resolve-both pattern, change as little as possible, and do not touch the letterbox math. If you cannot do this safely from reading alone, **skip shake, write why in the summary, and offer a UI-less alternative** (jitter only the environment root sprites) for the human to decide. This is a human-verification item either way.
3. **Damage numbers:** the HUD (`hud.gui_script`) creates pooled text nodes at runtime (`gui.new_text_node`; cap 24; fade and rise 0.6 s). The game posts `dmg_number { x, y, text, r, g, b, big }` (design-space coordinates, bottom-left origin). Colour = element B of the skill; reactions use the larger "name" label; immortal dummies show numbers too (excellent for tuning). Avoid `.label` components (needs font/material resources you cannot verify).
4. **Kill FX per element:** use the existing FX packs: fire kills leave embers rising, water kills splash, wind kills spiral, earth kills dust (reuse `ELEMENT_FX`), capped by the existing `self.anims` cap.
5. **Cast anticipation:** a 0.05 s wand-glow pulse and 6-10 % player scale pop on cast (through `anim.lua` multipliers, never negative scale).
6. **Low-HP feedback:** below 30 % HP, a red vignette pulse (HUD node) in time with the `pl_lowhp` heartbeat.
7. **Boss kill:** slow-motion (0.3x for 0.8 s) plus burst of sparks, then the win state.
8. Tests: shake/hit-stop must not break the smoke runs; verify `time_scale` always returns to 1.0; sprite cap and leak checks still pass with the new nodes/objects.

### P9: UI polish and settings

1. **Shape glyphs on skill cards** (skipped earlier): generate five white 64 px glyphs with `tools/make_shape_glyphs.py` (Pillow, original art: Bolt = zigzag arrow, Pool = circle with ripples, Orbit = ring with three dots, Spray = fan, Nova = starburst), add them with `tools/add_to_atlas.py` (ids `glyph_projectile`, ...), and show them in the HUD and the cauldron through `gui.play_flipbook`. Prefer creating the nodes in `hud.gui_script` at runtime over hand-editing the 11 KB `hud.gui` (README: GUI edits are fragile; if you edit `.gui` do it additively and carefully). Fallback: text letter if the animation is missing.
2. **Pause menu** (`Esc`): resume, settings, quit to title. The sim freezes; music keeps playing at 50 %.
3. **Settings screen:** master / sfx / music sliders or +/- buttons, screenshake on/off, flash on/off, damage numbers on/off, **colour-blind aid** (draw the element icon next to every element-coloured thing in the HUD and over damage numbers). Persist with `sys.save` / `sys.load` / `sys.get_save_file` (**verify the API and that it works for the HTML5 target in the docs**) to a small settings table; missing/corrupt file -> defaults.
4. **Title screen:** add a **Practice** button that enters the Training Arena **without** `TUNING.DEBUG`; add subtle animated magic circle (reuse the rotating sigil) and play `mus_title`.
5. **Gamepad:** add additive gamepad bindings (left stick = move, right stick = aim, triggers = cast1/cast2, A = dash) to `input/game.input_binding`, handle the axis actions and aim from the right stick in `on_input`. **Verify the binding syntax in the docs**; if it cannot be tested, mark it "not verified (no pad)".
6. **Cauldron presentation:** when crafting, play a short animation (three ingredient icons fly in, a burst plays in the result colour, the preview name appears with the compound signature sound).
7. Tests: settings table round-trip in a pure function; headless run unaffected.

---

### Tier B: depth

### P10: Enemy affinities

- Add `weak = { element }` and `resist = { element }` to each type in `enemies.lua` (suggested: wisp none, slinger weak earth, charger weak water resist fire, brute weak wind resist earth, splitter weak fire, boss `affinity` rotating below, dummy none).
- Skill match: for a skill with elements {A, B}, count how many of its two elements match the enemy's weak/resist (0, 1, 2). Damage multiplier = `1 + 0.25 * (weak_matches) - 0.20 * (resist_matches)`, clamped to 0.6-1.5 (`TUNING.AFFINITY_ENABLED`). Applied inside `apply_hit` after reactions.
- Feedback: tinted pop + floating "WEAK" / "RESIST" text (small), `hit_weak` (crisp crunch) / `hit_resist` (dull ting) layered on the normal hit sound. A small element icon appears above the enemy's head on first hit to teach the player.
- Keep `skillgen` untouched; keep the reward cards unchanged; the smoke test's win/dead expectations (`WIN,WIN,DEAD,DEAD,DEAD`) must not change: if affinities break the scripted runs, tune multiplier defaults so the harness still passes and record it.

### P11: New enemies and boss phases

- Three new enemy types (data in `enemies.lua`, art mapped in `art.ACTORS` with **existing** Tiny Creatures sprites or tinted shapes (`ART_TEST=0` fallback must work), animation in `anim.lua`): **Shieldbearer** (frontal shield absorbs bolts; broken by Wind push or Quake stun), **Healer Wisp** (heals nearby enemies 3 hp/s; weak to everything, flees), **Bomber** (runs at the player and explodes after a 0.8 s telegraphed ring; kill it first or dash). Each gets sounds (`en_*` ids added to the manifest + generator).
- Add them to `room_composition` budgets (unlock rooms 3-6) and to the authored room legend (`level.lua`, `validate_rooms.py`, new letters) **only where needed**; keep rooms valid.
- **Mid-boss at room 4** ("Guardian": a scaled-up brute with a ring slam) and **boss phases at 66 % / 33 % HP**: phase change = roar, brief invulnerability, new attack set, new `affinity` (fire -> water -> earth), weakness icon shown over the boss.
- Tests: the smoke test gains one pass that spawns each new type and asserts no errors, no leaks, valid art ids.

### P12: Environment and decals

- **Persistent decals** (cosmetic, capped at 40, fade after 12 s, drawn under actors): scorch (fire), wet patch (water), crack (earth Quake), no decal for wind. Spawned by `apply_hit` listeners and puddles. They count against the sprite budget and are cleaned in `clear_world`.
- **Destructible crates (`C` in room rows):** block movement and bolts, destroyed by any damage, **burn** when hit by fire (ignite neighbours), extinguished by water. Add to `level.lua` legend + `validate_rooms.py` + 2-3 authored rooms; give each a `crate_break` sound.
- **Hazard tiles (one new kind only):** wind vents (`^`) that push anything standing on them toward a direction each second; show with a small animated arrow. Document the legend letters in `rooms.lua` header comments.
- **Environmental reactions:** a water puddle turns a nearby earth hit into Mud (rooting enemies standing in it), and a fire hit on a water puddle makes a short steam cloud (blind). Pure logic in `src/game/level.lua`/`reactions.lua`, with tests.

---

### Tier C: meta, content and run structure (ask the human before each phase)

### P13: Finish the original M8 extras
1. **Player-name seeding** (`TUNING.USE_PLAYER_NAME`): a text-entry screen. Text input is not covered by the field guide: read the Defold manual on text input (`text` action and the `key_trigger` for text) first; if it fails, fall back to a short preset-name list. The name goes to `makeSkill` as `playerName` exactly as designed (golden vectors with empty name must still pass).
2. **Quirk reroll** at the cauldron for 10 HP: salted seed `key .. "#" .. rerollIndex` (computed in a wrapper **outside** `makeSkill`; the unsalted result must be unchanged).
3. **"Magic is fading":** each crafted skill lowers a `saturation` value (0.0-0.4 total) applied to the room palette tint and HUD tint, so the world drains of colour as the player grows stronger. Cosmetic, flagged, reversible, and **spells never lose power**.

### P14: Grimoire and mastery
- **Grimoire** screen (from title and pause): the 10 compounds x 5 shapes grid; a recipe is "discovered" when first crafted; shows name, power, quirk, elements, and plays its `sig_*` sound when clicked. Persist with the settings save (a separate `grimoire` key).
- **Mastery:** casts counted per `skill.key` per profile; ranks at 25 / 100 / 250 casts: a tiny ring around the HUD icon, +3 % / +6 % / +10 % power applied **at cast time as a runtime multiplier** (never inside `makeSkill`), and a slightly brighter cast sound layer. Document it, flag it.

### P15: Relics, shrines, shop
- `src/core/relics.lua`: 12 data-driven relics, each a small hook on the event bus (examples: "Fire spells leave embers", "Kills with Wind refund 0.3 s cooldown", "Pools last +2 s", "Reactions deal +30 %", "+15 max HP", "Dash leaves a damaging trail"). Max 4 held.
- **Essence** currency dropped by kills (cosmetic orb flies to the player).
- A **shrine** room type after rooms 3 and 6 (choose 1 of 3 relics, or a risky trade: lose 20 HP for a rare relic) and a **shop** after room 5 (relics and healing for essence). UI built at runtime in the GUI script, sounds `relic_get`, `shrine`, `shop_buy`.
- Keep the Definition of Done: the full run must still reach WIN with all relic flags off.

### P16: Meta-progression and daily seed
- Persisted unlocks: starting elements beyond the first two, wizard "classes" (data tables that tweak HP, dash, starting shape), and a **heat** ladder (opt-in modifiers: more enemies, faster bullets, no heal on clear).
- **Daily seed:** a date-based seed (from `os.date`) used only for **run randomness** (rewards, spawns) through a dedicated RNG, never inside `makeSkill`; show the seed on the title and the result screen.
- Profile save/versioning with a `version` field and migration stub; corrupt file -> defaults.

---

## 4. Definition of done (per phase and at the end)

- Title to WIN and DEAD to title loops without console errors (human-verified; you report headless results only).
- `SELFCHECK OK` and golden vectors unchanged.
- Smoke test default, `ART_TEST=1`, `ART_TEST=0`, anim, rooms: all pass, and numbers compared to the P0 baseline are explained.
- Game fully playable with audio disabled and with each new feature flag off.
- Every new sound id exists in manifest + `SFX_MAP.md` + a file; every third-party asset has credits in `CREDITS.md` **and** `src/core/credits.lua` and a licence in `assets/third_party/`.
- `PROGRESS_SUMMARY.md`, `CHANGES.md`, `AGENTS.md` (Part D), `SFX_MAP.md` updated for the phase.
- A short list of what the human must verify in the running game.

## 5. Things that will break this project (do not do them)

- `gui.*` in the game script, `go.*` in a GUI script, `goto`, `//`, negative sprite scale, `go.set(tint)` on the game object instead of the sprite component.
- Changing `skillgen` generation order, using `math.random` in skill code, or spending gameplay RNG on cosmetics.
- Writing a protobuf-text resource from memory when an example exists or the editor can produce one; writing files with a BOM.
- Hand-rewriting `main.collection`, `game.project` or `hud.gui` instead of editing additively.
- Playing a sound per tick (burn, puddle, orbit contact), one loop per instance, or loops that are never stopped on `reset_run`.
- Unbounded new visuals (decals, numbers, particles) without caps and cleanup.
- Adding a dependency to `make_sfx.py` beyond the standard library.
- Replacing the user's files in place, deleting earlier deliveries, or turning off `TUNING.DEBUG` yourself.
- Claiming "works" without a test, or hiding a failing test.

## 6. Final deliverable (after the last phase you were asked to do)

1. Make sure `PROGRESS_SUMMARY.md` has an up-to-date **Overall summary** a stranger could read in two minutes.
2. Include a **"Human verification checklist"** section: numbered, one line per feature (what to do, what should be heard/seen).
3. Include a **"Replacing the placeholder sounds"** section: the SFX_MAP workflow (drop a file with the same name, run `python tools\add_sounds.py`, Project -> Reload in the editor).
4. Reply with the final report in the section 2.2 format and the list of phases completed, skipped or blocked.

Begin with **P0**. Before writing anything, tell me in 5 to 8 lines how you understood the project and the plan, then start.
