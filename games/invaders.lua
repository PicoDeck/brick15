-- invaders.lua — game 04: shoot the marching block before it reaches you.
-- Game contract: see lib/runner.lua. Needs the SFX global.

local COLS, ROWS = 10, 20
local BLOCK_W, BLOCK_H = 4, 3    -- aliens, each with a clear cell around it
local SPACING = 2
local GUN_ROW = 19                -- gun is .#. on row 19, ### on row 20
local MARCH_MS = 600              -- block step at speed 1, level 1, full block
local BULLET_MS = 40
local BOMB_MS = 150               -- bomb fall step
local BOMB_EVERY_MS = 900         -- a new bomb at most this often
local MAX_BOMBS = 3

local DEMO = {
    {
        "..........",
        "#.#.#.#...",
        "..........",
        "#.#.#.#...",
        "..........",
        "#.#.#.#...",
        "..#.......",
        "..........",
        "..........",
        "..........",
        "....#.....",
        "...###....",
    },
    {
        "..........",
        ".#.#.#.#..",
        "..........",
        ".#.#.#.#..",
        "..........",
        ".#.#.#.#..",
        "....#.....",
        "..........",
        "..#.......",
        "....#.....",
        "....#.....",
        "...###....",
    },
}

local function new(ctx)
    local game = { score = 0, level = 1, lives = 3, gun = 5, bombs = {} }

    local function new_wave(now)
        game.aliens = {}
        for r = 1, BLOCK_H do
            for c = 1, BLOCK_W do
                game.aliens[#game.aliens + 1] = { c = c, r = r, alive = true }
            end
        end
        game.ox, game.oy = 1, 2          -- grid position of block cell (1,1)
        game.march_dir = 1
        game.bullet, game.bombs = nil, {}
        game.next_march = now + ctx.interval(MARCH_MS, game.level)
        game.next_bomb = now + BOMB_EVERY_MS
        game.next_bombs = now + BOMB_MS
    end

    function game:alien_pos(a)
        return self.ox + (a.c - 1) * SPACING, self.oy + (a.r - 1) * SPACING
    end

    local function alive_count()
        local n = 0
        for _, a in ipairs(game.aliens) do if a.alive then n = n + 1 end end
        return n
    end

    -- Columns of the live block's leftmost/rightmost aliens, and its lowest row.
    local function extent()
        local minx, maxx, maxy = COLS + 1, 0, 0
        for _, a in ipairs(game.aliens) do
            if a.alive then
                local x, y = game:alien_pos(a)
                minx, maxx, maxy = math.min(minx, x), math.max(maxx, x), math.max(maxy, y)
            end
        end
        return minx, maxx, maxy
    end

    local function gun_hit(x, y)
        return (y == GUN_ROW and x == game.gun)
            or (y == GUN_ROW + 1 and x >= game.gun - 1 and x <= game.gun + 1)
    end

    local function march_interval()
        -- the block speeds up as it thins out
        local frac = 0.4 + 0.6 * alive_count() / (BLOCK_W * BLOCK_H)
        return math.max(80, ctx.interval(MARCH_MS, game.level) * frac)
    end

    function game:update(pad, now)
        if pad.repeated.left and self.gun > 2 then self.gun = self.gun - 1 end
        if pad.repeated.right and self.gun < COLS - 1 then self.gun = self.gun + 1 end
        if (pad.pressed.up or pad.pressed.enter or pad.pressed.f1) and not self.bullet then
            self.bullet = { x = self.gun, y = GUN_ROW - 1 }
            self.next_bullet = now + BULLET_MS
            SFX.move()
        end

        -- player bullet
        if self.bullet and now >= self.next_bullet then
            self.next_bullet = now + BULLET_MS
            local b = self.bullet
            b.y = b.y - 1
            for _, a in ipairs(self.aliens) do
                local x, y = self:alien_pos(a)
                if a.alive and x == b.x and y == b.y then
                    a.alive = false
                    self.bullet = nil
                    self.score = self.score + 10 * self.level
                    SFX.hit()
                    break
                end
            end
            if self.bullet and b.y < 1 then self.bullet = nil end
            if alive_count() == 0 then
                self.level = self.level + 1
                SFX.levelup()
                new_wave(now)
                return nil
            end
        end

        -- march
        if now >= self.next_march then
            self.next_march = now + march_interval()
            local minx, maxx = extent()
            if (self.march_dir == 1 and maxx >= COLS) or (self.march_dir == -1 and minx <= 1) then
                self.oy = self.oy + 1
                self.march_dir = -self.march_dir
            else
                self.ox = self.ox + self.march_dir
            end
            local _, _, maxy = extent()
            if maxy >= GUN_ROW - 1 then return "over" end
        end

        -- new bomb from the lowest alien of a random live column
        if now >= self.next_bomb and #self.bombs < MAX_BOMBS then
            self.next_bomb = now + BOMB_EVERY_MS
            local lowest = {}
            for _, a in ipairs(self.aliens) do
                if a.alive and (not lowest[a.c] or a.r > lowest[a.c].r) then lowest[a.c] = a end
            end
            local cols = {}
            for _, a in pairs(lowest) do cols[#cols + 1] = a end
            if #cols > 0 then
                local x, y = self:alien_pos(cols[math.random(#cols)])
                self.bombs[#self.bombs + 1] = { x = x, y = y + 1 }
            end
        end

        -- bombs fall
        if now >= self.next_bombs then
            self.next_bombs = now + BOMB_MS
            local kept = {}
            for _, b in ipairs(self.bombs) do
                b.y = b.y + 1
                if gun_hit(b.x, b.y) then
                    self.lives = self.lives - 1
                    SFX.over()
                    self.bombs, self.bullet = {}, nil
                    if self.lives <= 0 then return "over" end
                    return nil
                end
                if b.y <= ROWS then kept[#kept + 1] = b end
            end
            self.bombs = kept
        end
        return nil
    end

    function game:draw(grid)
        for _, a in ipairs(self.aliens) do
            if a.alive then grid:set(self:alien_pos(a)) end
        end
        grid:stamp({ ".#.", "###" }, self.gun - 1, GUN_ROW)
        if self.bullet then grid:set(self.bullet.x, self.bullet.y, true) end
        for _, b in ipairs(self.bombs) do grid:set(b.x, b.y, true) end
    end

    new_wave(ctx.now)
    return game
end

return {
    id = "invaders",
    name = "INVADERS",
    hint = { "< > MOVE", "UP FIRE" },
    order = "high",
    demo = DEMO,
    new = new,
}
