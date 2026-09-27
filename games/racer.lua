-- racer.lua — game 06. Expects globals: LCD, SFX, PAD, disp, picocalc.

local disp = picocalc.display
local scene_mgr = picocalc.game.scene
local save = picocalc.game.save

local ROAD_L, ROAD_R = 60, 260
local CAR_W, CAR_H = 24, 34
local PLAYER_Y = 250

local function new()
    local scene = {}
    local px, cars, lives, score, speed, frame, spawn_timer, flash, game_over, scroll

    local function save_hi()
        local hi = (save.get("hi_racer") or {}).v or 0
        if score > hi then save.set("hi_racer", { v = score }) end
    end

    local function reset()
        px = 160
        cars = {}
        lives = 3
        score = 0
        speed = 2
        frame = 0
        spawn_timer = 0
        flash = 0
        game_over = false
        scroll = 0
    end

    local function spawn_car()
        local lane = math.random(3)
        local x = ROAD_L + 14 + (lane - 1) * 66
        for _, c in ipairs(cars) do
            if math.abs(c.x - x) < 40 and c.y < 80 then return end
        end
        cars[#cars + 1] = { x = x, y = -CAR_H, vy = math.random() * 1.5 + 0.5 }
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

        if h.left then px = px - 4 end
        if h.right then px = px + 4 end
        px = math.max(ROAD_L + CAR_W / 2, math.min(ROAD_R - CAR_W / 2, px))

        frame = frame + 1
        speed = math.min(6, 2 + frame / 600)
        scroll = (scroll + speed) % 40
        score = score + 1

        if flash > 0 then flash = flash - 1 end

        -- spawn traffic
        spawn_timer = spawn_timer + 1
        if spawn_timer > math.max(20, 55 - math.floor(speed * 5)) then
            spawn_timer = 0
            spawn_car()
        end

        -- move traffic down relative to player speed
        for i = #cars, 1, -1 do
            local c = cars[i]
            c.y = c.y + speed - c.vy
            if c.y > 340 then table.remove(cars, i) goto continue end
            -- collision with player
            if flash <= 0 and math.abs(c.x - px) < CAR_W and c.y + CAR_H > PLAYER_Y
               and c.y < PLAYER_Y + CAR_H then
                table.remove(cars, i)
                lives = lives - 1
                SFX.hit()
                if lives <= 0 then
                    game_over = true
                    SFX.over()
                    save_hi()
                else
                    flash = 40
                end
            end
            ::continue::
        end
    end

    function scene:draw()
        LCD.clear()
        LCD.textCentered("RACER", 6, 1, LCD.MID)
        LCD.seg(score, 16, 16, 2, 6, LCD.DARK)
        LCD.text("HI " .. ((save.get("hi_racer") or {}).v or 0), 252, 20, 1, LCD.DARK)

        -- grass + road
        disp.fillRect(ROAD_L - 8, 36, ROAD_R - ROAD_L + 16, 280, LCD.MID)
        disp.fillRect(ROAD_L, 36, ROAD_R - ROAD_L, 280, LCD.BG)

        -- lane markings scroll
        for lane = 1, 2 do
            local x = ROAD_L + lane * 66 - 2
            for y = -40 + scroll, 316, 40 do
                disp.fillRect(x, math.floor(y), 4, 18, LCD.MID)
            end
        end

        -- traffic
        for _, c in ipairs(cars) do
            disp.fillRect(c.x - CAR_W / 2, math.floor(c.y), CAR_W, CAR_H, LCD.DARK)
            disp.fillRect(c.x - CAR_W / 2 + 4, math.floor(c.y) + 5, CAR_W - 8, 8, LCD.BG)
        end

        -- player (blink while invincible)
        if flash % 6 < 4 then
            disp.fillRect(px - CAR_W / 2, PLAYER_Y, CAR_W, CAR_H, LCD.DARK)
            disp.fillRect(px - CAR_W / 2 + 4, PLAYER_Y + 5, CAR_W - 8, 8, LCD.BG)
        end

        for i = 1, lives do disp.fillRect(252 + (i - 1) * 12, 36, 8, 8, LCD.DARK) end

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
