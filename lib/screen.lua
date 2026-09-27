-- screen.lua — owns the grid and the panel, and puts only what changed on
-- the LCD. Shared by the menu and the play runner. Needs the LCD global.
--
-- display.flush() swaps two framebuffers without copying, so a partial
-- redraw would land on a frame from two flushes ago. display.flushRegion
-- sends just the changed rows and copies them into the other buffer, which
-- keeps both buffers identical and partial redraws correct.

local STALL_MS = 250   -- a longer gap between frames means the OS (e.g. the
                       -- F10 system menu) had the screen: repaint it all

local Screen = {}
Screen.__index = Screen

function Screen.new(disp, grid, panel)
    return setmetatable({ disp = disp, grid = grid, panel = panel,
                          full = true, last = nil }, Screen)
end

function Screen:repaint()
    self.full = true
end

-- Render the grid and panel; flush the changed rows. Returns true if
-- anything was drawn.
function Screen:present(now)
    if self.last and now - self.last > STALL_MS then self.full = true end
    self.last = now

    local y0, y1
    if self.full then
        LCD.clear()
        self.grid:draw_frame()
        self.grid:invalidate()
        self.panel:invalidate()
        y0, y1 = 0, 319
        self.full = false
    end

    local a, b = self.grid:render(now)
    if a then
        if not y0 or a < y0 then y0 = a end
        if not y1 or b > y1 then y1 = b end
    end
    a, b = self.panel:render(now)
    if a then
        if not y0 or a < y0 then y0 = a end
        if not y1 or b > y1 then y1 = b end
    end

    if y0 then self.disp.flushRegion(y0, y1) end
    return y0 ~= nil
end

return Screen
