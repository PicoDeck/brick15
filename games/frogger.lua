-- frogger.lua — game 05: cross the road, ride the logs, fill the 5 homes.
-- Rows: 1 homes, 2-7 river, 8-9 bank, 10-18 road, 19-20 start.
-- Game contract: see lib/runner.lua. Needs the SFX global.

local COLS, ROWS = 10, 20
local START_X, START_Y = 5, 20
local HOME_COLS = { 1, 3, 5, 7, 9 }   -- walls stand on the even columns

-- Each lane is a 10-cell loop ('#' = log or car) that shifts one cell every
-- `ms` in `dir`. Cars are 2 long, logs 4-5 long.
local LANES = {
    [2]  = { kind = "river", pattern = "#####.....", dir = -1, ms = 700 },
    [3]  = { kind = "river", pattern = "####.####.", dir = 1,  ms = 900 },
    [4]  = { kind = "river", pattern = "#####.....", dir = -1, ms = 600 },
    [5]  = { kind = "river", pattern = "####.####.", dir = 1,  ms = 800 },
    [6]  = { kind = "river", pattern = "#####.....", dir = -1, ms = 750 },
    [7]  = { kind = "river", pattern = "####.####.", dir = 1,  ms = 650 },
    [10] = { kind = "road",  pattern = "##....##..", dir = 1,  ms = 500 },
    [11] = { kind = "road",  pattern = "##........", dir = -1, ms = 350 },
    [12] = { kind = "road",  pattern = "##...##...", dir = 1,  ms = 700 },
    [13] = { kind = "road",  pattern = "##........", dir = -1, ms = 450 },
    [14] = { kind = "road",  pattern = "##....##..", dir = 1,  ms = 600 },
    [15] = { kind = "road",  pattern = "##...##...", dir = -1, ms = 800 },
    [16] = { kind = "road",  pattern = "##........", dir = 1,  ms = 400 },
    [17] = { kind = "road",  pattern = "##....##..", dir = -1, ms = 550 },
    [18] = { kind = "road",  pattern = "##........", dir = 1,  ms = 650 },
}

local DEMO = {
    {
        "#.#.#.#.#.",
        "#####.....",
        "..####.###",
        "..........",
        "##....##..",
        "....##....",
        "##...##...",
        "..........",
        "..........",
        "..........",
        "..........",
        "....#.....",
    },
    {
        "#.#.#.#.#.",
        ".#####....",
        ".####.###.",
        "..........",
        ".##....##.",
        "...##.....",
        ".##...##..",
        "..........",
        "..........",
        "..........",
        "....#.....",
        "..........",
    },
}

local function occupied(lane, c)
    local i = (c - 1 - lane.offset) % COLS + 1
    return string.sub(lane.pattern, i, i) == "#"
end

local function new(ctx)
    local game = { score = 0, level = 1, lives = 3, homes = {}, lanes = {} }
    for _, c in ipairs(HOME_COLS) do game.homes[c] = false end
    for row, def in pairs(LANES) do
        game.lanes[row] = { kind = def.kind, pattern = def.pattern, dir = def.dir, ms = def.ms,
                            offset = math.random(0, COLS - 1),
                            next_shift = ctx.now + ctx.interval(def.ms, 1) }
    end

    local function reset_frog()
        game.fx, game.fy = START_X, START_Y
        game.best = START_Y           -- furthest row reached by this frog
    end

    local function hazard()
        local lane = game.lanes[game.fy]
        if not lane then return false end
        if lane.kind == "road" then return occupied(lane, game.fx) end
        return not occupied(lane, game.fx)          -- river: must be on a log
    end

    local function die()
        game.lives = game.lives - 1
        SFX.over()
        if game.lives <= 0 then return "over" end
        reset_frog()
        return nil
    end

    local function reach_home(c)
        if game.homes[c] ~= false then return die() end   -- wall or filled home
        game.homes[c] = true
        game.score = game.score + 50 * game.level
        SFX.score()
        local all = true
        for _, filled in pairs(game.homes) do all = all and filled end
        if all then
            game.level = game.level + 1
            game.score = game.score + 100
            for _, h in ipairs(HOME_COLS) do game.homes[h] = false end
            SFX.levelup()
        end
        reset_frog()
        return nil
    end

    local HOPS = { { "up", 0, -1 }, { "down", 0, 1 }, { "left", -1, 0 }, { "right", 1, 0 } }

    function game:update(pad, now)
        for _, h in ipairs(HOPS) do
            if pad.pressed[h[1]] then
                local nx = math.max(1, math.min(COLS, self.fx + h[2]))
                local ny = math.max(1, math.min(ROWS, self.fy + h[3]))
                if ny == 1 then return reach_home(nx) end
                self.fx, self.fy = nx, ny
                SFX.move()
                if self.fy < self.best then
                    self.best = self.fy
                    self.score = self.score + 10
                end
                if hazard() then return die() end
                break
            end
        end

        for row, lane in pairs(self.lanes) do
            if now >= lane.next_shift then
                lane.next_shift = now + ctx.interval(lane.ms, self.level)
                lane.offset = (lane.offset + lane.dir) % COLS
                if lane.kind == "river" and self.fy == row then
                    self.fx = self.fx + lane.dir
                    if self.fx < 1 or self.fx > COLS then return die() end
                end
            end
        end
        if hazard() then return die() end
        return nil
    end

    function game:draw(grid)
        for c = 1, COLS do
            if self.homes[c] ~= false then grid:set(c, 1, true) end   -- walls and filled homes
        end
        for row, lane in pairs(self.lanes) do
            for c = 1, COLS do
                if occupied(lane, c) then grid:set(c, row, true) end
            end
        end
        grid:set(self.fx, self.fy, "blink")
    end

    reset_frog()
    return game
end

return {
    id = "frogger",
    name = "FROGGER",
    hint = { "D-PAD HOP", "RIDE THE LOGS" },
    order = "high",
    demo = DEMO,
    new = new,
}
