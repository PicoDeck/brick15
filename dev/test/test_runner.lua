need("lib/lcd.lua")
local Grid = need("lib/grid.lua")
local Panel = need("lib/panel.lua")
local Screen = need("lib/screen.lua")
local Scores = need("lib/scores.lua")
local Runner = need("lib/runner.lua")

local input = picocalc.input

-- A fake game: ends its round when `over_next` is set.
local function fake_def(opts)
    opts = opts or {}
    local def = { id = "fake", name = "FAKE", hint = { "HINT LINE" },
                  order = opts.order or "high", demo = {}, made = 0 }
    def.new = function(ctx)
        def.made = def.made + 1
        def.ctx = ctx
        local game = { score = opts.score or 0, level = 1, lives = 3 }
        function game:update(pad, now)
            if def.over_next then def.over_next = false return "over" end
        end
        function game:draw(grid, next) grid:set(1, 1, true) end
        return game
    end
    return def
end

local T = 0
local function setup(def)
    T = 0
    local grid = Grid.new(10, 20, 12, 10)
    local screen = Screen.new(picocalc.display, grid, Panel.new(Grid))
    local switched = {}
    local r = Runner.new({
        screen = screen,
        scores = Scores.new(picocalc.game.save, { def }),
        scene = { switch = function(name) switched[#switched + 1] = name end },
        clock = function() return T end,
        input = input,
    })
    r:start(def, 3)
    r:enter()
    return r, screen, switched
end

local function with_pressed(mask, fn)
    local old = input.getButtonsPressed
    input.getButtonsPressed = function() return mask end
    fn()
    input.getButtonsPressed = old
end

local function frame(r, dt)
    T = T + (dt or 16)
    r:update()
    r:draw()
end

test("runner: interval shrinks with speed and level, floor 40 ms", function()
    eq(Runner.interval(800, 1, 1), 800, "speed 1 level 1")
    eq(math.floor(Runner.interval(800, 2, 1)), 696, "speed 2")
    eq(math.floor(Runner.interval(800, 1, 2)), 696, "level 2")
    eq(Runner.interval(800, 9, 30), 40, "floor")
end)

test("runner: a round gets the chosen speed and an interval helper", function()
    local def = fake_def()
    setup(def)
    eq(def.made, 1, "one game made")
    eq(def.ctx.speed, 3, "speed passed")
    eq(math.floor(def.ctx.interval(800, 1)), math.floor(Runner.interval(800, 3, 1)), "interval uses speed")
end)

test("runner: the controls hint stays up while the game shows no status", function()
    local def = fake_def()
    local r, screen = setup(def)
    frame(r)
    eq(screen.panel.values.status1, "HINT LINE", "hint")
    T = 30000; frame(r, 0)
    eq(screen.panel.values.status1, "HINT LINE", "still there later in the round")
end)

test("runner: Esc returns to the menu", function()
    local r, _, switched = setup(fake_def())
    with_pressed(input.BTN_ESC, function() frame(r) end)
    eq(switched[1], "menu", "switched")
end)

test("runner: game over plays the curtain, then shows the over status", function()
    local def = fake_def()
    local r, screen = setup(def)
    frame(r)
    def.over_next = true
    frame(r)
    eq(r.state, "curtain", "curtain starts")
    eq(screen.panel.values.status1, "GAME OVER", "line 1 during curtain")
    for _ = 1, 100 do frame(r, 30) end
    eq(r.state, "over", "curtain finished")
    eq(screen.panel.values.status2, "ENTER AGAIN", "line 2")
    eq(screen.panel.values.status3, "ESC MENU", "line 3")
    eq(screen.grid:get(1, 1), false, "grid cleared after the curtain")
end)

test("runner: Esc during the curtain still returns to the menu", function()
    local def = fake_def()
    local r, _, switched = setup(def)
    def.over_next = true
    frame(r)
    with_pressed(input.BTN_ESC, function() frame(r) end)
    eq(switched[1], "menu", "switched")
end)

test("runner: Enter during the curtain does not restart the round", function()
    local def = fake_def()
    local r = setup(def)
    def.over_next = true
    frame(r)
    with_pressed(input.BTN_ENTER, function() frame(r) end)
    eq(def.made, 1, "still the first round")
    eq(r.state, "curtain", "curtain continues")
end)

test("runner: a beaten record adds NEW HI under the headline and is saved", function()
    local def = fake_def({ score = 50 })
    local r, screen = setup(def)
    def.over_next = true
    frame(r)
    eq(screen.panel.values.status1, "GAME OVER", "headline kept")
    eq(screen.panel.values.status2, "NEW HI", "record")
    eq(SAVES.hi_fake.v, 50, "saved")
    for _ = 1, 100 do frame(r, 30) end
    eq(screen.panel.values.status3, "ENTER AGAIN", "how to play again")
end)

test("runner: a game's own result stays the headline when it sets a record", function()
    local def = fake_def({ score = 5 })
    local r, screen = setup(def)
    r.game.status = { "YOU WIN" }
    def.over_next = true
    frame(r)
    eq(screen.panel.values.status1, "YOU WIN", "result")
    eq(screen.panel.values.status2, "NEW HI", "record")
end)

test("runner: fewer-is-better games announce NEW BEST", function()
    local def = fake_def({ score = 12, order = "low" })
    local r, screen = setup(def)
    def.over_next = true
    frame(r)
    eq(screen.panel.values.status2, "NEW BEST", "record")
end)

test("runner: a game can relabel SCORE", function()
    local def = fake_def()
    local r, screen = setup(def)
    frame(r)
    eq(screen.panel.values.label, "SCORE", "default")
    r.game.score_label = "TURNS"
    frame(r)
    eq(screen.panel.values.label, "TURNS", "relabelled")
end)

test("runner: a game can relabel the NEXT box", function()
    local def = fake_def()
    local r, screen = setup(def)
    frame(r)
    eq(screen.panel.values.next_label, "NEXT", "default")
    r.game.next_label = "FUEL"
    frame(r)
    eq(screen.panel.values.next_label, "FUEL", "relabelled")
end)

test("runner: Enter after game over starts a new round", function()
    local def = fake_def()
    local r = setup(def)
    def.over_next = true
    frame(r)
    for _ = 1, 100 do frame(r, 30) end
    with_pressed(input.BTN_ENTER, function() frame(r) end)
    eq(def.made, 2, "second round")
    eq(r.state, "play", "playing again")
end)

test("runner: the game-over screen draws nothing while idle", function()
    local def = fake_def()
    local r = setup(def)
    def.over_next = true
    frame(r)
    for _ = 1, 100 do frame(r, 30) end
    reset_calls()
    frame(r); frame(r)
    eq(count_calls("fillRect"), 0, "no draws")
    eq(count_calls("flushRegion"), 0, "no flushes")
end)

test("runner: lower-is-better games label the record BEST", function()
    local r, screen = setup(fake_def({ order = "low" }))
    frame(r)
    eq(screen.panel.values.hi_label, "BEST", "label")
end)
