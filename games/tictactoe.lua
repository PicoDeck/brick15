-- tictactoe.lua — game 12. Expects globals: LCD, SFX, PAD, disp, picocalc.

local disp = picocalc.display
local scene_mgr = picocalc.game.scene

local N = 3
local CELL = 70
local OX, OY = 55, 70

local function new()
    local scene = {}
    local board, cursor, turn, result, tally
    -- turn: "player" | "ai"; result: nil | "X" | "O" | "draw"

    local function reset()
        board = {}
        for i = 1, 9 do board[i] = " " end
        cursor = 5
        turn = "player"
        result = nil
    end

    local function check_win(b, mark)
        local lines = {
            { 1, 2, 3 }, { 4, 5, 6 }, { 7, 8, 9 },
            { 1, 4, 7 }, { 2, 5, 8 }, { 3, 6, 9 },
            { 1, 5, 9 }, { 3, 5, 7 },
        }
        for _, line in ipairs(lines) do
            if b[line[1]] == mark and b[line[2]] == mark and b[line[3]] == mark then
                return line
            end
        end
        return nil
    end

    local function ai_move()
        -- 1. win, 2. block, 3. center, 4. corner, 5. random
        local choice = nil
        for _, mark in ipairs({ "O", "X" }) do
            for i = 1, 9 do
                if board[i] == " " then
                    board[i] = mark
                    if check_win(board, mark) then choice = i end
                    board[i] = " "
                    if choice then break end
                end
            end
            if choice then break end
        end
        if not choice and board[5] == " " then choice = 5 end
        if not choice then
            local corners = {}
            for _, i in ipairs({ 1, 3, 7, 9 }) do
                if board[i] == " " then corners[#corners + 1] = i end
            end
            if #corners > 0 then choice = corners[math.random(#corners)] end
        end
        if not choice then
            local open = {}
            for i = 1, 9 do
                if board[i] == " " then open[#open + 1] = i end
            end
            choice = open[math.random(#open)]
        end
        board[choice] = "O"
    end

    local function end_if_done()
        local line = check_win(board, "X")
        if line then
            result = "X"
            tally.x = tally.x + 1
            SFX.levelup()
            return line
        end
        line = check_win(board, "O")
        if line then
            result = "O"
            tally.o = tally.o + 1
            SFX.over()
            return line
        end
        local full = true
        for i = 1, 9 do
            if board[i] == " " then full = false break end
        end
        if full then
            result = "draw"
            tally.d = tally.d + 1
            SFX.hit()
        end
        return nil
    end

    function scene:enter()
        tally = { x = 0, o = 0, d = 0 }
        reset()
    end

    function scene:update()
        local p = PAD.pressed()
        if p.esc then scene_mgr.switch("menu") return end

        if result then
            if p.enter then
                SFX.start()
                reset()
            end
            return
        end

        if turn == "player" then
            local c = (cursor - 1) % 3 + 1
            local r = math.floor((cursor - 1) / 3) + 1
            if p.left and c > 1 then cursor = cursor - 1 SFX.move() end
            if p.right and c < 3 then cursor = cursor + 1 SFX.move() end
            if p.up and r > 1 then cursor = cursor - 3 SFX.move() end
            if p.down and r < 3 then cursor = cursor + 3 SFX.move() end
            if (p.enter or p.f1) and board[cursor] == " " then
                board[cursor] = "X"
                SFX.rotate()
                if not end_if_done() then
                    turn = "ai"
                end
            end
        else
            ai_move()
            if not end_if_done() then
                turn = "player"
            else
                SFX.drop()
            end
        end
    end

    function scene:draw()
        LCD.clear()
        LCD.textCentered("TIC-TAC-TOE", 6, 1, LCD.MID)

        -- series tally
        LCD.text("W " .. tally.x, 16, 16, 1, LCD.DARK)
        LCD.text("L " .. tally.o, 16, 28, 1, LCD.DARK)
        LCD.text("D " .. tally.d, 16, 40, 1, LCD.DARK)

        -- board
        for i = 1, 9 do
            local c = (i - 1) % 3 + 1
            local r = math.floor((i - 1) / 3) + 1
            local x, y = OX + (c - 1) * CELL, OY + (r - 1) * CELL
            disp.drawRect(x + 4, y + 4, CELL - 8, CELL - 8, LCD.DARK)
            local mark = board[i]
            if mark ~= " " then
                LCD.textCenteredAt(mark, x + CELL / 2, y + CELL / 2 - 5, 2, LCD.DARK)
            end
            if i == cursor and not result and turn == "player" then
                disp.drawRect(x + 1, y + 1, CELL - 2, CELL - 2, LCD.MID)
            end
        end

        if result then
            disp.fillRect(40, 120, 240, 80, LCD.DARK)
            disp.drawRect(40, 120, 240, 80, LCD.BG)
            if result == "X" then
                LCD.textCentered("YOU WIN", 132, 2, LCD.BG)
            elseif result == "O" then
                LCD.textCentered("AI WINS", 132, 2, LCD.BG)
            else
                LCD.textCentered("DRAW", 132, 2, LCD.BG)
            end
            LCD.textCentered("ENTER AGAIN", 172, 1, LCD.BG)
            LCD.textCentered("ESC MENU", 184, 1, LCD.BG)
        else
            LCD.textCentered(turn == "player" and "YOUR MOVE" or "AI THINKING", 290, 1, LCD.MID)
        end

        disp.flush()
    end

    function scene:exit() end

    return scene
end

return { new = new }
