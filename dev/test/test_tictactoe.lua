need("dev/test/game_helpers.lua")
local ttt = need("games/tictactoe.lua")

local function new_game()
    local g = ttt.new(game_ctx())
    g.mistake = 0                          -- the CPU always plays its best move
    return g
end

local function board(g, s)                 -- s: 9 chars of "X", "O" or "."
    for i = 1, 9 do
        local ch = s:sub(i, i)
        g.board[i] = ch == "." and " " or ch
    end
end

local function place(g, i, now)
    g.cursor = i
    return g:update(press("enter"), now)
end

test("tictactoe: meets the game contract", function()
    check_contract(ttt, "tictactoe", "TIC-TAC-TOE")
end)

test("tictactoe: empty board, cursor in the centre, streak 0", function()
    local g = new_game()
    eq(g.cursor, 5, "centre"); eq(g.score, 0, "streak")
    for i = 1, 9 do eq(g.board[i], " ", "empty") end
end)

test("tictactoe: the cursor moves within the 3x3 board", function()
    local g = new_game()
    g:update(pad({ repeated = { "up" } }), 1)
    eq(g.cursor, 2, "up"); g:update(pad({ repeated = { "up" } }), 2)
    eq(g.cursor, 2, "top edge"); g:update(pad({ repeated = { "left" } }), 3)
    eq(g.cursor, 1, "left")
end)

test("tictactoe: you place X, the CPU answers after a moment", function()
    local g = new_game()
    place(g, 1, 0)
    eq(g.board[1], "X", "placed")
    g:update(NONE, 399)
    local o = 0 for i = 1, 9 do if g.board[i] == "O" then o = o + 1 end end
    eq(o, 0, "CPU still thinking")
    g:update(NONE, 400)
    o = 0 for i = 1, 9 do if g.board[i] == "O" then o = o + 1 end end
    eq(o, 1, "CPU moved")
end)

test("tictactoe: you can't play on a taken cell", function()
    local g = new_game()
    board(g, "O........")
    place(g, 1, 0)
    eq(g.board[1], "O", "unchanged"); eq(g.cpu_at, nil, "no CPU turn")
end)

test("tictactoe: the CPU takes a winning move", function()
    local g = new_game()
    board(g, "OO.XX....")
    eq(ttt.cpu_move(g.board, 0), 3, "completes its row")
end)

test("tictactoe: the CPU blocks your winning move", function()
    local g = new_game()
    board(g, "XX..O....")
    eq(ttt.cpu_move(g.board, 0), 3, "blocks")
end)

test("tictactoe: a win adds to the streak and deals a new board", function()
    local g = new_game()
    board(g, "XX.OO....")
    place(g, 3, 0)
    eq(g.score, 1, "streak"); eq(g.status[1], "YOU WIN", "result"); check_status(ttt, g)
    g:update(NONE, 1200)
    eq(g.board[1], " ", "new board"); eq(g.status, nil, "result cleared")
end)

test("tictactoe: a draw keeps the streak", function()
    local g = new_game()
    g.score = 2
    board(g, "XOXXOOOX.")
    place(g, 9, 0)
    eq(g.status[1], "DRAW", "result"); eq(g.score, 2, "streak kept")
end)

test("tictactoe: a CPU win ends the round", function()
    local g = new_game()
    board(g, "OO.XX...X")
    place(g, 7, 0)                         -- a wasted move; the CPU completes 1-2-3
    g:update(NONE, 400)
    eq(g.status[1], "CPU WINS", "result"); check_status(ttt, g)
    eq(g:update(NONE, 400 + 1200), "over", "over")
end)

test("tictactoe: each empty cell shows a centre dot, so the board is visible", function()
    local g = new_game()
    g.cursor = 1
    local grid = draw_game(g)
    for i = 2, 9 do
        local x = 1 + ((i - 1) % 3) * 3 + 1
        local y = 6 + ((i - 1) // 3) * 3 + 1
        eq(grid:get(x, y), true, "centre dot of cell " .. i)
        eq(grid:get(x - 1, y), false, "only the centre of cell " .. i)
    end
end)

test("tictactoe: the cursor on an empty cell is a blinking plus", function()
    local g = new_game()
    g.cursor = 5                               -- cell 5 spans cols 4-6, rows 9-11
    local grid = draw_game(g)
    for _, p in ipairs({ { 5, 9 }, { 4, 10 }, { 6, 10 }, { 5, 11 } }) do
        eq(grid:get(p[1], p[2]), "blink", "arm " .. p[1] .. "," .. p[2])
    end
    eq(grid:get(4, 9), false, "corners stay dark, unlike X")
    eq(grid:get(5, 10), true, "the centre dot stays steady")
end)

test("tictactoe: X and O are drawn as 3x3 marks in their cells", function()
    local g = new_game()
    board(g, "X.......O")
    g.cursor = 5
    local grid = draw_game(g)
    eq(grid:get(1, 6), true, "X corner"); eq(grid:get(2, 6), false, "X gap"); eq(grid:get(2, 7), true, "X centre")
    eq(grid:get(8, 13), false, "O hollow"); eq(grid:get(7, 12), true, "O ring")
    eq(grid:get(5, 9), "blink", "cursor on the empty centre cell: plus arm")
end)
