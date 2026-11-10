# M0 DONE

## MILESTONE 0 DONE

Files created:
- game.project (960x640 display, bootstrap /main/main.collectionc, input binding, zero gravity)
- input/game.input_binding (WASD → up/left/down/right, mouse1 → cast1, mouse2 → cast2)
- main/main.collection (instance "game" → /main/game.go)
- main/game.go (script component → /main/game.script; visual_factory component → /main/visual.factory)
- main/game.script (init: acquire_input_focus, run selfcheck, spawn dark background rect; state = TITLE)
- main/visual.go (sprite component → /main/visual.sprite)
- main/visual.sprite (tile_set → /assets/art/shapes.atlas, default_animation "square")
- main/visual.factory (prototype → /main/visual.go)
- assets/art/shapes.atlas (square.png = frame 0 / anim "square", circle.png = frame 1 / anim "circle")
- assets/art/square.png (64x64 solid white, generated via System.Drawing)
- assets/art/circle.png (64x64 white AA circle on transparent, generated via System.Drawing)
- src/core/hash.lua (FNV-1a 32-bit, bit library shift-and-add)
- src/core/rng.lua (xorshift32, [0,1) floats)
- src/core/data.lua (elements, compounds, shapes, quirks, TUNING)
- src/core/skillgen.lua (makeSkill: key = playerName..sortedA.."+"..sortedB.."|"..shape, power + quirk from RNG)
- src/core/selfcheck.lua (hash + rng + skillgen golden vectors; prints SELFCHECK OK / FAIL)
- src/core/credits.lua (returns {"Code and game design: Ash"})
- CREDITS.md (header + "Code and game design: Ash")

Files changed: none (all new)

Wiring:
- game.project [bootstrap] main_collection = /main/main.collectionc loads main.collection
- main.collection → instance "game" → /main/game.go
- game.go → script component /main/game.script (runs simulation) + visual_factory component /main/visual.factory
- visual.factory → prototype /main/visual.go → sprite /main/visual.sprite → atlas /assets/art/shapes.atlas
- game.script init posts acquire_input_focus to ".", runs selfcheck.run(), spawns background via factory.create("#visual_factory", ...), tints it dark and scales to cover 960x640

How to test:
1. Open the project in the Defold editor
2. Project ▸ Build and Run
3. Confirm console prints "SELFCHECK OK" and "Game initialized. State: TITLE"
4. Confirm a dark rectangle fills the 960x640 window (white square sprite scaled 15x10, tinted dark purple-gray)
5. Confirm no ERROR: lines in the console

Expected console:
- "SELFCHECK OK"
- "Game initialized. State: TITLE"
- No "ERROR:" lines

Known gaps:
- No player movement yet (M1)
- No UI, title screen, or HUD yet (M4)
- No enemies, skills, rooms, rewards, or cauldron yet (M2, M3, M5)
- No boss or win/dead screens yet (M6)
- Player-name seeding not implemented (M8, optional)
- Third-party art not used yet (optional; shapes fall back to generated squares/circles)

Credits added: "Code and game design: Ash" (in CREDITS.md and src/core/credits.lua); no third-party assets yet.
