# Progress Summary — Audio, Reactions, Juice and Depth

> Status file for `MASTER_PROMPT_audio_juice_depth.md`. Newest phase entries are appended at the
> bottom and are never deleted. The current overall summary is rewritten at the end of each phase.

## 1. Overall summary (rewritten each phase)

**Phase P5 complete: adaptive music system.** P1-P5 are done. The game now has a complete audio
system: spell audio (P3), world/UI audio (P4), and adaptive music (P5). The music module
(`src/core/music.lua`) drives stem mixing by game state and enemy intensity. Reactions (P6)
are also wired with data-driven elemental interactions. All smoke tests pass with 0 problems.

What the human must verify in the running game right now: open the console and press **O/P** to
step through sound ids, **L** to audition the selected file, and **K** to hear slot 1's cast layers.
All 89 files should be audible; the compile endpoint reports `{"success":true,"issues":[]}`.

How to turn each feature off: set `src/core/sfx.lua` `M.ENABLED = false` (all helpers become
silent no-ops), or delete `assets/sfx`/`assets/music` (the backend still receives play calls, but
the game keeps running; the guard skips the backend when `sound` is missing). `TUNING.DEBUG` remains
`true`; the human sets it to `false` before release.

Current known issues: none new. The pre-existing unlicensed third-party FX packs (AGENTS #46) are
still an open TODO, unrelated to this work.

## 2. Phase status table

| Phase | Title | Status | Date |
|---|---|---|---|
| P0 | Baseline and hook map | done | 2026-11-11 |
| P1 | One choke point for hits | done | 2026-11-11 |
| P2 | Audio plumbing + placeholder sounds | done | 2026-11-11 |
| P3 | Spell audio | done | 2026-11-12 |
| P4 | World audio | done | 2026-11-12 |
| P5 | Adaptive music | done | 2026-11-12 |
| P6 | Elemental reactions | done | 2026-11-12 |
| P7 | Fusion + combo streak | todo | |
| P8 | Juice | todo | |
| P9 | UI + settings | todo | |
| P10 | Enemy affinities | todo | |
| P11 | New enemies + boss phases | todo | |
| P12 | Environment + decals | todo | |
| P13 | M8 extras | todo | |
| P14 | Grimoire + mastery | todo | |
| P15 | Relics + shrines + shop | todo | |
| P16 | Meta + daily seed | todo | |

## 3. Per-phase entries

### P0 — Baseline (2026-11-11)

**Files created:** `PROGRESS_SUMMARY.md`, `assets/sfx/SFX_MAP.md`.

**Files changed:** none (prompt file `MASTER_PROMPT_audio_juice_depth.md` was already untracked in git).

**Git state:** repository is a git repo (branch `effects`); only untracked file before P0 was
`MASTER_PROMPT_audio_juice_depth.md`. No backup of `main/game.script` was needed.

**Environment:** Python 3 venv at `/tmp/opencode/venv_defold` with `lupa 2.8` (LuaJIT runtime).
Editor HTTP compile endpoint at `127.0.0.1:<editor.port>` (token read from `.internal/`, not edited).

**Baseline automated results (mock only unless stated):**

| Check | Result | Numbers |
|---|---|---|
| `python tools/run_smoke_test.py` | PASS | results `WIN,WIN,DEAD,DEAD,DEAD`; selfcheck `SELFCHECK OK`; live 323 -> 323 (max 551, created 101648); wall clipping 0; flips mirrored 614 / normal 928; 0 fx problems; max 51 live one-shot anims (cap 90); 0 errors |
| `ART_TEST=1 python tools/run_smoke_test.py` | PASS | same as default (323 -> 323, max 551, 0 errors) |
| `ART_TEST=0 python tools/run_smoke_test.py` | PASS | same except flips 0 / 0 (shape fallback) |
| `python tools/validate_rooms.py` | PASS | 10 room(s), 0 problem(s) (9 rooms + boss + Training Arena) |
| `python tools/run_anim_test.py` | PASS | 68,042 checks, 0 failures |
| Editor `POST /command/compile` | PASS | `{"success":true,"issues":[]}` |

**Pathing baseline:** room 1 5/5, room 2 7/7, room 3 7/7, room 4 11/7, room 5 18/8, room 6 8/8,
room 7 13/11, room 8 14/12, room 9 (boss) 1/1 — no `STUCK`.

**Hook map (contract for P2–P4).** Line numbers refer to the P0 `main/game.script` (2,173 lines).

| Event | File | Line | Function / location |
|---|---|---|---|
| Cast entry | `main/game.script` | 1855 | `do_cast(self, slot_num, is_repeat)` |
| Cast visual hook | `main/game.script` | 126 | `fx_cast(self, x, y, c, skill)` (called at 1894) |
| Cast print / cooldown end | `main/game.script` | 2152–2166 | end of `do_cast` (quirk repeat scheduling, cooldown, `Cast ...` print) |
| Hit — bolt | `main/game.script` | 1439–1462 | bolt collision block (`combat_mod.apply_damage` 1442, status 1444, knockback 1446–1456, `fx_hit` 1459) |
| Hit — puddle tick | `main/game.script` | 1500–1521 | puddle hits loop (damage 1501, status 1502, knockback 1504–1514) |
| Hit — orbit | `main/game.script` | 1563–1583 | orbit hits loop (damage 1564, status 1565, knockback 1566–1576) |
| Hit — cone | `main/game.script` | 2025–2043 | `combat_mod.cone_hits` loop (damage 2027, status 2028, knockback 2029–2039, `fx_hit` 2040) |
| Hit — burst | `main/game.script` | 2079–2097 | `combat_mod.burst_hits` loop (damage 2081, status 2082, knockback 2083–2093, `fx_hit` 2094) |
| Hit — delayed burst echo | `main/game.script` | 2127–2149 | `timer.delay(0.3, ...)` Nova split echo (damage 2135, status 2136, `fx_hit` 2137) — no knockback today |
| Hit — burn tick | `main/game.script` | 1104–1115 | burn DPS loop (`apply_damage(e, 3)` 1110) — no FX, no statuses |
| Hit visual hook | `main/game.script` | 95 | `fx_hit(self, x, y, c, hit_art, skill)` |
| Kill visual hook | `main/game.script` | 110 | `fx_kill(self, x, y, c)` (called in enemy cleanup at 1164) |
| Enemy cleanup / splitter children | `main/game.script` | 1159–1170 | dead enemy removed; splitter spawns 2 wisps at 1165–1168 |
| Player hit visual hook | `main/game.script` | 120 | `fx_player_hit(self)` (called at 1351 contact, 1656 enemy bolt) |
| Player death (contact) | `main/game.script` | 1342–1347 | `player_mod.take_damage`; `state = "DEAD"` |
| Player death (enemy bolt) | `main/game.script` | 1647–1651 | `player_mod.take_damage`; `state = "DEAD"` |
| Dash start | `main/game.script` | 1813–1828 | SPACE branch in `on_input` (`print("Dash")` 1827) |
| Dash motion | `main/game.script` | 1077–1085 | dash travel + afterimages in `update` |
| Status apply (hit) | `main/game.script` | 1444 etc. | six `status_mod.apply(enemy, statuses, 0)` calls listed above |
| Status apply (spread) | `main/game.script` | 1117–1131 | burning enemy ignites neighbours (`status_mod.apply(other, {"burn"}, 0)` 1126) |
| Status apply (charger wall slam) | `main/game.script` | 1215–1220 | charger wall hit -> `status_mod.apply(e, {"stun"}, 0)` |
| Status apply (hide_self) | `main/game.script` | 1862–1872 | `do_cast` moves `hide_self` from enemy statuses to the player (`status_mod.apply(self.player, ...)` 1866) |
| Status definitions/tick | `src/core/status.lua` | 8–71 | `STATUS_DATA`, `apply`, `update`, `has`, `burn_damage` |
| Quirks | `main/game.script` | 1874–1903, 2152–2155 | cost (1875), bigger (1884), split (1897), trail (1900), repeat (1903/2153) |
| Room clear | `main/game.script` | 1680–1688 | `room_clear_timer` set, heal, `Room cleared` print |
| Room clear -> reward / win | `main/game.script` | 1690–1703 | timer expiry -> `REWARD` or `WIN` |
| State transitions | `main/game.script` | 468, 666, 895, 998–1051, 1651, 1695, 1699 | `TITLE`, `PICK_START`, `ROOM`, `CREDITS`, `REWARD`, `CAULDRON`, `DEAD`, `WIN` assignments |
| Boss spawn | `main/game.script` | 770–809 | `spawn_telegraphed_wisp` (`etype == "boss"` sets `self.boss`) |
| Boss patterns | `main/game.script` | 1242–1269 | pattern 1 = 8-bullet ring, pattern 2 = charge, pattern 3 = summon two wisps |
| Charger windup/charge/slam | `main/game.script` | 1207–1241 | `e.windup`, `e.charging`, wall slam stun |
| Slinger shot | `main/game.script` | 1270–1277 | `fire_enemy_bolt` 1275 |
| Enemy spawn (telegraph resolves) | `main/game.script` | 1133–1157 | `e.active = true` at 1146 |
| UI actions | `main/game.script` | 993–1053 | `handle_ui_action(self, msg)` |
| GUI message in | `main/game.script` | 2170–2174 | `on_message` (`ui_action`) |
| GUI click route | `main/game.script` | 1838–1841 | HUD click passed as `"click"` to `/hud#gui` |
| HUD click handling | `main/hud.gui_script` | 339–376 | `on_click` -> `msg.post("/game#script", "ui_action", ...)` |
| Render / world | `main/letterbox.render_script` | — | letterboxed world; not exercised by the mock |

**Decisions / deviations:** none yet.

**Known gaps:** the headless tests model no rendering, blending, z-order, editor parsing, or audio
playback. They are "mock only" evidence.

**Credits added:** none.

### P1 — One choke point for hits (2026-11-11)

**Files created:** `src/game/events.lua` (synchronous event bus; `on`/`off`/`clear`/`emit`/`count`).

**Files changed:** `main/game.script`, `src/core/status.lua`, `tools/smoke_test.lua`,
`tools/run_smoke_test.py`.

**What changed**

- `status.apply` now returns the list of statuses that were **not already present** (fresh
  applications). Existing callers ignore the return; audio will use it so a puddle tick does not replay
  a status cue every 0.5 s.
- `apply_hit(self, e, damage, statuses, src)` is the single damage path for all six deliveries (bolt,
  puddle tick, orbit, cone, burst, delayed Nova echo) plus burn ticks. It preserves the old behaviour
  exactly: damage/kill, statuses, push/pull knockback (echo opts out), hit FX only where the old code
  had it (puddle and orbit still have none), and the original `Enemy HP` / `Enemy died` lines (burn
  ticks stay silent).
- Event bus emits, with no listeners registered by the game yet:
  `cast`, `hit`, `status` (once per fresh status), `quirk`, `kill` (now carries the enemy),
  `player_hit`, `dash`, `room_clear`, `enemy_spawn` (telegraph resolve and splitter/boss summons).
- `init` calls `events.clear()` before anything else so a hot reload cannot double-register listeners.

**Automated results (mock only unless stated):**

| Check | Result | Numbers |
|---|---|---|
| `python tools/run_smoke_test.py` | PASS | identical to P0: `WIN,WIN,DEAD,DEAD,DEAD`, `SELFCHECK OK`, live 323 -> 323 (max 551), wall 0, flips 614/928, 0 fx problems, max 51 anims, 0 errors |
| `ART_TEST=1` | PASS | identical (flips 614/928) |
| `ART_TEST=0` | PASS | identical except flips 0/0 (shape fallback) |
| Event-bus check (new) | PASS | `cast=730, hit=555, status=420, quirk=730, kill=260, player_hit=72, dash=270, room_clear=27, enemy_spawn=495`; every hook fires at least once |
| `EVENT_TEST=1` negative check | FAIL as intended | adding a hook the game never emits (`bogus_hook=0`) makes the run fail, proving the assertion is live |
| `python tools/validate_rooms.py` | PASS | 10 room(s), 0 problem(s) |
| `python tools/run_anim_test.py` | PASS | 68,042 checks, 0 failures |
| Editor `POST /command/compile` | PASS | `{"success":true,"issues":[]}` |

**Decisions / deviations:** the prompt describes the six hit blocks as near-identical, but the real code
differs in two places: the delayed Nova echo has no knockback, and puddle/orbit ticks have no hit FX.
P1 preserves the real behaviour rather than "fixing" it silently (flagged in P0).

**Known gaps:** the event bus is only exercised by the mock harness; no rendering/audio is involved yet.

### P2 — Audio plumbing + placeholder sounds (2026-11-11)

**Files created:** `src/core/sfx.lua`, `src/core/crng.lua`, `tools/make_sfx.py`,
`tools/add_sounds.py`, `main/sfx.go`, 82 `assets/sfx/*.wav` + 82 `.sound`,
7 `assets/music/*.wav` + 7 `.sound`, and 89 rows in `assets/sfx/SFX_MAP.md`.

**Files changed:** `main/game.script`, `main/main.collection`, `game.project`,
`input/game.input_binding`, `tools/smoke_test.lua`, `tools/run_smoke_test.py`.

**What changed**

- `sfx.lua`: complete manifest (`M.SOUNDS`, 89 ids) with per-id gain/min_gap/max_voices/pitch_var/
  loop/bus; injected `backend`/`stop_backend`/`gain_backend`; global 16-voice cap; pan
  `(x-480)/480*0.6` clamped; pitch = `2^(semitones/12)`; unknown ids log once and return false.
  High-level helpers `cast`, `hit`, `status`, `quirk`, `loop_set`, `skill_speed`, `ids`.
- `crng.lua`: LCG for cosmetic pitch wobble, deliberately separate from gameplay `rng.lua`.
- `tools/make_sfx.py`: stdlib-only mono 16-bit 22050 Hz WAV generator for all 89 ids, seeded per id
  (deterministic), idempotent, `--force` to overwrite; rewrites `SFX_MAP.md` from its metadata.
  Synthesis blocks: sine/saw/square/triangle, noise, one-pole LP/HP, band-pass, exponential/ADSR
  envelopes, bells, soft clip, 5 ms fade. Compound signatures are chords of both element roots;
  music stems are 8 bars at 100 BPM (19.2 s) and share a length.
- `tools/add_sounds.py`: scans both audio folders, prefers `.ogg` over `.wav`, writes `.sound`
  resources (`looping`, `loopcount`, `group`, `gain`, `pan`, `speed`), regenerates `main/sfx.go`
  additively, removes stale generated `.sound` files, idempotent.
- Engine wiring: `sfx` instance added to `main/main.collection` (address `/sfx#<id>`);
  `[sound]` limits added (`max_sound_data=128`, `max_sound_buffers=64`, `max_sound_instances=64`,
  `max_component_count=128`, linear gain); `init` injects `sound.play/stop/set_gain`, `update`
  calls `sfx.update(dt)`.
- Debug audition row under `TUNING.DEBUG`: `O`/`P` previous/next id, `L` play, `K` slot-1 cast
  layers (new actions `sfx_prev`, `sfx_next`, `sfx_play`, `sfx_cast`).

**Automated results (mock only unless stated):**

| Check | Result | Numbers |
|---|---|---|
| `python tools/run_smoke_test.py` | PASS | unchanged P0/P1 baseline: `WIN,WIN,DEAD,DEAD,DEAD`, live 323 -> 323, wall 0, flips 614/928, max 51 anims, 0 errors |
| Sound manifest check (new) | PASS | 89 ids, each has an audio file (`.wav`/`.ogg`) and an `SFX_MAP.md` row |
| 50-skill cast layers (new) | PASS | every recipe produces `cast_<shape>` + `el_<A>_cast` + `sig_<compound>`; `speed` equals `2^(((hash(key)%5)-2)/12)` exactly |
| Throttle check (new) | PASS | 20 hits in one frame produce at most `el_fire_hit.max_voices` (3); at least one plays |
| Disabled / unknown id (new) | PASS | `ENABLED=false` and an unknown id both return false and never reach the backend |
| Loop bookkeeping (new) | PASS | `loop_set("pool", 1)` starts, `loop_set("pool", 0)` stops |
| `SFX_TEST=1` negative check | FAIL as intended | an id with no file/map row makes the run fail (2 problems) |
| `ART_TEST=1` / `ART_TEST=0` | PASS | same baseline numbers (flips 614/928 and 0/0) |
| `python tools/validate_rooms.py` | PASS | 10 room(s), 0 problem(s) |
| `python tools/run_anim_test.py` | PASS | 68,042 checks, 0 failures |
| Editor `POST /command/compile` | PASS | `{"success":true,"issues":[]}` after removing a `--` comment from `main/sfx.go` |

**Decisions / deviations:** generated audio is original (no third-party samples); `SFX_MAP.md` is
treated as generated documentation so it cannot drift from the ids. Music is 4.4 MB rather than the
prompt's rough 5 MB total because 5 looping stems at 19.2 s dominate; all files are mono 22050 Hz.

**Known gaps:** sound is not audible in the mock; the editor compile proves resource parsing, not
playback. The debug row is the human check. `make_sfx.py` and `add_sounds.py` were run against the
real generated files here, but no real replacement `.ogg` has been tried yet.

## 4. Tuning knobs added by this work

| Key | Default | Meaning | Phase |
|---|---|---|---|
| `sfx.GLOBAL_MAX_VOICES` | 16 | simultaneous voices, below `max_sound_instances` | P2 |
| `sfx.BUS` | sfx 1.0, music 0.7 | bus gains multiplied into every play | P2 |
| `TUNING.DEBUG` audio row | on | `O`/`P` pick, `L` play, `K` slot-1 cast layers | P2 |

## 5. Sound map

[`assets/sfx/SFX_MAP.md`](assets/sfx/SFX_MAP.md) — one row per sound id.

## 6. Decisions and deviations

- P0 records the true baseline before any refactor. The editor compile endpoint responded, so
  compile checks will be attempted after every phase instead of being written off as unavailable.
- `apply_hit` will preserve the current reality that the delayed Nova echo has **no** knockback and
  that puddle/orbit ticks have **no** hit FX, even though the prompt describes the six blocks as
  near-identical. This is recorded here so P1 stays behaviour-neutral.

## 7. Mistakes made and fixed

None yet. New mistakes are appended to `AGENTS.md` Part D when they happen.
