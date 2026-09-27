-- copter.lua — game 08. Expects globals: LCD, SFX, PAD, disp, picocalc.

local disp = picocalc.display
local scene_mgr = picocalc.game.scene
local save = picocalc.game.save

local SHIP_X = 60
local SHIP = 10
local TOP, BOT = 40, 312

local function new()
    local scene = {}
    local y, vy, gap_h, gap_c, score, game_over, col_x
    -- column model: the world is a vertical gap [gap_c-gap_h/2, gap_c+gap_h/2]
    -- scrolled by generating a new gap center as columns pass.

    local function save_hi()
        local hi = (save.get("hi_copter") or {}).v or 0
        if score > hi then save.set("hi_copter", { v = score }) end
    end

    local function reset()
        y = 176
        vy = 0
        gap_h = 90
        gap_c = 176
        score = 0
        game_over = false
        col_x = 0
    end

    function scene:enter()
        reset()
    end

    function scene:update()
        if game_over then
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
        local h = PAD.held()
        if p.esc then scene_mgr.switch("menu") return end

        local thrust = h.up or h.enter or h.f1
        vy = vy + (thrust and -0.42 or 0.22)
        vy = math.max(-3.5, math.min(3.5, vy))
        y = y + vy

        -- distance: score ticks up; gap tightens as score grows
        col_x = col_x + 2.5
        if col_x >= 40 then
            col_x = 0
            score = score + 1
            gap_h = math.max(48, 90 - math.floor(score / 4))
            -- random-walk the gap center
            gap_c = gap_c + math.random() * 44 - 22
            gap_c = math.max(TOP + gap_h / 2 + 4, math.min(BOT - gap_h / 2 - 4, gap_c))
            if score % 25 == 0 then SFX.score() end
        end

        local gap_top = gap_c - gap_h / 2
        local gap_bot = gap_c + gap_h / 2
        if y - SHIP / 2 < gap_top or y + SHIP / 2 > gap_bot then
            game_over = true
            SFX.over()
            save_hi()
        end
    end

    function scene:draw()
        LCD.clear()
        LCD.textCentered("COPTER", 6, 1, LCD.MID)
        LCD.seg(score, 16, 16, 2, 6, LCD.DARK)
        LCD.text("HI " .. ((save.get("hi_copter") or {}).v or 0), 252, 20, 1, LCD.DARK)

        local gap_top = gap_c - gap_h / 2
        local gap_bot = gap_c + gap_h / 2

        -- solid ceiling and floor around the gap
        disp.fillRect(0, TOP, 320, gap_top - TOP, LCD.DARK)
        disp.fillRect(0, gap_bot, 320, BOT - gap_bot, LCD.DARK)
        disp.fillRect(0, gap_top - 2, 320, 2, LCD.MID)
        disp.fillRect(0, gap_bot, 320, 2, LCD.MID)

        -- ship
        disp.fillRect(SHIP_X - SHIP / 2, math.floor(y) - SHIP / 2, SHIP, SHIP, LCD.DARK)
        disp.fillRect(SHIP_X + SHIP / 2, math.floor(y) - 2, 8, 4, LCD.DARK)

        if game_over then
            disp.fillRect(40, 120, 240, 80, LCD.DARK)
            disp.drawRect(40, 120, 240, 80, LCD.BG)
            LCD.textCentered("GAME OVER", 132, 2, LCD.BG)
            LCD.textCentered("SCORE " .. score, 152, 1, LCD.BG)
            LCD.textCentered("ENTER AGAIN", 172, 1, LCD.BG)
            LCD.textCentered("ESC MENU", 184, 1, LCD.BG)
        end

        disp.flush()
    end

    function scene:exit() end

    return scene
end

return { new = new }
