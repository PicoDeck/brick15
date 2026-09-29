-- grid.lua — a matrix of LCD bricks that redraws only what changed.
-- Cells are false (unlit), true (lit) or "blink" (lit on the shared 2 Hz
-- phase). Column 1 is the left edge, row 1 the top. Needs the LCD global.

local disp = picocalc.display

local PITCH = 15
local CURTAIN_STEP = 30   -- ms per row of the game-over / power-on curtain

local Grid = {}
Grid.__index = Grid
Grid.PITCH = PITCH
Grid.CURTAIN_STEP = CURTAIN_STEP

function Grid.new(cols, rows, x, y)
    local g = setmetatable({ cols = cols, rows = rows, x = x, y = y,
                             cells = {}, shown = {} }, Grid)
    g:clear()
    return g
end

-- Blinking cells are lit for the first 250 ms of every 500 ms.
function Grid.blink_on(now)
    return (now // 250) % 2 == 0
end

-- A 13x13 framed brick inside a 15x15 cell at (px, py).
function Grid.draw_brick(px, py, color)
    disp.fillRect(px + 1, py + 1, 13, 13, color)
    disp.fillRect(px + 3, py + 3, 9, 9, LCD.BG)
    disp.fillRect(px + 5, py + 5, 5, 5, color)
end

function Grid:clear()
    local cells = self.cells
    for i = 1, self.cols * self.rows do cells[i] = false end
end

function Grid:set(c, r, v)
    c, r = math.floor(c), math.floor(r)
    if c < 1 or c > self.cols or r < 1 or r > self.rows then return end
    if v == nil then v = true end
    self.cells[(r - 1) * self.cols + c] = v
end

function Grid:get(c, r)
    c, r = math.floor(c), math.floor(r)
    if c < 1 or c > self.cols or r < 1 or r > self.rows then return false end
    return self.cells[(r - 1) * self.cols + c]
end

-- pattern: list of strings, '#' = set to v (default lit), anything else skipped.
function Grid:stamp(pattern, c, r, v)
    for dy = 1, #pattern do
        local line = pattern[dy]
        for dx = 1, #line do
            if string.sub(line, dx, dx) == "#" then
                self:set(c + dx - 1, r + dy - 1, v)
            end
        end
    end
end

-- Font glyphs as bricks, one empty column between characters.
function Grid:text(str, c, r, v)
    str = string.upper(str)
    for i = 1, #str do
        local glyph = LCD.FONT[string.sub(str, i, i)]
        if glyph then
            for dy = 1, 5 do
                for dx = 1, #glyph[dy] do
                    if string.sub(glyph[dy], dx, dx) == "1" then
                        self:set(c + dx - 1, r + dy - 1, v)
                    end
                end
            end
            c = c + #glyph[1] + 1
        else
            c = c + 4
        end
    end
end

-- Overlay the curtain `elapsed` ms after it started: rows fill from the
-- bottom, then clear from the top. Returns true once it has finished.
function Grid:curtain(elapsed)
    local step = elapsed // CURTAIN_STEP
    local rows = self.rows
    if step < rows then
        for r = rows - step, rows do
            for c = 1, self.cols do self:set(c, r, true) end
        end
        return false
    end
    local cleared = step - rows + 1
    for r = 1, rows do
        for c = 1, self.cols do self:set(c, r, r > cleared) end
    end
    return cleared >= rows
end

-- The 2px DARK frame around the grid (drawn by Screen on a full repaint).
function Grid:draw_frame()
    local w, h = self.cols * PITCH, self.rows * PITCH
    disp.drawRect(self.x - 4, self.y - 4, w + 8, h + 8, LCD.DARK)
    disp.drawRect(self.x - 3, self.y - 3, w + 6, h + 6, LCD.DARK)
end

-- Forget what is on screen so the next render redraws every cell.
function Grid:invalidate()
    local shown = self.shown
    for i = 1, self.cols * self.rows do shown[i] = nil end
end

-- Redraw every cell whose visible state differs from what it last drew.
-- Returns the pixel rows touched (y0, y1), or nil if nothing changed.
function Grid:render(now)
    local on = Grid.blink_on(now)
    local cells, shown, cols = self.cells, self.shown, self.cols
    local y0, y1
    for r = 1, self.rows do
        for c = 1, cols do
            local i = (r - 1) * cols + c
            local v = cells[i]
            local lit = v == true or (v == "blink" and on)
            if shown[i] ~= lit then
                local px = self.x + (c - 1) * PITCH
                local py = self.y + (r - 1) * PITCH
                Grid.draw_brick(px, py, lit and LCD.DARK or LCD.GHOST)
                shown[i] = lit
                if not y0 then y0 = py end
                y1 = py + PITCH - 1
            end
        end
    end
    return y0, y1
end

return Grid
