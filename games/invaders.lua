-- invaders.lua — game 04. Expects globals: LCD, SFX, PAD, disp, picocalc.

local disp = picocalc.display
local scene_mgr = picocalc.game.scene
local save = picocalc.game.save

local GUN_Y = 296
local ALIEN_COLS, ALIEN_ROWS = 8, 5
local CELL_W, CELL_H = 16, 12
local GAP_X, GAP_Y = 8, 8
local FIELD_OX, FIELD_OY = 56, 48

local function new()
    local scene = {}
    local gun_x, aliens, off_x, off_y, alien_dir, alien_step
    local bullets, ebullets, score, lives, wave, frame, game_over

    local function save_hi()
        local hi = (save.get("hi_invaders") or {}).v or 0
        if score > hi then save.set("hi_invaders", { v = score }) end
    end

    local function alien_pos(r, c)
        return FIELD_OX + (c - 1) * (CELL_W + GAP_X) + off_x,
               FIELD_OY + r * (CELL_H + GAP_Y) - CELL_H + off_y
    end

    local function spawn_wave()
        aliens = {}
        for r = 1, ALIEN_ROWS do
            aliens[r] = {}
            for c = 1, ALIEN_COLS do aliens[r][c] = 1 end
        end
        off_x, off_y = 0, 0
        alien_dir = 1
        alien_step = 0
    end

    local function reset()
        gun_x = 160
        bullets = {}
        ebullets = {}
        score = 0
        lives = 3
        wave = 1
        frame = 0
        game_over = false
        spawn_wave()
    end

    local function alive_count()
        local n = 0
        for r = 1, ALIEN_ROWS do
            for c = 1, ALIEN_COLS do
                if aliens[r][c] > 0 then n = n + 1 end
            end
        end
        return n
    end

    local function any_alive()
        for r = 1, ALIEN_ROWS do
            for c = 1, ALIEN_COLS do
                if aliens[r][c] > 0 then return true end
            end
        end
        return false
    end

    local function fire()
        if #bullets < 2 then
            bullets[#bullets + 1] = { x = gun_x, y = GUN_Y - 6 }
            SFX.rotate()
        end
    end

    local function alien_fire()
        local shooters = {}
        for c = 1, ALIEN_COLS do
            for r = ALIEN_ROWS, 1, -1 do
                if aliens[r][c] > 0 then
                    shooters[#shooters + 1] = { r = r, c = c }
                    break
                end
            end
        end
        if #shooters > 0 and #ebullets < 3 then
            local s = shooters[math.random(#shooters)]
            local x, y = alien_pos(s.r, s.c)
            ebullets[#ebullets + 1] = { x = x + CELL_W / 2, y = y + CELL_H }
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
        local h = PAD.held()
        if p.esc then scene_mgr.switch("menu") return end

        if h.left then gun_x = gun_x - 3 end
        if h.right then gun_x = gun_x + 3 end
        gun_x = math.max(8, math.min(312, gun_x))
        if p.up or p.enter or p.f1 then fire() end

        frame = frame + 1

        -- alien march: faster as their numbers thin
        local total = ALIEN_COLS * ALIEN_ROWS
        local interval = math.max(2, math.floor((alive_count() / total) * 26) - wave)
        alien_step = alien_step + 1
        if alien_step >= interval then
            alien_step = 0
            local at_edge = false
            for c = 1, ALIEN_COLS do
                for r = 1, ALIEN_ROWS do
                    if aliens[r][c] > 0 then
                        local x = FIELD_OX + (c - 1) * (CELL_W + GAP_X) + off_x + alien_dir * 6
                        if x < 4 or x + CELL_W > 316 then at_edge = true end
                    end
                end
            end
            if at_edge then
                alien_dir = -alien_dir
                off_y = off_y + 8
                SFX.hit()
            else
                off_x = off_x + alien_dir * 6
                SFX.move()
            end
        end

        -- player bullets
        for i = #bullets, 1, -1 do
            local b = bullets[i]
            b.y = b.y - 4
            if b.y < 36 then
                table.remove(bullets, i)
            else
                for r = 1, ALIEN_ROWS do
                    for c = 1, ALIEN_COLS do
                        if aliens[r][c] > 0 then
                            local ax, ay = alien_pos(r, c)
                            if b.x >= ax and b.x <= ax + CELL_W and b.y >= ay and b.y <= ay + CELL_H then
                                aliens[r][c] = 0
                                score = score + (ALIEN_ROWS - r + 1) * 10
                                table.remove(bullets, i)
                                SFX.score()
                                goto next_bullet
                            end
                        end
                    end
                end
            end
            ::next_bullet::
        end

        -- enemy bullets
        for i = #ebullets, 1, -1 do
            local b = ebullets[i]
            b.y = b.y + 2.5
            if b.y > 316 then
                table.remove(ebullets, i)
            elseif b.x >= gun_x - 8 and b.x <= gun_x + 8 and b.y >= GUN_Y and b.y <= GUN_Y + 8 then
                table.remove(ebullets, i)
                lives = lives - 1
                SFX.hit()
                if lives <= 0 then
                    game_over = true
                    SFX.over()
                    save_hi()
                end
            end
        end

        -- aliens land on the gun line
        for c = 1, ALIEN_COLS do
            for r = ALIEN_ROWS, 1, -1 do
                if aliens[r][c] > 0 then
                    local _, ay = alien_pos(r, c)
                    if ay + CELL_H >= GUN_Y - 4 then
                        game_over = true
                        SFX.over()
                        save_hi()
                    end
                    break
                end
            end
        end

        -- alien fire
        if frame % math.max(10, 40 - wave * 3) == 0 then alien_fire() end

        -- wave cleared
        if not any_alive() then
            wave = wave + 1
            SFX.levelup()
            spawn_wave()
        end
    end

    function scene:draw()
        LCD.clear()
        LCD.textCentered("INVADERS", 6, 1, LCD.MID)
        LCD.seg(score, 16, 16, 2, 6, LCD.DARK)
        LCD.text("HI " .. ((save.get("hi_invaders") or {}).v or 0), 252, 20, 1, LCD.DARK)

        -- gun
        disp.fillRect(gun_x - 8, GUN_Y, 16, 8, LCD.DARK)
        disp.fillRect(gun_x - 2, GUN_Y - 4, 4, 4, LCD.DARK)

        -- aliens
        for r = 1, ALIEN_ROWS do
            for c = 1, ALIEN_COLS do
                if aliens[r][c] > 0 then
                    local x, y = alien_pos(r, c)
                    disp.fillRect(x, y, CELL_W, 4, LCD.DARK)
                    disp.fillRect(x + 2, y + 4, CELL_W - 4, 4, LCD.DARK)
                    disp.fillRect(x - 2, y + 6, 4, 4, LCD.DARK)
                    disp.fillRect(x + CELL_W - 2, y + 6, 4, 4, LCD.DARK)
                end
            end
        end

        for _, b in ipairs(bullets) do disp.fillRect(b.x - 1, b.y, 2, 6, LCD.DARK) end
        for _, b in ipairs(ebullets) do disp.fillRect(b.x - 1, b.y, 2, 6, LCD.MID) end

        for i = 1, lives do disp.fillRect(252 + (i - 1) * 12, 34, 8, 6, LCD.DARK) end

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
