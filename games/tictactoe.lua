-- tictactoe.lua — game 12: X against the CPU's O. Wins build a streak;
-- a loss ends the round. The board is 3x3 cells of 3x3 bricks.
-- Game contract: see lib/runner.lua. Needs the SFX global.

local BOARD_X, BOARD_Y = 1, 6     -- top-left brick of cell 1
local CPU_MS = 400                -- the CPU "thinks" this long
local RESULT_MS = 1200            -- a finished board shows this long
local X_MARK = { "#.#", ".#.", "#.#" }
local O_MARK = { "###", "#.#", "###" }
local LINES = {
    { 1, 2, 3 }, { 4, 5, 6 }, { 7, 8, 9 },
    { 1, 4, 7 }, { 2, 5, 8 }, { 3, 6, 9 },
    { 1, 5, 9 }, { 3, 5, 7 },
}

local DEMO = {
    {
        "..........",
        "..........",
        "#.####.#..",
        ".##.#..#..",
        "#.####.#..",
        "..........",
        "..........",
        "...#.#....",
        "....#.....",
        "...#.#....",
        "..........",
        "..........",
    },
    {
        "..........",
        "..........",
        "#.####.#..",
        ".##.#..#..",
        "#.####.#..",
        "...###....",
        "...#.#....",
        "...####.#.",
        "....#..#..",
        "...#.##.#.",
        "..........",
        "..........",
    },
}

local function winner(board)
    for _, l in ipairs(LINES) do
        local a = board[l[1]]
        if a ~= " " and a == board[l[2]] and a == board[l[3]] then return a, l end
    end
    return nil
end

local function full(board)
    for i = 1, 9 do if board[i] == " " then return false end end
    return true
end

-- The CPU's move: win, block, centre, a corner, a side; with chance
-- `mistake` it plays a random free cell instead.
local function cpu_move(board, mistake)
    local free = {}
    for i = 1, 9 do if board[i] == " " then free[#free + 1] = i end end
    if math.random() < mistake then return free[math.random(#free)] end
    for _, mark in ipairs({ "O", "X" }) do
        for _, i in ipairs(free) do
            board[i] = mark
            local w = winner(board)
            board[i] = " "
            if w then return i end
        end
    end
    for _, i in ipairs({ 5, 1, 3, 7, 9, 2, 4, 6, 8 }) do
        if board[i] == " " then return i end
    end
end

local function new(ctx)
    local game = { score = 0, cursor = 5, board = {} }
    game.mistake = math.max(0, 0.35 - 0.04 * (ctx.speed - 1))

    local function clear_board()
        for i = 1, 9 do game.board[i] = " " end
        game.win_line, game.status, game.result_until, game.cpu_at = nil, nil, nil, nil
    end

    -- After a move: a finished board shows its result for a moment.
    local function settle(now)
        local w, line = winner(game.board)
        if w == "X" then
            game.score = game.score + 1
            game.status, game.win_line = { "YOU WIN" }, line
            SFX.score()
        elseif w == "O" then
            game.status, game.win_line = { "CPU WINS" }, line
            game.lost = true
            SFX.over()
        elseif full(game.board) then
            game.status = { "DRAW" }
            SFX.select()
        else
            return false
        end
        game.result_until = now + RESULT_MS
        return true
    end

    function game:update(pad, now)
        if self.result_until then
            if now < self.result_until then return nil end
            if self.lost then return "over" end
            clear_board()
            return nil
        end
        if self.cpu_at then
            if now < self.cpu_at then return nil end
            self.cpu_at = nil
            self.board[cpu_move(self.board, self.mistake)] = "O"
            SFX.move()
            settle(now)
            return nil
        end

        local r, c = (self.cursor - 1) // 3, (self.cursor - 1) % 3
        if pad.repeated.up and r > 0 then self.cursor = self.cursor - 3 end
        if pad.repeated.down and r < 2 then self.cursor = self.cursor + 3 end
        if pad.repeated.left and c > 0 then self.cursor = self.cursor - 1 end
        if pad.repeated.right and c < 2 then self.cursor = self.cursor + 1 end
        if (pad.pressed.enter or pad.pressed.f1) and self.board[self.cursor] == " " then
            self.board[self.cursor] = "X"
            SFX.select()
            if not settle(now) then self.cpu_at = now + CPU_MS end
        end
        return nil
    end

    function game:draw(grid)
        local blink = {}
        for _, i in ipairs(self.win_line or {}) do blink[i] = true end
        for i = 1, 9 do
            local x = BOARD_X + ((i - 1) % 3) * 3
            local y = BOARD_Y + ((i - 1) // 3) * 3
            local mark = self.board[i]
            local v = blink[i] and "blink" or true
            if mark == "X" then grid:stamp(X_MARK, x, y, v)
            elseif mark == "O" then grid:stamp(O_MARK, x, y, v)
            else grid:set(x + 1, y + 1, true) end       -- empty: a centre dot marks the cell
            if i == self.cursor and not self.result_until then
                if mark == " " then grid:stamp({ "###", "###", "###" }, x, y, "blink")
                else grid:stamp(mark == "X" and X_MARK or O_MARK, x, y, "blink") end
            end
        end
    end

    clear_board()
    return game
end

return {
    id = "tictactoe",
    name = "TIC-TAC-TOE",
    hint = { "D-PAD MOVE", "ENTER PLACE X" },
    messages = { "YOU WIN", "DRAW", "CPU WINS" },
    order = "high",
    demo = DEMO,
    new = new,
    cpu_move = cpu_move,
}
