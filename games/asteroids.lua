-- asteroids.lua — game 09: rotate, thrust and shoot the rocks apart.
-- Everything wraps around the grid edges.
-- Game contract: see lib/runner.lua. Needs the SFX global.

local COLS, ROWS = 10, 20
local TICK_MS = 50                -- ship physics tick
local ACCEL = 0.06                -- cells/tick added per tick of thrust
local MAX_SPEED = 0.5             -- cells/tick
local FRICTION = 0.96
local BULLET_MS = 45
local BULLET_RANGE = 10           -- cells a bullet flies
local MAX_BULLETS = 3
local ROCK_MS = 450               -- rock step at speed 1, level 1
local SAFE_MS = 2000              -- invulnerable after a respawn
local ROCK_SCORE = { [3] = 20, [2] = 50, [1] = 100 }

-- Directions clockwise from up; the ship pattern for each.
local DIRS = {
    { 0, -1, { ".#.", "###", "#.#" } },   -- up
    { 1, -1, { "..#", "##.", ".#." } },   -- up-right
    { 1, 0,  { "##.", ".##", "##." } },   -- right
    { 1, 1,  { ".#.", "##.", "..#" } },   -- down-right
    { 0, 1,  { "#.#", "###", ".#." } },   -- down
    { -1, 1, { ".#.", ".##", "#.." } },   -- down-left
    { -1, 0, { ".##", "##.", ".##" } },   -- left
    { -1, -1, { "#..", ".##", ".#." } },  -- up-left
}

local ROCK_SHAPES = {
    [3] = { "###", "#.#", "###" },   -- hollow, so rocks never look like the solid ship
    [2] = { "##", "##" },
    [1] = { "#" },
}

-- Big rocks start in the corners and edges, away from the ship.
local SPAWNS = { { 1, 1 }, { 8, 1 }, { 1, 17 }, { 8, 17 }, { 4, 1 } }

local DEMO = {
    {
        "###.......",
        "#.#.....##",
        "###.....##",
        "..........",
        "....#.....",
        "..........",
        "....#.....",
        "...###....",
        "...#.#....",
        "..........",
        "......###.",
        "......#.#.",
    },
    {
        ".###......",
        ".#.#....##",
        ".###....##",
        "....#.....",
        "..........",
        "..........",
        "....#.....",
        "...###....",
        "...#.#....",
        "..........",
        ".......###",
        ".......#.#",
    },
}

local function wrap_c(c) return (c - 1) % COLS + 1 end
local function wrap_r(r) return (r - 1) % ROWS + 1 end

local function new(ctx)
    local game = { score = 0, level = 1, lives = 3, bullets = {}, rocks = {} }

    local function place_ship()
        game.x, game.y, game.vx, game.vy, game.dir = 5.5, 10.5, 0, 0, 1
    end

    local function new_wave()
        game.rocks = {}
        for i = 1, math.min(#SPAWNS, 2 + game.level) do
            local dx, dy
            repeat dx, dy = math.random(-1, 1), math.random(-1, 1) until dx ~= 0 or dy ~= 0
            game.rocks[i] = { size = 3, x = SPAWNS[i][1], y = SPAWNS[i][2], dx = dx, dy = dy }
        end
    end

    -- Cells (wrapped) of a pattern whose top-left is (x, y), as "c,r" keys.
    local function cells(pattern, x, y, out)
        out = out or {}
        for dy = 1, #pattern do
            for dx = 1, #pattern[dy] do
                if string.sub(pattern[dy], dx, dx) == "#" then
                    out[wrap_c(x + dx - 1) .. "," .. wrap_r(y + dy - 1)] = true
                end
            end
        end
        return out
    end

    local function ship_cells()
        return cells(DIRS[game.dir][3], math.floor(game.x) - 1, math.floor(game.y) - 1)
    end

    local function rock_cells(rock)
        return cells(ROCK_SHAPES[rock.size], rock.x, rock.y)
    end

    local function split(i)
        local rock = table.remove(game.rocks, i)
        game.score = game.score + ROCK_SCORE[rock.size]
        SFX.hit()
        if rock.size > 1 then
            -- the halves fly off at right angles to the parent
            local a = { size = rock.size - 1, x = rock.x, y = rock.y, dx = -rock.dy, dy = rock.dx }
            local b = { size = rock.size - 1, x = rock.x, y = rock.y, dx = rock.dy, dy = -rock.dx }
            table.insert(game.rocks, a)
            table.insert(game.rocks, b)
        end
    end

    -- Remove bullets that sit on a rock, splitting that rock.
    local function bullets_vs_rocks()
        local kept = {}
        for _, b in ipairs(game.bullets) do
            local hit = false
            for i, rock in ipairs(game.rocks) do
                if rock_cells(rock)[b.x .. "," .. b.y] then split(i) hit = true break end
            end
            if not hit then kept[#kept + 1] = b end
        end
        game.bullets = kept
    end

    local function ship_hit(now)
        if now < game.safe_until then return nil end
        local mine = ship_cells()
        for _, rock in ipairs(game.rocks) do
            for key in pairs(rock_cells(rock)) do
                if mine[key] then
                    game.lives = game.lives - 1
                    SFX.over()
                    if game.lives <= 0 then return "over" end
                    place_ship()
                    game.safe_until = now + SAFE_MS
                    return nil
                end
            end
        end
        return nil
    end

    function game:update(pad, now)
        self.now = now
        if pad.repeated.left then self.dir = (self.dir - 2) % 8 + 1 end
        if pad.repeated.right then self.dir = self.dir % 8 + 1 end
        if (pad.pressed.enter or pad.pressed.f1) and #self.bullets < MAX_BULLETS then
            local d = DIRS[self.dir]
            self.bullets[#self.bullets + 1] = {
                x = wrap_c(math.floor(self.x) + d[1]), y = wrap_r(math.floor(self.y) + d[2]),
                dx = d[1], dy = d[2], left = BULLET_RANGE }
            SFX.move()
        end

        if now >= self.next_tick then
            self.next_tick = now + TICK_MS
            if pad.held.up then
                local d = DIRS[self.dir]
                self.vx, self.vy = self.vx + d[1] * ACCEL, self.vy + d[2] * ACCEL
            end
            local speed = math.sqrt(self.vx * self.vx + self.vy * self.vy)
            if speed > MAX_SPEED then
                self.vx, self.vy = self.vx * MAX_SPEED / speed, self.vy * MAX_SPEED / speed
            end
            self.vx, self.vy = self.vx * FRICTION, self.vy * FRICTION
            self.x = (self.x + self.vx - 1) % COLS + 1
            self.y = (self.y + self.vy - 1) % ROWS + 1
        end

        if now >= self.next_bullet then
            self.next_bullet = now + BULLET_MS
            local kept = {}
            for _, b in ipairs(self.bullets) do
                b.x, b.y, b.left = wrap_c(b.x + b.dx), wrap_r(b.y + b.dy), b.left - 1
                if b.left > 0 then kept[#kept + 1] = b end
            end
            self.bullets = kept
        end
        bullets_vs_rocks()

        if now >= self.next_rock then
            self.next_rock = now + ctx.interval(ROCK_MS, self.level)
            for _, rock in ipairs(self.rocks) do
                rock.x, rock.y = wrap_c(rock.x + rock.dx), wrap_r(rock.y + rock.dy)
            end
            bullets_vs_rocks()
        end

        if #self.rocks == 0 then
            self.level = self.level + 1
            SFX.levelup()
            new_wave()
            self.safe_until = now + SAFE_MS
            return nil
        end
        return ship_hit(now)
    end

    function game:draw(grid)
        for _, rock in ipairs(self.rocks) do
            for key in pairs(rock_cells(rock)) do
                local c, r = key:match("(%d+),(%d+)")
                grid:set(tonumber(c), tonumber(r), true)
            end
        end
        for _, b in ipairs(self.bullets) do grid:set(b.x, b.y, true) end
        local v = (self.now and self.now < self.safe_until) and "blink" or true
        for key in pairs(ship_cells()) do
            local c, r = key:match("(%d+),(%d+)")
            grid:set(tonumber(c), tonumber(r), v)
        end
    end

    place_ship()
    new_wave()
    game.safe_until = ctx.now + SAFE_MS
    game.next_tick = ctx.now + TICK_MS
    game.next_bullet = ctx.now + BULLET_MS
    game.next_rock = ctx.now + ctx.interval(ROCK_MS, game.level)
    return game
end

return {
    id = "asteroids",
    name = "ASTEROIDS",
    hint = { "< > TURN", "UP THRUST", "ENTER FIRE" },
    order = "high",
    demo = DEMO,
    new = new,
}
