need("dev/test/game_helpers.lua")
local tank = need("games/tank.lua")

local function new_game()
    local g = tank.new(game_ctx())
    g.next_spawn, g.next_enemy = math.huge, math.huge   -- a quiet field for tests
    return g
end

local function shot(x, y, dx, dy, owner)
    return { x = x, y = y, dx = dx, dy = dy, owner = owner or "enemy" }
end

test("tank: meets the game contract", function()
    check_contract(tank, "tank", "TANK")
end)

test("tank: you start bottom-left facing up, 3 lives, base intact", function()
    local g = new_game()
    eq(g.player.x, 1, "x"); eq(g.player.y, 18, "y"); eq(g.player.dir, "up", "facing")
    eq(g.lives, 3, "lives"); eq(g.base_alive, true, "base")
end)

test("tank: the d-pad turns and moves one cell, walls block", function()
    local g = new_game()
    g:update(pad({ repeated = { "up" } }), 1)
    eq(g.player.y, 17, "moved up")
    g:update(pad({ repeated = { "right" } }), 2)
    eq(g.player.dir, "right", "turned"); eq(g.player.x, 1, "wall at column 4 blocks")
end)

test("tank: you can drive out of the start, up the left lane", function()
    local g = new_game()
    for t = 1, 20 do g:update(pad({ repeated = { "up" } }), t) end
    truthy(g.player.y <= 7, "drove up past the lower walls, reached y=" .. g.player.y)
end)

test("tank: one shot at a time, fired from the barrel", function()
    local g = new_game()
    g:update(press("enter"), 1)
    eq(#g.bullets, 1, "fired")
    eq(g.bullets[1].x, 2, "barrel column"); eq(g.bullets[1].y, 17, "just ahead")
    g:update(press("enter"), 2)
    eq(#g.bullets, 1, "second shot ignored")
end)

test("tank: a shot knocks out one wall brick", function()
    local g = new_game()
    g.bullets = { shot(4, 17, 0, 1, "player") }   -- next cell (4,18) is a wall
    g.next_bullet = 0
    g:update(NONE, 0)
    eq(g.walls[18][4], false, "brick gone"); eq(#g.bullets, 0, "shot used")
end)

test("tank: your shot destroys an enemy tank and scores 100", function()
    local g = new_game()
    g.enemies = { { x = 1, y = 7, dir = "down" } }     -- box cols 1-3, rows 7-9
    g.bullets = { shot(2, 5, 0, 1, "player") }         -- column 2 is clear
    g.next_bullet = 0
    g:update(NONE, 0); g:update(NONE, 100)
    eq(#g.enemies, 0, "destroyed"); eq(g.score, 100, "score")
end)

test("tank: an enemy shot costs you a life and sends you back to the start", function()
    local g = new_game()
    g.player.y = 12
    g.bullets = { shot(2, 10, 0, 1) }
    g.next_bullet = 0
    g:update(NONE, 0); g:update(NONE, 100)
    eq(g.lives, 2, "hit"); eq(g.player.y, 18, "back at the start")
end)

test("tank: an enemy shot on the base ends the round with BASE LOST", function()
    local g = new_game()
    g.bullets = { shot(5, 18, 0, 1) }             -- (5,18) is a wall: clear it first
    g.walls[18][5] = false
    g.next_bullet = 0
    eq(g:update(NONE, 0), "over", "over")
    eq(g.status[1], "BASE LOST", "headline"); check_status(tank, g)
end)

test("tank: an enemy's shot hits the wall right in front of it, not what's behind", function()
    local g = new_game()
    g.enemies = { { x = 8, y = 18, dir = "left" } }   -- beside the base's right wall
    g.next_enemy, g.next_bullet = 0, math.huge
    -- pin the enemy's choices: no random turn, turn "left", then fire
    local real, draws = math.random, { 0.9, 0.1 }
    math.random = function(n) if n then return 3 end return table.remove(draws, 1) or 0.5 end
    local ok, err = pcall(function() g:update(NONE, 0) end)
    math.random = real
    assert(ok, err)
    eq(g.walls[19][7], false, "the base's side wall takes the shot")
    g.next_bullet = 0
    eq(g:update(NONE, 100), nil, "round goes on"); eq(g.base_alive, true, "base intact")
end)

test("tank: losing the last life ends the round", function()
    local g = new_game()
    g.lives = 1
    g.player.y = 12
    g.bullets = { shot(2, 11, 0, 1) }
    g.next_bullet = 0
    eq(g:update(NONE, 0), "over", "over")
end)

test("tank: destroying the whole wave starts the next with fresh walls", function()
    local g = new_game()
    g.walls[5][1] = false
    g.killed, g.spawned = g.wave_total - 1, g.wave_total
    g.enemies = { { x = 1, y = 7, dir = "down" } }
    g.bullets = { shot(2, 6, 0, 1, "player") }
    g.next_bullet = 0
    g:update(NONE, 0)
    eq(g.level, 2, "level 2"); eq(g.walls[5][1], true, "walls restored")
end)

test("tank: an enemy never spawns on top of your tank", function()
    local g = new_game()
    g.player.x, g.player.y = 1, 1       -- sitting on a spawn point
    for i = 1, 60 do
        g.next_spawn = 0
        g:update(NONE, i)
        for _, e in ipairs(g.enemies) do
            truthy(math.abs(e.x - g.player.x) >= 3 or math.abs(e.y - g.player.y) >= 3, "overlap")
        end
        g.enemies = {}
    end
end)

test("tank: your tank is solid and steady, enemy tanks are hollow and blink", function()
    local g = new_game()
    g.enemies = { { x = 4, y = 1, dir = "down" } }
    local grid = draw_game(g)
    eq(grid:get(2, 19), true, "player centre")
    eq(grid:get(5, 2), false, "enemy centre hollow")
    eq(grid:get(5, 3), "blink", "enemy barrel down, blinking")
end)
