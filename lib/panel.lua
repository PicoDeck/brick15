-- panel.lua — the side panel, laid out the same in every game and the menu.
-- Fields redraw only when their value changes; unused fields (nil) keep
-- their ghost segments or bricks. Needs the LCD global.

local disp = picocalc.display

local X = 176            -- panel left edge
local W = 320 - X        -- 144px to the screen edge (content uses 136)
local RIGHT = X + 99     -- every 7-segment field ends on this column

-- Left edge of a 7-segment field that ends at RIGHT (see LCD.seg widths).
local function seg_x(t, digits) return RIGHT - (digits * (3 * t + t // 2) - t // 2) end

local Panel = {}
Panel.__index = Panel
Panel.X = X

local function text(v, y) LCD.text(v or "", X, y, 2, LCD.DARK) end

-- Each field: the keys that dirty it, the rectangle it owns, how to draw it.
local FIELDS = {
    { keys = { "label" }, x = X, y = 8, w = W, h = 10,
      draw = function(v) text(v.label, 8) end },
    { keys = { "score" }, x = X, y = 22, w = W, h = 24,
      draw = function(v) LCD.seg(v.score, seg_x(4, 6), 22, 4, 6) end },
    { keys = { "hi", "hi_label" }, x = X, y = 50, w = W, h = 18,
      draw = function(v)
          text(v.hi_label or "HI", 54)
          LCD.seg(v.hi, seg_x(3, 6), 50, 3, 6)
      end },
    { keys = { "next_label" }, x = X, y = 76, w = W, h = 10,
      draw = function(v) text(v.next_label or "NEXT", 76) end },
    { keys = { "speed" }, x = X + 80, y = 160, w = W - 80, h = 18,
      draw = function(v) LCD.seg(v.speed, seg_x(3, 1), 160, 3, 1) end },
    { keys = { "level" }, x = X + 80, y = 184, w = W - 80, h = 18,
      draw = function(v) LCD.seg(v.level, seg_x(3, 2), 184, 3, 2) end },
    { keys = { "name" }, x = X, y = 252, w = W, h = 10,
      draw = function(v) text(v.name, 252) end },
    { keys = { "status1" }, x = X, y = 270, w = W, h = 10,
      draw = function(v) text(v.status1, 270) end },
    { keys = { "status2" }, x = X, y = 284, w = W, h = 10,
      draw = function(v) text(v.status2, 284) end },
    { keys = { "status3" }, x = X, y = 298, w = W, h = 10,
      draw = function(v) text(v.status3, 298) end },
}

-- Printed legends: drawn once per full repaint.
local LEGENDS = { { "SPEED", 164 }, { "LEVEL", 188 }, { "LIVES", 212 } }

function Panel.new(Grid)
    local p = setmetatable({ values = {}, dirty = {}, full = true }, Panel)
    p.next = Grid.new(4, 4, X, 90)
    p.lives = Grid.new(4, 1, X, 226)
    return p
end

function Panel:set(key, value)
    if self.values[key] ~= value then
        self.values[key] = value
        self.dirty[key] = true
    end
end

-- lines: nil or a list of up to 3 strings (at most 17 characters each).
function Panel:set_status(lines)
    lines = lines or {}
    for i = 1, 3 do self:set("status" .. i, lines[i] or "") end
end

function Panel:invalidate()
    self.full = true
end

-- Draw what changed. Returns the pixel rows touched (y0, y1) or nil.
function Panel:render(now)
    local y0, y1
    local function touch(a, b)
        if not y0 or a < y0 then y0 = a end
        if not y1 or b > y1 then y1 = b end
    end

    local full = self.full
    if full then
        disp.fillRect(X, 0, W, 320, LCD.BG)
        for _, l in ipairs(LEGENDS) do text(l[1], l[2]) end
        self.next:invalidate()
        self.lives:invalidate()
        touch(0, 319)
        self.full = false
    end

    for _, f in ipairs(FIELDS) do
        local dirty = full
        for _, k in ipairs(f.keys) do
            if self.dirty[k] then dirty = true end
        end
        if dirty then
            disp.fillRect(f.x, f.y, f.w, f.h, LCD.BG)
            f.draw(self.values)
            touch(f.y, f.y + f.h - 1)
        end
    end
    self.dirty = {}

    local n = self.values.lives
    for i = 1, 4 do self.lives:set(i, 1, n ~= nil and i <= n) end
    local a, b = self.next:render(now)
    if a then touch(a, b) end
    a, b = self.lives:render(now)
    if a then touch(a, b) end
    return y0, y1
end

return Panel
