-- breakout.lua — game 03: knock out 4 rows of bricks with a 1-brick ball.
-- Game contract: see lib/runner.lua. Needs the SFX global.

local COLS, ROWS = 10, 20
local BRICK_ROWS = { 2, 3, 4, 5 }
local PADDLE_W = 3
local STEP_MS = 150        -- ball speed at speed 1, level 1

local DEMO = {
    {
        "##########",
        "##########",
        "###..#####",
        "##########",
        "..........",
        "..........",
        "....#.....",
        "..........",
        "..........",
        "..........",
        "..........",
        "...###....",
    },
    {
        "##########",
        "##########",
        "###..#####",
        "##########",
        "..........",
        "..........",
        "..........",
        "..........",
        "......#...",
        "..........",
        "..........",
        "....###...",
    },
}

local function new(ctx)
    local game = { score = 0, level = 1, lives = 3, paddle = 4 }   -- paddle = left cell

    local function fill_bricks()
        game.bricks = {}
        for r = 1, ROWS do
            game.bricks[r] = {}
            for c = 1, COLS do game.bricks[r][c] = false end
        end
        for _, r in ipairs(BRICK_ROWS) do
            for c = 1, COLS do game.bricks[r][c] = true end
        end
    end

    local function serve_position()
        game.serving = true
        game.ball = { x = game.paddle + 1, y = ROWS - 1, dx = 1, dy = -1 }
    end

    local function bricks_left()
        for _, r in ipairs(BRICK_ROWS) do
            for c = 1, COLS do
                if game.bricks[r][c] then return true end
            end
        end
        return false
    end

    local function hit_brick(x, y)
        if y >= 1 and y <= ROWS and x >= 1 and x <= COLS and game.bricks[y][x] then
            game.bricks[y][x] = false
            game.score = game.score + 10 * game.level
            SFX.hit()
            return true
        end
        return false
    end

    -- One ball step. Returns "lost" when the ball gets past the paddle.
    local function step_ball()
        local b = game.ball
        if b.x + b.dx < 1 or b.x + b.dx > COLS then b.dx = -b.dx SFX.move() end
        if b.y + b.dy < 1 then b.dy = 1 SFX.move() end

        -- bricks: straight up/down first, then sideways, then the corner
        if hit_brick(b.x, b.y + b.dy) then b.dy = -b.dy return end
        if hit_brick(b.x + b.dx, b.y) then b.dx = -b.dx return end
        if hit_brick(b.x + b.dx, b.y + b.dy) then b.dx, b.dy = -b.dx, -b.dy return end

        -- paddle on the bottom row
        if b.dy == 1 and b.y + 1 == ROWS then
            local nx = b.x + b.dx
            local p = game.paddle
            if nx >= p and nx <= p + PADDLE_W - 1 then
                b.dy = -1
                if nx == p then b.dx = -1 elseif nx == p + PADDLE_W - 1 then b.dx = 1 end
                SFX.rotate()
                return
            end
        end

        b.x, b.y = b.x + b.dx, b.y + b.dy
        if b.y >= ROWS then return "lost" end   -- reached the paddle row uncaught
    end

    function game:update(pad, now)
        if pad.repeated.left and self.paddle > 1 then self.paddle = self.paddle - 1 end
        if pad.repeated.right and self.paddle < COLS - PADDLE_W + 1 then self.paddle = self.paddle + 1 end

        if self.serving then
            self.ball.x = self.paddle + 1
            if pad.pressed.enter or pad.pressed.up or pad.pressed.f1 then
                self.serving = false
                self.next_step = now + ctx.interval(STEP_MS, self.level)
            end
            return nil
        end

        if now < self.next_step then return nil end
        self.next_step = now + ctx.interval(STEP_MS, self.level)

        if step_ball() == "lost" then
            self.lives = self.lives - 1
            if self.lives <= 0 then return "over" end
            SFX.hit()
            serve_position()
            return nil
        end
        if not bricks_left() then
            self.level = self.level + 1
            SFX.levelup()
            fill_bricks()
            serve_position()
        end
        return nil
    end

    function game:draw(grid)
        for _, r in ipairs(BRICK_ROWS) do
            for c = 1, COLS do
                if self.bricks[r][c] then grid:set(c, r, true) end
            end
        end
        for i = 0, PADDLE_W - 1 do grid:set(self.paddle + i, ROWS, true) end
        grid:set(self.ball.x, self.ball.y, true)
    end

    fill_bricks()
    serve_position()
    return game
end

return {
    id = "breakout",
    name = "BREAKOUT",
    hint = { "< > MOVE", "ENTER SERVE" },
    order = "high",
    demo = DEMO,
    new = new,
}
