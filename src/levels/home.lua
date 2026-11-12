-- /src/levels/home.lua
-- The Lantern Hall: a peaceful room. See src/game/level.lua for the legend.
-- The altar sits on a pillar cell (row 3, col 6); the door sits on the top
-- border (row 1, col 10). Both are solid, so the player interacts from the
-- floor tile directly below each: (6,4) and (10,2).
return {
    name = "Lantern Hall",
    peaceful = true,
    altar = { c = 6, r = 3 },
    door  = { c = 10, r = 1 },
    rows = {
        "####T#####T####T####",
        "#..................#",
        "#....O........O....#",
        "#..................#",
        "#....O........O....#",
        "#........@.........#",
        "#..................#",
        "#..................#",
        "#......O....O......#",
        "#..................#",
        "#..................#",
        "#..................#",
        "####################",
    },
}
