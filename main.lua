-- BRICK-30 — 15 classic LCD brick games in one cart for PicoDeck.
-- Entry point: loads lib + games, wires the scene manager, runs the loop.

local pc = picocalc
local disp = pc.display

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

-- ── Load shared lib (sets globals LCD, SFX, PAD) ─────────────────────────────

load_module("lib/lcd")
local menu_mod = load_module("lib/menu")

-- ── Game registry ────────────────────────────────────────────────────────────

local GAMES = {
    { id = "tetris",  name = "TETRIS" },
    { id = "snake",   name = "SNAKE" },
    { id = "breakout", name = "BREAKOUT" },
    { id = "invaders", name = "INVADERS" },
    { id = "frogger", name = "FROGGER" },
    { id = "racer",   name = "RACER" },
    { id = "pong",    name = "PONG" },
    { id = "copter",  name = "COPTER" },
    { id = "asteroids", name = "ASTEROIDS" },
    { id = "memory",  name = "MEMORY" },
    { id = "simon",   name = "SIMON" },
    { id = "tictactoe", name = "TIC-TAC-TOE" },
    { id = "moonlander", name = "MOON LANDER" },
    { id = "missile", name = "MISSILE CMD" },
    { id = "tank",    name = "TANK" },
}

-- ── Load game modules; only loaded games join the registry ─────────────────

local registry = {}
for _, g in ipairs(GAMES) do
    local ok, factory = pcall(function() return load_module("games/" .. g.id).new end)
    if ok then
        registry[#registry + 1] = {
            num = string.format("%02d", #registry + 1),
            name = g.name,
            id = g.id,
            factory = factory,
        }
    end
end

-- ── Register one wrapper scene per game ──────────────────────────────────────

for _, g in ipairs(registry) do
    local factory = g.factory
    local inst
    local sc = {}

    function sc:enter()
        picocalc.input.clearState()
        inst = factory()
        if inst.enter then inst:enter() end
    end

    function sc:update()
        if inst then inst:update() end
    end

    function sc:draw()
        if inst then inst:draw() end
    end

    function sc:exit()
        if inst and inst.exit then inst:exit() end
        inst = nil
        picocalc.input.clearState()
    end

    pc.game.scene.add("game_" .. g.id, sc)
end

-- ── Menu + main loop ────────────────────────────────────────────────────────

local menu_scene = menu_mod.new(registry)
pc.game.scene.add("menu", menu_scene)
pc.game.scene.switch("menu")

while true do
    pc.input.update()
    pc.game.scene.update()
    pc.game.scene.draw()
    SFX.update(pc.sys.getTimeMs())
    if menu_scene.quit then return end
    pc.sys.sleep(16)
end
