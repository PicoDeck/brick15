-- game_helpers.lua — shared builders and checks for game rule tests.
-- Load with need("dev/test/game_helpers.lua"); defines globals.

need("lib/lcd.lua")
Grid = need("lib/grid.lua")

-- ctx as the runner builds it, with an interval that ignores speed/level
-- so tests can reason in the game's base milliseconds.
function game_ctx(speed)
    return { speed = speed or 1, now = 0,
             interval = function(base_ms) return base_ms end }
end

-- pad{ pressed = { "left" }, held = { "up" } }. Like the device, a pressed
-- key is also held and repeated that frame.
function pad(spec)
    local p = { held = {}, pressed = {}, repeated = {} }
    for kind, keys in pairs(spec or {}) do
        for _, k in ipairs(keys) do
            p[kind][k] = true
            if kind == "pressed" then p.held[k] = true p.repeated[k] = true end
            if kind == "repeated" then p.held[k] = true end
        end
    end
    return p
end
NONE = pad()

function press(key) return pad({ pressed = { key } }) end
function hold(key) return pad({ held = { key } }) end

-- Draw a game onto fresh grids; returns the 10x20 grid and the 4x4 NEXT grid.
function draw_game(game)
    local g, n = Grid.new(10, 20, 0, 0), Grid.new(4, 4, 0, 0)
    game:draw(g, n)
    return g, n
end

function count_lit(grid)
    local n = 0
    for r = 1, grid.rows do
        for c = 1, grid.cols do
            if grid:get(c, r) then n = n + 1 end
        end
    end
    return n
end

-- Panel text: fits the panel (136 px at scale 2), only characters the font has.
function check_text(lines)
    for _, l in ipairs(lines) do
        truthy(LCD.textWidth(string.upper(l), 2) <= 136, "fits the panel: " .. l)
        for ch in string.upper(l):gmatch(".") do
            truthy(LCD.FONT[ch], "font has '" .. ch .. "' (" .. l .. ")")
        end
    end
end

-- The game contract every module must meet (see lib/runner.lua). `messages`
-- lists every status line the game can show; each must fit the panel.
function check_contract(mod, id, name)
    eq(mod.id, id, "id")
    eq(mod.name, name, "name")
    truthy(mod.order == "high" or mod.order == "low", "order")
    eq(type(mod.new), "function", "new")
    eq(#mod.demo, 2, "two demo frames")
    for _, f in ipairs(mod.demo) do
        eq(#f, 12, "demo rows")
        for _, row in ipairs(f) do eq(#row, 10, "demo row width: " .. row) end
    end
    truthy(#mod.name <= 11, "name at most 11 characters")
    truthy(#mod.hint >= 1 and #mod.hint <= 3, "1-3 hint lines")
    check_text({ mod.name })
    check_text(mod.hint)
    check_text(mod.messages or {})
end

-- A status the game shows must be one it declares in `messages`.
function check_status(mod, game)
    for _, line in ipairs(game.status or {}) do
        local known = false
        for _, m in ipairs(mod.messages or {}) do known = known or m == line end
        truthy(known, "status '" .. line .. "' is listed in messages")
    end
end
