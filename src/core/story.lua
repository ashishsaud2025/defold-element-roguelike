-- /src/core/story.lua
-- Story text: the intro dialogue in the Lantern Hall, the chest at the end of the
-- dungeon, and the "journey has just begun" ending. Plain data, no engine calls.
-- Each page = { title = speaker/headline, body = text (\n for line breaks) }.
local M = {}

-- The cure needs these. The boss of the final room only drops the FIRST one.
M.INGREDIENTS = {
    "Fire Dragon's Bone",
    "Heart of the Frost Wyrm",
    "Horn of the Moonlit Calf",
    "Ashen Phoenix Feather",
    "Tear of the Archmage",
}

M.INTRO = {
    { title = "WIFE",   body = "*cough* ... Is that you, my love?\nI am so tired. I can barely lift my head." },
    { title = "WIZARD", body = "Rest, my dear. I have read the old tomes all night.\nThere is a cure, but the ingredients are rare." },
    { title = "WIZARD", body = "I need:\n" .. "the " .. M.INGREDIENTS[1] .. ",\n" .. M.INGREDIENTS[2] .. ",\n"
        .. M.INGREDIENTS[3] .. ",\n" .. M.INGREDIENTS[4] .. " and the " .. M.INGREDIENTS[5] .. "." },
    { title = "WIFE",   body = "But those can only be found in...\nthe Dungeon of Lucas? Nobody ever returns from there!" },
    { title = "WIZARD", body = "Then I will be the first.\nI will enter the Dungeon of Lucas tonight and bring them back." },
    { title = "WIFE",   body = "Please... come back to me." },
}

-- Shown when the chest is opened (the boss only gives one ingredient).
function M.chest_pages()
    return {
        { title = "THE CHEST OPENS", body = "Inside you find the " .. M.INGREDIENTS[1] .. "!\n\nIngredient 1 of " .. #M.INGREDIENTS .. " collected.\nThe cure is still incomplete." },
    }
end

-- Shown at the exit door, right before the credits roll.
M.ENDING = {
    { title = "THE JOURNEY HAS JUST BEGUN", body = "Your journey is incomplete.\nYour wife still waits, and four ingredients remain.\n\nThe quest has only just begun..." },
}

return M
