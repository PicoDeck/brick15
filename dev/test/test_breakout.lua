need("dev/test/game_helpers.lua")
local breakout = need("games/breakout.lua")

local function new_game() return breakout.new(game_ctx()) end

-- Put the ball in play at (x, y) moving (dx, dy), due to move at `now`.
local function launch(g, x, y, dx, dy, now)
    g.serving = false
    g.ball = { x = x, y = y, dx = dx, dy = dy }
    g.next_step = now or 0
end

test("breakout: meets the game contract", function()
    check_contract(breakout, "breakout", "BREAKOUT")
end)

test("breakout: 40 bricks on rows 2-5, 3 lives, ball waiting on the paddle", function()
    local g = new_game()
    local n = 0
    for r = 2, 5 do for c = 1, 10 do if g.bricks[r][c] then n = n + 1 end end end
    eq(n, 40, "bricks"); eq(g.lives, 3, "lives"); eq(g.serving, true, "serving")
    eq(g.ball.y, 19, "ball above the paddle")
end)

test("breakout: the waiting ball follows the paddle, Enter serves it", function()
    local g = new_game()
    g:update(press("left"), 1)
    eq(g.ball.x, g.paddle + 1, "ball over paddle centre")
    g:update(press("enter"), 2)
    eq(g.serving, false, "served"); eq(g.ball.dy, -1, "going up")
end)

test("breakout: the ball bounces off the side wall", function()
    local g = new_game()
    launch(g, 1, 10, -1, -1)
    g:update(NONE, 0)
    eq(g.ball.dx, 1, "reflected"); eq(g.ball.x, 2, "moved right")
end)

test("breakout: a ball driven into a corner bounces out of it", function()
    local g = new_game()
    for r = 2, 5 do for c = 1, 10 do g.bricks[r][c] = false end end
    g.bricks[5][5] = true                -- keep the board alive
    launch(g, 1, 1, -1, -1)
    g:update(NONE, 0)
    eq(g.ball.dx, 1, "off the side"); eq(g.ball.dy, 1, "off the top")
    truthy(g.ball.x >= 1 and g.ball.y >= 1, "still on the grid")
end)

test("breakout: hitting a brick removes it, scores and bounces", function()
    local g = new_game()
    launch(g, 3, 6, 1, -1)       -- next cell up is (3,5), a brick
    g:update(NONE, 0)
    eq(g.bricks[5][3], false, "brick gone")
    eq(g.score, 10, "score"); eq(g.ball.dy, 1, "bounced down")
end)

test("breakout: the paddle bounces the ball, its edge angles it", function()
    local g = new_game()
    g.paddle = 4                 -- cells 4-6
    launch(g, 5, 19, 1, 1)
    g:update(NONE, 0)
    eq(g.ball.dy, -1, "bounced up")
    launch(g, 3, 19, 1, 1)       -- will land on cell 4, the left edge
    g:update(NONE, 0)
    eq(g.ball.dx, -1, "left edge sends it left")
end)

test("breakout: missing the ball costs a life and re-serves", function()
    local g = new_game()
    g.paddle = 1
    launch(g, 8, 19, 1, 1)
    g:update(NONE, 0)
    eq(g.lives, 2, "life lost"); eq(g.serving, true, "serving again")
end)

test("breakout: losing the last life ends the round", function()
    local g = new_game()
    g.paddle, g.lives = 1, 1
    launch(g, 8, 19, 1, 1)
    eq(g:update(NONE, 0), "over", "over")
end)

test("breakout: clearing every brick starts the next board", function()
    local g = new_game()
    for r = 2, 5 do for c = 1, 10 do g.bricks[r][c] = false end end
    g.bricks[5][3] = true
    launch(g, 3, 6, 1, -1)
    g:update(NONE, 0)
    eq(g.level, 2, "level 2"); eq(g.serving, true, "serve the new board")
    eq(g.bricks[2][1], true, "bricks back")
end)

test("breakout: draw shows bricks, the 3-brick paddle and the ball", function()
    local g = new_game()
    local grid = draw_game(g)
    eq(count_lit(grid), 40 + 3 + 1, "lit cells")
end)
