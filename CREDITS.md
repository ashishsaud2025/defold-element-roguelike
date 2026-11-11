# Credits

Code and game design: Ash

Icon "fire" by sbed (game-icons.net, CC BY 3.0)
Icon "drop" by lorc (game-icons.net, CC BY 3.0)
Icon "air-zigzag" by lorc (game-icons.net, CC BY 3.0)
Icon "rock" by lorc (game-icons.net, CC BY 3.0)
Icon "wizard-staff" by lorc (game-icons.net, CC BY 3.0)
Icon "rune-stone" by lorc (game-icons.net, CC BY 3.0)
Icon "cauldron" by lorc (game-icons.net, CC BY 3.0)

Kenney Particle Pack by Kenney (kenney.nl, CC0)
Tiny Dungeon by Kenney (kenney.nl, CC0)
Tiny Creatures by Clint Bellanger (clintbellanger.net, CC0)

Pixel fire asset pack by devkidd (devkidd.itch.io) — free for personal/commercial use, attribution appreciated.
Pixel Holy Effects Pack 01 by Sentient Dream Studio (sentient-dream-studio.itch.io) — free for personal/commercial use, attribution appreciated.

Animated spell effects (assets/art/fxa, built by tools/build_fx_anim.py) use these itch.io packs:
- "Effect and FX Pixel All Free" - TODO: add author + licence (no licence file was included in the download)
- "RPG Effect All Free" - TODO: add author + licence (no licence file was included in the download)
- "Free Smoke Fx Pixel 2" - TODO: add author + licence (no licence file was included in the download)
- Pixel fire asset pack by devkidd (flame loops for bolt heads and orbit orbs)
Confirm each licence on its itch.io page before releasing; remove a pack (edit COMPOUNDS in the tool) if it does not allow use in a game.

Particle sprites in assets/art/particles are the Kenney Particle Pack (CC0, kenney.nl), brightened and recoloured to white so they can be tinted.
Element FX sprites in assets/art/fx are whitened to white-on-alpha (tools/whiten_sprite.py): fx_flame/fx_scorch/fx_spark use the devkidd Pixel fire asset pack (white variant); fx_streak/fx_swirl use the Sentient Dream Studio Pixel Holy Effects Pack 01; fx_drop/fx_splash/fx_bubble/fx_debris use the Kenney Particle Pack.
fx_drop.png is generated for this project (tools/make_drop.py).
actors/target_dummy.png is generated for this project (tools/make_target.py).
glow.png, floor.png and vignette.png are generated for this project.

All audio in assets/sfx and assets/music is generated for this project by tools/make_sfx.py (original synthesis, no third-party samples). Replace any file with a same-named .ogg/.wav and run tools/add_sounds.py.
