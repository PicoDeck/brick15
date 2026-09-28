-- simon.lua — game 11: watch the pads light up, then repeat the sequence.
-- The four pads form a plus that matches the d-pad.
-- Game contract: see lib/runner.lua. Needs the SFX global.

local INTRO_MS = 2000             -- the hint shows before the first sequence
local ON_MS = 450                 -- each pad lights this long at speed 1
local GAP_MS = 200
local PRESS_MS = 250              -- a pressed pad stays lit this long
local ROUND_PAUSE_MS = 700
local TIMEOUT_MS = 4000           -- no press for this long ends the round

local PADS = {
    up    = { x = 4, y = 3,  tone = 440 },
    left  = { x = 1, y = 9,  tone = 220 },
    right = { x = 7, y = 9,  tone = 330 },
    down  = { x = 4, y = 15, tone = 262 },
}
local NAMES = { "up", "left", "right", "down" }
local OUTLINE = { "####", "#..#", "#..#", "####" }
local FILLED = { "####", "####", "####", "####" }

local DEMO = {
    {
        "...####...",
        "...####...",
        "...####...",
        "...####...",
        "..........",
        "..........",
        "####..####",
        "#..#..#..#",
        "#..#..#..#",
        "####..####",
        "..........",
        "..........",
    },
    {
        "...####...",
        "...#..#...",
        "...#..#...",
        "...####...",
        "..........",
        "..........",
        "####..####",
        "#..#..####",
        "#..#..####",
        "####..####",
        "..........",
        "..........",
    },
}

local function new(ctx)
    local game = { score = 0, seq = {}, state = "intro" }

    local function add_pad() game.seq[#game.seq + 1] = NAMES[math.random(#NAMES)] end

    local function light(name, now, ms)
        game.lit, game.lit_until = name, now + ms
        SFX.tone(PADS[name].tone, ms)
    end

    local function start_show(now)
        game.state = "show"
        game.status = { "WATCH" }
        game.show_i = 0
        game.next_show = now
    end

    function game:update(pad, now)
        if self.lit and now >= self.lit_until then self.lit = nil end

        if self.state == "intro" or self.state == "pause" then
            if now >= self.wait_until then start_show(now) end
            return nil
        end

        if self.state == "show" then
            if now < self.next_show then return nil end
            self.show_i = self.show_i + 1
            if self.show_i > #self.seq then
                self.state = "input"
                self.status = { "YOUR TURN" }
                self.input_i = 1
                self.last_input = now
                return nil
            end
            local on = ctx.interval(ON_MS, 1)
            light(self.seq[self.show_i], now, on)
            self.next_show = now + on + GAP_MS
            return nil
        end

        -- input
        for _, name in ipairs(NAMES) do
            if pad.pressed[name] then
                self.last_input = now
                light(name, now, PRESS_MS)
                if name ~= self.seq[self.input_i] then
                    self.status = { "WRONG" }
                    return "over"
                end
                self.input_i = self.input_i + 1
                if self.input_i > #self.seq then
                    self.score = #self.seq
                    add_pad()
                    self.state = "pause"
                    self.status = nil
                    self.wait_until = now + ROUND_PAUSE_MS
                end
                return nil
            end
        end
        if now - self.last_input > TIMEOUT_MS then
            self.status = { "TOO SLOW" }
            return "over"
        end
        return nil
    end

    function game:draw(grid)
        for name, p in pairs(PADS) do
            grid:stamp(name == self.lit and FILLED or OUTLINE, p.x, p.y)
        end
    end

    add_pad()
    game.wait_until = ctx.now + INTRO_MS
    return game
end

return {
    id = "simon",
    name = "SIMON",
    hint = { "WATCH THE PADS", "THEN REPEAT", "WITH THE D-PAD" },
    messages = { "WATCH", "YOUR TURN", "WRONG", "TOO SLOW" },
    order = "high",
    demo = DEMO,
    new = new,
    PADS = PADS,
}
