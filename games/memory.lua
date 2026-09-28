-- memory.lua — game 10: find the 9 pairs in as few turns as possible.
-- 18 cards (3 across, 6 down) of 2x2 bricks; face down they are solid.
-- Game contract: see lib/runner.lua. Needs the SFX global.

local CARD_COLS, CARD_ROWS = 3, 6
local CARD_X = { 2, 5, 8 }        -- left column of each card column
local SHOW_MISS_MS = 900          -- a mismatched pair stays up this long
local SHOW_MATCH_MS = 400         -- a matched pair shows this long, then goes

-- The 9 faces: every 2-brick pattern of a 2x2 plus three 3-brick ones.
local FACES = {
    { "##", ".." }, { "..", "##" }, { "#.", "#." }, { ".#", ".#" },
    { "#.", ".#" }, { ".#", "#." },
    { "##", "#." }, { "##", ".#" }, { "#.", "##" },
}

local DEMO = {
    {
        ".##.##.##.",
        ".##.##.##.",
        "..........",
        ".##.#..##.",
        ".##..#.##.",
        "..........",
        ".##.##.##.",
        ".##.##.##.",
        "..........",
        ".##.##.##.",
        ".##.##.##.",
        "..........",
    },
    {
        ".##.##.##.",
        ".##.##.##.",
        "..........",
        ".##.#..##.",
        ".##..#.##.",
        "..........",
        ".##.##.#..",
        ".##.##..#.",
        "..........",
        ".##.##.##.",
        ".##.##.##.",
        "..........",
    },
}

local function card_pos(i)
    local col = (i - 1) % CARD_COLS + 1
    local row = (i - 1) // CARD_COLS + 1
    return CARD_X[col], 2 + (row - 1) * 3
end

local function new(ctx)
    local game = { score = 0, cursor = 1, cards = {} }

    local syms = {}
    for s = 1, #FACES do syms[#syms + 1] = s syms[#syms + 1] = s end
    for i = #syms, 2, -1 do                           -- shuffle
        local j = math.random(i)
        syms[i], syms[j] = syms[j], syms[i]
    end
    for i, s in ipairs(syms) do game.cards[i] = { sym = s, up = false, done = false } end

    local function all_done()
        for _, card in ipairs(game.cards) do if not card.done then return false end end
        return true
    end

    function game:update(pad, now)
        -- a pair on show: wait, then remove it or turn it back over
        if self.showing then
            if now < self.showing.until_ms then return nil end
            local a, b = self.cards[self.showing[1]], self.cards[self.showing[2]]
            if a.sym == b.sym then a.done, b.done = true, true
            else a.up, b.up = false, false end
            self.showing = nil
            if all_done() then
                self.status = { "CLEARED" }
                return "over"
            end
            return nil
        end

        local c = (self.cursor - 1) % CARD_COLS
        if pad.repeated.left and c > 0 then self.cursor = self.cursor - 1 end
        if pad.repeated.right and c < CARD_COLS - 1 then self.cursor = self.cursor + 1 end
        if pad.repeated.up and self.cursor > CARD_COLS then self.cursor = self.cursor - CARD_COLS end
        if pad.repeated.down and self.cursor <= CARD_COLS * (CARD_ROWS - 1) then
            self.cursor = self.cursor + CARD_COLS
        end

        local card = self.cards[self.cursor]
        if (pad.pressed.enter or pad.pressed.f1) and not card.done and not card.up then
            card.up = true
            SFX.select()
            if self.first then
                self.score = self.score + 1                    -- one turn = two cards
                local match = self.cards[self.first].sym == card.sym
                self.showing = { self.first, self.cursor,
                                 until_ms = now + (match and SHOW_MATCH_MS or SHOW_MISS_MS) }
                if match then SFX.score() else SFX.hit() end
                self.first = nil
            else
                self.first = self.cursor
            end
        end
        return nil
    end

    function game:draw(grid)
        for i, card in ipairs(self.cards) do
            if not card.done then
                local x, y = card_pos(i)
                local v = (i == self.cursor) and "blink" or true
                if card.up then grid:stamp(FACES[card.sym], x, y, v)
                else grid:stamp({ "##", "##" }, x, y, v) end
            end
        end
        -- the cursor on an empty slot still shows where it is
        if self.cards[self.cursor].done then
            local x, y = card_pos(self.cursor)
            grid:set(x, y, "blink")
        end
    end

    return game
end

return {
    id = "memory",
    name = "MEMORY",
    hint = { "D-PAD MOVE", "ENTER FLIP", "FEWEST TURNS WIN" },
    messages = { "CLEARED" },
    order = "low",
    demo = DEMO,
    new = new,
    FACES = FACES,
}
