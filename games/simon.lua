-- simon.lua — game 11. Expects globals: LCD, SFX, PAD, disp, picocalc.

local disp = picocalc.display
local scene_mgr = picocalc.game.scene
local save = picocalc.game.save

local ZONES = { "up", "down", "left", "right" }
local ZONE_TONES = { up = 440, down = 330, left = 262, right = 220 }
local ZONE_LABEL = { up = "^", down = "v", left = "<", right = ">" }

local function new()
    local scene = {}
    local seq, input_idx, show_idx, show_timer, state, score
    -- state: "show" | "input" | "over"

    local function save_hi()
        local hi = (save.get("hi_simon") or {}).v or 0
        if score > hi then save.set("hi_simon", { v = score }) end
    end

    local next_round

    local function reset()
        seq = {}
        score = 0
        next_round()
    end

    function next_round()
        seq[#seq + 1] = ZONES[math.random(4)]
        input_idx = 0
        show_idx = 0
        show_timer = 0
        state = "show"
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
            show_timer = show_timer + 1
            if show_timer == 1 then
                SFX.tone(ZONE_TONES[seq[show_idx + 1]], 180)
            end
            if show_timer >= 30 then
                show_timer = 0
                show_idx = show_idx + 1
                if show_idx >= #seq then
                    state = "input"
                end
            end
            return
        end

        -- input state
        local pressed_zone = nil
        if p.up then pressed_zone = "up" end
        if p.down then pressed_zone = "down" end
        if p.left then pressed_zone = "left" end
        if p.right then pressed_zone = "right" end

        if pressed_zone then
            SFX.tone(ZONE_TONES[pressed_zone], 150)
            if pressed_zone == seq[input_idx + 1] then
                input_idx = input_idx + 1
                if input_idx >= #seq then
                    score = #seq
                    SFX.levelup()
                    next_round()
                end
            else
                state = "over"
                SFX.over()
                save_hi()
            end
        end
    end

    function scene:draw()
        LCD.clear()
        LCD.textCentered("SIMON", 6, 1, LCD.MID)
        LCD.text("SCORE", 16, 16, 1, LCD.MID)
        LCD.seg(score, 16, 26, 1, 3, LCD.DARK)
        LCD.text("HI", 252, 16, 1, LCD.MID)
        LCD.seg((save.get("hi_simon") or {}).v or 0, 252, 26, 1, 3, LCD.DARK)

        -- 2x2 zone pad
        local zx, zy, zs = 96, 96, 100
        for i, zone in ipairs(ZONES) do
            local cx = zx + ((i - 1) % 2) * zs
            local cy = zy + math.floor((i - 1) / 2) * zs
            local lit = false
            if state == "show" and show_timer <= 15 and seq[show_idx + 1] == zone then
                lit = true
            end
            if lit then
                disp.fillRect(cx + 4, cy + 4, zs - 8, zs - 8, LCD.DARK)
                LCD.textCentered(ZONE_LABEL[zone], cy + zs / 2 - 5, 2, LCD.BG)
            else
                disp.drawRect(cx + 4, cy + 4, zs - 8, zs - 8, LCD.DARK)
                LCD.textCentered(ZONE_LABEL[zone], cy + zs / 2 - 5, 2, LCD.MID)
            end
        end

        if state == "input" then
            LCD.textCentered("YOUR TURN", 220, 1, LCD.MID)
        elseif state == "over" then
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
