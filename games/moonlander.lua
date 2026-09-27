-- moonlander.lua — game 13. Expects globals: LCD, SFX, PAD, disp, picocalc.

local disp = picocalc.display
local scene_mgr = picocalc.game.scene
local save = picocalc.game.save

local GROUND = 296
local SHIP = 10

local function new()
    local scene = {}
    local ship, pads, fuel, score, ships, state, land_timer
    -- state: "fly" | "landed" | "over"

    local function save_hi()
        local hi = (save.get("hi_moonlander") or {}).v or 0
        if score > hi then save.set("hi_moonlander", { v = score }) end
    end

    local function build_pads()
        pads = {}
        local x = 20
        while x < 300 do
            local w = math.random(30, 60)
            pads[#pads + 1] = { x = x, w = w, mult = math.random(1, 3) }
            x = x + w + math.random(30, 70)
        end
    end

    local function reset_ship()
        ship = { x = math.random(60, 260), y = 60, angle = math.pi / 2, vx = 0, vy = 0 }
        fuel = 100
    end

    local function reset()
        build_pads()
        reset_ship()
        score = 0
        ships = 3
        state = "fly"
        land_timer = 0
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

        if state == "landed" then
            land_timer = land_timer - 1
            if land_timer <= 0 then
                reset_ship()
                state = "fly"
            end
            return
        end

        -- controls
        if h.left then ship.angle = ship.angle - 0.08 end
        if h.right then ship.angle = ship.angle + 0.08 end
        if h.up and fuel > 0 then
            ship.vx = ship.vx + math.cos(ship.angle) * 0.15
            ship.vy = ship.vy + math.sin(ship.angle) * 0.15
            fuel = fuel - 0.5
            if fuel % 10 < 0.5 then SFX.move() end
        end

        ship.vy = ship.vy + 0.06  -- gravity
        ship.x = ship.x + ship.vx
        ship.y = ship.y + ship.vy

        -- wrap horizontally
        if ship.x < 0 then ship.x = 320 end
        if ship.x > 320 then ship.x = 0 end

        -- ceiling
        if ship.y < 36 then
            ship.y = 36
            ship.vy = math.abs(ship.vy) * 0.5
        end

        -- ground collision
        if ship.y + SHIP / 2 >= GROUND then
            ship.y = GROUND - SHIP / 2
            -- on a pad?
            local pad = nil
            for _, pd in ipairs(pads) do
                if ship.x >= pd.x and ship.x <= pd.x + pd.w then pad = pd break end
            end
            local gentle = math.abs(ship.vy) < 1.2 and math.abs(ship.vx) < 1.2
            if pad and gentle then
                local bonus = pad.mult * 10 + math.floor(fuel)
                score = score + bonus
                SFX.levelup()
                state = "landed"
                land_timer = 50
            else
                ships = ships - 1
                SFX.hit()
                if ships <= 0 then
                    state = "over"
                    SFX.over()
                    save_hi()
                else
                    reset_ship()
                end
            end
        end
    end

    function scene:draw()
        LCD.clear()
        LCD.textCentered("MOON LANDER", 6, 1, LCD.MID)
        LCD.seg(score, 16, 16, 2, 6, LCD.DARK)
        LCD.text("HI " .. ((save.get("hi_moonlander") or {}).v or 0), 252, 20, 1, LCD.DARK)

        -- terrain between pads
        local cursor = 0
        for _, pd in ipairs(pads) do
            if pd.x > cursor then
                disp.fillRect(cursor, GROUND - 6, pd.x - cursor, 6, LCD.MID)
            end
            cursor = pd.x + pd.w
        end
        if cursor < 320 then
            disp.fillRect(cursor, GROUND - 6, 320 - cursor, 6, LCD.MID)
        end

        -- pads
        for _, pd in ipairs(pads) do
            disp.fillRect(pd.x, GROUND - 4, pd.w, 4, LCD.DARK)
            LCD.textCenteredAt(tostring(pd.mult), pd.x + pd.w / 2, GROUND - 16, 1, LCD.DARK)
        end

        -- ship
        local c, s = math.cos(ship.angle), math.sin(ship.angle)
        disp.fillTriangle(
            math.floor(ship.x + c * 8), math.floor(ship.y + s * 8),
            math.floor(ship.x + math.cos(ship.angle + 2.6) * 6), math.floor(ship.y + math.sin(ship.angle + 2.6) * 6),
            math.floor(ship.x + math.cos(ship.angle - 2.6) * 6), math.floor(ship.y + math.sin(ship.angle - 2.6) * 6),
            LCD.DARK)

        -- fuel gauge
        disp.drawRect(252, 40, 20, 60, LCD.DARK)
        local fh = math.floor(fuel * 0.56)
        disp.fillRect(254, 98 - fh, 16, fh, LCD.DARK)
        LCD.text("F", 252, 104, 1, LCD.MID)

        for i = 1, ships do disp.fillRect(252 + (i - 1) * 12, 120, 8, 8, LCD.DARK) end

        if state == "landed" then
            LCD.textCentered("LANDED +" .. (score), 150, 1, LCD.DARK)
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
