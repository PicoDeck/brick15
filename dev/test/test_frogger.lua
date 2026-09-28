need("dev/test/game_helpers.lua")
local frogger = need("games/frogger.lua")

local function new_game()
    local g = frogger.new(game_ctx())
    for _, lane in pairs(g.lanes) do lane.next_shift = math.huge end   -- freeze traffic
    return g
end

-- Replace one lane's contents with a fixed pattern (offset 0).
local function set_lane(g, row, pattern)
    g.lanes[row].pattern, g.lanes[row].offset = pattern, 0
end

test("frogger: meets the game contract", function()
    check_contract(frogger, "frogger", "FROGGER")
end)

test("frogger: frog starts on row 20, 3 lives, 5 empty homes", function()
    local g = new_game()
    eq(g.fy, 20, "start row"); eq(g.lives, 3, "lives")
    local empty = 0
    for _, filled in pairs(g.homes) do if not filled then empty = empty + 1 end end
    eq(empty, 5, "homes")
end)

test("frogger: a hop moves one cell and scores the first time a row is reached", function()
    local g = new_game()
    set_lane(g, 18, "..........")
    g:update(press("up"), 1)
    eq(g.fy, 19, "hopped"); eq(g.score, 10, "new row scores")
    g:update(press("down"), 2)
    g:update(press("up"), 3)
    eq(g.score, 10, "no score for a row already reached")
end)

test("frogger: a car on the frog costs a life and resets the frog", function()
    local g = new_game()
    set_lane(g, 18, "##........")
    g.fx, g.fy = 1, 19
    g:update(press("up"), 1)         -- hop onto the car at column 1
    eq(g.lives, 2, "life lost"); eq(g.fy, 20, "back at the start")
end)

test("frogger: landing in the river off a log drowns", function()
    local g = new_game()
    set_lane(g, 7, "#####.....")
    g.fx, g.fy = 8, 8
    g:update(press("up"), 1)
    eq(g.lives, 2, "drowned")
end)

test("frogger: a log carries the frog when its lane moves", function()
    local g = new_game()
    set_lane(g, 7, "#####.....")
    g.lanes[7].dir = 1
    g.fx, g.fy = 3, 7
    g.lanes[7].next_shift = 0
    g:update(NONE, 0)
    eq(g.fx, 4, "carried right"); eq(g.lives, 3, "still alive")
end)

test("frogger: being carried off the edge drowns", function()
    local g = new_game()
    set_lane(g, 7, "#........#")
    g.lanes[7].dir = 1
    g.fx, g.fy = 10, 7
    g.lanes[7].next_shift = 0
    g:update(NONE, 0)
    eq(g.lives, 2, "carried off")
end)

test("frogger: an empty home scores 50 and fills; a wall kills", function()
    local g = new_game()
    set_lane(g, 2, "##########")
    g.fx, g.fy = 3, 2
    g:update(press("up"), 1)
    eq(g.homes[3], true, "home filled"); eq(g.fy, 20, "new frog")
    truthy(g.score >= 50, "scored")
    g.fx, g.fy = 4, 2
    g:update(press("up"), 2)
    eq(g.lives, 2, "wall kills")
end)

test("frogger: filling all 5 homes raises the level and empties them", function()
    local g = new_game()
    set_lane(g, 2, "##########")
    for _, c in ipairs({ 1, 3, 5, 7 }) do g.homes[c] = true end
    g.fx, g.fy = 9, 2
    g:update(press("up"), 1)
    eq(g.level, 2, "level 2"); eq(g.homes[1], false, "homes emptied")
end)

test("frogger: losing the last life ends the round", function()
    local g = new_game()
    g.lives = 1
    set_lane(g, 18, "##########")
    g.fy = 19
    eq(g:update(press("up"), 1), "over", "over")
end)

test("frogger: road cars are 2 long, river logs 4-5 long", function()
    local g = new_game()
    for row, lane in pairs(g.lanes) do
        -- patterns wrap around: rotate so the pattern starts with a gap
        local p = lane.pattern
        local i = p:find("%.")
        p = p:sub(i) .. p:sub(1, i - 1)
        for run in p:gmatch("#+") do
            if lane.kind == "road" then eq(#run, 2, "car length row " .. row)
            else truthy(#run >= 4 and #run <= 5, "log length row " .. row) end
        end
    end
end)
