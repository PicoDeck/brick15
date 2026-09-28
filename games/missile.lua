-- missile.lua — game 14: protect 3 cities from falling missiles.
-- Aim the crosshair and set off explosions in the missiles' path.
-- Game contract: see lib/runner.lua. Needs the SFX global.

local COLS, ROWS = 10, 20
local CITY_COLS = { 2, 5, 8 }     -- each city is 2 bricks: col and col+1, row 20
local AMMO = 12
local MISSILE_MS = 450            -- missile step at speed 1, level 1
local SPAWN_MS = 1400             -- a new missile at most this often
local MAX_ON_SCREEN = 3
local BLAST = { { 150, 1 }, { 300, 2 }, { 450, 1 } }   -- age limit, radius

local DEMO = {
    {
        "#.........",
        ".#.......#",
        "..#.....#.",
        "........#.",
        "...#......",
        "..###.....",
        "...#......",
        "..........",
        "..........",
        "..........",
        "..........",
        ".##.##.##.",
    },
    {
        "..........",
        "#.........",
        ".#........",
        "..#.....#.",
        "...#...#..",
        "..###.....",
        ".#####....",
        "..###.....",
        "...#......",
        "..........",
        "..........",
        ".##.##.##.",
    },
}

-- Blast radius of explosion `e` at time `now`, or nil once it has faded.
local function radius(e, now)
    local age = now - e.t0
    for _, stage in ipairs(BLAST) do
        if age < stage[1] then return stage[2] end
    end
    return nil
end

local function new(ctx)
    local game = { score = 0, level = 1, ammo = AMMO, cx = 5, cy = 10,
                   missiles = {}, explosions = {}, cities = {} }
    for i, c in ipairs(CITY_COLS) do game.cities[i] = { x = c, alive = true } end

    local function start_wave(now)
        game.wave_total = 6 + 2 * game.level
        game.spawned = 0
        game.ammo = AMMO
        game.next_spawn = now + ctx.interval(SPAWN_MS, game.level)
    end

    local function cities_left()
        local n = 0
        for _, city in ipairs(game.cities) do if city.alive then n = n + 1 end end
        return n
    end

    local function spawn()
        local targets = {}
        for _, city in ipairs(game.cities) do
            if city.alive then
                targets[#targets + 1] = city.x
                targets[#targets + 1] = city.x + 1
            end
        end
        local x0 = math.random(COLS)
        game.missiles[#game.missiles + 1] = { x0 = x0, x = x0, y = 1, tx = targets[math.random(#targets)] }
        game.spawned = game.spawned + 1
    end

    local function blasted(m, now)
        for _, e in ipairs(game.explosions) do
            local r = radius(e, now)
            if r and math.abs(m.x - e.x) + math.abs(m.y - e.y) <= r then return true end
        end
        return false
    end

    local function land(m)
        for _, city in ipairs(game.cities) do
            if city.alive and (m.x == city.x or m.x == city.x + 1) then
                city.alive = false
                SFX.hit()
            end
        end
    end

    function game:update(pad, now)
        if pad.repeated.left and self.cx > 2 then self.cx = self.cx - 1 end
        if pad.repeated.right and self.cx < COLS - 1 then self.cx = self.cx + 1 end
        if pad.repeated.up and self.cy > 2 then self.cy = self.cy - 1 end
        if pad.repeated.down and self.cy < ROWS - 3 then self.cy = self.cy + 1 end
        if (pad.pressed.enter or pad.pressed.f1) and self.ammo > 0 then
            self.ammo = self.ammo - 1
            self.explosions[#self.explosions + 1] = { x = self.cx, y = self.cy, t0 = now }
            SFX.drop()
        end

        -- fade explosions, destroy missiles caught in one
        local live = {}
        for _, e in ipairs(self.explosions) do
            if radius(e, now) then live[#live + 1] = e end
        end
        self.explosions = live
        local kept = {}
        for _, m in ipairs(self.missiles) do
            if blasted(m, now) then
                self.score = self.score + 25 * self.level
                SFX.score()
            else
                kept[#kept + 1] = m
            end
        end
        self.missiles = kept

        if now >= self.next_step then
            self.next_step = now + ctx.interval(MISSILE_MS, self.level)
            kept = {}
            for _, m in ipairs(self.missiles) do
                m.y = m.y + 1
                m.x = m.x0 + math.floor((m.tx - m.x0) * (m.y - 1) / (ROWS - 1) + 0.5)
                if m.y >= ROWS then land(m) else kept[#kept + 1] = m end
            end
            self.missiles = kept
            self.lives = cities_left()
            if self.lives == 0 then return "over" end
        end

        if self.spawned < self.wave_total and #self.missiles < MAX_ON_SCREEN
           and now >= self.next_spawn then
            self.next_spawn = now + ctx.interval(SPAWN_MS, self.level)
            spawn()
        end

        if self.spawned >= self.wave_total and #self.missiles == 0 and #self.explosions == 0 then
            self.score = self.score + 50 * cities_left() + 5 * self.ammo
            self.level = self.level + 1
            SFX.levelup()
            start_wave(now)
        end
        return nil
    end

    function game:draw(grid, next)
        for _, city in ipairs(self.cities) do
            if city.alive then
                grid:set(city.x, ROWS, true)
                grid:set(city.x + 1, ROWS, true)
            end
        end
        for _, m in ipairs(self.missiles) do grid:set(m.x, m.y, true) end
        local now = self.now or 0
        for _, e in ipairs(self.explosions) do
            local r = radius(e, now) or 0
            for dy = -r, r do
                for dx = -r, r do
                    if math.abs(dx) + math.abs(dy) <= r then grid:set(e.x + dx, e.y + dy, true) end
                end
            end
        end
        grid:stamp({ ".#.", "###", ".#." }, self.cx - 1, self.cy - 1, "blink")
        for i = 1, self.ammo do next:set((i - 1) % 4 + 1, (i - 1) // 4 + 1, true) end
    end

    game.lives = cities_left()
    game.next_step = ctx.now + ctx.interval(MISSILE_MS, game.level)
    start_wave(ctx.now)
    return game
end

return {
    id = "missile",
    name = "MISSILE CMD",
    hint = { "D-PAD AIM", "ENTER FIRE" },
    order = "high",
    demo = DEMO,
    new = new,
    radius = radius,
}
