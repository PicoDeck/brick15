-- snake.lua — game 02: eat the blinking food, don't hit the walls or yourself.
-- Game contract: see lib/runner.lua. Needs the SFX global.

local COLS, ROWS = 10, 20
local STEP_MS = 300        -- one cell per step at speed 1, level 1
local FOODS_PER_LEVEL = 5

local DEMO = {
    {
        "..........",
        "..........",
        "..######..",
        "..#.......",
        "..#.......",
        "..#####...",
        "..........",
        "......#...",
        "..........",
        "..........",
        "..........",
        "..........",
    },
    {
        "..........",
        "..........",
        "...#####..",
        "..##......",
        "..#.......",
        "..######..",
        "..........",
        "......#...",
        "..........",
        "..........",
        "..........",
        "..........",
    },
}

local function new(ctx)
    local game = {
        score = 0, level = 1, eaten = 0,
        body = { { x = 5, y = 10 }, { x = 4, y = 10 }, { x = 3, y = 10 } },
        dir = { x = 1, y = 0 },
    }
    game.next_dir = game.dir
    game.next_step = ctx.now + ctx.interval(STEP_MS, game.level)

    local function on_body(x, y)
        for _, s in ipairs(game.body) do
            if s.x == x and s.y == y then return true end
        end
        return false
    end

    -- A random free cell; false when the snake fills the field.
    function game:place_food()
        local free = {}
        for y = 1, ROWS do
            for x = 1, COLS do
                if not on_body(x, y) then free[#free + 1] = { x = x, y = y } end
            end
        end
        if #free == 0 then return false end
        self.food = free[math.random(#free)]
        return true
    end

    local TURNS = {
        up = { x = 0, y = -1 }, down = { x = 0, y = 1 },
        left = { x = -1, y = 0 }, right = { x = 1, y = 0 },
    }

    function game:update(pad, now)
        for key, d in pairs(TURNS) do
            -- turns must be at right angles to the heading: no reversing
            -- into yourself, even with two presses inside one step
            if pad.pressed[key] and d.x * self.dir.x + d.y * self.dir.y == 0 then
                self.next_dir = d
            end
        end
        if now < self.next_step then return nil end
        self.next_step = now + ctx.interval(STEP_MS, self.level)
        self.dir = self.next_dir

        local head = self.body[1]
        local nx, ny = head.x + self.dir.x, head.y + self.dir.y
        if nx < 1 or nx > COLS or ny < 1 or ny > ROWS then return "over" end
        local eating = self.food and nx == self.food.x and ny == self.food.y
        if not eating then table.remove(self.body) end   -- the tail moves on
        if on_body(nx, ny) then return "over" end
        table.insert(self.body, 1, { x = nx, y = ny })

        if eating then
            self.eaten = self.eaten + 1
            self.score = self.score + 10 * self.level
            self.level = self.eaten // FOODS_PER_LEVEL + 1
            SFX.eat()
            if not self:place_food() then
                self.status = { "CLEARED" }
                return "over"
            end
        end
        return nil
    end

    function game:draw(grid)
        for _, s in ipairs(self.body) do grid:set(s.x, s.y, true) end
        if self.food then grid:set(self.food.x, self.food.y, "blink") end
    end

    game:place_food()
    return game
end

return {
    id = "snake",
    name = "SNAKE",
    hint = { "D-PAD STEER" },
    messages = { "CLEARED" },
    order = "high",
    demo = DEMO,
    new = new,
}
