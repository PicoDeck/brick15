-- BRICK-15 — 15 classic LCD brick games in one cart for PicoDeck.
-- Entry point: loads lib + games, wires the menu and play scenes, runs the loop.

local DEBUG = false   -- true: log draw and flush counts every second

local pc = picocalc

math.randomseed(pc.sys.getTimeMs())

-- ── Module loader (require/dofile are blocked) ───────────────────────────────

local function load_module(name)
    local path = APP_DIR .. "/" .. name .. ".lua"
    local handle = pc.fs.open(path, "r")
    if not handle then
        error("Cannot open module: " .. path)
    end
    local chunks = {}
    while true do
        local chunk = pc.fs.read(handle, 4096)
        if not chunk or #chunk == 0 then break end
        chunks[#chunks + 1] = chunk
    end
    pc.fs.close(handle)
    return load(table.concat(chunks), "@" .. name .. ".lua")()
end

-- ── Shared lib (lcd sets globals LCD, SFX, PAD) ─────────────────────────────

load_module("lib/lcd")
local Grid = load_module("lib/grid")
local Panel = load_module("lib/panel")
local Screen = load_module("lib/screen")
local Scores = load_module("lib/scores")
local Runner = load_module("lib/runner")
local Menu = load_module("lib/menu")

-- ── Games, in menu order; a game that fails to load is left out ─────────────

local GAME_IDS = {
    "tetris", "snake", "breakout", "invaders", "frogger",
    "racer", "pong", "copter", "asteroids", "memory",
    "simon",
}

local games = {}
for _, id in ipairs(GAME_IDS) do
    local ok, def = pcall(load_module, "games/" .. id)
    if ok then
        games[#games + 1] = def
    else
        pc.sys.log("[brick15] skipped " .. id .. ": " .. tostring(def))
    end
end
if #games == 0 then error("BRICK-15: no games loaded") end

-- ── Debug counters ───────────────────────────────────────────────────────────

local stats = { draws = 0, flushes = 0, since = pc.sys.getTimeMs() }
if DEBUG then
    local disp = pc.display
    for _, fn in ipairs({ "fillRect", "drawRect", "clear" }) do
        local raw = disp[fn]
        disp[fn] = function(...) stats.draws = stats.draws + 1 return raw(...) end
    end
    local raw_flush = disp.flushRegion
    disp.flushRegion = function(...) stats.flushes = stats.flushes + 1 return raw_flush(...) end
end

-- ── Scenes ───────────────────────────────────────────────────────────────────

local grid = Grid.new(10, 20, 12, 10)
local screen = Screen.new(pc.display, grid, Panel.new(Grid))
local scores = Scores.new(pc.game.save, games)
local clock = pc.sys.getTimeMs

local runner = Runner.new({ screen = screen, scores = scores, scene = pc.game.scene,
                            clock = clock, input = pc.input })
local menu = Menu.new({ screen = screen, games = games, scores = scores, runner = runner,
                        scene = pc.game.scene, clock = clock, input = pc.input })

-- The scene manager calls enter/update/draw/exit as plain functions (no self),
-- so each object gets a small adapter.
local function as_scene(obj)
    return {
        enter = function() obj:enter() end,
        exit = function() obj:exit() end,
        update = function() obj:update() end,
        draw = function() obj:draw() end,
    }
end

pc.game.scene.add("play", as_scene(runner))
pc.game.scene.add("menu", as_scene(menu))
pc.game.scene.switch("menu")

-- ── Main loop ───────────────────────────────────────────────────────────────

while true do
    pc.input.update()
    pc.game.scene.update()
    pc.game.scene.draw()
    local now = pc.sys.getTimeMs()
    SFX.update(now)
    if DEBUG and now - stats.since >= 1000 then
        pc.sys.log(string.format("[brick15] draws=%d flushes=%d", stats.draws, stats.flushes))
        stats.draws, stats.flushes, stats.since = 0, 0, now
    end
    if menu.quit then return end
    pc.sys.sleep(16)
end
