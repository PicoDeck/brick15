need("dev/test/game_helpers.lua")
local lander = need("games/moonlander.lua")

local function new_game()
    local g = lander.new(game_ctx())
    -- flat ground 2 high, pad at columns 4-6 at height 2
    for c = 1, 10 do g.heights[c] = 2 end
    g.pad = 4
    return g
end

-- Run physics ticks until the lander touches down (or n ticks pass).
local function fly(g, p, n)
    local result
    local lives, landings = g.lives, g.landings
    for _ = 1, n or 400 do
        result = g:update(p or NONE, g.next_tick)
        if result or g.landings > landings or g.lives < lives then break end
    end
    return result
end

test("moonlander: meets the game contract", function()
    check_contract(lander, "moonlander", "MOON LANDER")
end)

test("moonlander: starts at the top with full fuel and 3 lives", function()
    local g = lander.new(game_ctx())
    eq(g.lives, 3, "lives"); eq(g.fuel, 160, "fuel"); eq(math.floor(g.y), 1, "top")
    local h = g.heights[g.pad]
    eq(g.heights[g.pad + 1], h, "pad flat"); eq(g.heights[g.pad + 2], h, "pad flat")
end)

test("moonlander: gravity pulls the lander down faster and faster", function()
    local g = new_game()
    g:update(NONE, g.next_tick)
    local v1 = g.vy
    for _ = 1, 5 do g:update(NONE, g.next_tick) end
    truthy(g.vy > v1 and v1 > 0, "accelerating")
end)

test("moonlander: thrust pushes up and burns fuel", function()
    local g = new_game()
    g.y = 10                                      -- mid-air: row 1 is the ceiling
    for _ = 1, 5 do g:update(hold("up"), g.next_tick) end
    truthy(g.vy < 0, "rising"); eq(g.fuel, 155, "fuel used")
end)

test("moonlander: no thrust once the fuel is gone", function()
    local g = new_game()
    g.fuel = 0
    g:update(hold("up"), g.next_tick)
    truthy(g.vy > 0, "still falling"); eq(g.fuel, 0, "empty")
end)

test("moonlander: a slow landing on the pad scores and starts the next level", function()
    local g = new_game()
    g.x, g.y, g.vx, g.vy = 5.5, 16.2, 0, 0.05     -- just above the pad, slow
    fly(g)
    eq(g.landings, 1, "landed"); eq(g.level, 2, "level 2")
    truthy(g.score > 0, "scored"); eq(math.floor(g.y), 1, "new lander at the top")
end)

test("moonlander: touching down off the pad is a crash", function()
    local g = new_game()
    g.x, g.y, g.vx, g.vy = 8.5, 16.2, 0, 0.05     -- columns 7-9: not the pad
    fly(g)
    eq(g.lives, 2, "crashed")
end)

test("moonlander: hitting the pad too fast is a crash", function()
    local g = new_game()
    g.x, g.y, g.vx, g.vy = 5.5, 14, 0, 0.5
    fly(g)
    eq(g.lives, 2, "too fast")
end)

test("moonlander: losing the last life ends the round", function()
    local g = new_game()
    g.lives = 1
    g.x, g.y, g.vx, g.vy = 8.5, 16.2, 0, 0.05
    eq(fly(g), "over", "over")
end)

test("moonlander: the lander blinks while it is too fast to land", function()
    local g = new_game()
    g.vy = 0.5
    local grid = draw_game(g)
    eq(grid:get(math.floor(g.x), math.floor(g.y)), "blink", "warning")
    g.vy = 0.05
    grid = draw_game(g)
    eq(grid:get(math.floor(g.x), math.floor(g.y)), true, "steady when safe")
end)

test("moonlander: NEXT shows the fuel, one brick per 10 units", function()
    local g = new_game()
    g.fuel = 95
    local _, nextg = draw_game(g)
    eq(count_lit(nextg), 10, "ceil(95 / 10) bricks")
end)

test("moonlander: the pad blinks, the rest of the ground is solid", function()
    local g = new_game()
    local grid = draw_game(g)
    eq(grid:get(5, 19), "blink", "pad top"); eq(grid:get(5, 20), true, "under the pad")
    eq(grid:get(1, 19), true, "ground")
end)
