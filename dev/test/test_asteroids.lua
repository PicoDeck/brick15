need("dev/test/game_helpers.lua")
local asteroids = need("games/asteroids.lua")

local function new_game()
    local g = asteroids.new(game_ctx())
    g.rocks = {}                           -- tests place their own rocks
    g.next_rock = math.huge
    g.safe_until = 0                       -- no start-of-wave invulnerability
    return g
end

local function rock(size, x, y, dx, dy)
    return { size = size, x = x, y = y, dx = dx or 1, dy = dy or 0 }
end

test("asteroids: meets the game contract", function()
    check_contract(asteroids, "asteroids", "ASTEROIDS")
end)

test("asteroids: a wave starts with big rocks away from the ship, 3 lives", function()
    local g = asteroids.new(game_ctx())
    eq(g.lives, 3, "lives"); eq(g.dir, 1, "facing up")
    eq(#g.rocks, 3, "three big rocks")
    for _, r in ipairs(g.rocks) do eq(r.size, 3, "big") end
end)

test("asteroids: left and right rotate through 8 directions", function()
    local g = new_game()
    g:update(press("right"), 1)
    eq(g.dir, 2, "up-right")
    g:update(press("left"), 2); g:update(press("left"), 3)
    eq(g.dir, 8, "up-left")
end)

test("asteroids: thrust accelerates the ship the way it faces", function()
    local g = new_game()
    g.dir = 3                              -- right
    local x = g.x
    for t = 1, 10 do g:update(hold("up"), t * 50) end
    truthy(g.x > x, "moved right"); truthy(g.vx > 0, "velocity right")
end)

test("asteroids: the ship wraps around the edges", function()
    local g = new_game()
    g.x, g.vx = 10.9, 0.5
    g:update(NONE, g.next_tick)
    truthy(g.x < 2, "came back on the left: " .. g.x)
end)

test("asteroids: at most 3 bullets at once", function()
    local g = new_game()
    for t = 1, 5 do g:update(press("enter"), t) end
    eq(#g.bullets, 3, "bullets")
end)

test("asteroids: a bullet destroys a small rock and scores 100", function()
    local g = new_game()
    g.rocks = { rock(1, 5, 3), rock(1, 1, 18) }   -- the second keeps the wave going
    g.bullets = { { x = 5, y = 4, dx = 0, dy = -1, left = 5 } }
    g.next_bullet = 0
    g:update(NONE, 0)
    eq(#g.rocks, 1, "rock gone"); eq(g.score, 100, "score")
end)

test("asteroids: a big rock splits into two medium rocks", function()
    local g = new_game()
    g.rocks = { rock(3, 4, 2) }            -- cells rows 2-4
    g.bullets = { { x = 5, y = 5, dx = 0, dy = -1, left = 5 } }
    g.next_bullet = 0
    g:update(NONE, 0)
    eq(#g.rocks, 2, "split"); eq(g.rocks[1].size, 2, "medium"); eq(g.score, 20, "score")
    truthy(g.rocks[1].dx ~= g.rocks[2].dx or g.rocks[1].dy ~= g.rocks[2].dy, "fly apart")
end)

test("asteroids: a rock hitting the ship costs a life, then a safe respawn", function()
    local g = new_game()
    g.rocks = { rock(2, 5, 10, 0, 1), rock(1, 1, 18) }   -- second rock keeps the wave alive
    g:update(NONE, 1)
    eq(g.lives, 2, "hit")
    truthy(g.safe_until > 1, "invulnerable for a while")
    g:update(NONE, 2)
    eq(g.lives, 2, "no second hit while invulnerable")
end)

test("asteroids: losing the last life ends the round", function()
    local g = new_game()
    g.lives = 1
    g.rocks = { rock(2, 5, 10, 0, 1) }
    eq(g:update(NONE, 1), "over", "over")
end)

test("asteroids: clearing the rocks starts the next wave a level up", function()
    local g = new_game()
    g.rocks = { rock(1, 5, 3) }
    g.bullets = { { x = 5, y = 4, dx = 0, dy = -1, left = 5 } }
    g.next_bullet = 0
    g:update(NONE, 0)
    eq(g.level, 2, "level 2"); eq(#g.rocks, 4, "3 + 1 big rocks")
end)

test("asteroids: the ship blinks while it is invulnerable", function()
    local g = new_game()
    g.rocks = { rock(1, 1, 18) }
    g.safe_until = 1000
    g:update(NONE, 10)
    local grid = draw_game(g)
    eq(grid:get(5, 9), "blink", "nose blinks")
end)

test("asteroids: draw wraps rock cells across the edges", function()
    local g = new_game()
    g.rocks = { rock(2, 10, 20) }          -- cells (10,20) (1,20) (10,1) (1,1)
    g.x, g.y = 5.5, 10.5
    local grid = draw_game(g)
    eq(grid:get(1, 1), true, "wrapped corner"); eq(grid:get(10, 20), true, "own corner")
end)
