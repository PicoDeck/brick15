need("dev/test/game_helpers.lua")
local pong = need("games/pong.lua")

local function new_game()
    local g = pong.new(game_ctx())
    g.next_ai = math.huge                  -- CPU paddle still unless a test moves it
    return g
end

local function launch(g, x, y, dx, dy)
    g.serving = false
    g.ball = { x = x, y = y, dx = dx, dy = dy }
    g.next_step = 0
end

test("pong: meets the game contract", function()
    check_contract(pong, "pong", "PONG")
end)

test("pong: starts 00-00 with the ball on your paddle", function()
    local g = new_game()
    eq(g.score, 0, "score"); eq(g.score_text, "00-00", "shown score")
    eq(g.serving, true, "serving"); eq(g.ball.y, 19, "on the paddle")
end)

test("pong: Enter serves the ball upwards", function()
    local g = new_game()
    g:update(press("enter"), 1)
    eq(g.serving, false, "served"); eq(g.ball.dy, -1, "up")
end)

test("pong: the ball bounces off the side walls", function()
    local g = new_game()
    launch(g, 10, 10, 1, -1)
    g:update(NONE, 0)
    eq(g.ball.dx, -1, "reflected"); eq(g.ball.x, 9, "moved left")
end)

test("pong: your paddle returns the ball, its edge angles it", function()
    local g = new_game()
    g.player = 4                           -- cells 4-6
    launch(g, 4, 19, 1, 1)                 -- lands on 5, the middle
    g:update(NONE, 0)
    eq(g.ball.dy, -1, "returned"); eq(g.ball.dx, 1, "middle keeps direction")
    launch(g, 7, 19, -1, 1)                -- lands on 6, the right edge
    g:update(NONE, 0)
    eq(g.ball.dx, 1, "right edge sends it right")
end)

test("pong: missing the ball gives the CPU a point", function()
    local g = new_game()
    g.player = 1
    launch(g, 8, 19, 1, 1)
    g:update(NONE, 0)
    eq(g.cpu_points, 1, "cpu point"); eq(g.score_text, "00-01", "shown")
    eq(g.serving, true, "serve again")
end)

test("pong: getting past the CPU scores for you", function()
    local g = new_game()
    g.cpu = 1
    launch(g, 8, 2, 1, -1)
    g:update(NONE, 0)
    eq(g.score, 1, "your point"); eq(g.score_text, "01-00", "shown")
end)

test("pong: first to 7 ends the round with the result", function()
    local g = new_game()
    g.score, g.cpu = 6, 1
    launch(g, 8, 2, 1, -1)
    eq(g:update(NONE, 0), "over", "over"); eq(g.status[1], "YOU WIN", "result")
    check_status(pong, g)
    local h = new_game()
    h.cpu_points, h.player = 6, 1
    launch(h, 8, 19, 1, 1)
    eq(h:update(NONE, 0), "over", "over"); eq(h.status[1], "CPU WINS", "result")
    check_status(pong, h)
end)

test("pong: the CPU paddle chases a ball coming its way", function()
    local g = new_game()
    g.cpu = 4                              -- centre column 5
    launch(g, 9, 8, 1, -1)
    g.next_step, g.next_ai = math.huge, 0
    g:update(NONE, 0)
    eq(g.cpu, 5, "moved toward the ball")
end)
