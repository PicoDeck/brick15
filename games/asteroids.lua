-- asteroids.lua — game 09. Expects globals: LCD, SFX, PAD, disp, picocalc.

local disp = picocalc.display
local scene_mgr = picocalc.game.scene
local save = picocalc.game.save

local SHIP = 10
local function new()
    local scene = {}
    local ship, rocks, bullets, score, lives, frame, game_over, respawn_timer

    local function save_hi()
        local hi = (save.get("hi_asteroids") or {}).v or 0
        if score > hi then save.set("hi_asteroids", { v = score }) end
    end

    local function spawn_rock(x, y, size)
        local angle = math.random() * math.pi * 2
        local speed = 0.4 + math.random() * 0.6 + (3 - size) * 0.2
        rocks[#rocks + 1] = {
            x = x, y = y,
            vx = math.cos(angle) * speed,
            vy = math.sin(angle) * speed,
            size = size, -- 3 large, 2 medium, 1 small
        }
    end

    local function reset()
        ship = { x = 160, y = 160, angle = -math.pi / 2, vx = 0, vy = 0 }
        rocks = {}
        bullets = {}
        score = 0
        lives = 3
        frame = 0
        game_over = false
        respawn_timer = 0
        for i = 1, 4 do
            local x, y
                repeat
                x = math.random(40, 280)
                y = math.random(40, 280)
            until math.abs(x - 160) + math.abs(y - 160) > 90
            spawn_rock(x, y, 3)
        end
    end

    local function wrap(v)
        if v < 0 then return v + 320 end
        if v >= 320 then return v - 320 end
        return v
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

        frame = frame + 1

        -- respawn invincibility
        if respawn_timer > 0 then respawn_timer = respawn_timer - 1 end

        -- ship control
        if h.left then ship.angle = ship.angle - 0.09 end
        if h.right then ship.angle = ship.angle + 0.09 end
        if h.up then
            ship.vx = ship.vx + math.cos(ship.angle) * 0.12
            ship.vy = ship.vy + math.sin(ship.angle) * 0.12
        end
        ship.vx = ship.vx * 0.99
        ship.vy = ship.vy * 0.99
        ship.x = wrap(ship.x + ship.vx)
        ship.y = wrap(ship.y + ship.vy)

        if (p.enter or p.f1) and #bullets < 4 then
            bullets[#bullets + 1] = {
                x = ship.x + math.cos(ship.angle) * 8,
                y = ship.y + math.sin(ship.angle) * 8,
                vx = math.cos(ship.angle) * 4,
                vy = math.sin(ship.angle) * 4,
                life = 50,
            }
            SFX.rotate()
        end

        -- bullets
        for i = #bullets, 1, -1 do
            local b = bullets[i]
            b.x = wrap(b.x + b.vx)
            b.y = wrap(b.y + b.vy)
            b.life = b.life - 1
            if b.life <= 0 then
                table.remove(bullets, i)
            else
                for ri = #rocks, 1, -1 do
                    local r = rocks[ri]
                    local rad = r.size * 6
                    if (b.x - r.x) ^ 2 + (b.y - r.y) ^ 2 < rad * rad then
                        table.remove(bullets, i)
                        table.remove(rocks, ri)
                        score = score + (4 - r.size) * 20
                        SFX.score()
                        if r.size > 1 then
                            spawn_rock(r.x, r.y, r.size - 1)
                            spawn_rock(r.x, r.y, r.size - 1)
                        end
                        goto next_bullet
                    end
                end
            end
            ::next_bullet::
        end

        -- rocks
        for _, r in ipairs(rocks) do
            r.x = wrap(r.x + r.vx)
            r.y = wrap(r.y + r.vy)
            -- ship collision
            if respawn_timer <= 0 then
                local rad = r.size * 6 + SHIP / 2
                if (ship.x - r.x) ^ 2 + (ship.y - r.y) ^ 2 < rad * rad then
                    lives = lives - 1
                    SFX.hit()
                    if lives <= 0 then
                        game_over = true
                        SFX.over()
                        save_hi()
                    else
                        ship.x, ship.y = 160, 160
                        ship.vx, ship.vy = 0, 0
                        respawn_timer = 60
                    end
                    goto done
                end
            end
        end
        ::done::

        -- wave cleared
        if #rocks == 0 then
            SFX.levelup()
            for i = 1, 4 + math.floor(score / 300) do
                spawn_rock(math.random(40, 280), math.random(40, 280), 3)
            end
        end
    end

    function scene:draw()
        LCD.clear()
        LCD.textCentered("ASTEROIDS", 6, 1, LCD.MID)
        LCD.seg(score, 16, 16, 2, 6, LCD.DARK)
        LCD.text("HI " .. ((save.get("hi_asteroids") or {}).v or 0), 252, 20, 1, LCD.DARK)

        -- rocks
        for _, r in ipairs(rocks) do
            local s = r.size * 5
            disp.drawCircle(math.floor(r.x), math.floor(r.y), s, LCD.DARK)
        end

        -- bullets
        for _, b in ipairs(bullets) do disp.fillRect(b.x - 1, b.y - 1, 3, 3, LCD.DARK) end

        -- ship (triangle, blink while respawning)
        if respawn_timer % 8 < 6 then
            local c, s = math.cos(ship.angle), math.sin(ship.angle)
            local nose = { x = ship.x + c * 8, y = ship.y + s * 8 }
            local left = { x = ship.x + math.cos(ship.angle + 2.5) * 7, y = ship.y + math.sin(ship.angle + 2.5) * 7 }
            local right = { x = ship.x + math.cos(ship.angle - 2.5) * 7, y = ship.y + math.sin(ship.angle - 2.5) * 7 }
            disp.fillTriangle(math.floor(nose.x), math.floor(nose.y),
                              math.floor(left.x), math.floor(left.y),
                              math.floor(right.x), math.floor(right.y), LCD.DARK)
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
