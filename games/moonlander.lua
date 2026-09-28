-- moonlander.lua — game 13: land gently on the blinking pad.
-- The lander blinks while it is falling too fast to land safely.
-- Game contract: see lib/runner.lua. Needs the SFX global.

local COLS, ROWS = 10, 20
local LANDER = { "###", "#.#" }
local TICK_MS = 60                -- physics tick at speed 1
local GRAVITY = 0.012             -- cells/tick added per tick at level 1
local THRUST = 0.03
local SIDE = 0.015
local MAX_VX, MAX_UP, MAX_DOWN = 0.3, 0.4, 0.6
local SAFE_VY, SAFE_VX = 0.15, 0.1
local FUEL = 160                  -- ticks of burn; NEXT shows one brick per 10
local REFUEL = 40                 -- fuel added after each landing

local DEMO = {
    {
        "..........",
        "...###....",
        "...#.#....",
        "..........",
        "..........",
        "..........",
        "..........",
        "..........",
        "#.........",
        "##...###.#",
        "###..###.#",
        "####.#####",
    },
    {
        "..........",
        "..........",
        "..........",
        "..........",
        "....###...",
        "....#.#...",
        "..........",
        "..........",
        "#.........",
        "##...###.#",
        "###..###.#",
        "####.#####",
    },
}

local function new(ctx)
    local game = { score = 0, level = 1, lives = 3, landings = 0, fuel = FUEL, heights = {},
                   next_label = "FUEL" }

    local function new_ground()
        for c = 1, COLS do game.heights[c] = math.random(2, 6) end
        game.pad = math.random(1, COLS - 2)
        local h = math.random(1, 3)
        for c = game.pad, game.pad + 2 do game.heights[c] = h end
    end

    local function new_lander()
        game.x, game.y = 5.5, 1
        game.vx, game.vy = (math.random() - 0.5) * 0.1, 0
    end

    local function top_row(c) return ROWS + 1 - game.heights[c] end

    -- Touching down: work out whether it was a landing or a crash.
    local function touch_down(left)
        local on_pad = left == game.pad
        if on_pad and game.vy <= SAFE_VY and math.abs(game.vx) <= SAFE_VX then
            game.landings = game.landings + 1
            game.level = game.landings + 1
            game.score = game.score + (50 + game.fuel // 2) * game.level
            game.fuel = math.min(FUEL, game.fuel + REFUEL)
            SFX.levelup()
            new_ground()
            new_lander()
            return nil
        end
        game.lives = game.lives - 1
        SFX.over()
        if game.lives <= 0 then return "over" end
        new_lander()
        return nil
    end

    function game:update(pad, now)
        if now < self.next_tick then return nil end
        self.next_tick = now + ctx.interval(TICK_MS, 1)

        self.vy = self.vy + GRAVITY * (1 + 0.15 * (self.level - 1))
        if self.fuel > 0 then
            if pad.held.up then self.vy = self.vy - THRUST self.fuel = self.fuel - 1 end
            if pad.held.left then self.vx = self.vx - SIDE self.fuel = math.max(0, self.fuel - 1) end
            if pad.held.right then self.vx = self.vx + SIDE self.fuel = math.max(0, self.fuel - 1) end
        end
        self.vx = math.max(-MAX_VX, math.min(MAX_VX, self.vx))
        self.vy = math.max(-MAX_UP, math.min(MAX_DOWN, self.vy))
        self.x = self.x + self.vx
        if self.x < 2 then self.x, self.vx = 2, 0 end
        if self.x >= COLS then self.x, self.vx = COLS - 0.001, 0 end
        self.y = self.y + self.vy
        if self.y < 1 then self.y, self.vy = 1, 0 end

        -- the lander's bottom row reaching the row above the ground is touchdown
        local left = math.floor(self.x) - 1
        local ground = math.huge
        for c = left, left + 2 do ground = math.min(ground, top_row(c)) end
        if math.floor(self.y) + 1 >= ground - 1 then
            self.y = ground - 2
            return touch_down(left)
        end
        return nil
    end

    function game:draw(grid, next)
        for c = 1, COLS do
            local top = top_row(c)
            for r = top, ROWS do grid:set(c, r, true) end
            if c >= self.pad and c <= self.pad + 2 then grid:set(c, top, "blink") end
        end
        local v = self.vy > SAFE_VY and "blink" or true
        grid:stamp(LANDER, math.floor(self.x) - 1, math.floor(self.y), v)
        for i = 1, math.ceil(self.fuel / 10) do
            next:set((i - 1) % 4 + 1, (i - 1) // 4 + 1, true)
        end
    end

    new_ground()
    new_lander()
    game.next_tick = ctx.now + ctx.interval(TICK_MS, 1)
    return game
end

return {
    id = "moonlander",
    name = "MOON LANDER",
    hint = { "UP THRUST", "< > DRIFT", "LAND SLOWLY" },
    order = "high",
    demo = DEMO,
    new = new,
}
