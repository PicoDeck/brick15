-- missile.lua — game 14 (Missile Command). Expects globals: LCD, SFX, PAD, disp, picocalc.

local disp = picocalc.display
local scene_mgr = picocalc.game.scene
local save = picocalc.game.save

local GROUND = 300
local CITY_X = { 44, 84, 124, 196, 236, 276 }
local CITY_W = 14
local BATTERY_X = { 20, 160, 300 }
local AMMO_PER = 10

local function new()
    local scene = {}
    local cross, cities, batteries, pmissiles, emissiles, explosions
    local score, level, frame, game_over, spawn_timer

    local function save_hi()
        local hi = (save.get("hi_missile") or {}).v or 0
        if score > hi then save.set("hi_missile", { v = score }) end
    end

    local function reset()
        cross = { x = 160, y = 160 }
        cities = {}
        for _, x in ipairs(CITY_X) do cities[#cities + 1] = { x = x, alive = true } end
        batteries = {}
        for _, x in ipairs(BATTERY_X) do batteries[#batteries + 1] = { x = x, ammo = AMMO_PER } end
        pmissiles = {}
        emissiles = {}
        explosions = {}
        score = 0
        level = 1
        frame = 0
        game_over = false
        spawn_timer = 0
    end

    local function cities_alive()
        local n = 0
        for _, c in ipairs(cities) do
            if c.alive then n = n + 1 end
        end
        return n
    end

    local function fire()
        -- nearest battery with ammo
        local best, best_d = nil, 9999
        for _, b in ipairs(batteries) do
            if b.ammo > 0 then
                local d = math.abs(b.x - cross.x)
                if d < best_d then best, best_d = b, d end
            end
        end
        if not best then return end
        best.ammo = best.ammo - 1
        pmissiles[#pmissiles + 1] = { sx = best.x, sy = GROUND - 8, tx = cross.x, ty = cross.y, x = best.x, y = GROUND - 8 }
        SFX.rotate()
    end

    local function spawn_enemy()
        local target_kind = math.random(2) == 1 and "city" or "battery"
        local tx
        if target_kind == "city" then
            local alive_cities = {}
            for _, c in ipairs(cities) do
                if c.alive then alive_cities[#alive_cities + 1] = c end
            end
            if #alive_cities == 0 then return end
            tx = alive_cities[math.random(#alive_cities)].x + CITY_W / 2
        else
            tx = BATTERY_X[math.random(#BATTERY_X)]
        end
        emissiles[#emissiles + 1] = {
            sx = math.random(20, 300), sy = 36,
            x = 0, y = 36, tx = tx, ty = GROUND - 4,
        }
        local m = emissiles[#emissiles]
        local dx, dy = m.tx - m.sx, m.ty - m.sy
        local dist = math.sqrt(dx * dx + dy * dy)
        local speed = 0.5 + level * 0.12
        m.vx, m.vy = dx / dist * speed, dy / dist * speed
    end

    local function explode(x, y)
        explosions[#explosions + 1] = { x = x, y = y, r = 2, max = 26, growing = true }
        SFX.hit()
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

        -- crosshair
        if h.left then cross.x = cross.x - 3 end
        if h.right then cross.x = cross.x + 3 end
        if h.up then cross.y = cross.y - 3 end
        if h.down then cross.y = cross.y + 3 end
        cross.x = math.max(4, math.min(316, cross.x))
        cross.y = math.max(40, math.min(GROUND - 8, cross.y))
        if p.enter or p.f1 then fire() end

        frame = frame + 1

        -- spawn enemies
        spawn_timer = spawn_timer + 1
        if spawn_timer > math.max(15, 50 - level * 4) then
            spawn_timer = 0
            if #emissiles < 8 then spawn_enemy() end
        end

        -- player missiles
        for i = #pmissiles, 1, -1 do
            local m = pmissiles[i]
            local dx, dy = m.tx - m.x, m.ty - m.y
            local dist = math.sqrt(dx * dx + dy * dy)
            if dist < 6 then
                table.remove(pmissiles, i)
                explode(m.tx, m.ty)
            else
                m.x = m.x + dx / dist * 5
                m.y = m.y + dy / dist * 5
            end
        end

        -- enemy missiles
        for i = #emissiles, 1, -1 do
            local m = emissiles[i]
            m.x = m.x + m.vx
            m.y = m.y + m.vy
            if m.y >= m.ty then
                table.remove(emissiles, i)
                explode(m.x, m.ty)
                -- destroy a city?
                for _, c in ipairs(cities) do
                    if c.alive and math.abs(m.tx - (c.x + CITY_W / 2)) < CITY_W then
                        c.alive = false
                        SFX.over()
                    end
                end
                if cities_alive() == 0 then
                    game_over = true
                    SFX.over()
                    save_hi()
                end
            end
        end

        -- explosions
        for i = #explosions, 1, -1 do
            local e = explosions[i]
            if e.growing then
                e.r = e.r + 1.5
                if e.r >= e.max then e.growing = false end
            else
                e.r = e.r - 1.5
            end
            if e.r <= 0 then
                table.remove(explosions, i)
            else
                -- chain-destroy enemy missiles
                for j = #emissiles, 1, -1 do
                    local m = emissiles[j]
                    if (m.x - e.x) ^ 2 + (m.y - e.y) ^ 2 < e.r * e.r then
                        table.remove(emissiles, j)
                        score = score + 25
                        SFX.score()
                    end
                end
            end
        end

        -- level up when the sky is clear
        if #emissiles == 0 and #pmissiles == 0 and frame > 60 then
            level = level + 1
            SFX.levelup()
            for _, b in ipairs(batteries) do b.ammo = AMMO_PER end
            frame = 0
        end
    end

    function scene:draw()
        LCD.clear()
        LCD.textCentered("MISSILE CMD", 6, 1, LCD.MID)
        LCD.seg(score, 16, 16, 2, 6, LCD.DARK)
        LCD.text("HI " .. ((save.get("hi_missile") or {}).v or 0), 252, 20, 1, LCD.DARK)
        LCD.text("LV " .. level, 252, 34, 1, LCD.MID)

        -- ground
        disp.fillRect(0, GROUND, 320, 20, LCD.MID)

        -- cities
        for _, c in ipairs(cities) do
            if c.alive then
                disp.fillRect(c.x, GROUND - 10, CITY_W, 10, LCD.DARK)
                disp.fillRect(c.x + 3, GROUND - 14, 3, 4, LCD.DARK)
                disp.fillRect(c.x + 8, GROUND - 14, 3, 4, LCD.DARK)
            else
                disp.fillRect(c.x, GROUND - 4, CITY_W, 4, LCD.MID)
            end
        end

        -- batteries + ammo
        for _, b in ipairs(batteries) do
            disp.fillRect(b.x - 8, GROUND - 6, 16, 6, LCD.DARK)
            for i = 1, b.ammo do
                disp.fillRect(b.x - 8 + (i - 1) * 2, GROUND - 10, 1, 4, LCD.DARK)
            end
        end

        -- enemy missiles + trails
        for _, m in ipairs(emissiles) do
            disp.drawLine(math.floor(m.sx), math.floor(m.sy), math.floor(m.x), math.floor(m.y), LCD.MID)
            disp.fillRect(m.x - 1, m.y - 1, 3, 3, LCD.DARK)
        end

        -- player missiles + trails
        for _, m in ipairs(pmissiles) do
            disp.drawLine(math.floor(m.sx), math.floor(m.sy), math.floor(m.x), math.floor(m.y), LCD.DARK)
        end

        -- explosions
        for _, e in ipairs(explosions) do
            disp.drawCircle(math.floor(e.x), math.floor(e.y), math.floor(e.r), LCD.DARK)
        end

        -- crosshair
        disp.drawLine(cross.x - 6, cross.y, cross.x + 6, cross.y, LCD.DARK)
        disp.drawLine(cross.x, cross.y - 6, cross.x, cross.y + 6, LCD.DARK)

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
