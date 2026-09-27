need("lib/lcd.lua")
local Grid = need("lib/grid.lua")
local Panel = need("lib/panel.lua")
local Screen = need("lib/screen.lua")

local function new_screen()
    local grid = Grid.new(10, 20, 12, 10)
    return Screen.new(picocalc.display, grid, Panel.new(Grid)), grid
end

local function flushes()
    local out = {}
    for _, c in ipairs(CALLS) do
        if c[1] == "flushRegion" then out[#out + 1] = { c[2], c[3] } end
        if c[1] == "flush" then out[#out + 1] = { "full" } end
    end
    return out
end

test("screen: first present clears, frames and flushes the whole screen", function()
    local s = new_screen()
    s:present(0)
    eq(CALLS[1][1], "clear", "clears first")
    eq(count_calls("drawRect"), 2, "frame")
    local f = flushes()
    eq(#f, 1, "one flush"); eq(f[1][1], 0, "from 0"); eq(f[1][2], 319, "to 319")
end)

test("screen: an unchanged frame draws and flushes nothing", function()
    local s = new_screen()
    s:present(0)
    reset_calls()
    s:present(16)
    eq(#CALLS, 0, "no calls at all")
end)

test("screen: a changed cell flushes only its rows", function()
    local s, grid = new_screen()
    s:present(0)
    reset_calls()
    grid:set(1, 1, true)
    s:present(16)
    local f = flushes()
    eq(#f, 1, "one flush"); eq(f[1][1], 10, "top"); eq(f[1][2], 24, "bottom")
end)

test("screen: never uses the buffer-swapping full flush", function()
    local s, grid = new_screen()
    s:present(0); grid:set(2, 2, true); s:present(16)
    eq(count_calls("flush"), 0, "display.flush calls")
end)

test("screen: a stall longer than 250 ms repaints everything", function()
    local s = new_screen()
    s:present(0)
    s:present(16)
    reset_calls()
    s:present(16 + 251)
    eq(CALLS[1][1], "clear", "full repaint after the system menu")
end)

test("screen: repaint() forces a full repaint on the next present", function()
    local s = new_screen()
    s:present(0)
    reset_calls()
    s:repaint()
    s:present(16)
    local f = flushes()
    eq(f[1][1], 0, "from 0"); eq(f[1][2], 319, "to 319")
end)
