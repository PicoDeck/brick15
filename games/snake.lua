-- snake.lua — game 02. Expects globals: LCD, SFX, PAD, disp, picocalc.

local disp = picocalc.display
local scene_mgr = picocalc.game.scene
local save = picocalc.game.save

local COLS, ROWS = 20, 20
local CELL = 14
local OX, OY = 20, 40

local function new()
    local scene = {}
    local snake, dir, food, score, alive, frame, step_interval

    local function save_hi()
        local hi = (save.get("hi_snake") or {}).v or 0
        if score > hi then save.set("hi_snake", { v = score }) end
    end

    local function place_food()
        while true do
            local fx, fy = math.random(1, COLS), math.random(1, ROWS)
            local ok = true
            for _, s in ipairs(snake) do
                if s.x == fx and s.y == fy then ok = false break end
            end
            if ok then food = { x = fx, y = fy } return end
        end
    end

    local function reset()
        snake = { { x = 10, y = 10 }, { x = 9, y = 10 }, { x = 8, y = 10 } }
        dir = { x = 1, y = 0 }
        score = 0
        alive = true
        frame = 0
        step_interval = 8
        place_food()
    end

    function scene:enter()
        reset()
    end

    function scene:update()
        if not alive then
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

        if p.up and dir.y == 0 then dir = { x = 0, y = -1 } SFX.move()
        elseif p.down and dir.y == 0 then dir = { x = 0, y = 1 } SFX.move()
        elseif p.left and dir.x == 0 then dir = { x = -1, y = 0 } SFX.move()
        elseif p.right and dir.x == 0 then dir = { x = 1, y = 0 } SFX.move()
        end

        frame = frame + 1
        if frame % step_interval ~= 0 then return end

        local head = snake[1]
        local nx, ny = head.x + dir.x, head.y + dir.y

        if nx < 1 or nx > COLS or ny < 1 or ny > ROWS then
            alive = false
            SFX.over()
            save_hi()
            return
        end
        for _, s in ipairs(snake) do
            if s.x == nx and s.y == ny then
                alive = false
                SFX.over()
                save_hi()
                return
            end
        end

        table.insert(snake, 1, { x = nx, y = ny })
        if nx == food.x and ny == food.y then
            score = score + 10
            step_interval = math.max(3, step_interval - (score % 50 == 0 and 1 or 0))
            SFX.eat()
            place_food()
        else
            table.remove(snake)
        end
    end

    function scene:draw()
        LCD.clear()
        LCD.textCentered("SNAKE", 6, 1, LCD.MID)
        LCD.seg(score, 16, 16, 2, 6, LCD.DARK)
        LCD.text("HI " .. ((save.get("hi_snake") or {}).v or 0), 252, 20, 1, LCD.DARK)

        disp.drawRect(OX - 2, OY - 2, COLS * CELL + 4, ROWS * CELL + 4, LCD.MID)

        -- food (blinks)
        if frame % 20 < 14 then
            disp.fillRect(OX + (food.x - 1) * CELL + 3, OY + (food.y - 1) * CELL + 3, 8, 8, LCD.DARK)
        end

        for i, s in ipairs(snake) do
            local c = (i == 1) and LCD.DARK or LCD.MID
            disp.fillRect(OX + (s.x - 1) * CELL + 1, OY + (s.y - 1) * CELL + 1, CELL - 2, CELL - 2, c)
        end

        LCD.text("ARROWS STEER", 252, 40, 1, LCD.MID)

        if not alive then
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
