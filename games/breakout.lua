-- breakout.lua — game 03. Expects globals: LCD, SFX, PAD, disp, picocalc.

local disp = picocalc.display
local scene_mgr = picocalc.game.scene
local save = picocalc.game.save

local PADDLE_W, PADDLE_H = 44, 8
local PADDLE_Y = 288
local BALL = 6
local COLS, ROWS = 10, 5
local BW, BH = 26, 10
local OX, OY = 20, 48

local function new()
    local scene = {}
    local paddle_x, ball, ball_v, bricks, lives, score, level, state
    -- state: "serve" | "play" | "over" | "win"

    local function save_hi()
        local hi = (save.get("hi_breakout") or {}).v or 0
        if score > hi then save.set("hi_breakout", { v = score }) end
    end

    local function build_bricks()
        bricks = {}
        for r = 1, ROWS do
            bricks[r] = {}
            for c = 1, COLS do bricks[r][c] = ROWS - r + 1 end
        end
    end

    local function reset_ball()
        ball = { x = paddle_x + PADDLE_W / 2 - BALL / 2, y = PADDLE_Y - BALL - 2 }
        local angle = math.random() * 0.8 - 0.4
        local speed = 2.2 + level * 0.35
        ball_v = { x = math.sin(angle) * speed, y = -math.cos(angle) * speed }
        state = "serve"
    end

    local function reset()
        paddle_x = (320 - PADDLE_W) / 2
        lives = 3
        score = 0
        level = 1
        build_bricks()
        reset_ball()
    end

    local function bricks_left()
        local n = 0
        for r = 1, ROWS do
            for c = 1, COLS do
                if bricks[r][c] > 0 then n = n + 1 end
            end
        end
        return n
    end

    local function hit_brick()
        for r = 1, ROWS do
            for c = 1, COLS do
                if bricks[r][c] > 0 then
                    local bx, by = OX + (c - 1) * (BW + 2), OY + (r - 1) * (BH + 4)
                    if ball.x + BALL >= bx and ball.x <= bx + BW
                       and ball.y + BALL >= by and ball.y <= by + BH then
                        local val = bricks[r][c]
                        bricks[r][c] = 0
                        score = score + val * 10
                        -- bounce off nearest face
                        local overlap_l = ball.x + BALL - bx
                        local overlap_r = bx + BW - ball.x
                        local overlap_t = ball.y + BALL - by
                        local overlap_b = by + BH - ball.y
                        local min_h = math.min(overlap_l, overlap_r)
                        local min_v = math.min(overlap_t, overlap_b)
                        if min_h < min_v then ball_v.x = -ball_v.x else ball_v.y = -ball_v.y end
                        SFX.score()
                        return true
                    end
                end
            end
        end
        return false
    end

    function scene:enter()
        reset()
    end

    function scene:update()
        local p = PAD.pressed()
        local h = PAD.held()

        if p.esc then scene_mgr.switch("menu") return end

        if state == "over" or state == "win" then
            if p.enter then
                SFX.start()
                reset()
            end
            return
        end

        -- paddle
        if h.left then paddle_x = paddle_x - 4 end
        if h.right then paddle_x = paddle_x + 4 end
        paddle_x = math.max(4, math.min(320 - PADDLE_W - 4, paddle_x))

        if state == "serve" then
            ball.x = paddle_x + PADDLE_W / 2 - BALL / 2
            if p.enter or p.up then
                SFX.rotate()
                state = "play"
            end
            return
        end

        -- ball
        ball.x = ball.x + ball_v.x
        ball.y = ball.y + ball_v.y

        if ball.x < 4 then ball.x = 4 ball_v.x = -ball_v.x SFX.move() end
        if ball.x > 320 - 4 - BALL then ball.x = 320 - 4 - BALL ball_v.x = -ball_v.x SFX.move() end
        if ball.y < 34 then ball.y = 34 ball_v.y = -ball_v.y SFX.move() end

        -- paddle bounce
        if ball_v.y > 0 and ball.y + BALL >= PADDLE_Y and ball.y + BALL <= PADDLE_Y + PADDLE_H + 2
           and ball.x + BALL >= paddle_x and ball.x <= paddle_x + PADDLE_W then
            local hit = (ball.x + BALL / 2 - paddle_x) / PADDLE_W  -- 0..1
            local angle = (hit - 0.5) * 1.9
            local speed = math.min(5, math.sqrt(ball_v.x * ball_v.x + ball_v.y * ball_v.y) + 0.03)
            ball_v.x = math.sin(angle) * speed
            ball_v.y = -math.cos(angle) * speed
            ball.y = PADDLE_Y - BALL - 1
            SFX.rotate()
        end

        -- brick bounce
        if hit_brick() then end

        -- lost ball
        if ball.y > 320 then
            lives = lives - 1
            if lives <= 0 then
                state = "over"
                SFX.over()
                save_hi()
            else
                SFX.hit()
                reset_ball()
            end
        end

        -- level cleared
        if bricks_left() == 0 then
            level = level + 1
            SFX.levelup()
            build_bricks()
            reset_ball()
        end
    end

    function scene:draw()
        LCD.clear()
        LCD.textCentered("BREAKOUT", 6, 1, LCD.MID)
        LCD.seg(score, 16, 16, 2, 6, LCD.DARK)
        LCD.text("LV", 16, 34, 1, LCD.MID)
        LCD.seg(level, 40, 32, 1, 2, LCD.DARK)

        -- lives
        for i = 1, lives do
            disp.fillRect(252 + (i - 1) * 12, 18, 8, 8, LCD.DARK)
        end
        LCD.text("HI " .. ((save.get("hi_breakout") or {}).v or 0), 252, 34, 1, LCD.DARK)

        disp.drawRect(2, 36, 316, 268, LCD.MID)

        for r = 1, ROWS do
            for c = 1, COLS do
                if bricks[r][c] > 0 then
                    local bx, by = OX + (c - 1) * (BW + 2), OY + (r - 1) * (BH + 4)
                    disp.fillRect(bx, by, BW, BH, LCD.DARK)
                end
            end
        end

        disp.fillRect(math.floor(paddle_x), PADDLE_Y, PADDLE_W, PADDLE_H, LCD.DARK)
        disp.fillRect(math.floor(ball.x), math.floor(ball.y), BALL, BALL, LCD.DARK)

        if state == "serve" then
            LCD.textCentered("ENTER SERVE", 200, 1, LCD.MID)
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
