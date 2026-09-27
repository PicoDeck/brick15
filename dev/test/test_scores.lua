local Scores = need("lib/scores.lua")
local save = picocalc.game.save

local GAMES = { { id = "tetris" }, { id = "memory" } }

local function gets() local n = 0 for _, e in ipairs(SAVE_LOG) do if e[1] == "get" then n = n + 1 end end return n end
local function sets() local n = 0 for _, e in ipairs(SAVE_LOG) do if e[1] == "set" then n = n + 1 end end return n end

test("scores: load reads each game's slot exactly once", function()
    SAVES.hi_tetris = { v = 500 }
    local s = Scores.new(save, GAMES)
    eq(gets(), 2, "reads at load")
    eq(s:get("tetris"), 500, "cached"); eq(s:get("memory"), nil, "no record")
    s:get("tetris"); s:get("tetris")
    eq(gets(), 2, "get never touches the SD card")
end)

test("scores: a higher score is a record and is saved", function()
    SAVES.hi_tetris = { v = 500 }
    local s = Scores.new(save, GAMES)
    eq(s:submit("tetris", 400, "high"), false, "lower is not a record")
    eq(sets(), 0, "nothing written")
    eq(s:submit("tetris", 600, "high"), true, "higher is a record")
    eq(sets(), 1, "written once"); eq(SAVES.hi_tetris.v, 600, "stored")
    eq(s:get("tetris"), 600, "cache updated")
end)

test("scores: zero is never a record", function()
    local s = Scores.new(save, GAMES)
    eq(s:submit("tetris", 0, "high"), false, "zero")
    eq(sets(), 0, "nothing written")
end)

test("scores: low order keeps the smallest, 0 or nil means no record yet", function()
    SAVES.hi_memory = { v = 0 }
    local s = Scores.new(save, GAMES)
    eq(s:submit("memory", 30, "low"), true, "first result is a record")
    eq(s:submit("memory", 35, "low"), false, "more turns is worse")
    eq(s:submit("memory", 22, "low"), true, "fewer turns is better")
    eq(s:get("memory"), 22, "best")
end)

test("scores: a damaged slot reads as no record and can be beaten", function()
    SAVES.hi_tetris = { v = "abc" }
    SAVES.hi_memory = {}
    local s = Scores.new(save, GAMES)
    eq(s:get("tetris"), nil, "string value"); eq(s:get("memory"), nil, "missing value")
    eq(s:submit("tetris", 10, "high"), true, "first real score is a record")
end)

test("scores: a stored 0 in low order shows as no record", function()
    SAVES.hi_memory = { v = 0 }
    local s = Scores.new(save, GAMES)
    eq(s:get("memory"), nil, "0 reads as nil")
end)
