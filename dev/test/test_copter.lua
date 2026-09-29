need("dev/test/game_helpers.lua")
local copter = need("games/copter.lua")

local function new_game() return copter.new(game_ctx()) end

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

test("copter: a perfect pilot can always get through, at every level", function()
    -- Valid ship columns for the current rows; between scrolls the pilot may
    -- slide along valid columns (each step is checked), then must be on a
    -- column that is still valid once the tunnel scrolls.
    local function valid(g)
        local function blocked(c, r)
            local row = g.rows[r]
            return c <= row.left or c > 10 - row.right or c == row.block
        end
        local v = {}
        for x = 2, 9 do
            v[x] = not blocked(x, 18) and not blocked(x - 1, 19)
                   and not blocked(x, 19) and not blocked(x + 1, 19)
        end
        return v
    end
    local function run(seed, level_of)
        math.randomseed(seed)
        local g = new_game()
        local reach = { [5] = true }
        for step = 1, 2000 do
            g.level = level_of(step)
            local v, grown = valid(g), true
            while grown do
                grown = false
                for x = 2, 9 do
                    if reach[x] then
                        for _, n in ipairs({ x - 1, x + 1 }) do
                            if v[n] and not reach[n] then reach[n], grown = true, true end
                        end
                    end
                end
            end
            g:scroll()
            local after, any = valid(g), false
            for x = 2, 9 do
                if reach[x] and after[x] then any = true else reach[x] = nil end
            end
            truthy(any, "seed " .. seed .. " step " .. step .. " level " .. g.level .. ": no way through")
        end
    end
    for seed = 1, 40 do run(seed, function(step) return step // 60 + 1 end) end
    for seed = 1, 20 do run(seed, function() return 9 end) end
end)

test("copter: the gap narrows with level but never below 4", function()
    local g = new_game()
    g.level = 9
    for _ = 1, 200 do g.x = nil g:scroll() end
    local row = g.rows[1]
    eq(10 - row.left - row.right, 4, "narrowest gap")
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
