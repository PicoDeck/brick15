-- tank.lua — game 15: destroy the enemy tanks and protect your base.
-- Tanks are 3x3: yours is solid, the enemy's is hollow.
-- Game contract: see lib/runner.lua. Needs the SFX global.

local COLS, ROWS = 10, 20
local START_X, START_Y = 1, 18
local BASE = { { 5, 19 }, { 6, 19 }, { 5, 20 }, { 6, 20 } }
local SPAWNS = { { 1, 1 }, { 4, 1 }, { 8, 1 } }
local MAX_ENEMIES = 3
local ENEMY_MS = 450              -- enemy move at speed 1, level 1
local SPAWN_MS = 2000
local BULLET_MS = 60
local FIRE_CHANCE = 0.3

-- '#' walls; every wall row leaves 3-wide gaps so 3x3 tanks can pass.
local MAP = {
    "..........", "..........", "..........", "..........",
    "#...##...#", "#...##...#",
    "..........", "..........", "..........",
    "...####...", "...####...",
    "..........", "..........", "..........",
    "...####...", "...####...",
    "..........",
    "...####...", "...#..#...", "...#..#...",
}

local DIRS = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }
local PLAYER = {
    up = { ".#.", "###", "#.#" }, down = { "#.#", "###", ".#." },
    left = { ".##", "##.", ".##" }, right = { "##.", ".##", "##." },
}
local ENEMY = {
    up = { ".#.", "#.#", "#.#" }, down = { "#.#", "#.#", ".#." },
    left = { ".##", "#..", ".##" }, right = { "##.", "..#", "##." },
}
local ENEMY_TURNS = { "down", "down", "left", "right", "up" }   -- they drift toward you

local DEMO = {
    {
        "#.#.......",
        "#.#.......",
        ".#........",
        "......#...",
        "#...##...#",
        "#...##...#",
        "..........",
        "..........",
        "....#.....",
        ".#........",
        "###.####..",
        "#.#.#..#..",
    },
    {
        "..........",
        "#.#.......",
        "#.#.......",
        ".#........",
        "#...##...#",
        "#...##...#",
        "..........",
        "....#.....",
        "..........",
        ".#........",
        "###.####..",
        "#.#.#..#..",
    },
}

local function new(ctx)
    local game = { score = 0, level = 1, lives = 3, enemies = {}, bullets = {} }

    local function reset_walls()
        game.walls = {}
        for r = 1, ROWS do
            game.walls[r] = {}
            for c = 1, COLS do game.walls[r][c] = string.sub(MAP[r], c, c) == "#" end
        end
    end

    local function reset_player()
        game.player = { x = START_X, y = START_Y, dir = "up" }
    end

    local function start_wave(now)
        reset_walls()
        reset_player()
        game.enemies, game.bullets = {}, {}
        game.wave_total = 4 + 2 * game.level
        game.spawned, game.killed = 0, 0
        game.next_spawn = now + 500
    end

    local function is_base(c, r)
        for _, b in ipairs(BASE) do if b[1] == c and b[2] == r then return true end end
        return false
    end

    local function in_box(t, c, r)
        return c >= t.x and c <= t.x + 2 and r >= t.y and r <= t.y + 2
    end

    -- Can tank t (ignoring itself) have its top-left at (x, y)?
    local function free_box(t, x, y)
        if x < 1 or y < 1 or x + 2 > COLS or y + 2 > ROWS then return false end
        for r = y, y + 2 do
            for c = x, x + 2 do
                if game.walls[r][c] or (game.base_alive and is_base(c, r)) then return false end
            end
        end
        local tanks = { game.player }
        for _, e in ipairs(game.enemies) do tanks[#tanks + 1] = e end
        for _, o in ipairs(tanks) do
            if o ~= t and math.abs(o.x - x) < 3 and math.abs(o.y - y) < 3 then return false end
        end
        return true
    end

    local function drive(t, dir)
        t.dir = dir
        local d = DIRS[dir]
        if free_box(t, t.x + d[1], t.y + d[2]) then
            t.x, t.y = t.x + d[1], t.y + d[2]
            return true
        end
        return false
    end

    local function fire(t, owner)
        local d = DIRS[t.dir]
        -- the barrel is the middle of the facing side; the shot starts beyond it
        game.bullets[#game.bullets + 1] = {
            x = t.x + 1 + d[1] * 2, y = t.y + 1 + d[2] * 2,
            dx = d[1], dy = d[2], owner = owner, from = t }
    end

    local function player_shot_live()
        for _, b in ipairs(game.bullets) do if b.owner == "player" then return true end end
        return false
    end

    -- Resolve bullet b at its cell. Returns "gone", "over" or nil (keep flying).
    local function hit(b, now)
        if b.x < 1 or b.x > COLS or b.y < 1 or b.y > ROWS then return "gone" end
        if game.walls[b.y][b.x] then
            game.walls[b.y][b.x] = false
            SFX.hit()
            return "gone"
        end
        if game.base_alive and is_base(b.x, b.y) then
            game.base_alive = false
            game.status = { "BASE LOST" }
            SFX.over()
            return "over"
        end
        if b.owner == "player" then
            for i, e in ipairs(game.enemies) do
                if in_box(e, b.x, b.y) then
                    table.remove(game.enemies, i)
                    game.killed = game.killed + 1
                    game.score = game.score + 100 * game.level
                    SFX.score()
                    return "gone"
                end
            end
        elseif in_box(game.player, b.x, b.y) then
            game.lives = game.lives - 1
            SFX.over()
            if game.lives <= 0 then return "over" end
            reset_player()
            return "gone"
        end
        return nil
    end

    function game:update(pad, now)
        for dir in pairs(DIRS) do
            if pad.repeated[dir] then drive(self.player, dir) break end
        end
        if (pad.pressed.enter or pad.pressed.f1) and not player_shot_live() then
            fire(self.player, "player")
            SFX.move()
            local b = self.bullets[#self.bullets]
            local r = hit(b, now)
            if r == "over" then return "over" end
            if r == "gone" then table.remove(self.bullets) end
        end

        if now >= self.next_bullet then
            self.next_bullet = now + BULLET_MS
            local kept = {}
            for _, b in ipairs(self.bullets) do
                b.x, b.y = b.x + b.dx, b.y + b.dy
                local r = hit(b, now)
                if r == "over" then return "over" end
                if r ~= "gone" then kept[#kept + 1] = b end
            end
            self.bullets = kept
        end

        if self.killed >= self.wave_total then
            self.level = self.level + 1
            SFX.levelup()
            start_wave(now)
            return nil
        end

        if now >= self.next_spawn and self.spawned < self.wave_total and #self.enemies < MAX_ENEMIES then
            self.next_spawn = now + SPAWN_MS
            local s = SPAWNS[math.random(#SPAWNS)]
            local e = { x = s[1], y = s[2], dir = "down" }
            if free_box(e, e.x, e.y) then
                self.enemies[#self.enemies + 1] = e
                self.spawned = self.spawned + 1
            end
        end

        if now >= self.next_enemy then
            self.next_enemy = now + ctx.interval(ENEMY_MS, self.level)
            for _, e in ipairs(self.enemies) do
                if math.random() < 0.25 or not drive(e, e.dir) then
                    drive(e, ENEMY_TURNS[math.random(#ENEMY_TURNS)])
                end
                local has_shot = false
                for _, b in ipairs(self.bullets) do has_shot = has_shot or b.from == e end
                if not has_shot and math.random() < FIRE_CHANCE then fire(e, "enemy") end
            end
        end
        return nil
    end

    function game:draw(grid)
        for r = 1, ROWS do
            for c = 1, COLS do
                if self.walls[r][c] then grid:set(c, r, true) end
            end
        end
        if self.base_alive then
            for _, b in ipairs(BASE) do grid:set(b[1], b[2], "blink") end
        end
        for _, e in ipairs(self.enemies) do grid:stamp(ENEMY[e.dir], e.x, e.y) end
        grid:stamp(PLAYER[self.player.dir], self.player.x, self.player.y)
        for _, b in ipairs(self.bullets) do grid:set(b.x, b.y, true) end
    end

    game.base_alive = true
    start_wave(ctx.now)
    game.next_bullet = ctx.now + BULLET_MS
    game.next_enemy = ctx.now + ctx.interval(ENEMY_MS, game.level)
    return game
end

return {
    id = "tank",
    name = "TANK",
    hint = { "D-PAD DRIVE", "ENTER FIRE", "GUARD THE BASE" },
    messages = { "BASE LOST" },
    order = "high",
    demo = DEMO,
    new = new,
}
