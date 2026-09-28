-- racer.lua — game 06: switch lanes to dodge oncoming cars.
-- Game contract: see lib/runner.lua. Needs the SFX global.

local ROWS = 20
local LANE_COL = { 3, 6 }         -- left column of each lane's 3-wide car
local PLAYER_ROW = 17             -- the player's car fills rows 17-20
local STEP_MS = 160               -- road speed at speed 1, level 1
local SPACING = 7                 -- rows from one car's top to the next's
local SPAWN_Y = -3                -- new cars start just above the screen
local CRASH_MS = 800              -- the road stops this long after a crash
local ROWS_PER_LEVEL = 100

local PLAYER = { ".#.", "###", ".#.", "#.#" }
local ONCOMING = { "#.#", ".#.", "###", ".#." }   -- upside down: facing you

local DEMO = {
    {
        "#...#.#..#",
        "#....#...#",
        ".....###..",
        ".....#....",
        "#........#",
        "#........#",
        "..........",
        "..........",
        "#...#....#",
        "#..###...#",
        "....#.....",
        "...#.#....",
    },
    {
        "..........",
        "#...#.#..#",
        "#....#...#",
        ".....###..",
        "......#...",
        "#........#",
        "#........#",
        "..........",
        "..........",
        "#.....#..#",
        "#....###.#",
        "......#...",
    },
}

local function new(ctx)
    local game = { score = 0, level = 1, lives = 3, lane = 1, distance = 0,
                   cars = {}, scroll = 0 }
    game.next_step = ctx.now + ctx.interval(STEP_MS, game.level)

    local function crash(now)
        game.lives = game.lives - 1
        SFX.over()
        game.cars = {}
        game.crash_until = now + CRASH_MS
        if game.lives <= 0 then return "over" end
        return nil
    end

    local function hits_player(car)
        return car.lane == game.lane and car.y + 3 >= PLAYER_ROW and car.y <= ROWS
    end

    function game:update(pad, now)
        if pad.pressed.left and self.lane > 1 then self.lane = self.lane - 1 SFX.move() end
        if pad.pressed.right and self.lane < #LANE_COL then self.lane = self.lane + 1 SFX.move() end

        if self.crash_until and now < self.crash_until then return nil end
        self.crash_until = nil
        for _, car in ipairs(self.cars) do
            if hits_player(car) then return crash(now) end   -- you steered into it
        end
        if now < self.next_step then return nil end
        self.next_step = now + ctx.interval(STEP_MS, self.level)

        self.scroll = self.scroll + 1
        self.distance = self.distance + 1
        self.score = self.score + 1
        self.level = self.distance // ROWS_PER_LEVEL + 1

        local kept, top = {}, math.huge
        for _, car in ipairs(self.cars) do
            car.y = car.y + 1
            if car.y > ROWS then
                self.score = self.score + 10         -- passed it
            else
                kept[#kept + 1] = car
                top = math.min(top, car.y)
            end
        end
        self.cars = kept
        for _, car in ipairs(self.cars) do
            if hits_player(car) then return crash(now) end
        end
        if top - SPAWN_Y >= SPACING then            -- room for a new car above
            self.cars[#self.cars + 1] = { lane = math.random(#LANE_COL), y = SPAWN_Y }
        end
        return nil
    end

    function game:draw(grid)
        for r = 1, ROWS do
            if (r + self.scroll) % 4 < 2 then
                grid:set(1, r, true)
                grid:set(10, r, true)
            end
        end
        for _, car in ipairs(self.cars) do grid:stamp(ONCOMING, LANE_COL[car.lane], car.y) end
        local v = self.crash_until and "blink" or true
        if LANE_COL[self.lane] then grid:stamp(PLAYER, LANE_COL[self.lane], PLAYER_ROW, v) end
    end

    return game
end

return {
    id = "racer",
    name = "RACER",
    hint = { "< > CHANGE LANE" },
    order = "high",
    demo = DEMO,
    new = new,
}
