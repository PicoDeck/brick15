need("lib/lcd.lua")
local Grid = need("lib/grid.lua")
local Panel = need("lib/panel.lua")
local Screen = need("lib/screen.lua")
local Scores = need("lib/scores.lua")
local Menu = need("lib/menu.lua")

local input = picocalc.input
local T = 0
local BOOT = 40 * Grid.CURTAIN_STEP   -- long enough for the power-on curtain

local function def(id, order)
    return { id = id, name = string.upper(id), hint = {}, order = order or "high",
             demo = { { "#" }, { ".#" } }, new = function() end }
end

local function setup(games)
    T = 0
    games = games or { def("aaa"), def("bbb"), def("ccc", "low") }
    local grid = Grid.new(10, 20, 12, 10)
    local screen = Screen.new(picocalc.display, grid, Panel.new(Grid))
    local runner = { started = nil }
    function runner:start(d, speed) self.started = { def = d, speed = speed } end
    local switched = {}
    local m = Menu.new({
        screen = screen, games = games,
        scores = Scores.new(picocalc.game.save, games),
        runner = runner,
        scene = { switch = function(name) switched[#switched + 1] = name end },
        clock = function() return T end,
        input = input,
    })
    m:enter()
    return m, screen, runner, switched
end

local function frame(m, dt)
    T = T + (dt or 16)
    m:update()
    m:draw()
end

local function boot(m)
    for _ = 1, BOOT // 30 + 2 do frame(m, 30) end
end

local function with(getter, mask, fn)
    local old = input[getter]
    input[getter] = function() return mask end
    fn()
    input[getter] = old
end

test("menu: the power-on curtain plays first and blocks input", function()
    local m = setup()
    frame(m)
    eq(m.booted, false, "booting")
    with("getButtonsRepeated", input.BTN_RIGHT, function() frame(m) end)
    eq(m.sel, 1, "input ignored during the curtain")
    boot(m)
    eq(m.booted, true, "booted")
end)

test("menu: shows the game number as big brick digits", function()
    local m, screen = setup()
    boot(m)
    -- "0" at cols 2-4 (top row 111), "1" at cols 7-9 (top row 010)
    eq(screen.grid:get(2, 2), true, "0 top-left"); eq(screen.grid:get(3, 3), false, "0 hollow")
    eq(screen.grid:get(8, 2), true, "1 stem"); eq(screen.grid:get(7, 2), false, "1 left blank")
end)

test("menu: left and right change game and wrap around", function()
    local m = setup()
    boot(m)
    with("getButtonsRepeated", input.BTN_LEFT, function() frame(m) end)
    eq(m.sel, 3, "wrapped to last")
    with("getButtonsRepeated", input.BTN_RIGHT, function() frame(m) end)
    eq(m.sel, 1, "wrapped to first")
end)

test("menu: up and down set speed within 1-9", function()
    local m = setup()
    boot(m)
    with("getButtonsRepeated", input.BTN_DOWN, function() frame(m) end)
    eq(m.speed, 1, "floor 1")
    for _ = 1, 12 do with("getButtonsRepeated", input.BTN_UP, function() frame(m) end) end
    eq(m.speed, 9, "ceiling 9")
end)

test("menu: Enter starts the selected game at the chosen speed", function()
    local m, _, runner, switched = setup()
    boot(m)
    with("getButtonsRepeated", input.BTN_RIGHT, function() frame(m) end)
    with("getButtonsRepeated", input.BTN_UP, function() frame(m) end)
    with("getButtonsPressed", input.BTN_ENTER, function() frame(m) end)
    eq(runner.started.def.id, "bbb", "game"); eq(runner.started.speed, 2, "speed")
    eq(switched[1], "play", "scene")
end)

test("menu: Esc asks to quit", function()
    local m = setup()
    boot(m)
    with("getButtonsPressed", input.BTN_ESC, function() frame(m) end)
    eq(m.quit, true, "quit")
end)

test("menu: panel shows the record, BEST for low-order games", function()
    SAVES.hi_ccc = { v = 12 }
    local m, screen = setup()
    boot(m)
    with("getButtonsRepeated", input.BTN_LEFT, function() frame(m) end)
    eq(screen.panel.values.hi_label, "BEST", "label"); eq(screen.panel.values.hi, 12, "value")
    eq(screen.panel.values.label, "BRICK-15", "title")
end)

test("menu: nothing is drawn between demo frames", function()
    local m = setup()
    boot(m)
    T = (T // 400 + 1) * 400   -- start of a demo frame
    frame(m, 0)
    reset_calls()
    frame(m, 16); frame(m, 16)
    eq(count_calls("fillRect"), 0, "no draws")
end)

test("menu: coming back from a game keeps the selection and skips the curtain", function()
    local m = setup()
    boot(m)
    with("getButtonsRepeated", input.BTN_RIGHT, function() frame(m) end)
    m:exit(); m:enter()
    frame(m)
    eq(m.sel, 2, "same game"); eq(m.booted, true, "no second curtain")
end)
