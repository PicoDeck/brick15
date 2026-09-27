-- frogger.lua — game 05. Expects globals: LCD, SFX, PAD, disp, picocalc.

local disp = picocalc.display
local scene_mgr = picocalc.game.scene
local save = picocalc.game.save

local FROG = 16
local START_Y = 268
local GOAL_Y = 44
local ROW_H = 28

-- river lanes (logs) then road lanes (cars): dir, speed, y, vehicles {x, w}
local LANES = {
    { dir =  1, speed = 0.8, y = 76,  w = 72, objs = { { x = 0, }, { x = 130 }, { x = 260 } } },
    { dir = -1, speed = 1.2, y = 104, w = 56, objs = { { x = 60 }, { x = 230 } } },
    { dir =  1, speed = 1.6, y = 132, w = 90, objs = { { x = 20 }, { x = 210 } } },
    { dir = -1, speed = 1.0, y = 180, w = 30, objs = { { x = 30 }, { x = 170 }, { x = 300 } } },
    { dir =  1, speed = 1.4, y = 208, w = 30, objs = { { x = 100 }, { x = 250 } } },
    { dir = -1, speed = 1.8, y = 236, w = 30, objs = { { x = 0 }, { x = 140 }, { x = 280 } } },
}
local RIVER_TOP, RIVER_BOT = 76, 132
local ROAD_TOP, ROAD_BOT = 180, 236

local function new()
    local scene = {}
    local fx, fy, lives, score, best_row, flash, game_over, won_row

    local function save_hi()
        local hi = (save.get("hi_frogger") or {}).v or 0
        if score > hi then save.set("hi_frogger", { v = score }) end
    end

    local function reset()
        fx, fy = 160, START_Y
        lives = 3
        score = 0
        best_row = START_Y
        flash = 0
        game_over = false
        for _, lane in ipairs(LANES) do
            for i, o in ipairs(lane.objs) do
                o.x = (i - 1) * (320 / #lane.objs) + lane.dir * 20
            end
        end
    end

    local function die()
        lives = lives - 1
        SFX.hit()
        if lives <= 0 then
            game_over = true
            SFX.over()
            save_hi()
        else
            flash = 30
            fx, fy = 160, START_Y
        end
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
        if p.esc then scene_mgr.switch("menu") return end

        -- move vehicles
        for _, lane in ipairs(LANES) do
            for _, o in ipairs(lane.objs) do
                o.x = o.x + lane.dir * lane.speed
                if lane.dir > 0 and o.x > 320 then o.x = -lane.w end
                if lane.dir < 0 and o.x < -lane.w then o.x = 320 end
            end
        end

        if flash > 0 then
            flash = flash - 1
            return
        end

        -- frog hop
        if p.up then fy = fy - ROW_H SFX.move() end
        if p.down then fy = fy + ROW_H SFX.move() end
        if p.left then fx = fx - ROW_H SFX.move() end
        if p.right then fx = fx + ROW_H SFX.move() end
        fx = math.max(8, math.min(304, fx))
        fy = math.max(GOAL_Y, math.min(START_Y, fy))

        -- progress score
        if fy < best_row then
            score = score + math.floor((best_row - fy) / ROW_H) * 10
            best_row = fy
        end

        -- reached the goal
        if fy <= GOAL_Y then
            score = score + 50
            SFX.levelup()
            fx, fy = 160, START_Y
            best_row = START_Y
            -- speed the world up a little
            for _, lane in ipairs(LANES) do lane.speed = lane.speed + 0.05 end
            return
        end

        local in_river = fy >= RIVER_TOP - ROW_H / 2 and fy <= RIVER_BOT + ROW_H / 2
        local on_road = fy >= ROAD_TOP - ROW_H / 2 and fy <= ROAD_BOT + ROW_H / 2

        if in_river then
            local riding = false
            for li = 1, 3 do
                local lane = LANES[li]
                if math.abs(fy - lane.y) < ROW_H / 2 then
                    for _, o in ipairs(lane.objs) do
                        if fx + FROG / 2 >= o.x and fx + FROG / 2 <= o.x + lane.w then
                            riding = true
                            fx = fx + lane.dir * lane.speed
                        end
                    end
                end
            end
            if fx < 4 or fx > 316 then riding = false end
            if not riding then die() return end
        elseif on_road then
            for li = 4, 6 do
                local lane = LANES[li]
                if math.abs(fy - lane.y) < ROW_H / 2 then
                    for _, o in ipairs(lane.objs) do
                        if fx + FROG > o.x and fx < o.x + lane.w then
                            die()
                            return
                        end
                    end
                end
            end
        end
    end

    function scene:draw()
        LCD.clear()
        LCD.textCentered("FROGGER", 6, 1, LCD.MID)
        LCD.seg(score, 16, 16, 2, 6, LCD.DARK)
        LCD.text("HI " .. ((save.get("hi_frogger") or {}).v or 0), 252, 20, 1, LCD.DARK)

        -- goal band + start band
        disp.fillRect(0, GOAL_Y - 14, 320, 14, LCD.MID)
        disp.fillRect(0, START_Y + FROG / 2, 320, 296 - START_Y - FROG / 2, LCD.MID)

        for i, lane in ipairs(LANES) do
            local is_river = i <= 3
            for _, o in ipairs(lane.objs) do
                if is_river then
                    disp.fillRect(math.floor(o.x), lane.y - 12, lane.w, 24, LCD.DARK)
                else
                    disp.fillRect(math.floor(o.x), lane.y - 10, lane.w, 20, LCD.DARK)
                    disp.fillRect(math.floor(o.x) + 4, lane.y - 4, lane.w - 8, 8, LCD.BG)
                end
            end
        end

        -- frog (blink while flashing)
        if flash % 6 < 4 then
            disp.fillRect(fx - FROG / 2, fy - FROG / 2, FROG, FROG, LCD.DARK)
            disp.fillRect(fx - FROG / 2 + 3, fy - FROG / 2 + 3, FROG - 6, FROG - 6, LCD.BG)
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
