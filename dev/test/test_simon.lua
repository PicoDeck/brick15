need("dev/test/game_helpers.lua")
local simon = need("games/simon.lua")

local function new_game() return simon.new(game_ctx()) end

-- Advance time until the game is waiting for input.
local function until_input(g, now)
    for _ = 1, 200 do
        if g.state == "input" then return now end
        now = now + 50
        g:update(NONE, now)
    end
    error("never reached input")
end

test("simon: meets the game contract", function()
    check_contract(simon, "simon", "SIMON")
end)

test("simon: shows the hint first, then WATCH, then YOUR TURN", function()
    local g = new_game()
    eq(g.status, nil, "hint shows during the intro")
    eq(#g.seq, 1, "one pad to remember")
    local now = 0
    repeat now = now + 50 g:update(NONE, now) until g.state == "show"
    eq(g.status[1], "WATCH", "watching"); check_status(simon, g)
    until_input(g, now)
    eq(g.status[1], "YOUR TURN", "your turn"); check_status(simon, g)
end)

test("simon: presses are ignored while the sequence plays", function()
    local g = new_game()
    local now = 0
    repeat now = now + 50 g:update(NONE, now) until g.state == "show"
    local wrong = g.seq[1] == "up" and "down" or "up"
    eq(g:update(press(wrong), now + 1), nil, "not a mistake")
    eq(g.state, "show", "still showing")
end)

test("simon: repeating the sequence scores it and adds a pad", function()
    local g = new_game()
    local now = until_input(g, 0)
    g:update(press(g.seq[1]), now + 10)
    eq(g.score, 1, "scored")
    for _ = 1, 40 do now = now + 50 g:update(NONE, now) end
    eq(#g.seq, 2, "sequence grew")
end)

test("simon: a wrong pad ends the round with WRONG", function()
    local g = new_game()
    local now = until_input(g, 0)
    local wrong = g.seq[1] == "up" and "down" or "up"
    eq(g:update(press(wrong), now + 10), "over", "over")
    eq(g.status[1], "WRONG", "headline"); check_status(simon, g)
end)

test("simon: waiting too long ends the round with TOO SLOW", function()
    local g = new_game()
    local now = until_input(g, 0)
    eq(g:update(NONE, now + 4001), "over", "over")
    eq(g.status[1], "TOO SLOW", "headline"); check_status(simon, g)
end)

test("simon: the four pads sit in a plus that matches the d-pad", function()
    eq(simon.PADS.up.x, 4); eq(simon.PADS.up.y, 3)
    eq(simon.PADS.left.x, 1); eq(simon.PADS.left.y, 9)
    eq(simon.PADS.right.x, 7); eq(simon.PADS.right.y, 9)
    eq(simon.PADS.down.x, 4); eq(simon.PADS.down.y, 15)
end)

test("simon: unlit pads are outlines, a lit pad is filled", function()
    local g = new_game()
    local grid = draw_game(g)
    eq(grid:get(4, 3), true, "outline corner"); eq(grid:get(5, 4), false, "hollow middle")
    eq(count_lit(grid), 4 * 12, "four outlines")
    g.lit = "up"
    grid = draw_game(g)
    eq(grid:get(5, 4), true, "filled when lit")
end)
