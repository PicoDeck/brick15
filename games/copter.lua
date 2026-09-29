-- copter.lua — game 08: steer through a tunnel that scrolls down at you.
-- Game contract: see lib/runner.lua. Needs the SFX global.

local COLS, ROWS = 10, 20
local SHIP = { ".#.", "###" }     -- nose on row 18, body on row 19
local SHIP_ROW = 18
local STEP_MS = 220               -- scroll speed at speed 1, level 1
local ROWS_PER_LEVEL = 60
local MIN_GAP = 4                 -- a 3-wide ship can't follow a 3-wide gap that shifts
local BLOCK_MIN_GAP = 6           -- blocks only appear in gaps this wide
local BLOCK_CHANCE = 0.12

local DEMO = {
    {
        "##.....###",
        "##.....###",
        "###.....##",
        "###..#..##",
        "###.....##",
        "####.....#",
        "###.....##",
        "###.....##",
        "##.....###",
        "##..#..###",
        "##.###.###",
        "##.....###",
    },
    {
        "##.....###",
        "##.....###",
        "##.....###",
        "###.....##",
        "###..#..##",
        "###.....##",
        "####.....#",
        "###.....##",
        "###.....##",
        "##.#...###",
        "######.###",
        "##.....###",
    },
}

local function new(ctx)
    local game = { score = 0, level = 1, x = 5, rows = {} }
    for r = 1, ROWS do game.rows[r] = { left = 1, right = 2 } end
    game.gen_left, game.gen_width = 1, 7             -- the gap of the newest row
    game.next_step = ctx.now + ctx.interval(STEP_MS, game.level)

    local function target_width()
        return math.max(MIN_GAP, 8 - game.level)
    end

    -- Next tunnel row. Per row the gap EITHER changes width by one OR shifts
    -- by one. The ship must fit both the rows before and after each scroll,
    -- so blocks only go in a row whose gap held still after a block-free
    -- row, and the row after a block holds still too (checked by the
    -- "perfect pilot" test).
    local function next_row()
        local left, width = game.gen_left, game.gen_width
        if game.gen_hold then
            game.gen_hold = false
        else
            local want = target_width()
            if width ~= want then
                if width > want then
                    width = width - 1
                    if math.random(2) == 1 then left = left + 1 end
                else
                    width = width + 1
                    if left > 0 and math.random(2) == 1 then left = left - 1 end
                end
            else
                local shift = math.random(-1, 1)
                if left + shift >= 0 and left + shift + width <= COLS then left = left + shift end
            end
            left = math.max(0, math.min(COLS - width, left))
        end
        local still = left == game.gen_left and width == game.gen_width
        game.gen_left, game.gen_width = left, width
        local row = { left = left, right = COLS - left - width }
        if still and not game.gen_block and width >= BLOCK_MIN_GAP
           and math.random() < BLOCK_CHANCE then
            -- one cell in from either wall, leaving a wide free run
            row.block = math.random(2) == 1 and left + 2 or left + width - 1
            game.gen_hold = true
        end
        game.gen_block = row.block ~= nil
        return row
    end

    function game:scroll()
        table.remove(self.rows)
        table.insert(self.rows, 1, next_row())
    end

    local function blocked(c, r)
        local row = game.rows[r]
        return c <= row.left or c > COLS - row.right or c == row.block
    end

    local function crashed()
        if blocked(game.x, SHIP_ROW) then return true end
        for c = game.x - 1, game.x + 1 do
            if blocked(c, SHIP_ROW + 1) then return true end
        end
        return false
    end

    function game:update(pad, now)
        if pad.repeated.left and self.x > 2 then self.x = self.x - 1 end
        if pad.repeated.right and self.x < COLS - 1 then self.x = self.x + 1 end
        if crashed() then return "over" end

        if now < self.next_step then return nil end
        self.next_step = now + ctx.interval(STEP_MS, self.level)
        self:scroll()
        self.score = self.score + 1
        self.level = self.score // ROWS_PER_LEVEL + 1
        if crashed() then return "over" end
        return nil
    end

    function game:draw(grid)
        for r, row in ipairs(self.rows) do
            for c = 1, row.left do grid:set(c, r, true) end
            for c = COLS - row.right + 1, COLS do grid:set(c, r, true) end
            if row.block then grid:set(row.block, r, true) end
        end
        grid:stamp(SHIP, self.x - 1, SHIP_ROW)
    end

    return game
end

return {
    id = "copter",
    name = "COPTER",
    hint = { "< > STEER" },
    order = "high",
    demo = DEMO,
    new = new,
}
