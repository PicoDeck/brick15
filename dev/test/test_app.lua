-- Whole-app checks for the spec's acceptance criteria that don't need a device.

local function read(path)
    local f = assert(io.open(path, "r"))
    local s = f:read("a")
    f:close()
    return s
end

local MENU_ORDER = {
    "tetris", "snake", "breakout", "invaders", "frogger",
    "racer", "pong", "copter", "asteroids", "memory",
    "simon", "tictactoe", "moonlander", "missile", "tank",
}

test("app: the manifest is BRICK-15", function()
    local manifest = read("app.json")
    truthy(manifest:find('"id": "net.picodeck.brick15"', 1, true), "id")
    truthy(manifest:find('"name": "BRICK-15"', 1, true), "name")
    truthy(not manifest:lower():find("brick30", 1, true), "no BRICK-30 left")
end)

test("app: main.lua loads all 15 games in menu order", function()
    local list = read("main.lua"):match("GAME_IDS = (%b{})")
    local ids = {}
    for id in list:gmatch('"([%w]+)"') do ids[#ids + 1] = id end
    eq(#ids, 15, "games")
    for i, id in ipairs(MENU_ORDER) do
        eq(ids[i], id, "game " .. i)
        truthy(io.open("games/" .. id .. ".lua"), "games/" .. id .. ".lua exists")
    end
end)

test("app: games draw only through the grid", function()
    for _, id in ipairs(MENU_ORDER) do
        local src = read("games/" .. id .. ".lua")
        -- no display, save or scene calls, and no Esc handling
        truthy(not src:find("picocalc", 1, true), id .. ": uses picocalc directly")
        truthy(not src:find("%.esc"), id .. ": handles Esc")
    end
end)

test("app: every game module meets the contract", function()
    need("dev/test/game_helpers.lua")
    for _, id in ipairs(MENU_ORDER) do
        local mod = need("games/" .. id .. ".lua")
        eq(mod.id, id, "id of games/" .. id)
        check_contract(mod, id, mod.name)
    end
end)
