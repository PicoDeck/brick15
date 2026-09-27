-- tank.lua — game 15 (Battle City-style). Expects globals: LCD, SFX, PAD, disp, picocalc.

local disp = picocalc.display
local scene_mgr = picocalc.game.scene
local save = picocalc.game.save

local COLS, ROWS = 13, 13
local CELL = 24
local OX, OY = 4, 40
local EMPTY, BRICK, STEEL, BASE = 0, 1, 2, 3
local DIRS = { { x = 0, y = -1 }, { x = 0, y = 1 }, { x = -1, y = 0 }, { x = 1, y = 0 } }

local function new()
    local scene = {}
    local map, player, enemies, bullets, lives, score, frame, game_over, spawn_timer

    local function save_hi()
        local hi = (save.get("hi_tank") or {}).v or 0
        if score > hi then save.set("hi_tank", { v = score }) end
    end

    local function build_map()
        map = {}
        for r = 1, ROWS do
            map[r] = {}
            for c = 1, COLS do map[r][c] = EMPTY end
        end
        -- brick clusters
        for r = 2, ROWS - 4, 2 do
            for c = 2, COLS - 2, 3 do
                if math.random() < 0.7 then
                    map[r][c] = BRICK
                    if math.random() < 0.5 then map[r][c + 1] = BRICK end
                    if math.random() < 0.4 then map[r + 1][c] = BRICK end
                end
            end
        end
        -- steel blocks
        for i = 1, 4 do
            map[math.random(3, ROWS - 6)][math.random(2, COLS - 2)] = STEEL
        end
        -- base with brick shelter
        local bc = math.floor(COLS / 2)
        map[ROWS][bc] = BASE
        map[ROWS - 1][bc] = BRICK
        map[ROWS - 1][bc - 1] = BRICK
        map[ROWS - 1][bc + 1] = BRICK
        map[ROWS][bc - 1] = BRICK
        map[ROWS][bc + 1] = BRICK
    end

    local function reset()
        build_map()
        player = { x = OX + 5 * CELL, y = OY + 12 * CELL, dir = 1, cooldown = 0 }
        enemies = {}
        bullets = {}
        lives = 3
        score = 0
        frame = 0
        game_over = false
        spawn_timer = 0
    end

    local function cell_at(x, y)
        local c = math.floor((x - OX) / CELL) + 1
        local r = math.floor((y - OY) / CELL) + 1
        if c < 1 or c > COLS or r < 1 or r > ROWS then return STEEL end
        return map[r][c]
    end

    local function tank_blocked(x, y, w, h)
        -- check the four corners against the map
        for _, pt in ipairs({ { x, y }, { x + w, y }, { x, y + h }, { x + w, y + h } }) do
            local cell = cell_at(pt[1], pt[2])
            if cell ~= EMPTY then return true end
        end
        -- base counts as blocked
        return false
    end

    local function spawn_enemy()
        if #enemies >= 4 then return end
        local spots = { { 2, 2 }, { 7, 2 }, { 12, 2 } }
        local s = spots[math.random(#spots)]
        local x, y = OX + (s[1] - 1) * CELL, OY + (s[2] - 1) * CELL
        for _, e in ipairs(enemies) do
            if math.abs(e.x - x) < CELL and math.abs(e.y - y) < CELL then return end
        end
        enemies[#enemies + 1] = { x = x, y = y, dir = math.random(4), cooldown = 0, move_timer = 0 }
    end

    local function fire_shooter(s)
        if s.cooldown and s.cooldown > 0 then return end
        local d = DIRS[s.dir]
        bullets[#bullets + 1] = {
            x = s.x + CELL / 2 + d.x * CELL / 2,
            y = s.y + CELL / 2 + d.y * CELL / 2,
            dx = d.x, dy = d.y, friendly = s == player,
        }
        s.cooldown = 20
        SFX.rotate()
    end

    local function bullet_hit(b)
        local cell = cell_at(b.x, b.y)
        if cell == BRICK then
            local c = math.floor((b.x - OX) / CELL) + 1
            local r = math.floor((b.y - OY) / CELL) + 1
            map[r][c] = EMPTY
            return true
        elseif cell == STEEL then
            return true
        elseif cell == BASE then
            game_over = true
            SFX.over()
            save_hi()
            return true
        end
        -- tank hits
        if b.friendly then
            for i = #enemies, 1, -1 do
                local e = enemies[i]
                if b.x >= e.x and b.x <= e.x + CELL and b.y >= e.y and b.y <= e.y + CELL then
                    table.remove(enemies, i)
                    score = score + 100
                    SFX.score()
                    return true
                end
            end
        else
            if b.x >= player.x and b.x <= player.x + CELL and b.y >= player.y and b.y <= player.y + CELL then
                lives = lives - 1
                SFX.hit()
                if lives <= 0 then
                    game_over = true
                    SFX.over()
                    save_hi()
                else
                    player.x = OX + 5 * CELL
                    player.y = OY + 12 * CELL
                end
                return true
            end
        end
        return false
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

        -- player
        if player.cooldown > 0 then player.cooldown = player.cooldown - 1 end
        local moved = false
        local speed = 1.6
        if h.up and player.dir ~= 1 then player.dir = 1 moved = true end
        if h.down and player.dir ~= 2 then player.dir = 2 moved = true end
        if h.left and player.dir ~= 3 then player.dir = 3 moved = true end
        if h.right and player.dir ~= 4 then player.dir = 4 moved = true end
        if not (h.up or h.down or h.left or h.right) then moved = false end
        if moved or h.up or h.down or h.left or h.right then
            local d = DIRS[player.dir]
            local nx = player.x + d.x * speed
            local ny = player.y + d.y * speed
            if nx >= OX and nx + CELL <= OX + COLS * CELL
               and ny >= OY and ny + CELL <= OY + ROWS * CELL
               and not tank_blocked(nx, ny, CELL - 2, CELL - 2) then
                player.x = nx
                player.y = ny
            end
        end
        if (p.enter or p.f1) and player.cooldown <= 0 then
            fire_shooter(player)
        end

        -- enemies
        spawn_timer = spawn_timer + 1
        if spawn_timer > 90 then
            spawn_timer = 0
            spawn_enemy()
        end
        for _, e in ipairs(enemies) do
            if e.cooldown > 0 then e.cooldown = e.cooldown - 1 end
            e.move_timer = e.move_timer + 1
            if e.move_timer > 40 then
                e.move_timer = 0
                e.dir = math.random(4)
            end
            local d = DIRS[e.dir]
            local nx = e.x + d.x * 1.1
            local ny = e.y + d.y * 1.1
            if nx >= OX and nx + CELL <= OX + COLS * CELL
               and ny >= OY and ny + CELL <= OY + ROWS * CELL
               and not tank_blocked(nx, ny, CELL - 2, CELL - 2) then
                e.x = nx
                e.y = ny
            else
                e.dir = math.random(4)
            end
            if e.cooldown <= 0 and math.random() < 0.03 then
                fire_shooter(e)
            end
        end

        -- bullets
        for i = #bullets, 1, -1 do
            local b = bullets[i]
            b.x = b.x + b.dx * 4
            b.y = b.y + b.dy * 4
            if b.x < OX or b.x > OX + COLS * CELL or b.y < OY or b.y > OY + ROWS * CELL then
                table.remove(bullets, i)
            elseif bullet_hit(b) then
                table.remove(bullets, i)
            end
        end
    end

    function scene:draw()
        LCD.clear()
        LCD.textCentered("TANK", 6, 1, LCD.MID)
        LCD.seg(score, 16, 16, 2, 6, LCD.DARK)
        LCD.text("HI " .. ((save.get("hi_tank") or {}).v or 0), 252, 20, 1, LCD.DARK)

        disp.drawRect(OX - 2, OY - 2, COLS * CELL + 4, ROWS * CELL + 4, LCD.MID)

        for r = 1, ROWS do
            for c = 1, COLS do
                local cell = map[r][c]
                if cell ~= EMPTY then
                    local x, y = OX + (c - 1) * CELL, OY + (r - 1) * CELL
                    if cell == BRICK then
                        disp.fillRect(x, y, CELL, CELL, LCD.DARK)
                        disp.fillRect(x + 2, y + 2, CELL - 4, CELL - 4, LCD.MID)
                    elseif cell == STEEL then
                        disp.fillRect(x, y, CELL, CELL, LCD.MID)
                        disp.fillRect(x + 4, y + 4, CELL - 8, CELL - 8, LCD.DARK)
                    elseif cell == BASE then
                        disp.fillRect(x + 4, y + 4, CELL - 8, CELL - 8, LCD.DARK)
                    end
                end
            end
        end

        -- player tank
        disp.fillRect(player.x + 2, player.y + 2, CELL - 4, CELL - 4, LCD.DARK)
        local pd = DIRS[player.dir]
        disp.fillRect(player.x + CELL / 2 + pd.x * 6 - 2, player.y + CELL / 2 + pd.y * 6 - 2, 4, 4, LCD.DARK)

        -- enemy tanks
        for _, e in ipairs(enemies) do
            disp.fillRect(e.x + 2, e.y + 2, CELL - 4, CELL - 4, LCD.MID)
            local ed = DIRS[e.dir]
            disp.fillRect(e.x + CELL / 2 + ed.x * 6 - 2, e.y + CELL / 2 + ed.y * 6 - 2, 4, 4, LCD.MID)
        end

        -- bullets
        for _, b in ipairs(bullets) do disp.fillRect(b.x - 2, b.y - 2, 4, 4, LCD.DARK) end

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
