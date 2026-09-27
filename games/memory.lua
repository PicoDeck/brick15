-- memory.lua — game 10. Expects globals: LCD, SFX, PAD, disp, picocalc.

local disp = picocalc.display
local scene_mgr = picocalc.game.scene
local save = picocalc.game.save

local COLS, ROWS = 4, 4
local CELL = 56
local OX, OY = 32, 56
local SYMBOLS = { "A", "B", "C", "D", "E", "F", "G", "H" }

local function new()
    local scene = {}
    local cards, flipped, matched, cursor, turns, state, hide_timer
    -- state: "pick" | "show" | "over"

    local function save_best()
        local best = (save.get("hi_memory") or {}).v or 0
        if best == 0 or turns < best then save.set("hi_memory", { v = turns }) end
    end

    local function reset()
        local deck = {}
        for i = 1, 8 do
            deck[#deck + 1] = SYMBOLS[i]
            deck[#deck + 1] = SYMBOLS[i]
        end
        -- shuffle
        for i = #deck, 2, -1 do
            local j = math.random(i)
            deck[i], deck[j] = deck[j], deck[i]
        end
        cards = {}
        for i = 1, 16 do cards[i] = { sym = deck[i], up = false, done = false } end
        flipped = {}
        matched = 0
        cursor = 1
        turns = 0
        state = "pick"
        hide_timer = 0
    end

    local function cell_xy(i)
        local c = (i - 1) % COLS + 1
        local r = math.floor((i - 1) / COLS) + 1
        return OX + (c - 1) * CELL, OY + (r - 1) * CELL
    end

    function scene:enter()
        reset()
    end

    function scene:update()
        if state == "over" then
            local p = PAD.pressed()
            if p.enter then
                SFX.start()
                reset()
            elseif p.esc then
                scene_mgr.switch("menu")
            end
            return
        end

        local p = PAD.pressed()
        if p.esc then scene_mgr.switch("menu") return end

        if state == "show" then
            hide_timer = hide_timer - 1
            if hide_timer <= 0 then
                for _, i in ipairs(flipped) do cards[i].up = false end
                flipped = {}
                state = "pick"
            end
            return
        end

        -- cursor move
        local c = (cursor - 1) % COLS + 1
        local r = math.floor((cursor - 1) / COLS) + 1
        if p.left and c > 1 then cursor = cursor - 1 SFX.move() end
        if p.right and c < COLS then cursor = cursor + 1 SFX.move() end
        if p.up and r > 1 then cursor = cursor - COLS SFX.move() end
        if p.down and r < ROWS then cursor = cursor + COLS SFX.move() end

        -- flip
        if (p.enter or p.f1) and #flipped < 2 and not cards[cursor].done then
            cards[cursor].up = true
            flipped[#flipped + 1] = cursor
            SFX.rotate()
            if #flipped == 2 then
                turns = turns + 1
                local a, b = cards[flipped[1]], cards[flipped[2]]
                if a.sym == b.sym then
                    a.done, b.done = true, true
                    matched = matched + 2
                    flipped = {}
                    SFX.score()
                    if matched == 16 then
                        state = "over"
                        SFX.levelup()
                        save_best()
                    end
                else
                    state = "show"
                    hide_timer = 45
                end
            end
        end
    end

    function scene:draw()
        LCD.clear()
        LCD.textCentered("MEMORY", 6, 1, LCD.MID)
        LCD.text("TURNS", 16, 16, 1, LCD.MID)
        LCD.seg(turns, 16, 26, 1, 3, LCD.DARK)
        LCD.text("BEST", 252, 16, 1, LCD.MID)
        LCD.seg((save.get("hi_memory") or {}).v or 0, 252, 26, 1, 3, LCD.DARK)

        for i = 1, 16 do
            local x, y = cell_xy(i)
            local card = cards[i]
            if card.done then
                disp.fillRect(x + 4, y + 4, CELL - 8, CELL - 8, LCD.MID)
            elseif card.up then
                disp.fillRect(x + 4, y + 4, CELL - 8, CELL - 8, LCD.DARK)
                LCD.textCenteredAt(card.sym, x + CELL / 2, y + CELL / 2 - 5, 2, LCD.BG)
            else
                disp.drawRect(x + 4, y + 4, CELL - 8, CELL - 8, LCD.DARK)
                disp.drawRect(x + 8, y + 8, CELL - 16, CELL - 16, LCD.MID)
            end
            if i == cursor and state ~= "over" then
                disp.drawRect(x + 1, y + 1, CELL - 2, CELL - 2, LCD.DARK)
            end
        end

        if state == "over" then
            disp.fillRect(40, 120, 240, 80, LCD.DARK)
            disp.drawRect(40, 120, 240, 80, LCD.BG)
            LCD.textCentered("YOU WIN", 132, 2, LCD.BG)
            LCD.textCentered("TURNS " .. turns, 152, 1, LCD.BG)
            LCD.textCentered("ENTER AGAIN", 172, 1, LCD.BG)
            LCD.textCentered("ESC MENU", 184, 1, LCD.BG)
        end

        disp.flush()
    end

    function scene:exit() end

    return scene
end

return { new = new }
