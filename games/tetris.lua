-- tetris.lua — game 01. Expects globals: LCD, SFX, PAD, disp, picocalc.

local disp = picocalc.display
local scene_mgr = picocalc.game.scene
local save = picocalc.game.save

local COLS, ROWS = 10, 20
local CELL = 12
local OX, OY = 100, 44

local PIECES = {
    { { {0,1},{1,1},{2,1},{3,1} }, { {2,0},{2,1},{2,2},{2,3} } }, -- I
    { { {0,0},{1,0},{0,1},{1,1} } },                                     -- O
    { { {1,0},{0,1},{1,1},{2,1} }, { {1,0},{0,1},{1,1},{1,2} },
      { {0,1},{1,1},{2,1},{1,2} }, { {1,0},{1,1},{2,1},{1,2} } },      -- T
    { { {1,0},{2,0},{0,1},{1,1} }, { {1,0},{1,1},{2,1},{2,2} } },      -- S
    { { {0,0},{1,0},{1,1},{2,1} }, { {2,0},{1,1},{2,1},{1,2} } },      -- Z
    { { {0,0},{0,1},{1,1},{2,1} }, { {1,0},{2,0},{1,1},{1,2} },
      { {0,1},{1,1},{2,1},{2,2} }, { {1,0},{1,1},{0,2},{1,2} } },      -- J
    { { {2,0},{0,1},{1,1},{2,1} }, { {1,0},{1,1},{1,2},{2,2} },
      { {0,1},{1,1},{2,1},{0,2} }, { {0,0},{1,0},{1,1},{1,2} } },      -- L
}

local function new()
    local scene = {}
    local grid, piece, ptype, next_type, px, py, rot
    local score, lines, level, frame, game_over
    local l_timer, r_timer

    local function save_hi()
        local hi = (save.get("hi_tetris") or {}).v or 0
        if score > hi then save.set("hi_tetris", { v = score }) end
    end

    local function collides(cells, cx, cy)
        for _, c in ipairs(cells) do
            local x, y = cx + c[1], cy + c[2]
            if x < 1 or x > COLS or y > ROWS then return true end
            if y >= 1 and grid[y][x] ~= 0 then return true end
        end
        return false
    end

    local function spawn()
        ptype = next_type
        local defs = PIECES[ptype]
        piece = defs[1]
        rot = 1
        px = 4
        py = 1
        next_type = math.random(#PIECES)
        if collides(piece, px, py) then
            game_over = true
            SFX.over()
            save_hi()
        end
    end

    local function reset()
        grid = {}
        for r = 1, ROWS do
            grid[r] = {}
            for c = 1, COLS do grid[r][c] = 0 end
        end
        score, lines, level, frame = 0, 0, 1, 0
        game_over = false
        l_timer, r_timer = 0, 0
        next_type = math.random(#PIECES)
        spawn()
    end

    local function try_move(dx, dy)
        if not collides(piece, px + dx, py + dy) then
            px, py = px + dx, py + dy
            return true
        end
        return false
    end

    local function do_rotate()
        local defs = PIECES[ptype]
        local new_rot = rot % #defs + 1
        local new_cells = defs[new_rot]
        for _, dx in ipairs({ 0, -1, 1, -2, 2 }) do
            if not collides(new_cells, px + dx, py) then
                rot, piece = new_rot, new_cells
                px = px + dx
                SFX.rotate()
                return
            end
        end
    end

    local function lock()
        for _, c in ipairs(piece) do
            local x, y = px + c[1], py + c[2]
            if y >= 1 then grid[y][x] = 1 end
        end
        local cleared = 0
        for r = ROWS, 1, -1 do
            local full = true
            for c = 1, COLS do
                if grid[r][c] == 0 then full = false break end
            end
            if full then
                cleared = cleared + 1
                table.remove(grid, r)
                local fresh = {}
                for c = 1, COLS do fresh[c] = 0 end
                table.insert(grid, 1, fresh)
            end
        end
        if cleared > 0 then
            lines = lines + cleared
            score = score + ({ 100, 300, 500, 800 })[cleared] * level
            level = math.floor(lines / 10) + 1
            if cleared == 4 then SFX.levelup() else SFX.score() end
        else
            SFX.drop()
        end
        spawn()
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

        -- left / right with delayed auto-shift
        if p.left then try_move(-1, 0) l_timer = 14 end
        if p.right then try_move(1, 0) r_timer = 14 end
        if l_timer > 0 then
            l_timer = l_timer - 1
            if l_timer <= 0 and h.left then try_move(-1, 0) l_timer = 5 end
        end
        if r_timer > 0 then
            r_timer = r_timer - 1
            if r_timer <= 0 and h.right then try_move(1, 0) r_timer = 5 end
        end

        if p.up or p.enter or p.f1 then do_rotate() end

        -- gravity
        local interval = math.max(2, 16 - level)
        local stepping = h.down and 2 or interval
        frame = frame + 1
        if frame % stepping == 0 then
            if not try_move(0, 1) then lock() end
        end
    end

    function scene:draw()
        LCD.clear()
        LCD.textCentered("TETRIS", 6, 1, LCD.MID)

        LCD.seg(score, 16, 16, 2, 6, LCD.DARK)
        LCD.text("LV", 16, 34, 1, LCD.MID)
        LCD.seg(level, 40, 32, 1, 2, LCD.DARK)

        -- next piece preview
        local nx, ny = 252, 16
        disp.drawRect(nx - 4, ny - 4, 52, 44, LCD.MID)
        local defs = PIECES[next_type]
        for _, c in ipairs(defs[1]) do
            disp.fillRect(nx + c[1] * 8, ny + c[2] * 8, 7, 7, LCD.DARK)
        end

        -- field
        disp.drawRect(OX - 2, OY - 2, COLS * CELL + 4, ROWS * CELL + 4, LCD.MID)
        local playfield = {}
        for r = 1, ROWS do
            playfield[r] = {}
            for c = 1, COLS do playfield[r][c] = grid[r][c] == 1 and LCD.DARK or nil end
        end
        for _, c in ipairs(piece) do
            local x, y = px + c[1], py + c[2]
            if y >= 1 then playfield[y][x] = LCD.DARK end
        end
        picocalc.graphics.drawPlayfield(playfield, OX, OY, CELL, COLS, ROWS, LCD.MID)

        LCD.text("HI " .. ((save.get("hi_tetris") or {}).v or 0), 252, 70, 1, LCD.DARK)
        LCD.text("DOWN DROP", 252, 90, 1, LCD.MID)
        LCD.text("UP ROTATE", 252, 102, 1, LCD.MID)

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
