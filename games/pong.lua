-- pong.lua — game 07. Expects globals: LCD, SFX, PAD, disp, picocalc.

local disp = picocalc.display
local scene_mgr = picocalc.game.scene
local save = picocalc.game.save

local PADDLE_W, PADDLE_H = 6, 40
local PLAYER_X, AI_X = 16, 298
local BALL = 6
local WIN_SCORE = 7

local function new()
    local scene = {}
    local py, ay, ball, ball_v, pscore, aiseore, state, winner
    -- state: "serve" | "play" | "over"

    local function save_hi()
        local hi = (save.get("hi_pong") or {}).v or 0
        if pscore > hi then save.set("hi_pong", { v = pscore }) end
    end

    local function serve()
        ball = { x = 157, y = 160 }
        local angle = math.random() * 0.9 - 0.45
        local dir = math.random(2) == 1 and 1 or -1
        ball_v = { x = math.cos(angle) * 2.2 * dir, y = math.sin(angle) * 2.2 }
        state = "serve"
    end

    local function reset()
        py = 140
        ay = 140
        pscore = 0
        aiseore = 0
        winner = nil
        serve()
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
        local h = PAD.held()
        if p.esc then scene_mgr.switch("menu") return end

        -- player paddle
        if h.up then py = py - 4 end
        if h.down then py = py + 4 end
        py = math.max(40, math.min(272, py))

        -- AI paddle tracks the ball
        local target = ball.y - PADDLE_H / 2
        if target < ay - 2 then ay = ay - 2.6 end
        if target > ay + 2 then ay = ay + 2.6 end
        ay = math.max(40, math.min(272, ay))

        if state == "serve" then
            if p.enter or p.up then
                SFX.rotate()
                state = "play"
            end
            return
        end

        ball.x = ball.x + ball_v.x
        ball.y = ball.y + ball_v.y

        if ball.y < 40 then ball.y = 40 ball_v.y = -ball_v.y SFX.move() end
        if ball.y > 314 then ball.y = 314 ball_v.y = -ball_v.y SFX.move() end

        -- paddle bounces
        if ball_v.x < 0 and ball.x <= PLAYER_X + PADDLE_W and ball.x >= PLAYER_X - BALL
           and ball.y + BALL >= py and ball.y <= py + PADDLE_H then
            local hit = (ball.y + BALL / 2 - py) / PADDLE_H
            local angle = (hit - 0.5) * 1.6
            local speed = math.min(5.5, math.sqrt(ball_v.x ^ 2 + ball_v.y ^ 2) + 0.15)
            ball_v.x = math.cos(angle) * speed
            ball_v.y = math.sin(angle) * speed
            ball.x = PLAYER_X + PADDLE_W + 1
            SFX.rotate()
        end
        if ball_v.x > 0 and ball.x + BALL >= AI_X and ball.x <= AI_X + PADDLE_W + BALL
           and ball.y + BALL >= ay and ball.y <= ay + PADDLE_H then
            local hit = (ball.y + BALL / 2 - ay) / PADDLE_H
            local angle = (hit - 0.5) * 1.6
            local speed = math.min(5.5, math.sqrt(ball_v.x ^ 2 + ball_v.y ^ 2) + 0.15)
            ball_v.x = -math.cos(angle) * speed
            ball_v.y = math.sin(angle) * speed
            ball.x = AI_X - BALL - 1
            SFX.rotate()
        end

        -- scoring
        if ball.x < 0 then
            aiseore = aiseore + 1
            SFX.hit()
            if aiseore >= WIN_SCORE then
                winner = "AI"
                state = "over"
                SFX.over()
                save_hi()
            else
                serve()
            end
        elseif ball.x > 320 then
            pscore = pscore + 1
            SFX.score()
            if pscore >= WIN_SCORE then
                winner = "YOU"
                state = "over"
                SFX.levelup()
                save_hi()
            else
                serve()
            end
        end
    end

    function scene:draw()
        LCD.clear()
        LCD.textCentered("PONG", 6, 1, LCD.MID)

        -- scores
        LCD.seg(pscore, 120, 14, 3, 1, LCD.DARK)
        LCD.seg(aiseore, 184, 14, 3, 1, LCD.DARK)

        -- center net
        for y = 38, 316, 16 do
            disp.fillRect(158, y, 4, 8, LCD.MID)
        end

        disp.fillRect(PLAYER_X, math.floor(py), PADDLE_W, PADDLE_H, LCD.DARK)
        disp.fillRect(AI_X, math.floor(ay), PADDLE_W, PADDLE_H, LCD.DARK)
        disp.fillRect(math.floor(ball.x), math.floor(ball.y), BALL, BALL, LCD.DARK)

        if state == "serve" then
            LCD.textCentered("ENTER SERVE", 200, 1, LCD.MID)
        elseif state == "over" then
            disp.fillRect(40, 120, 240, 80, LCD.DARK)
            disp.drawRect(40, 120, 240, 80, LCD.BG)
            LCD.textCentered(winner .. " WIN", 132, 2, LCD.BG)
            LCD.textCentered("YOU " .. pscore .. "  AI " .. aiseore, 152, 1, LCD.BG)
            LCD.textCentered("ENTER AGAIN", 172, 1, LCD.BG)
            LCD.textCentered("ESC MENU", 184, 1, LCD.BG)
        end

        disp.flush()
    end

    function scene:exit() end

    return scene
end

return { new = new }
