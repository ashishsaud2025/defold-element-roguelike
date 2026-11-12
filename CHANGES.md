# Pause, Settings, Rebind and Training Hall in the menu (v19)

Plan: `docs/superpowers/plans/2026-11-12-pause-settings-training.md` (spec: design doc, approved).
Branch `settings-pause-training`; never touched `main` and never built a zip.
**Nothing in this delivery has been verified on screen.**

## What shipped

- **TITLE gains two buttons**: `SETTINGS` (mid stack, under CREDITS) and `TRAINING HALL` (under SETTINGS).
  The debug `T` key is gone; training is the menu button and only that.
- **ESC = pause** in ROOM, HOME and HOME_EDIT. ESC toggles `PAUSED` — a world-rendered overlay
  over the frozen world (enemies, timers, dashes, cooldowns all freeze exactly like DEAD/WIN). Four buttons:
  `RESUME` / `SETTINGS` / `QUIT` / `QUIT TO MAIN MENU`. RESUME returns to the state ESC was pressed in
  (`ROOM`, `HOME`, `HOME_EDIT`). QUIT is `sys.exit(0)`;
  QUIT TO MAIN MENU resets the run (loadout kept), like DEAD/WIN continue.
- **Editor tabs**: MOUSE / Q / R read white on the dark slot-bg; the active tab is warm gold
  (`accent_gold`) with matching gold-tinted box.
- **Training Arena gains the Lantern Hall altar**: room 10 now declares `altar = { c = 10, r = 10 }`
  (after `rows`, like the validator wants) with a matching `O` pillar under it. Entering via
  TITLE -> TRAINING HALL spawns the same glowing altar prop used by the home room, and standing
  next to it shows `E - EDIT SPELLS` on the control line (gold). E opens the spell editor; `DONE`
  returns to the arena (editor remembers `editor_from`), not to the home hall. Home-only stations
  are cleared on room transitions; the prompt only rides the ROOM payload while a room altar exists.
  The control line in ROOM is now one owner: banner > training-altar prompt > relic tooltip > hint.
- **SETTINGS screen**: `MST/SFX/MUSIC` volume bars at 0.1 steps (0-100%), wired straight into
  `sfx.BUS`; live-rebindable rows for WASD / Q / R / E / SPACE / LMB↔RMB toggle.
  Master, SFX and Music values show as numbers next to the bar.
- **Live key rebinding**: every physical key in the binding file now has a static `k_*` id
  (`k_a`..`k_z`, `k_0`..`k_9`, `k_f1`..`k_f12`, arrows, `k_space`, `k_tab`, `k_enter`,
  brackets, minus, equals, shift/ctrl/alt). The game reads
  `self.bind = { up, left, down, right, cast1, cast2, interact, dash, basic }` and `self.bind_hash`
  (hash map rebuilt only on rebind). Capture mode: click a bind row → next static key becomes
  the binding. Last write wins (duplicates allowed, never a hard error). ESC cancels capture;
  ESC in capture does **not** also pause.
- **HUD**: `hud.gui` grows 154 → **222** nodes. New screens `PAUSED` and `SETTINGS`, plus the six
  new TITLE nodes. All positions validated headlessly (F1 audit 0 problems on both new states).
- **Pathing unchanged** (`8/8` twin lanes, `14/12` gauntlet); results `WIN,WIN,DEAD,DEAD,DEAD`
  identical to the v18 baseline.
- **SFX/fonts untouched** — capture and volume rows are clicky box/text nodes, reuse HUD bars.

## Not shipped

- No settings persistence (bindings reset every launch — there is no save backend yet).
- No gamepad rebinding; mouse is LMB/RMB only.
- The `TRAINING HALL` button always enters room 10 (the Training Arena). ESC opens the pause menu
  from there; otherwise the player is stuck with dummies (but can leave via pause).
- Binding a key used by the debug row (1-5/6-0 shape selectors, `[`/`]` compound cycle, F1 audit) is
  fine; those are read raw, not through `self.bind`.
- No visual asset for the capture banner beyond the existing `capture_note` text line.
- No `KEY_ESC -> pause` metadata comment in the file — the binding reads clean, no comments flag it.

## Harness & verification

- `python tools/check_lua.py` (32 files, 32 OK) — dungeon/game.script paths included.
- `python tools/run_smoke_test.py` (default + `ART_TEST=1`): results `WIN,WIN,DEAD,DEAD,DEAD`;
  `RESULT: PASS`; HUD harness `0 failed` — binding round-trip, capture-cancel, pause freeze,
  QUIT stub route, K/CAPTURE state poisoning, settings volume clamps, TITLE training button,
  payload ORDER/gates updated.
- `python tools/validate_ui.py`: 222 nodes, 222/222 positions mapped, 0 problems.
- `python tools/validate_rooms.py`: 11 room(s), 0 problems.

## Not verified (needs you in Defold)

- Rendering, blending, z-order, text widths, bar lengths under live sfx.BUS values.
- Rebinding feel — capture click, `capture_note` readback, whether the bind visually flashes.
- The pause overlay panels actually sitting behind the world correctly (DEAD/WIN-style reuse).
- Whether Escape is the right key for the player's keyboard layout.
- Whether settings/quit/resume button hit-boxes feel generous enough to click.
- Whether the `ui_audit` still passes on-screen (headless audit reads the model, not the pixels).

## Deliveries

This entry is v19 (`settings-pause-training` branch). No delivery zip built — ask first.

# Home, Loadout and HUD (v18)

Plan: `docs/superpowers/plans/2026-11-12-home-loadout-quirks-hud.md` (spec: design doc, approved).
Branch `home-loadout-hud`; never touched `main`. **Nothing in this delivery has been verified on screen.**

## What shipped

- **Walkable home room**: `src/levels/home.lua` ("Lantern Hall"), entered from TITLE via START.
  One altar and one door. The world keeps rendering behind the `HOME_EDIT` modal.
  The altar opens the loadout editor; the door officially starts a run (`begin_run`).
- **Ability loadout** (`main/game.script`): three slots - MOUSE = slot 3 (basic attack, Bolt only),
  Q = slot 1, R = slot 2. Each slot carries `{ ea, eb, shape, quirk_id }` chosen at the altar.
  Cauldron crafting keeps the slot's quirk (it never overwrites with the recipe hash pick);
  the debug re-craft and shape keys (1-0, `[` / `]`) also keep it.
- **Quirk registry** (`src/core/quirks.lua`): identity, labels, short forms, one-line descriptions,
  behaviour flags, `basic_ok`, display order, `default_id(r2)`, `register`/`unregister` for future
  quirks (two files + flags, no engine change). `skillgen.makeSkill` accepts an optional
  `quirk_id` override; the default path is unchanged (recipe quirk order frozen).
- **Basic attack exemptions** (user-approved): never pays the blood price, never increments the
  Echoing Crystal echo counter; `health_cost` is not offered to the MOUSE slot (`basic_ok = false`).
- **HUD rebuilt** (`hud.gui` grows to **154** authored nodes via `tools/build_hud_gui.py` +
  `tools/hud_nodes.py`, emitter proven byte-identical against the old 125-node file at Task 8):
  hotbar bottom-centre (MOUSE/Q/R keycaps, shape icon, element dots, cooldown overlay that
  drains bottom-to-top, gold frame when ready), portrait health bar with `hp / max` and a thin
  SPACE-dash gauge under it, relic bar + echo pips kept. `s1_name`/`s2_name` are gone.
- **PICK_START is gone**: the state, its screen, its nodes and its actions retired with the home flow.
- **UI art** generated for this project by `tools/make_ui.py` (CC0, see CREDITS.md): slot frames,
  keycaps, portrait, health/dash bars, altar and door sprites. All twelve added to `shapes.atlas`.
- **HOME music** = the calm CAULDRON pad-only stem; the basic attack reuses slot sounds; quirks
  keep their existing sounds.
- **Debug row** now: `[` / `]` cycle slot 1/2 compounds; 1-5 slot 1 shape, 6-0 slot 2 shape;
  T (training room), F1 (F1 audit), O/P/L/K (audio) unchanged. All bound; harness presses them.

## Harness & verification

- `python tools/check_lua.py` (new): LuaJIT `loadstring` on every `.lua`/`.script`/`.gui_script`/
  `.render_script` under `main/ src/ tools/` (33 files). RED-capable (proven on a scratch `return )` file).
- Smoke suite extended: registry section; default-path drift checks for all 50 recipes;
  loadout sanitisation; flag-driven cast path; input routing; home/stations/door/editor tests;
  payload ORDER/gates updated (HOME, HOME_EDIT added; ROOM inventory removed, REWARD/CAULDRON keep it).
- HUD harness extended: HOME and HOME_EDIT screens, three-slot hotbar, cooldown overlay, keycaps,
  ready frame, portrait/dash bars, and the F1 audit handler run headlessly on every state.
- `ART_TEST=1` and `ART_TEST=0` both requested before hand-off (see Verification).
- Fail-proofs run per the plan (see Verification).
- Determinism held: results `WIN,WIN,DEAD,DEAD,DEAD`, pathing room 6 = 8/8, room 8 = 14/12 - the home
  room consumes no gameplay RNG (the tile builder draws none; the mote seeding runs once at init before any room enters).
- UI payload under the 2048 B `msg.post` cap in every state (worst measured: CAULDRON 1974 B).

## Controls

WASD move  |  mouse aim  |  LMB hold = basic Bolt  |  Q = slot 1  |  R = slot 2  |  SPACE dash  |  E interact

## Verification

- `python tools/run_smoke_test.py`: 70 486 checks, 0 failed; pathing 8/8, 14/12; results WIN,WIN,DEAD,DEAD,DEAD; `RESULT: PASS (mock only)`; HUD result `2363` checks, `0 failed`.
- `python tools/validate_rooms.py`: 11 room(s), 0 problem(s) (10 rooms + the peaceful home).
- `python tools/validate_ui.py`: 154 node(s), 154/154 positions mapped, 0 problem(s).
- NOT VERIFIED: rendering, blending, z-order, the generated art's look, editor parsing of
  `hud.gui` / `shapes.atlas` / `home.lua`, the bracket keys on a real keyboard, editor behaviour of
  the door art (48x48, top wall cell), and whether the prompt reads at 960x640 in motion.
  Human hand-off steps: compile, F1 on HOME and HOME_EDIT, walk into a wall/into the door, cast all
  three slots, craft something at the cauldron and confirm the crafted skill keeps the slot quirk.

## Deliveries

This section is the v18 entry. No delivery zip was built - ask first.

# Audio layer (ported from the `effects` branch) (v17)

Audio ported from the `effects` branch (squashed into one commit on branch `audio-sfx`;
the 8-commit history was not preserved). Avinash Joshi's branch carried an audio layer
on top of an older tree; the audit/UI fixes it also contained were superseded by the
`ui-relics` work and are not ported. **Nothing here has been verified on screen** —
audio is unverifiable headlessly.

## What shipped

- **`src/game/events.lua`**: synchronous event bus (`cast`, `hit`, `status`, `quirk`,
  `kill`, `player_hit`, `dash`, `room_clear`, `enemy_spawn`); listeners registered once
  at init (hot-reload safe). No `pcall` — a broken listener is a real bug.
- **`src/core/sfx.lua`**: manifest of every sound id with gain/min_gap/voice cap, global
  voice cap 16, pan from x, `skill_speed` pitch-per-recipe. `sound.play` goes through
  `/sfx#<id>` components wired in `main/sfx.go` (89 components).
- **`src/core/music.lua`**: adaptive stems (`title`, `room_pad`/`rhythm`/`lead` with
  intensity, `boss`, `win`/`dead` stings, `CAULDRON`/`REWARD` pad-only calm).
- **`src/core/crng.lua`**: cosmetic-only RNG (Numerical Recipes LCG); used for pitch wobble.
- **SFX/music assets** (`assets/sfx/**`, `assets/music/**`): generated for this project by
  `tools/make_sfx.py` (original synthesis, no third-party samples — see CREDITS.md).
- **Wiring**: `apply_hit` now emits `hit` (+ `status` per fresh application), `do_cast`
  emits `cast`/`quirk`, `apply_statuses` emits `status` events, plus emitters at dash /
  spawn / kill / room-clear / WIN / DEAD / REWARD→CAULDRON transitions; low-HP heartbeat
  (`pl_lowhp` while below 30 % HP); ROOM music intensity from live enemy count (until
  room clear), `CAULDRON` pad-only music, `DEAD`/`WIN` music stops.
- **Audio audition row**: O/P = previous/next sound, L = play it, K = cast slot 1's
  elemental layers (`TUNING.DEBUG` only). F1 audit = `ui_audit`.
- **Trigger banners/toasts unchanged**: nothing about banners was altered.
- **NOT ported**: the effects branch's elemental-reaction damage engine
  (`src/core/reactions.lua`), its `apply_hit` rewrite, keyboard 1/2/3 reward fallback,
  and its HUD changes (all superseded or out of scope).
- **NOT verified on screen or in any engine build**: audio volume levels, pans, loops,
  music stems, timing. Editor must compile; human must play.

# UI Overhaul + Relic v2 (v16)

Plan: `Agent Instructions/ui_and_relics_master_prompt.md` (Phases 0–E; branch `ui-relics`).
This is the UI rebuild on top of v15 (Pool Reactions): the layout system is now a single
source of truth, the HUD is headlessly testable, and relics v2 replace the 60% roll with
a milestone schedule. **Nothing in this delivery has been verified on screen** — see the
NOT VERIFIED section.

## What shipped

- **Font**: vendored Cascadia Code (`assets/fonts/`, SIL OFL 1.1 — `OFL.txt` + `NOTICE.txt`,
  byte-copied from upstream). All text renders through the existing `cascadia.font`;
  fixed advance 1200/2048 em, exact for this monospace face.
- **`src/ui/layout.lua`**: single source of truth for every screen — palette, rects,
  components (panel/card/icon_slot/button), `M.VERSION` (now "v16"), `M.wrap`, mono-advance
  text width, button registry + `hit_enabled` (with dynamic ctx), `audit_screen` /
  `audit_text_fit` (width AND vertical fit, `M.LINE_HEIGHT = 1.2` assumed, documented as an
  estimate), `M.ALL_RECT_RECT` position map for all 125 nodes.
- **`tools/validate_ui.py`**: now audits all nine screens (inside, overlap, 40×100 min,
  panel inside bounds, all box sizes match their rects, all authored positions zero,
  full-screen nodes mapped to the full screen, exact 125-node count) and passes the
  COMBOS/CREDITS panel bodies built inside Lua.
- **`tools/hud_test.lua`** (new): headless HUD harness — loads the real `hud.gui_script`
  under a stub `gui.*`, renders every state, clicks every button through the real click
  path, asserts vector types, enabled ids, text fit, rect geometry (a)–(d), positions every
  node, and executes the F1 (`ui_audit`) handler headlessly. Wired into `run_smoke_test.py`.
- **2 KB `msg.post` fix**: the engine's message buffer overflowed at element #18 at REWARD.
  Long static text (credits/combos) is now built inside `hud.gui_script` from data, never
  sent; heavy payloads are state-gated per screen; permanant per-state 2048-byte test
  (`enc_upper` upper-bound model) in the smoke suite. Worst measured frame: **1762 bytes**.
- **Phase C gameplay screens** converted: PICK_START (role lines from data, wrapped at
  render time to the tile width), ROOM HUD (HP bar + number, slots with icon/quirk/cooldown/
  bar, room counter, relic bar, ROOM CLEARED banner on last-enemy death), REWARD (cards with
  icon/name/kind tag/desc from data, gold frame on relic cards), CAULDRON (ingredients with
  icons+counts, three slots Elem A/Elem B/Shape, preview with compound/shape/power/cooldown/
  quirk/statuses, pool-reaction hint only for pure pools, owned-relic panel from DEFS, craft
  buttons show current slot contents), DEAD/WIN (title, room reached, relics owned, hint).
  **Inventory string removed from the room HUD.**
- **Phase D — relics v2**: milestone offer schedule (reward screens after rooms 3, 6, 9
  offer exactly one unowned relic + two normal cards; all other screens offer none;
  deterministic for a seed; `src/game/rewards.lua`, pure, `rewards.offer(room_index, owned,
  rng_draw)`); relics carry `icon` + `trigger_text` in `DEFS` (single desc source);
  `relics.echo_progress` / `relics.describe`; relic bar shows one icon per owned relic with
  **hover tooltip** (name — desc) reusing the control-hint line; **5 Echoing Crystal pips**
  advancing on the player's own casts only (echoes never count); per-room, at-most-once
  trigger banners via the existing announce path (ECHO / INFERNO HEART +15% / CATALYST +20%,
  never overwrites another banner, no gameplay RNG, flags reset in `clear_world`).
- **Fixed (found by the console, not by review)**: the interaction banner could never render
  — `on_message` never copied `message.toast` to `self.toast`; `version_text` crashed the
  F1 audit (engine `gui.get_node` raises on unknown ids; it was the only runtime-created
  text node; it is now authored statically); the full-screen `panel`/`flash_box` were
  positioned at the screen's bottom-left corner (the `+480/+320` offset was removed with
  nothing replacing it) — the dark quarter on the title screen.

## Harness & verification

- 2129+ checks green in all three smoke modes (default/AR_TEST=1/ART_TEST=0), pathing
  room 6 = 8/8, room 8 = 14/12; HUD harness 1808 checks; `validate_ui.py` 0 problems
  (125/125); editor compile clean.
- 500 seeded runs assert the relic schedule; echo counter 0..5 wraps; trigger toasts once
  per room and consume no gameplay RNG; room/run reset leaves no relic UI state.

## Verification

- `python tools/run_smoke_test.py` (default / ART_TEST=1 / ART_TEST=0): `WIN,WIN,DEAD,
  DEAD,DEAD`, **70180 checks, 0 failed**, RESULT PASS, HUD RESULT PASS; pathing 8/8, 14/12.
- **NOT VERIFIED on screen**: every layout, font, click, hover, banner and fit claim —
  the mock cannot see the screen. Concrete steps are in the task report (F1 on every screen,
  hover the relic bar, trigger each relic, take a hit for the flash, reward screens via the
  debug key, default and a larger window).

# Pool Reactions (v15)

Plan: `pool_reactions_addendum.md` — one generic, data-driven rule giving six new named combos:
STEAM VENT, MOLTEN GROUND, FIRESTORM, SQUALL, QUAGMIRE, DUST DEVIL. Delivered on top of the v12 checkpoint.
Supersedes the v14 zip (built with the pre-fix FIRESTORM `short` and before the three §6 checks landed);
v13 was likewise superseded for the pre-fix `short` wording.
Mechanism name everywhere: **Pool Reaction** (never "infusion" / "fusion" — Pool Infusion is the separate feature).

## What shipped

- **`src/game/reaction.lua`** (new): pool-reaction resolver and lifecycle — `eligible`, `reaction_for`,
  `start`, `revert`, `live`. Reactions are data-driven: statuses come from the existing `data.COMPOUNDS`
  entry for the pair, filtered to what exists in `STATUS_DATA`, is not `on_player`, and is not already on
  the pool. No status list is hand-written.
- **Targets**: only pure pools (`elements[1] == elements[2]`), alive, `duration > 0`, not `is_trail`,
  `skill_ref ~= nil`. Mixed pools never react (Mud + fire stays Burning Mud). Sources: any spell area
  including pools' own areas, orbit areas, and the bolt pseudo-area in `bolt_interactions`. A pool's own
  area never reacts with itself; at most one reaction per pool per tick; at most one banner per ticker tick.
- **Latch**: a pool reacts at most once per pair per lifetime (`pud.reacted[pair_key]`, never cleared);
  one reaction active per pool; after revert a *different* pair may react. Nothing "to add" = skip silently
  (no latch, no banner).
- **Duration/revert**: `INTERACT.REACTION_TIME = 3.0` s, then `reaction_restore` removes **only** the
  statuses this reaction added and restores the exact base tint of `vis` and `ring` (`==` comparisons, not
  approximate).
- **Banner priority fix**: a reaction banner announces only when no other toast is up
  (`(self.toast_t or 0) == 0`), so Burning Mud / Fire Cyclone / Dense Cloud banners win on conflict —
  Gale over Inferno shows FIRE CYCLONE, not FIRESTORM. The reaction itself (statuses, tint, sparks) still
  fires regardless.
- **Excluded cell**: pool `fire` + spell element `wind` is Fire Cyclone and never fires a reaction. A fire
  Bolt over a pure Gale pool fires FIRESTORM with no cyclone competing (the bolt has no spell area).
- **Visuals**: pool `vis`/`ring` tinted 50 % toward the source element's colour while the reaction lasts;
  deterministic fixed-angle sparks (no `math.random`).
- **COMBO_DATA**: ten entries, all with a ≤ 48-char `short`. The Combos panel now shows all ten as one
  line each (`NAME: short`). Ten short lines are fewer than the previous 14-line body. **Panel fit is not
  verified** - needs the human in Defold. FIRESTORM's `short` is "Fire on a wind pool: it burns."
(the mechanic and its `description` are governed by the `fire+wind` compound's on-pool statuses)
- **Infusion unchanged**: `infusion.lua` untouched; a pool carrying reaction statuses contributes them live
  to infused spells as normal.

## Harness

- `begin_room` and the pathing room loop reset `self.keys` and `self.dash_t, self.dash_cd` (the fuzz
  `play_run` leaves them pressed; targeted tests assume a stationary actor).
- New reaction suite: 11 puddle-path cells × 13 checks each (banner special-cased for wind+fire → expects
  FIRE CYCLONE, the one cell where the cyclone toast wins), `reaction_cells_done == 11`, wind+fire cell keeps
  its statuses/tint/revert/latch/different-pair checks, a fire-Bolt-over-pure-Gale cell (FIRESTORM, no cyclone),
  a fire+wind exclusion check, a listed-order check, and a decay-resume check that only asserts no second
  FIRE CYCLONE banner re-appears.

- Reaction suite additions: control Pool with no overlap never reacts; QUAGMIRE root infusion is live
  DURING the reaction (fresh bolt through the Quake pool) and gone AFTER the revert (the Mud source pool
  gets `duration = 2` in this test, which is what makes "absent after" falsifiable — its native root would
  otherwise infuse forever); room/run reset leaves no `pud.reaction` records and returns the live-object
  count to the like-for-like pristine baseline.
- `FIRESTORM`'s `description` no longer mentions spread; the `fire+wind` compound keeps its engine
  statuses unchanged.

## Verification

- `python tools/run_smoke_test.py` (default / `ART_TEST=1` / `ART_TEST=0`): **1093 checks, 0 failed**, all
  three modes; `RESULT: PASS (mock only)`. Pathing `8/8` (Twin Lanes) and `14/12` (Gauntlet).
- Editor HTTP API (the way earlier phases compile): `POST /command/compile` on the human's open editor →
  `{"success": true, "issues": []}` (re-run twice, including after the description/short edit).
- `python tools/validate_rooms.py`: 10 rooms, 0 problems. `python tools/run_anim_test.py`: 0 failures, PASS.
  Syntax check OK (15 files); BOM check clean; `git branch --show-current` = `pool-reactions`.
- **Note:** the Phase-B-accepted smoke harness was accidentally overwritten by a diagnostic copy during
  Phase-C diagnostics; it was reconstructed from a Temp snapshot and unified-diff-audited (AGENTS.md #68).

## Not verified (needs you in Defold)

- Tint and sparks appearance, whether the banners are readable in a fight, whether ten lines fit the Combos
  panel, and the cyclone/reaction two-banner behaviour on screen.

## Deliveries

- v14 and earlier zips untouched. This entry is **v15** (`Defold Games v15.zip`, next to v10-v14).

# Fire Cyclone (v12)

Plan: `fire_cyclone_combos_addendum.md` — pool-to-pool Fire Cyclone (Phase B) +
COMBOS screen (Phase C) + targeted RNG fix and delivery hygiene (Phase D). Delivered on
top of the v11 checkpoint.

## Phase D — final pass (delivered)

- **Targeted RNG fix, not a blanket revert.** The purity test compares gameplay RNG consumed by
  a Magma-only room vs a Magma+Gale room. Traced by caller-capture (`debug.traceback` per pass):
  the only call site that differed was the arena-mote recycle in `main/game.script:329`, which
  fires in pass A and not in pass B. Motes are cosmetic, so the two purity passes reset
  `self.motes = {}` around `frames(40)` instead of touching gameplay code. `game.script:329`
  is plain `math.random`, unchanged from HEAD. No other site was converted.
- Verified: **dev harness 855 / 0** in all three modes; **HEAD harness minus the six spread
  checks on the final tree runs 754 / 0** — identical to HEAD's count (760 − 6 deleted).
- Honesty about the infusion-globals: at HEAD they pass (754/0 on HEAD-minus-six) and on the
  final tree once the mote-recycle was masked; the earlier "they need the keys/dash reset"
  coupling was an artifact of room-order RNG layouts and no longer holds — with the final tree
  the ablation run of `begin_room` without the keys/dash reset passes **855/0**, so the reset
  was deleted. They are not "known" or "documented" failures; they are green everywhere.
- No per-call global reseed anywhere. The purity passes call `begin_room(PURITY_SEED)`
  (`PURITY_SEED = 0xC0FFEE`) to re-enter the identical room twice; all other rooms are
  generated in the normal, file-order sequence.
- Geometry corrected: `credits_title` screen-y is **510** (authored 190 + 320); `credits_body`
  at 380; `back_box` at 200. Panel body is **15 lines** at 58-column wrap.
  **Fit is not verified visually.**
- Smoke: **855 checks, 0 failed** (three modes); rooms 10 / 0; anim 68042 / 0; syntax OK;
  editor compile `{"success":true,"issues":[]}`; console 0 error lines.
- v11 zip untouched and delivered as previously; this entry is v12.

# Fire Cyclone (v11)

Plan: `fire_cyclone_combos_addendum.md` — pool-to-pool Fire Cyclone (Phase B) + COMBOS screen (Phases C + D).
One wind area over a lingering fire-eligible pool starts or extends a **growing vortex that lives
on the pool itself**; wind never creates a pool; `fire_spread_area` is gone.

## New mechanic
- `data.INTERACT`: `CYCLONE_GROW = 26` px/s, `CYCLONE_MAX_RADIUS = 110`, `CYCLONE_DECAY = 45`
  px/s back to base, `CYCLONE_BOLT_WIND_TIME = 1.0` s of wind per wind-bolt-overlap ticker.
- `spread_fire_area` removed along with its `spread_done` state and the `INTERACT.SPREAD_FRAC` /
  `SPREAD_RADIUS_FRAC` constants. Cyclone state lives on the pool: `pud.cyclone = { base, until_time }`.
  Growth while wind time is live (capped); decay at `CYCLONE_DECAY` back to the pre-cyclone radius;
  the record survives decay, so fresh wind mid-decay just extends (never a second banner).
- `is_fire_pool`: pool containing Fire **or Burning Mud** — Burning Mud counts as fire for the
  bolt path too (`bolt_interactions`).
- Self-trigger excluded: the area registered by a Pool carries `source = pud`, and the interaction
  ticker skips any area whose source is that pool (Ember's own fire-wind overlap is intentional).
- Visuals: the pool's `vis`/`ring` rescales every frame while cyclonic; ring `rotation` spins slowly;
  ember cadence scales inverse of radius so it stays even at the cap. No new sprites, no new art.
- `announce("FIRE CYCLONE", ...)` — 1.4 s HUD banner on the existing toast node (AGENTS #53: text a
  human can see), plus the existing ring+sparks burst. No new screen-shake / flash.

## Infusion toast
Unchanged: `INFUSED: <compound>`, ~0.8 s, never overwrites an interaction banner, throttled
(1.5 s). The Combos reference table ships in `src/core/data.lua` as `M.COMBO_DATA`
(ordered; upper-case names matching the existing banner lines byte-for-byte) with a
`COMBO_BY_ID` lookup next to it; `src/core/combos.lua` builds the panel body (name, wrapped
verbatim description, blank line, ×4).

## COMBOS screen
- Title screen gets a **COMBOS** button between START and CREDITS; CREDITS moved down one slot
  (y = -70 → -150). COMBOS at y = -70.
- `hud.gui_script`: COMBOS state — title group hides, `credits_title`/`credits_body` grow the
  panel (same nodes, reused; never a new gui file), `back_box`/`back_text` shown. Panel body
  text is `combos.panel_text()` — reads `M.COMBO_DATA` verbatim, line-wrapped at 58 columns
  without changing any word. COMBOS added to the menu flag at hud.gui_script.
- `handle_ui_action` (game.script): `combos` accepted only from TITLE → COMBOS; `back` from
  CREDITS **and** COMBOS → TITLE. `combos` ignored in ROOM/DEAD/WIN.
- All four interaction banners read their names from `M.COMBO_DATA[*].name` (Fire Cyclone,
  Burning Mud, Dense Cloud — unchanged strings, now single-sourced).
- Panel body contains all four combo names (smoke-checked on the real builder) and the three
  interaction banners match COMBO_DATA (smoke-checked end to end).
- Smoke: **855 checks, 0 failed** (27 new since 828), `ART_TEST=1/0` PASS, rooms 10/0,
  anim 68042/0, editor compile OK. Fire Cyclone remains in the failing-only list nowhere —
  all §6 cyclone + infusion + pathing + DENSE/Burning Mud + combos checks are green.

## Tests (tools/smoke_test.lua, rebuilt end-to-end)
- Harness rebuilt from `git show HEAD:tools/smoke_test.lua` + the cyclone suite at the tail;
  section order preserved everywhere before Phase D. Deterministic per-test rooms now:
  `begin_room()` does `ROOM_SEED = ROOM_SEED + 1; math.randomseed(ROOM_SEED)`, so every test
  gets an identical room each run regardless of section order.
- All enemies fully frozen in test helpers (charging, charge velocities, shoot/pattern/summon
  timers, wander timer/target) — a "calm" dummy that still rushes was the same enemy as before.
- Mock records `live[id].scale` (bounds, NaN, non-positive already enforced); tests assert on the
  visible scale values, not the flags that precede them.
- New checks: cap reached / never a second pool / forced-decay returns exactly to the pre-cyclone
  radius / pool expires mid-growth without leaking visuals / Ember (self vs separate fire pool) /
  trail patches never cyclone / Gale Bolt `CYCLONE_BOLT_WIND_TIME` with **burning Mud as the fire
  element** / cap-sized pool untouched / bigger-slower from 78 → 78 / banner on start, none on
  extend / scale tracking of vis+ring / **decay-resume: fresh wind mid-decay resumes growth, no
  second banner** / room reset leaves no cyclone behind / **fixed-seed: the cyclone path consumes
  no gameplay RNG** / infusion compatibility against the grown radius (bolt passes now that it
  misses at base, and does not pass after decay).
- Added at review: absolute `#self.puddles` constant during growth (no pool spawned while the
  cyclone grows) / **Burning Mud via the interaction ticker** (not just the bolt path) / reset
  leaves no cyclone records and the live-object count returns to the pristine baseline exactly.
- Fail-proof shown for the self-trigger guard (`a.source ~= pud` removed → exactly the three
  Ember Pool checks fail, restore → green); CYCLONE_GROW=0 fails exactly the ten
  growth-dependent checks (restore verified byte-for-byte, hash-tracked).
- Both `calm_enemy` copies (infusion section and cyclone suite) freeze every enemy channel;
  they had drifted, leaving the infusion tests weaker than the cyclone tests.
- **828 spellcraft checks, 0 failed**, `ART_TEST=1` and `ART_TEST=0` PASS, `validate_rooms.py`
  -> 0 problem(s), `tools/run_anim_test.py` -> 68042 checks / 0 failures, results WIN,WIN,DEAD,DEAD,DEAD.
- Intrinsic: the game and its harness had visual draws consuming gameplay `math.random()`, which
  shifted room layout for every later test; `crand`/`crand_angle` (mulberry-ish, seed
  `0x9E3779B9`) now feed every visual-only draw (hit sparks, kill scorch, motes, rising embers,
  spray fan). Gameplay RNG stays behind `math.random`. The D3/accent tests pass again, and
  pathing-room RNG matches HEAD in every logged room.
- Removed: the six `fire spread` checks that the addendum requires replaced by the cyclone
  suite; only four of the six can ever fire (the other two sat behind `if spread then`).
  Mislabeled infusion check names were corrected (`bolt infused at base radius`,
  `cyclone: bolt through the grown cyclone was not infused`, `bolt infused after the cyclone decayed`) — the infusion-adjacent checks now carry the `cyclone:` prefix like the suite they live in.

## Defold sanity
- `game.script` parses clean (headless `lupa` + `luac`-style syntax check of the chunk).
  Editor compile is the human's machine — the editor project loaded and rebuilt fine at 10:35,
  no file errors, but I have **not run the game**. Ask the console before assuming anything,
  especially anything rendering, z-order, blending, or HUD.
- No new files, no new art, no new actions/animations; nothing added to the sprite budget
  (the pool's existing `vis`/`ring` are rescaled, never spawned).

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

## Infused Spray and Nova are now readable
- Spray was invisible to a player: only 6 small 0.35 s sparks at the cast point, no tint
  anywhere. Now, only on infused casts: `c.vis` glow and all 14 fan particles are blended
  60% toward the newest live Pool's colour, and 7 pool-coloured accent particles land along
  the cone axis at fixed angles (deterministic, never per frame).
- Nova was the same invisible 6 sparks. Now, on infused casts: `b.vis` glow tinted toward the
  pool colour, one expanding pool-coloured ring grows from 0.6x to 1.2x the burst radius
  (particle cap-immune path), and 8 pool-coloured sparks fly off the rim at fixed angles.
  The delayed split burst mirrors it (its own accents) and does not re-toast.
- Both draw a short HUD toast `INFUSED: <Pool compound>` (~0.8 s, existing toast path). It
  never overwrites a live interaction banner (Burning Mud / Dense Cloud win) and fires at
  most once per 1.5 s. All new accents go through the bounded, cap-immune accent path
  (`ACCENT_CAP` raised 24 -> 48 so a fully-infused split Nova fits: 30). No new art.
- `TUNING.DEBUG` now logs one terse line per infused hit for all four shapes:
  `INFUSED <shape>: pools=<compounds> +<added statuses> x1.25`.
- Split note: the spray's `math.random()` fan spread is pre-existing spec 6.3 behaviour, not
  touched here (cosmetic spacing, always < 70 deg either side of the aim).

## Bugs fixed on the way
- The infusion accent called `spawn_particle`, whose 260-particle soft cap silently dropped every
  accent particle at a full budget — and the old smoke test asserted the `infused_visual` flag,
  which is set before dispatch, so it passed anyway. `infusion_accent` now inserts its particles
  directly with its own ceiling (originally 24, raised to 48 this round so a fully-infused split
  Nova fits — 30 accent entries), counted via an `accent` flag on the entry; `spawn_particle` is
  unchanged for everything else. New test fills `self.particles` to 260 and asserts the accent
  entries exist (Bolt/Spray/Nova/Orbit) plus the ceiling under heavy infusion. Fail-proofed by
  reverting the fix (all 7 accent checks fail).
- Infusion-only visuals could be confused with the compound's own fireworks even when they
  fired; Bolt/Orbit read because they tint a sprite the player watches, Spray/Nova had no
  persistent tint at all. Fixed as above.
- The visibility tests originally used a Mud pool with a fire nova/spray: the fire spell's
  area also ignites the Mud pool (Phase 3 interaction) and the resulting BURNING MUD banner
  raced the toast assertions. All infusion-toast assertions now use a Mist pool (no
  interaction). (AGENTS #56)
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

## Story intro + boss chest + ending
- New src/core/story.lua (intro dialogue, ingredients, chest + ending text).
- Intro dialogue with the sick wife (bed in the Lantern Hall) shown once per launch after START.
- Room 9 boss no longer ends in WIN: a chest (1 ingredient) and an exit door appear; door -> "journey has just begun" -> scrolling credits -> main menu.
- New states STORY and ROLL (HUD reuses the overlay + credits nodes). New art: chest.png, bed.png.
- Rooms 1-8: sealed entry door in the bottom wall (player arrives above it), exit door on the top/left/right wall that opens only after the room is cleared (and reward + cauldron are done); E at the door goes to the next room.
- Wife's bed moved to the top-right of the Lantern Hall (spawn next to it) so the bottom dialogue box does not cover it.

---
# CAULDRON screen redesign (2026-11-12)
- New look matching the mock: pixel-art alchemist room backdrop, gold-framed INGREDIENTS panel (icon, name, count, gold highlight on the picked rows), title banner, status scroll, three ingredient tiles under the cauldron, spell preview panel (animated element flame icon, Power/Cooldown, Quirk, Statuses), two CRAFT cards ("was: <spell>", "quirk: <short>"), purple DONE - ENTER ROOM button, relic summary (Relics: n/4 + newest relic) top-right and looping smoke puffs over the cauldron.
- Art: `tools/make_cauldron_ui.py` -> `assets/art/ui/cd_*.png` (registered in `shapes.atlas`). Smoke: existing `fxa_smoke_a` (Free Smoke Fx Pixel 2) looped from the HUD script.
- `src/ui/layout.lua` CAULDRON block rewritten (new `art`, `ing_shape_icons`, `align` text fields); `tools/hud_nodes.py` +32 nodes (254 total), removed `cauldron_icon`, `relic_2..4`; new `cdbg` GUI layer (backdrop/frames, drawn under everything).
- `main/hud.gui_script`: left/right aligned text via PIVOT_W/PIVOT_E, hover skins (`cd_tile_hot`, `cd_card_hot`, `cd_btn_done_hot`), `done_box` is an invisible hit area on this screen with the art in `cd_done_art`. The `panel` node and `panel_cauldron` are no longer drawn on CAULDRON.
- Tests updated for the new text format (`tools/hud_test.lua`) and node count (`tools/validate_ui.py`). Gameplay and the ui message size are unchanged.
- Not verifiable headlessly: real rendering. Check in the Defold editor that the `cdbg` layer order, the smoke loop and the preview flame look right.

