need("dev/test/game_helpers.lua")
local missile = need("games/missile.lua")

local function new_game()
    local g = missile.new(game_ctx())
    g.next_spawn = math.huge               -- no new missiles unless a test adds them
    return g
end

-- A missile from (x0, 1) aimed at (tx, 20), currently at row y.
local function incoming(x0, tx, y)
    local m = { x0 = x0, tx = tx, y = y or 1 }
    m.x = x0
    return m
end

test("missile: meets the game contract", function()
    check_contract(missile, "missile", "MISSILE CMD")
end)

test("missile: 3 cities, 12 shots, crosshair mid-screen", function()
    local g = new_game()
    eq(g.lives, 3, "cities as lives"); eq(g.ammo, 12, "ammo")
    eq(g.cx, 5, "crosshair x"); eq(g.cy, 10, "crosshair y")
end)

test("missile: the crosshair moves with the d-pad and stays on the sky", function()
    local g = new_game()
    g:update(pad({ repeated = { "up" } }), 1)
    eq(g.cy, 9, "moved up")
    for _ = 1, 30 do g:update(pad({ repeated = { "down" } }), 1) end
    eq(g.cy, 17, "stops above the ground")
end)

test("missile: firing spends a shot and explodes at the crosshair", function()
    local g = new_game()
    g:update(press("enter"), 100)
    eq(g.ammo, 11, "shot spent"); eq(#g.explosions, 1, "explosion")
    eq(g.explosions[1].x, 5, "at crosshair x"); eq(g.explosions[1].y, 10, "at crosshair y")
end)

test("missile: no shots left means no explosion", function()
    local g = new_game()
    g.ammo = 0
    g:update(press("enter"), 1)
    eq(#g.explosions, 0, "nothing")
end)

test("missile: an explosion grows from radius 1 to 2 and then fades", function()
    local g = new_game()
    g:update(press("enter"), 0)
    local e = g.explosions[1]
    eq(missile.radius(e, 100), 1, "starts small")
    eq(missile.radius(e, 200), 2, "grows")
    eq(missile.radius(e, 350), 1, "shrinks")
    eq(missile.radius(e, 500), nil, "gone")
end)

test("missile: a missile inside the blast is destroyed and scores", function()
    local g = new_game()
    g.missiles = { incoming(6, 6, 11) }     -- (6,11): 2 cells from (5,10)
    g.explosions = { { x = 5, y = 10, t0 = 0 } }
    g.next_step = math.huge
    g:update(NONE, 200)                      -- radius 2
    eq(#g.missiles, 0, "destroyed"); eq(g.score, 25, "score")
end)

test("missile: missiles step down one row toward their target", function()
    local g = new_game()
    g.missiles = { incoming(1, 10, 1) }
    g:update(NONE, g.next_step)
    eq(g.missiles[1].y, 2, "down a row")
    truthy(g.missiles[1].x >= 1 and g.missiles[1].x <= 2, "drifting toward its target")
end)

test("missile: a missile landing on a city destroys it", function()
    local g = new_game()
    g.missiles = { incoming(2, 2, 19) }
    g:update(NONE, g.next_step)
    eq(g.lives, 2, "city lost"); eq(#g.missiles, 0, "missile gone")
end)

test("missile: losing the last city ends the round", function()
    local g = new_game()
    g.cities[2].alive, g.cities[3].alive = false, false
    g.missiles = { incoming(2, 2, 19) }
    eq(g:update(NONE, g.next_step), "over", "over")
end)

test("missile: a finished wave scores a bonus and refills the shots", function()
    local g = new_game()
    g.spawned, g.ammo = g.wave_total, 4
    g.missiles, g.explosions = {}, {}
    g:update(NONE, 1)
    eq(g.level, 2, "next wave"); eq(g.ammo, 12, "refilled")
    eq(g.score, 3 * 50 + 4 * 5, "bonus for cities and spare shots")
end)

test("missile: the NEXT box shows one brick per shot", function()
    local g = new_game()
    eq(g.next_label, "AMMO", "box labelled AMMO")
    g.ammo = 5
    local _, nextg = draw_game(g)
    eq(count_lit(nextg), 5, "5 shots")
end)
