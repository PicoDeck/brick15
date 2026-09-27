-- run.lua — desktop test runner for the Lua libraries and game rules.
-- Run from the app root:  lua dev/test/run.lua
-- A stub `picocalc` records display calls so tests can count draws.

CALLS = {}
SAVES = {}      -- stub SD card: slot name -> table
SAVE_LOG = {}   -- every stub save call, in order: { "get"|"set", name }

local function record(name)
    return function(...) CALLS[#CALLS + 1] = { name, ... } end
end

picocalc = {
    display = {
        rgb = function(r, g, b) return (r << 16) | (g << 8) | b end,
        clear = record("clear"),
        fillRect = record("fillRect"),
        drawRect = record("drawRect"),
        flush = record("flush"),
        flushRegion = record("flushRegion"),
    },
    input = {
        BTN_UP = 1, BTN_DOWN = 2, BTN_LEFT = 4, BTN_RIGHT = 8,
        BTN_ENTER = 16, BTN_ESC = 32, BTN_F1 = 64,
        getButtons = function() return 0 end,
        getButtonsPressed = function() return 0 end,
        getButtonsRepeated = function() return 0 end,
        setRepeat = function() end,
        clearState = function() end,
    },
    audio = { playTone = function() end },
    game = {
        save = {
            get = function(name)
                SAVE_LOG[#SAVE_LOG + 1] = { "get", name }
                return SAVES[name]
            end,
            set = function(name, value)
                SAVE_LOG[#SAVE_LOG + 1] = { "set", name }
                SAVES[name] = value
            end,
        },
    },
}

function reset_calls() CALLS = {} end

function count_calls(name)
    local n = 0
    for _, c in ipairs(CALLS) do
        if c[1] == name then n = n + 1 end
    end
    return n
end

-- ── Tiny test framework ─────────────────────────────────────────────────────

local tests = {}

function test(name, fn) tests[#tests + 1] = { name = name, fn = fn } end

function eq(actual, expected, what)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", what or "value",
            tostring(expected), tostring(actual)), 2)
    end
end

function truthy(v, what)
    if not v then error((what or "value") .. ": expected truthy, got " .. tostring(v), 2) end
end

function raises(fn, what)
    local ok = pcall(fn)
    if ok then error((what or "call") .. ": expected an error", 2) end
end

-- Load a library once; test files call need("lib/grid.lua") etc.
-- lcd.lua sets the LCD, SFX and PAD globals the way main.lua relies on.
local LOADED = {}
function need(path)
    if LOADED[path] == nil then LOADED[path] = dofile(path) or true end
    return LOADED[path]
end

local files = {}
for _, f in ipairs(arg) do files[#files + 1] = f end
if #files == 0 then
    local p = io.popen("ls dev/test/test_*.lua")
    for f in p:lines() do files[#files + 1] = f end
    p:close()
end
for _, f in ipairs(files) do dofile(f) end

local fails = 0
for _, t in ipairs(tests) do
    reset_calls()
    SAVES, SAVE_LOG = {}, {}
    local ok, err = pcall(t.fn)
    if ok then
        print("PASS  " .. t.name)
    else
        fails = fails + 1
        print("FAIL  " .. t.name .. "\n      " .. tostring(err))
    end
end
print(string.format("\n%d tests, %d failed", #tests, fails))
os.exit(fails == 0 and 0 or 1)
