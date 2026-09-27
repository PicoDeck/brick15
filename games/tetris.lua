-- tetris.lua — game 01: falling blocks in the 10x20 well.
-- Game contract: see lib/runner.lua. Needs the SFX global.

local COLS, ROWS = 10, 20
local FALL_MS = 800        -- gravity at speed 1, level 1
local DROP_MS = 40         -- gravity while Down is held
local FLASH_MS = 300       -- a cleared row blinks this long before it goes

-- Cell offsets {x, y} (0-based) for each rotation of each piece.
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

local LINE_SCORE = { 100, 300, 500, 800 }

local DEMO = {
    {
        "....##....",
        "....##....",
        "..........",
        "..........",
        "..........",
        "..........",
        "..........",
        "..........",
        "#.........",
        "##.....#..",
        "###.#.####",
        "####.#####",
    },
    {
        "..........",
        "..........",
        "..........",
        "..........",
        "..........",
        "..........",
        "..........",
        "....##....",
        "#...##....",
        "##.....#..",
        "###.#.####",
        "####.#####",
    },
}

local function new(ctx)
    local game = { score = 0, level = 1, lines = 0 }

    game.well = {}
    for r = 1, ROWS do
        game.well[r] = {}
        for c = 1, COLS do game.well[r][c] = false end
    end

    local function collides(cells, x, y)
        for _, c in ipairs(cells) do
            local cx, cy = x + c[1], y + c[2]
            if cx < 1 or cx > COLS or cy > ROWS then return true end
            if cy >= 1 and game.well[cy][cx] then return true end
        end
        return false
    end

    -- Returns false when the new piece has nowhere to go (round over).
    local function spawn()
        game.ptype = game.next_type
        game.rot = 1
        game.piece = PIECES[game.ptype][1]
        game.px, game.py = 4, 1
        game.next_type = math.random(#PIECES)
        return not collides(game.piece, game.px, game.py)
    end

    local function try_move(dx, dy)
        if collides(game.piece, game.px + dx, game.py + dy) then return false end
        game.px, game.py = game.px + dx, game.py + dy
        return true
    end

    local function rotate()
        local defs = PIECES[game.ptype]
        local rot = game.rot % #defs + 1
        for _, dx in ipairs({ 0, -1, 1, -2, 2 }) do
            if not collides(defs[rot], game.px + dx, game.py) then
                game.rot, game.piece = rot, defs[rot]
                game.px = game.px + dx
                SFX.rotate()
                return
            end
        end
    end

    -- Lock the piece into the well; full rows start flashing.
    local function lock(now)
        for _, c in ipairs(game.piece) do
            local x, y = game.px + c[1], game.py + c[2]
            if y >= 1 then game.well[y][x] = true end
        end
        game.piece = nil
        local full = {}
        for r = 1, ROWS do
            local all = true
            for c = 1, COLS do
                if not game.well[r][c] then all = false break end
            end
            if all then full[#full + 1] = r end
        end
        if #full > 0 then
            game.flash = { rows = full, until_ms = now + FLASH_MS }
        else
            SFX.drop()
        end
    end

    -- Remove the flashed rows, score them, and bring in the next piece.
    local function clear_rows()
        local rows = game.flash.rows
        for i = #rows, 1, -1 do table.remove(game.well, rows[i]) end
        for _ = 1, #rows do
            local fresh = {}
            for c = 1, COLS do fresh[c] = false end
            table.insert(game.well, 1, fresh)
        end
        game.lines = game.lines + #rows
        game.score = game.score + LINE_SCORE[#rows] * game.level
        game.level = game.lines // 10 + 1
        if #rows == 4 then SFX.levelup() else SFX.score() end
        game.flash = nil
    end

    function game:update(pad, now)
        self.now = now
        if self.flash then
            if now < self.flash.until_ms then return nil end
            clear_rows()
            if not spawn() then return "over" end
            self.next_fall = now + ctx.interval(FALL_MS, self.level)
            return nil
        end

        if pad.repeated.left then try_move(-1, 0) end
        if pad.repeated.right then try_move(1, 0) end
        if pad.pressed.up or pad.pressed.enter or pad.pressed.f1 then rotate() end

        if now >= self.next_fall then
            local step = pad.held.down and DROP_MS or ctx.interval(FALL_MS, self.level)
            self.next_fall = now + step
            if not try_move(0, 1) then
                lock(now)
                if not self.flash and not spawn() then return "over" end
            end
        elseif pad.held.down and self.next_fall - now > DROP_MS then
            self.next_fall = now + DROP_MS
        end
        return nil
    end

    function game:draw(grid, next)
        local flashing = {}
        if self.flash then
            local on = ((self.now or 0) // 75) % 2 == 0
            for _, r in ipairs(self.flash.rows) do flashing[r] = on end
        end
        for r = 1, ROWS do
            for c = 1, COLS do
                if self.well[r][c] then
                    local v = true
                    if flashing[r] ~= nil then v = flashing[r] end
                    grid:set(c, r, v)
                end
            end
        end
        if self.piece then
            for _, c in ipairs(self.piece) do
                grid:set(self.px + c[1], self.py + c[2], true)
            end
        end
        for _, c in ipairs(PIECES[self.next_type][1]) do
            next:set(c[1] + 1, c[2] + 1, true)
        end
    end

    game.next_type = math.random(#PIECES)
    spawn()
    game.next_fall = ctx.now + ctx.interval(FALL_MS, game.level)
    return game
end

return {
    id = "tetris",
    name = "TETRIS",
    hint = { "< > MOVE", "UP ROTATE", "DOWN DROP" },
    order = "high",
    demo = DEMO,
    new = new,
    PIECES = PIECES,
}
