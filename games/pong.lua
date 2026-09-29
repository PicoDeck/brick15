-- pong.lua — game 07: vertical Pong against the CPU, first to 7.
-- Your paddle is on row 20, the CPU's on row 1.
-- Game contract: see lib/runner.lua. Needs the SFX global.

local COLS, ROWS = 10, 20
local PADDLE_W = 3
local WIN_POINTS = 7
local STEP_MS = 120               -- ball speed at speed 1
local AI_MS = 170                 -- CPU paddle speed at speed 1

local DEMO = {
    {
        "...###....",
        "..........",
        "..........",
        ".....#....",
        "..........",
        "..........",
        "..........",
        "..........",
        "..........",
        "..........",
        "..........",
        "....###...",
    },
    {
        "....###...",
        "..........",
        "..........",
        "..........",
        "..........",
        "..........",
        "..........",
        "..#.......",
        "..........",
        "..........",
        "..........",
        "...###....",
    },
}

local function new(ctx)
    -- score = your points (the record); score_text shows "you-cpu"
    local game = { score = 0, cpu_points = 0, player = 4, cpu = 4 }
    game.next_ai = ctx.now + ctx.interval(AI_MS, 1)

    local function refresh()
        game.score_text = string.format("%02d-%02d", game.score, game.cpu_points)
    end

    local function serve_position()
        game.serving = true
        game.ball = { x = game.player + 1, y = ROWS - 1, dx = 1, dy = -1 }
    end

    local function covers(left, x) return x >= left and x <= left + PADDLE_W - 1 end

    -- Bounce off a paddle whose left cell is `left`, landing at column nx.
    local function paddle_bounce(b, left, nx)
        b.dy = -b.dy
        if nx == left then b.dx = -1 elseif nx == left + PADDLE_W - 1 then b.dx = 1 end
        SFX.rotate()
    end

    local function point(for_player)
        if for_player then game.score = game.score + 1 SFX.score()
        else game.cpu_points = game.cpu_points + 1 SFX.hit() end
        refresh()
        if game.score >= WIN_POINTS then game.status = { "YOU WIN" } return "over" end
        if game.cpu_points >= WIN_POINTS then game.status = { "CPU WINS" } return "over" end
        serve_position()
        return nil
    end

    local function step_ball()
        local b = game.ball
        if b.x + b.dx < 1 or b.x + b.dx > COLS then b.dx = -b.dx end
        local nx = b.x + b.dx
        if b.dy == 1 and b.y + 1 == ROWS then
            if covers(game.player, nx) then paddle_bounce(b, game.player, nx) return nil end
            return point(false)
        end
        if b.dy == -1 and b.y - 1 == 1 then
            if covers(game.cpu, nx) then paddle_bounce(b, game.cpu, nx) return nil end
            return point(true)
        end
        b.x, b.y = nx, b.y + b.dy
        return nil
    end

    function game:update(pad, now)
        if pad.repeated.left and self.player > 1 then self.player = self.player - 1 end
        if pad.repeated.right and self.player < COLS - PADDLE_W + 1 then self.player = self.player + 1 end

        -- CPU: chase a ball heading its way, otherwise drift back to the middle
        if now >= self.next_ai then
            self.next_ai = now + ctx.interval(AI_MS, 1)
            local target = (self.ball.dy == -1 and not self.serving) and self.ball.x or 5
            local centre = self.cpu + 1
            if target < centre and self.cpu > 1 then self.cpu = self.cpu - 1
            elseif target > centre and self.cpu < COLS - PADDLE_W + 1 then self.cpu = self.cpu + 1 end
        end

        if self.serving then
            self.ball.x = self.player + 1
            if pad.pressed.enter or pad.pressed.up or pad.pressed.f1 then
                self.serving = false
                self.ball.dx = math.random(2) == 1 and -1 or 1
                self.next_step = now + ctx.interval(STEP_MS, 1)
            end
            return nil
        end
        if now < self.next_step then return nil end
        self.next_step = now + ctx.interval(STEP_MS, 1)
        return step_ball()
    end

    function game:draw(grid)
        for i = 0, PADDLE_W - 1 do
            grid:set(self.player + i, ROWS, true)
            grid:set(self.cpu + i, 1, true)
        end
        grid:set(self.ball.x, self.ball.y, true)
    end

    refresh()
    serve_position()
    return game
end

return {
    id = "pong",
    name = "PONG",
    hint = { "YOU: BOTTOM PAD", "< > MOVE", "ENTER SERVE" },
    messages = { "YOU WIN", "CPU WINS" },
    order = "high",
    demo = DEMO,
    new = new,
}
