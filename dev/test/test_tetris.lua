need("lib/lcd.lua")
local Grid = need("lib/grid.lua")
local tetris = need("games/tetris.lua")

local NONE = { held = {}, pressed = {}, repeated = {} }

local function new_game()
    return tetris.new({ speed = 1, now = 0,
                        interval = function(base_ms) return base_ms end })
end

local function fill_row(game, r, except_from, except_to)
    for c = 1, 10 do
        game.well[r][c] = not (c >= except_from and c <= except_to)
    end
end

test("tetris: module metadata follows the game contract", function()
    eq(tetris.id, "tetris", "id"); eq(tetris.name, "BLOCKS", "name")
    eq(tetris.order, "high", "order")
    eq(#tetris.demo, 2, "two demo frames")
    for _, f in ipairs(tetris.demo) do
        eq(#f, 12, "12 rows")
        for _, row in ipairs(f) do eq(#row, 10, "10 columns") end
    end
    truthy(#tetris.hint >= 1 and #tetris.hint <= 3, "1-3 hint lines")
end)

test("tetris: name and hint fit the panel and use only font glyphs", function()
    truthy(#tetris.name <= 11, "name at most 11 characters")
    local lines = { tetris.name }
    for _, h in ipairs(tetris.hint) do
        truthy(#h <= 17, "hint line at most 17 characters: " .. h)
        lines[#lines + 1] = h
    end
    for _, l in ipairs(lines) do
        for ch in string.upper(l):gmatch(".") do
            truthy(LCD.FONT[ch], "font has '" .. ch .. "' (" .. l .. ")")
        end
    end
end)

test("tetris: a new game starts at score 0, level 1, no lives field", function()
    local g = new_game()
    eq(g.score, 0, "score"); eq(g.level, 1, "level"); eq(g.lives, nil, "lives unused")
end)

test("tetris: the piece falls one row per interval", function()
    local g = new_game()
    local y = g.py
    g:update(NONE, 799)
    eq(g.py, y, "not yet")
    g:update(NONE, 800)
    eq(g.py, y + 1, "one row down")
end)

test("tetris: a full row flashes, then clears and scores 100 x level", function()
    local g = new_game()
    fill_row(g, 20, 1, 4)                   -- gap in cols 1-4
    g.ptype, g.rot = 1, 1                    -- I piece, flat: cells (0..3, 1)
    g.piece = tetris.PIECES[1][1]
    g.px, g.py = 1, 19                       -- occupies row 20, cols 1-4
    g.next_fall = 0
    g:update(NONE, 0)                        -- can't fall: locks
    truthy(g.flash, "row flashes")
    g:update(NONE, 299)
    truthy(g.flash, "still flashing")
    g:update(NONE, 300)
    eq(g.flash, nil, "flash over")
    eq(g.score, 100, "score")
    for c = 1, 10 do eq(g.well[20][c], false, "bottom row empty") end
end)

test("tetris: ten lines raise the level", function()
    local g = new_game()
    g.lines = 9
    fill_row(g, 20, 1, 4)
    g.piece, g.ptype, g.rot = tetris.PIECES[1][1], 1, 1
    g.px, g.py, g.next_fall = 1, 19, 0
    g:update(NONE, 0); g:update(NONE, 300)
    eq(g.level, 2, "level 2")
end)

test("tetris: a blocked spawn ends the round", function()
    local g = new_game()
    for r = 1, 3 do fill_row(g, r, 10, 10) end            -- spawn area full, col 10 open
    g.piece, g.ptype, g.rot = tetris.PIECES[2][1], 2, 1   -- O piece
    g.px, g.py, g.next_fall = 1, 19, 0                    -- resting on the floor
    eq(g:update(NONE, 0), "over", "round over")
end)

test("tetris: left moves the piece, walls stop it", function()
    local g = new_game()
    local x = g.px
    g:update({ held = {}, pressed = {}, repeated = { left = true } }, 1)
    eq(g.px, x - 1, "moved left")
    for _ = 1, 10 do g:update({ held = {}, pressed = {}, repeated = { left = true } }, 1) end
    local minx = 99
    for _, c in ipairs(g.piece) do minx = math.min(minx, g.px + c[1]) end
    eq(minx, 1, "stopped at the wall")
end)

test("tetris: draw puts the piece on the grid and the next piece in NEXT", function()
    local g = new_game()
    local grid, nextg = Grid.new(10, 20, 0, 0), Grid.new(4, 4, 0, 0)
    g:draw(grid, nextg)
    local lit = 0
    for r = 1, 20 do for c = 1, 10 do if grid:get(c, r) then lit = lit + 1 end end end
    eq(lit, 4, "four piece cells")
    local nlit = 0
    for r = 1, 4 do for c = 1, 4 do if nextg:get(c, r) then nlit = nlit + 1 end end end
    eq(nlit, 4, "next piece shown")
end)
