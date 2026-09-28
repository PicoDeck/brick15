need("dev/test/game_helpers.lua")
local copter = need("games/copter.lua")

local function new_game() return copter.new(game_ctx()) end

-- Free columns of a tunnel row, as a set.
local function free_cols(row)
    local free = {}
    for c = row.left + 1, 10 - row.right do
        if c ~= row.block then free[c] = true end
    end
    return free
end

local function longest_run(free)
    local best, run = 0, 0
    for c = 1, 10 do
        if free[c] then run = run + 1 best = math.max(best, run) else run = 0 end
    end
    return best
end

test("copter: meets the game contract", function()
    check_contract(copter, "copter", "COPTER")
end)

test("copter: starts in an open tunnel with the ship at column 5", function()
    local g = new_game()
    eq(#g.rows, 20, "tunnel rows"); eq(g.x, 5, "ship column"); eq(g.score, 0, "score")
end)

test("copter: the tunnel scrolls down one row per step and counts distance", function()
    local g = new_game()
    local top = g.rows[1]
    g:update(NONE, g.next_step)
    eq(g.rows[2], top, "old top row moved down"); eq(g.score, 1, "distance")
end)

test("copter: left and right steer, the ship stays on screen", function()
    local g = new_game()
    for _, row in ipairs(g.rows) do row.left, row.right, row.block = 0, 0, nil end
    g:update(pad({ repeated = { "left" } }), 1)
    eq(g.x, 4, "steered left")
    for _ = 1, 10 do g:update(pad({ repeated = { "left" } }), 1) end
    eq(g.x, 2, "stops at the edge")
end)

test("copter: steering into the wall ends the round", function()
    local g = new_game()
    for _, row in ipairs(g.rows) do row.left, row.right, row.block = 3, 3, nil end  -- gap 4-7
    g.x = 5
    eq(g:update(pad({ repeated = { "left" } }), 1), "over", "hit the wall")
end)

test("copter: the tunnel always leaves a way through", function()
    local g = new_game()
    for step = 1, 3000 do
        g.x = nil                               -- no ship: just generate tunnel
        g:scroll()
        local a, b = g.rows[1], g.rows[2]       -- new row and the one below it
        local fa, fb = free_cols(a), free_cols(b)
        truthy(longest_run(fa) >= 3, "3-wide opening at step " .. step)
        -- the nose (above) and the 3-wide body (below) must fit somewhere
        local ok = false
        for x = 2, 9 do
            if fa[x] and fb[x - 1] and fb[x] and fb[x + 1] then ok = true end
        end
        truthy(ok, "passable at step " .. step)
        if step % 60 == 0 then g.level = g.level + 1 end
    end
end)

test("copter: the gap narrows with level but never below 3", function()
    local g = new_game()
    g.level = 9
    for _ = 1, 200 do g.x = nil g:scroll() end
    local row = g.rows[1]
    eq(10 - row.left - row.right, 3, "narrowest gap")
end)

test("copter: every 60 rows of distance is a level", function()
    local g = new_game()
    g.score = 59
    for _, row in ipairs(g.rows) do row.left, row.right, row.block = 0, 0, nil end
    g.gen_left, g.gen_width = 0, 10
    g:update(NONE, g.next_step)
    eq(g.level, 2, "level 2")
end)

test("copter: draw shows walls and the .#./### ship", function()
    local g = new_game()
    local grid = draw_game(g)
    eq(grid:get(5, 18), true, "nose"); eq(grid:get(4, 18), false, "beside nose")
    eq(grid:get(4, 19), true, "body left"); eq(grid:get(6, 19), true, "body right")
    eq(grid:get(1, 1), true, "left wall")
end)
