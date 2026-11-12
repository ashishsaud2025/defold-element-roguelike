# Quintessence: The Fifth Element

A top-down **elemental roguelite** built with [Defold](https://defold.com/) (960×640, nearest-neighbour pixel art).

Mix two elements into compound spells. Survive the Dungeon of Lucas. Save your dying wife.

- 🎬 **Trailer:** https://youtu.be/fpe1YKIdLOA
- 🎮 **Rate on itch.io:** https://itch.io/jam/mxdgf/rate/5346816

## The premise

Valerie is bedridden. Every cure the old tomes mention grows in the Dungeon of Lucas, a place nobody survives. Playing as her husband, a self-taught wizard, you will go down there, mix every spell the world has to give you, and — if you live — bring her back.

## How it plays

- **Elements** — Fire, Water, Wind, Earth. Mix two (same pair = double effect) and you get one of **10 compound spells**: Ember Magma Steam Inferno Tide Gale Quake Mist Mud Dust.
- **Delivery** — every spell can be cast as a **Bolt**, **Pool**, **Orbit**, **Spray** or **Nova**. Five shapes, ten spells: fifty skills, no two quite alike.
- **Status interactions** — burn, slow, stun, root, blind, confuse, push, pull (+ a rogue-lite cast of combo interactions like Burning Mud and Fire Cyclone).
- **Relics** — four mid-run powers (Inferno Heart, Echoing Crystal, Ancient Catalyst, Orbital Crown).
- **Room** — the Lantern Hall at home, the Training Hall to practise, the dungeon proper, and The Archmage's Sanctum at the end of it.

## Controls

**Desktop**

| Key | Action |
| --- | --- |
| `W A S D` | move |
| mouse | aim |
| `LMB` | cast basic |
| `Q` / `R` | cast slot 1 / slot 2 |
| `E` | interact |
| `Space` | dash |

**Mobile (Android)**

Drag on the left half = move (analog stick). Buttons on the right edge cast slots and dash; drag out of a spell button to aim it.

## Built with

[Defold](https://defold.com/) 1.14.1 · Lua + LuaJIT (no goto, no Lua 5.2 sugar) · nearest-neighbour Sprite art · custom letterboxed renderer · 60 Hz.

## Releases

Tags `v0.1` and `v0.2` ship five platform builds: Windows, Linux, macOS (universal, unsigned), Android (debug APK) and HTML5 (wasm).

## Development

The game is plain source in this repository. Open the folder in Defold 1.14.1 and press **Project ▸ Build**.

For the project/Defold field guide, see [`docs.md`](docs.md).
Asset pipeline, test harness (`python tools/run_smoke_test.py`), rooms and art:
- `python tools/validate_rooms.py` — levels OK
- `python tools/run_smoke_test.py` — headless gameplay sim

Credits for all art/assets: [`CREDITS.md`](CREDITS.md).
Development history: [`CHANGES.md`](CHANGES.md).

## Credits

- **Code and game design:** Ashish Saud and Avinash Joshi
- Defold third-party art packs and fonts: see [`CREDITS.md`](CREDITS.md)
- **Trailer:** https://youtu.be/fpe1YKIdLOA

## License

Code is free to browse; all rights reserved. Third-party assets are licensed per [`CREDITS.md`](CREDITS.md) (primarily CC0 and CC BY 3.0 attribution).
