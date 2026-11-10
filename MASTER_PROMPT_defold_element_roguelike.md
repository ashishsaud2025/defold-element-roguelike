# MASTER PROMPT: Element-Mixing Roguelike (Defold, Game Jam, Theme: "Magic")

> **Status note (2026-11-10):** this is the original brief. The project has since moved on (authored rooms, additive effects, art manifest). Read `AGENTS.md` and `README.md` section 13 first; where they disagree with this file, **they win**. Known errors in this brief are listed in `AGENTS.md` Part B (items 26-29).

> Paste this whole file into your coding agent as the first message. Keep `README.md` (the Defold Agent Field Guide) in the project root so the agent can read it.

---

## 0. Your role and ground rules

You are the coding agent building a complete, playable 2D roguelike in **Defold 1.14.x on Windows**.

1. **Read `README.md` (the Defold Agent Field Guide) fully before writing anything.** Treat it as law. In particular:
   - You author and read files. **You do not run `bob`, bundle, or launch the engine.** The human opens the project in the Defold editor and runs it.
   - Resource paths use forward slashes with a leading `/` (`/main/game.script`). Filesystem paths and shell snippets are Windows / PowerShell.
   - Never edit `.internal/` or `build/`.
   - Edit `.collection`, `.go`, `.gui`, `game.project` **additively**. Never rewrite them from scratch and never drop existing keys.
   - Prefer standalone component files (`.sprite`, `.factory`) over `embedded_components` / `embedded_instances`.
   - Do not invent APIs. If a function is not in README section 7 and you are unsure, look it up (README section 11: `https://defold.com/ref/`) before using it.
   - Do not create a custom render script.
2. **Lua logic first, resource files minimal.** About 90% of the work should be Lua. Hand-written resource files are where agents break things, so keep them few and tiny.
3. **You cannot run the game.** So you work in **milestones** (section 9). After each milestone, stop and give the human a short checklist to test. Ask them to paste the **Defold console output** if anything fails. Do not start the next milestone until they confirm.
4. **Ask before assuming only about blocking things** (project folder path, missing assets). Everything else is decided below. Do not re-open the design decisions in section 3.
5. Every milestone must leave the game in a **runnable state**. Never leave the project half-wired.

When you finish a milestone, reply in exactly this format:

```
MILESTONE <n> DONE
Files created: ...
Files changed: ...
Wiring: <which .go/.collection/game.project lines connect it>
How to test: <numbered steps>
Expected console: <what should print, what must not appear>
Known gaps: ...
Credits added: <asset, author, license> or "none"
```

---

## 1. The game in one paragraph

A top-down 2D arena roguelike. The player is a wizard (a colored circle). After every room the player picks a reward: either an **element** (Fire, Water, Wind, Earth) or a **shape** (Projectile, Puddle, Orbit, Cone, Burst). At the **cauldron** the player combines **two elements + one shape** into a skill. The two elements form a **compound** (Fire + Water = Steam) which decides *what the skill does*, and the shape decides *how it is delivered*. Steam + Projectile = "Steam Bolt", a bolt that pushes and blinds. Fire + Fire + Puddle = "Inferno Pool", a burning zone. **Skills are deterministic**: the same recipe always produces the same skill (same power and same quirk), and optionally the player's name is mixed into the seed so every player gets their own unique version of each recipe.

Theme fit ("Magic"): spellcrafting is the whole game.

---

## 2. Hard constraints

- **No art skills.** The game must be fully playable using only tinted white shapes (circle and square) plus Defold text. No hand-drawn sprite sheets, no animation frames.
- **Third-party art is allowed, with credit** (the jam permits it). It is an optional upgrade layered on top of the generated shapes, never a dependency. Follow section 8.3a exactly.
- **No audio files** in the first pass.
- Single arena scene. No scrolling, no camera work.
- Target window: **960 x 640** (matches README `game.project` example).
- Jam scope. If something is not in the milestones, do not build it.

---

## 3. Locked design decisions (do not re-ask)

| Topic | Decision |
|---|---|
| Elements | Fire, Water, Wind, Earth |
| Compounds | Unordered pair, doubles allowed: 10 total |
| Shapes | Projectile, Puddle, Orbit, Cone, Burst: 5 total |
| Skills | 10 compounds x 5 shapes = 50 deterministic skills |
| Skill slots | 2. Left mouse = slot 1, right mouse = slot 2 |
| Starting kit | At run start the player picks **2 elements** (doubles allowed) from the 4. They are auto-crafted with **Projectile** into slot 1 |
| Reward | After each cleared room: choose **1 of 3** random cards (elements and shapes) |
| Cauldron | After each reward: optional crafting screen. Pick 2 elements + 1 shape from inventory, see a preview, assign to slot 1 or 2 (replaces the old skill). Crafting **consumes** the 3 ingredients. Skipping is allowed |
| Run length | 8 normal rooms + 1 boss room. Win after the boss |
| Death | Return to the title screen. No meta-progression |
| Determinism | Skill stats and quirk come only from the recipe (and optional player name). Run randomness (rewards, enemy spawns) is separate and may use `math.random` |
| Controls | WASD move, mouse aim, LMB/RMB cast |
| Player | 100 HP, speed 220 px/s, 0.6 s invulnerability after taking a hit |

All tuning numbers live in one file, `/src/core/data.lua`, in a `TUNING` table at the top.

---

## 4. Data specification

### 4.1 Elements and colors

| Element | Color (RGB 0 to 1) |
|---|---|
| fire | 1.00, 0.30, 0.15 |
| water | 0.20, 0.50, 1.00 |
| wind | 0.85, 0.95, 0.90 |
| earth | 0.65, 0.45, 0.20 |

A skill's color is the **average of its two elements' colors** (so the player can see what it is made of). Enemies use desaturated purple and gray so skills stand out.

### 4.2 Compounds (key = the two element names sorted alphabetically, joined by `+`)

| Key | Name | Base power | Statuses |
|---|---|---|---|
| `fire+fire` | Inferno | 14 | burn |
| `water+water` | Tide | 6 | pull, slow |
| `wind+wind` | Gale | 8 | push |
| `earth+earth` | Quake | 12 | stun |
| `fire+water` | Steam | 7 | push, blind |
| `fire+wind` | Ember | 8 | burn, spread |
| `earth+fire` | Magma | 9 | burn, slow |
| `water+wind` | Mist | 3 | blind, hide_self |
| `earth+water` | Mud | 4 | root |
| `earth+wind` | Dust | 5 | confuse |

Balance rule: doubles are strong with one effect; mixes are weaker with two effects. Keep it that way.

### 4.3 Shapes

| Key | Name | Cooldown (s) | Radius (px) | Duration (s) | Delivery |
|---|---|---|---|---|---|
| `projectile` | Bolt | 0.6 | 10 | 0 | Flies toward the cursor (speed 450), hits the first enemy, applies power and statuses once, then vanishes |
| `puddle` | Pool | 4.0 | 60 | 5 | Placed at the cursor (max range 300). Every 0.5 s it applies power/2 and statuses to enemies inside |
| `orbit` | Orbit | 5.0 | 14 | 6 | 3 orbs circle the player at radius 70 (1.5 rev/s). Each orb applies power and statuses on contact, with a 0.5 s per-enemy hit cooldown |
| `cone` | Spray | 1.5 | 90 | 0.3 | Instant 70-degree arc toward the cursor, range 90 px. Applies power and statuses to every enemy inside, once |
| `burst` | Nova | 2.5 | 70 | 0 | Instant circle centered on the player. Applies power and statuses once |

Skill name = `compound.name .. " " .. shape.name` (for example "Steam Bolt", "Inferno Pool").

### 4.4 Status effects (all in `/src/core/status.lua`, data driven)

| Status | Effect on an enemy |
|---|---|
| `burn` | 3 damage per second for 3 s (refreshes, does not stack) |
| `spread` | While the enemy is burning, it ignites enemies within 60 px |
| `slow` | Speed x 0.5 for 2 s |
| `push` | Instant knockback impulse (about 260 px/s decaying over 0.25 s) away from the skill source |
| `pull` | Same impulse toward the skill source |
| `stun` | Cannot move or attack for 1.2 s |
| `root` | Cannot move for 2 s (can still attack) |
| `blind` | Moves in a wandering random direction and cannot aim ranged attacks for 2 s |
| `confuse` | 50% of its attacks miss for 3 s |
| `hide_self` | **On the player**, not the enemies: for 2 s enemies lose track of the player and wander |

Each status stores an expiry timer on the enemy. Show active statuses with a small tint on the enemy (burn = orange flash, slow = blue tint, stun = yellow, and so on).

### 4.5 Quirks (assigned deterministically, one per skill)

`QUIRKS = { "splits in two", "leaves a trail", "repeats once", "bigger but slower", "costs 5% health" }`

| Quirk | Behavior |
|---|---|
| splits in two | Cast spawns 2 copies at 60% power each (projectile: +/-15 degrees; cone: +/-20 degrees; puddle: two offset puddles; orbit: 2 orbs instead of 3 but each at full power; burst: a second smaller burst 0.3 s later) |
| leaves a trail | A moving part drops small short-lived puddles (projectile and orbit). Instant shapes (cone, burst) leave one small puddle at the origin |
| repeats once | The cast fires a second time 0.5 s later |
| bigger but slower | Radius x 1.5 and cooldown x 1.5 |
| costs 5% health | Each cast costs the player 5% of max HP (cannot kill the player: clamp at 1 HP) but power x 1.5 |

---

## 5. The deterministic skill generator (critical, get this exactly right)

Put it in `/src/core/skillgen.lua`, using `/src/core/hash.lua` and `/src/core/rng.lua`.

### 5.1 Recipe key

```
key  = playerName .. sortedA .. "+" .. sortedB .. "|" .. shape
```

`sortedA`/`sortedB` are the two element names sorted alphabetically. `playerName` is `""` when `TUNING.USE_PLAYER_NAME = false` (the default). Same key always gives the same skill.

### 5.2 Generation order (the order of RNG calls must never change)

```
seed   = hash(key)
r      = rng(seed)
r1     = r()                                   -- power jitter
r2     = r()                                   -- quirk pick
power  = floor(compound.power * (0.9 + r1 * 0.2) + 0.5)
quirk  = QUIRKS[ floor(r2 * 5) + 1 ]
```

### 5.3 Why you must not use plain Lua arithmetic for the hash

Defold's Lua is Lua 5.1 / LuaJIT (HTML5 uses plain Lua 5.1.4). Multiplying a 32-bit value by the FNV prime in doubles loses precision. Use the **`bit` library** (README section 4 lists it) and the shift-and-add form of the multiplication.

**Reference implementation (already verified against LuaJIT 2.1; follow it exactly):**

```lua
-- /src/core/hash.lua
local bit = require "bit"
local M = {}
local TWO32 = 4294967296

-- FNV-1a, 32-bit. Prime 16777619 = 2^24 + 2^8 + 2^7 + 2^4 + 2^1 + 2^0,
-- so h * prime = sum of shifted copies of h (mod 2^32).
function M.hash(s)
    local h = 2166136261
    for i = 1, #s do
        h = bit.bxor(h, s:byte(i))
        local t = bit.lshift(h, 24) % TWO32
                + bit.lshift(h, 8)  % TWO32
                + bit.lshift(h, 7)  % TWO32
                + bit.lshift(h, 4)  % TWO32
                + bit.lshift(h, 1)  % TWO32
                + (h % TWO32)
        h = t % TWO32
    end
    return h
end

return M
```

```lua
-- /src/core/rng.lua  (xorshift32, returns floats in [0, 1))
local bit = require "bit"
local M = {}
local TWO32 = 4294967296

function M.new(seed)
    local x = bit.tobit(seed)
    if x == 0 then x = bit.tobit(0x9E3779B9) end
    return function()
        x = bit.bxor(x, bit.lshift(x, 13))
        x = bit.bxor(x, bit.rshift(x, 17))
        x = bit.bxor(x, bit.lshift(x, 5))
        return (x % TWO32) / TWO32
    end
end

return M
```

Never use `math.random` or the engine's own hashing (`hash()` the Defold function is a different thing) inside skill generation.

### 5.4 Golden test vectors (the self-check must reproduce these exactly)

| Key string | `hash(key)` | r1 | r2 | Result |
|---|---|---|---|---|
| `fire+water\|projectile` | 1682648556 | 0.246629 | 0.521085 | Steam Bolt, power 7, quirk "repeats once" |
| `fire+fire\|puddle` | 2074461886 | 0.676735 | 0.771629 | Inferno Pool, power 14, quirk "bigger but slower" |
| `Ashfire+wind\|burst` | 3898178612 | 0.235052 | 0.655529 | Ember Nova, power 8, quirk "bigger but slower" |
| `a` | 3826002220 | | | (hash only) |
| (empty string) | 2166136261 | | | (hash only) |

Round r1/r2 comparisons to 6 decimals. Add `/src/core/selfcheck.lua` that is called once from the game script's `init` and prints `SELFCHECK OK` or `SELFCHECK FAIL: <details>`. The human will confirm this line appears in the console. If it fails, fix the hash/RNG before anything else.

---

## 6. Game flow (state machine in the game script)

```
TITLE -> PICK_START -> ROOM -> REWARD -> CAULDRON -> ROOM -> ... -> BOSS -> WIN
                          \-> DEAD -> TITLE
```

- **TITLE:** game name, "Click to start". (Optional, last milestone: type a player name for per-player skills. See M8.)
- **PICK_START:** show 4 element buttons. The player clicks two (doubles allowed). Auto-craft with Projectile into slot 1.
- **ROOM:** spawn enemies with a 0.6 s telegraph marker. The room is cleared when no enemies remain.
- **REWARD:** 3 cards drawn with `math.random`. Click one. It goes into the inventory.
- **CAULDRON:** craft or skip. Shows live preview (name, power, shape stats, quirk text) before confirming.
- **WIN/DEAD:** a screen with "Click to return".

---

## 7. Enemies, rooms, boss

Colors: desaturated. Shapes: circle or square, scaled.

| Enemy | HP | Speed | Behavior | Cost |
|---|---|---|---|---|
| Wisp | 20 | 90 | Chases the player, contact damage 8 | 1 |
| Slinger | 25 | 60 | Keeps about 250 px away, fires a slow bullet every 2 s (damage 8) | 2 |
| Charger | 35 | 70 | Pauses 0.8 s (flash), then dashes straight at the player at 350 px/s | 3 |
| Brute | 90 | 45 | Slow, contact damage 18 | 4 |
| Splitter | 30 | 80 | Chases; on death splits into 2 small Wisps | 3 |

**Room budget:** room n (1 to 8) spawns enemies up to `3 + 2n` cost points, picking from the enemy types unlocked so far (Wisp at 1, Slinger at 2, Charger at 3, Splitter at 4, Brute at 5). Spawn at random points along the arena edge.

**Boss (room 9):** large circle, 400 HP. Cycles through: (a) a radial ring of 12 bullets, (b) a charge toward the player, (c) summons 3 Wisps. Pause 1.5 s between attacks.

Arena: 960 x 640 rectangle. Clamp the player and enemies inside with a 20 px margin.

---

## 8. Defold architecture

### 8.1 Philosophy (follow it, it is what keeps this safe without running the game)

- **The game is simulated in Lua tables.** One `game.script` owns all state: player, enemies, projectiles, zones, timers. Collisions are **manual circle-vs-circle checks** in Lua. Do **not** use Defold physics or collision objects.
- **Visuals are cheap sprite game objects.** A single `visual.go` (one sprite component, nothing else) is spawned with a `factory` for every circle or square on screen (player, enemies, bullets, puddles, orbs, flashes). The game script moves them with `go.set_position`, tints them with `go.set(url, "tint", vmath.vector4(...))` and sizes them with `go.set_scale`. When an entity dies, delete its visual (`go.delete`).
- **Pure logic lives in modules** under `/src/`, with no `go.*` or `gui.*` calls, so it is easy to reason about: hash, rng, data, skillgen, status.
- **All UI is built at runtime** in one `ui.gui_script` using `gui.new_box_node` and `gui.new_text_node`. The `.gui` file is minimal: one font, one texture (the atlas), no nodes. This avoids hand-writing large `.gui` files. The game script and the UI script communicate with `msg.post` (README section 3). Remember that GUI scripts cannot use `go.*`.
- Avoid per-frame vector allocations where easy (README section 9, item 13).

### 8.2 Proposed layout

```
game.project                      (edit additively: set display 960x640, bootstrap, input binding)
input/game.input_binding
main/main.collection              (contains: game object "game", factory object "factory", gui object "ui")
main/game.go            + game.script   (the whole simulation + state machine)
main/visual.go          + visual.sprite (one sprite, white square/circle via two animations)
main/visual.factory
main/ui.go              + ui.gui + ui.gui_script
assets/art/square.png, circle.png        (white, see 8.3)
assets/art/shapes.atlas                  (two single-frame animations: "square", "circle")
assets/third_party/<pack-name>/          (downloaded packs + each pack's license text, see 8.3a)
assets/fonts/ (optional; otherwise use /builtins/fonts/default.font)
CREDITS.md                                (project root, one line per third-party asset)
src/core/credits.lua                      (the same credits as a Lua table, shown on the title screen)
src/core/hash.lua  rng.lua  data.lua  skillgen.lua  status.lua  selfcheck.lua
src/game/player.lua  enemies.lua  combat.lua  rooms.lua  cards.lua   (plain Lua modules the game script calls)
```

Use `require "src.core.skillgen"` style (README section 4: dots become path separators).

### 8.3 Placeholder art

Create `assets/art/square.png` (64x64 solid white) and `assets/art/circle.png` (64x64 white anti-aliased circle, transparent corners). Generate them by writing a small **PowerShell script using System.Drawing** and running it once (creating new files this way is fine; do not hand-edit existing PNGs). If that fails, ask the human to drop in two white PNGs of those names. Then write the `.atlas` text file (README section 5.5): two animations, `square` and `circle`, each one frame.

Everything colored is a white sprite tinted at runtime. Use the sprite tint property; scale for size (a 64 px sprite at scale 0.3 is about 19 px).

### 8.3a Third-party art, icons and credits (optional, allowed with credit)

The jam allows third-party art as long as it is credited. These rules keep that safe and legal.

**1. Shapes first, art second.**
The game must work end to end with the generated circle and square. Third-party art replaces or decorates them. Look up every art animation by name and **fall back to `square` / `circle` if it is missing**, so a missing or renamed file never crashes the game.

**2. Who adds the files.**
The human downloads packs and puts them in `assets/third_party/<pack-name>/`, together with the pack's license text (`LICENSE.txt`). You do not download art yourself unless asked, and you never use art from a source or license that is not listed below.

**3. Allowed licenses.**

| License | Use? | Credit |
|---|---|---|
| CC0 / public domain | Yes | Optional, but do it anyway |
| CC BY 3.0 / 4.0 | Yes | **Required** |
| CC BY-SA | **No** (forces the whole game to be share-alike) | n/a |
| Any "NC" (non-commercial) or "ND" license | **No** | n/a |
| All rights reserved, or license unknown | **No** | n/a |

If a file's license is not clearly one of the "Yes" rows, do not use it. Ask the human.

**4. Approved sources and what each is for.**

| Source | License | Use it for |
|---|---|---|
| **Kenney Particle Pack** (kenney.nl, about 80 sprites at 512 x 512) | CC0 | Glow and spark heads on projectiles, trail puffs, puddle splashes, burst flashes. Mostly white/gray particle art, so tint it with the skill color |
| **game-icons.net** | CC BY 3.0 | Element icons (flame, droplet, wind, rock), shape icons, status icons on the HUD and cauldron cards |
| **Kenney UI pack** (check the license on the download page; it is expected to be CC0) | CC0 | Optional button and panel frames |
| Kenney top-down and tower-defense packs | CC0 | Reference or placeholders only. Their theme (soldiers, zombies) does not match a magic game, so do not mix styles |

Pick **one cohesive look**: flat tinted shapes + glowing particles + single-color icons. Do not mix in colorful character sprites.

**5. Preparing the files.**
- **Tinting only works on white or light-gray art.** Multiplying a black icon by a color stays black. Ask the human to download game-icons.net icons with a **white foreground and transparent background** (the site lets you choose the colors), at about 64 px.
- Kenney particle sprites are 512 x 512. Use only the 6 to 8 you need and scale them down in code (scale about 0.1 to 0.3). If memory or load time matters, ask the human to shrink the PNGs to 128 x 128.

**6. The atlas.**
Put every PNG you use in the one atlas (`assets/art/shapes.atlas`). **Do not write `animations { }` blocks**: this editor rejects `start/end`,
and Defold auto-creates one animation per image named after the image file (`glow.png` -> `"glow"`, `icon_fire.png` -> `"icon_fire"`),
so ids must be unique across folders. Add images with `python tools/add_to_atlas.py "assets/art/<folder>/<prefix>_*.png"` (additive, idempotent).
See `AGENTS.md` Part A item 1 and `README.md` section 13. (An earlier version of this prompt told you to number frames and append images; that was wrong.)

**7. Using art in code.**
Keep a single table in `/src/core/data.lua` mapping names to animation ids (for example `ART.elementIcon.fire = "icon_fire"`, `ART.projectileHead = "glow_01"`), so swapping art is a one-line change. Sprites: `sprite.play_flipbook(url, hash(id))`. GUI nodes: `gui.play_flipbook(node, id)` (README section 7).

**8. Credits (mandatory, kept in sync).**
- `CREDITS.md` in the project root: one line per third-party asset with name, author, license and source URL. Add the line **in the same step that adds the asset**.
- `/src/core/credits.lua` returns the same lines as a Lua table, and the title screen has a "Credits" button that shows them in the UI. If a pack's license text is not in `assets/third_party/<pack-name>/`, ask the human for it.
- Credit format for icons: `Icon "<name>" by <author> (game-icons.net, CC BY 3.0)`. Credit format for Kenney: `Kenney Particle Pack by Kenney (kenney.nl, CC0)`.
- Every milestone report lists the credits added in that milestone (see the report format in section 0).

### 8.4 Input

`input/game.input_binding` (README section 5.7), plus the `[input] game_binding` entry in `game.project` pointing at it:

- `key_trigger` W, A, S, D mapped to actions `up`, `left`, `down`, `right`
- `mouse_trigger MOUSE_BUTTON_1` mapped to `cast1`, `MOUSE_BUTTON_2` mapped to `cast2`

Mouse position arrives in `on_input` as an event with no action id, carrying `action.x` and `action.y`. Store them as the aim point. The game object must `msg.post(".", "acquire_input_focus")` (README section 9, item 5). If aiming looks offset after the human resizes the window, **tell them**; do not write a custom render script.

UI buttons are clickable by the game script forwarding clicks to the UI script, or by the UI script acquiring input focus and using `gui.pick_node`. Pick whichever is simpler, but choose **one** approach and use it consistently.

### 8.5 Lua gotchas to respect

- Callbacks are lowercase: `init`, `update`, `on_message`, `on_input`, `final` (README section 9, item 1).
- Compare message ids with `hash("name")`, never with strings.
- Per-instance state goes in `self`. Module-level locals are shared across components.
- Put `local bit = require "bit"` at the top of any file that uses it.

---

## 9. Milestones

Stop after each one, report in the format from section 0, and wait for the human.

**M0 Project skeleton and self-check.**
`game.project` (960x640), bootstrap `main.collection`, `game.go` + `game.script`, the `hash`/`rng`/`data`/`skillgen`/`selfcheck` modules. Console must print `SELFCHECK OK`. A colored background rectangle visible is enough for now. Also create an empty `CREDITS.md` (with a header and the line `Code and game design: Ash`) and `src/core/credits.lua` returning the same lines.
*Test:* run, confirm `SELFCHECK OK`, no errors.

**M1 Shapes on screen and a controllable player.**
Generate placeholder PNGs, atlas, `visual.go`/`visual.factory`. A tinted circle player moves with WASD inside the arena bounds. The aim point is tracked.
*Test:* move around, circle stops at the edges.

**M2 Enemies and the first skill.**
Wisp chasing and contact damage, player HP, invulnerability frames. Slot 1 holds a hardcoded "Fire + Fire + Projectile" skill built through `skillgen.makeSkill`. LMB fires bolts at the cursor, enemies take damage and die, HP is shown (temporary `print` or a simple label is fine until the UI milestone).
*Test:* kill wisps with bolts, take damage, die.

**M3 All 5 shapes and the status system.**
Implement Puddle, Orbit, Cone, Burst and all 10 statuses and 5 quirks via `status.lua` / `combat.lua`. Add a **debug key row** (keys 1 to 5 cycle the shape, Q/E cycle the elements for the two slots) so the human can test all 50 skills quickly. The debug row is removed or hidden behind a `TUNING.DEBUG` flag at the end.
*Test:* try several recipes and confirm each status is visible via tint.

**M4 UI.**
`ui.gui` and `ui.gui_script`: HP bar, two skill slot boxes with name, cooldown fill, element dots, and the quirk text. Title screen (with a "Credits" button that shows the lines from `credits.lua`), pick-start screen, win and dead screens. If element icons are present in the atlas (section 8.3a), show them on the pick-start buttons, reward cards and skill slots, tinted with the element color; otherwise use colored circles.
*Test:* the flow from title to the first room works with clicks.

**M5 Rooms, rewards, cauldron.**
Room budget spawning with telegraphs, clear detection, reward cards, the cauldron screen with live preview and consume rules. Inventory display.
*Test:* play rooms 1 to 3, craft a new skill, see the preview name and quirk match the golden table when you pick the matching recipe.

**M6 All enemy types, boss, win.**
Slinger, Charger, Brute, Splitter, the boss and its three patterns. Full run from title to WIN works.
*Test:* complete (or cheat through with a debug key) a full run.

**M7 Juice and polish.**
Hit flash, small fading particles built from short-lived `visual.go` instances (README section 10 "Spawn, animate, delete" recipe), screen flash on damage, nicer title text. If the Kenney Particle Pack sprites are in the atlas, use them for projectile heads, trails, puddle splashes and burst flashes (tinted with the skill color), falling back to the circle if an id is missing. Update `CREDITS.md` and `credits.lua` for everything used. Tuning pass on `TUNING`.

**M8 Optional extras (only if the human asks).**
1. **Player name seeding:** a text-input screen so `playerName` is mixed into the seed (`TUNING.USE_PLAYER_NAME = true`). Text input needs an input binding for text, and this is **not covered by the field guide**, so check the Defold manual for text input and the `text` action before writing it, and fall back to a short preset name list if it does not work.
2. **"Magic is fading" mechanic:** every crafted skill drains saturation from the arena background tint and the HUD, so the world visibly loses color as the player gets stronger.
3. Reroll the quirk at the cauldron for 10 HP using a salted seed (`key .. "#" .. rerollIndex`).
4. Sounds (CC0 packs such as Kenney audio, or effects the human generates themselves; credit anything third-party in `CREDITS.md`).

---

## 10. Definition of done (jam build)

- Title to WIN and DEAD to title loops without console errors.
- `SELFCHECK OK` prints at startup.
- All 5 shapes and all 10 compounds are reachable through normal play.
- The same recipe always shows the same name, power and quirk across runs and restarts.
- No `ERROR:` lines in the Defold console during a full run.
- The human can read the game's rules from the UI (cauldron preview shows name, effect words and quirk).
- Every third-party asset in the build has a matching line in `CREDITS.md` and in the in-game Credits screen, and its license text is in `assets/third_party/<pack-name>/`.
- The game still runs correctly if every third-party art file is removed (shape fallbacks work).

## 11. Things that will break this project (do not do them)

- Using `go.*` in the `.gui_script`, or `gui.*` in the game script.
- Using the Defold `hash()` function or `math.random` inside skill generation.
- Using Defold physics or collision objects.
- Writing `embedded_components` or `data:` strings by hand.
- Adding a render script or camera.
- Rewriting `main.collection` or `game.project` from scratch instead of editing them.
- Starting the next milestone without the human's confirmation.
- Calling an API you did not verify in README section 7 or the Defold reference.
- Using any art, icon, font or sound whose license is not clearly CC0 or CC BY, or adding an asset without its `CREDITS.md` line.
- Tinting black or colorful art (tinting only works on white or light-gray images).
- Reordering images in the atlas, which silently breaks every animation's frame indices.
- Making the game depend on a third-party file existing (always keep the shape fallback).

Begin with **M0**. Before writing anything, tell me in 3 to 5 lines how you understood the game and the milestone plan, then start.
