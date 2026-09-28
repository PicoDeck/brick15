need("dev/test/game_helpers.lua")
local racer = need("games/racer.lua")

local function new_game() return racer.new(game_ctx()) end

test("racer: meets the game contract", function()
    check_contract(racer, "racer", "RACER")
end)

test("racer: starts in the left lane with 3 lives", function()
    local g = new_game()
    eq(g.lane, 1, "left lane"); eq(g.lives, 3, "lives"); eq(g.score, 0, "score")
end)

test("racer: left and right switch lanes", function()
    local g = new_game()
    g:update(press("right"), 1)
    eq(g.lane, 2, "right lane")
    g:update(press("right"), 2)
    eq(g.lane, 2, "no third lane")
    g:update(press("left"), 3)
    eq(g.lane, 1, "back left")
end)

test("racer: each step moves traffic down a row and adds distance", function()
    local g = new_game()
    g.cars = { { lane = 2, y = 5 } }
    g:update(NONE, g.next_step)
    eq(g.cars[1].y, 6, "car moved"); eq(g.score, 1, "distance")
end)

test("racer: a car in your lane at your rows costs a life", function()
    local g = new_game()
    g.cars = { { lane = 1, y = 13 } }      -- rows 14-17 after the step: touches row 17
    g:update(NONE, g.next_step)
    eq(g.lives, 2, "crashed"); eq(#g.cars, 0, "road cleared")
end)

test("racer: a car in the other lane passes safely and scores a bonus", function()
    local g = new_game()
    g.cars = { { lane = 2, y = 20 } }
    g:update(NONE, g.next_step)
    eq(g.lives, 3, "no crash")
    for _, c in ipairs(g.cars) do eq(c.y, -3, "only a newly spawned car is left") end
    eq(g.score, 1 + 10, "distance + pass bonus")
end)

test("racer: losing the last life ends the round", function()
    local g = new_game()
    g.lives = 1
    g.cars = { { lane = 1, y = 13 } }
    eq(g:update(NONE, g.next_step), "over", "over")
end)

test("racer: new cars keep at least 3 clear rows between them", function()
    local g = new_game()
    local now = 0
    for _ = 1, 400 do
        now = g.next_step
        g.lane = 3                           -- park off-road so nothing crashes
        g:update(NONE, now)
        table.sort(g.cars, function(a, b) return a.y < b.y end)
        for i = 2, #g.cars do
            truthy(g.cars[i].y - g.cars[i - 1].y >= 7, "gap between cars")
        end
    end
end)

test("racer: every 100 rows of distance is a level", function()
    local g = new_game()
    g.score, g.distance = 99, 99
    g.cars = {}
    g:update(NONE, g.next_step)
    eq(g.level, 2, "level 2")
end)

test("racer: the player car is the upright shape at rows 17-20", function()
    local g = new_game()
    g.cars = {}
    local grid = draw_game(g)
    eq(grid:get(4, 17), true, "nose"); eq(grid:get(3, 17), false, "beside nose")
    eq(grid:get(3, 20), true, "left wheel"); eq(grid:get(4, 20), false, "between wheels")
end)
