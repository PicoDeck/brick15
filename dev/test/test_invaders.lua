need("dev/test/game_helpers.lua")
local invaders = need("games/invaders.lua")

local function new_game()
    local g = invaders.new(game_ctx())
    g.next_bomb = math.huge            -- no bombs unless a test adds them
    return g
end

local function alive(g)
    local n = 0
    for _, a in ipairs(g.aliens) do if a.alive then n = n + 1 end end
    return n
end

test("invaders: meets the game contract", function()
    check_contract(invaders, "invaders", "INVADERS")
end)

test("invaders: 4x3 aliens with a gap around each, gun at the bottom, 3 lives", function()
    local g = new_game()
    eq(#g.aliens, 12, "aliens"); eq(alive(g), 12, "all alive")
    local grid = draw_game(g)
    local x, y = g:alien_pos(g.aliens[1])
    eq(grid:get(x + 1, y), false, "gap to the right"); eq(grid:get(x, y + 1), false, "gap below")
    eq(g.lives, 3, "lives"); eq(g.gun, 5, "gun centre column")
end)

test("invaders: the block marches sideways, then drops and turns at the edge", function()
    local g = new_game()
    local x0 = g.ox
    g:update(NONE, g.next_march)
    eq(g.ox, x0 + 1, "stepped right")
    g.ox = 10 - 7 + 1                   -- right edge of the 7-wide block at column 10
    local y0 = g.oy
    g:update(NONE, g.next_march)
    eq(g.oy, y0 + 1, "dropped a row"); eq(g.march_dir, -1, "now marching left")
end)

test("invaders: only one bullet at a time", function()
    local g = new_game()
    g:update(press("up"), 1)
    truthy(g.bullet, "fired")
    local first = g.bullet
    g:update(press("up"), 2)
    eq(g.bullet, first, "second shot ignored")
end)

test("invaders: a bullet kills the alien it reaches and scores", function()
    local g = new_game()
    local a = g.aliens[9]               -- bottom row, first column
    local ax, ay = g:alien_pos(a)
    g.bullet = { x = ax, y = ay + 1 }
    g.next_bullet = 0
    g:update(NONE, 0)
    eq(a.alive, false, "alien dead"); eq(g.bullet, nil, "bullet used")
    eq(g.score, 10, "score")
end)

test("invaders: a bomb on the gun costs a life", function()
    local g = new_game()
    g.bombs = { { x = g.gun, y = 18 } }
    g.next_bombs = 0
    g:update(NONE, 0)
    eq(g.lives, 2, "life lost"); eq(#g.bombs, 0, "bombs cleared")
end)

test("invaders: losing the last life ends the round", function()
    local g = new_game()
    g.lives = 1
    g.bombs = { { x = g.gun, y = 18 } }
    g.next_bombs = 0
    eq(g:update(NONE, 0), "over", "over")
end)

test("invaders: aliens reaching the gun rows end the round", function()
    local g = new_game()
    g.oy = 13                           -- bottom alien row (oy + 4) at 18 after the drop
    g.ox, g.march_dir = 5, 1
    eq(g:update(NONE, g.next_march), "over", "invaded")
end)

test("invaders: clearing the wave starts the next one a level up", function()
    local g = new_game()
    for i = 1, 11 do g.aliens[i].alive = false end
    local a = g.aliens[12]
    local ax, ay = g:alien_pos(a)
    g.bullet, g.next_bullet = { x = ax, y = ay + 1 }, 0
    g:update(NONE, 0)
    eq(g.level, 2, "level 2"); eq(alive(g), 12, "new wave")
end)

test("invaders: draw shows 12 aliens and the 4-cell gun", function()
    local g = new_game()
    eq(count_lit(draw_game(g)), 12 + 4, "lit")
end)
