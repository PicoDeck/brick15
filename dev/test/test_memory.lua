need("dev/test/game_helpers.lua")
local memory = need("games/memory.lua")

local function new_game() return memory.new(game_ctx()) end

-- Index of another card with the same symbol as card i (or a different one).
local function partner(g, i, same)
    for j, card in ipairs(g.cards) do
        if j ~= i and (card.sym == g.cards[i].sym) == same and not card.done then return j end
    end
end

local function flip_at(g, i, now)
    g.cursor = i
    return g:update(press("enter"), now)
end

test("memory: meets the game contract", function()
    check_contract(memory, "memory", "MEMORY")
    eq(memory.order, "low", "fewer turns is better")
end)

test("memory: 18 face-down cards, 9 symbols in pairs", function()
    local g = new_game()
    eq(g.score_label, "TURNS", "the score is a turn count")
    eq(#g.cards, 18, "cards")
    local count = {}
    for _, card in ipairs(g.cards) do
        eq(card.up, false, "face down")
        count[card.sym] = (count[card.sym] or 0) + 1
    end
    for sym = 1, 9 do eq(count[sym], 2, "pair of " .. sym) end
end)

test("memory: the 9 face patterns are distinct, 1-3 bricks of a 2x2", function()
    local seen = {}
    for _, p in ipairs(memory.FACES) do
        local key = table.concat(p, "|")
        truthy(not seen[key], "distinct " .. key); seen[key] = true
        local n = select(2, key:gsub("#", ""))
        truthy(n >= 1 and n <= 3, "1-3 bricks " .. key)
    end
end)

test("memory: the cursor moves across the 3x6 layout and stops at the edges", function()
    local g = new_game()
    eq(g.cursor, 1, "top-left")
    g:update(pad({ repeated = { "right" } }), 1)
    eq(g.cursor, 2, "right")
    g:update(pad({ repeated = { "down" } }), 2)
    eq(g.cursor, 5, "down a row")
    g.cursor = 3
    g:update(pad({ repeated = { "right" } }), 3)
    eq(g.cursor, 3, "right edge")
end)

test("memory: a mismatched pair costs a turn and turns back over", function()
    local g = new_game()
    local j = partner(g, 1, false)
    flip_at(g, 1, 0)
    flip_at(g, j, 10)
    eq(g.score, 1, "one turn")
    eq(g.cards[1].up, true, "still showing")
    g:update(NONE, 10 + 900)
    eq(g.cards[1].up, false, "face down again"); eq(g.cards[j].up, false, "face down again")
end)

test("memory: a matched pair is removed", function()
    local g = new_game()
    local j = partner(g, 1, true)
    flip_at(g, 1, 0)
    flip_at(g, j, 10)
    g:update(NONE, 10 + 400)
    eq(g.cards[1].done, true, "matched"); eq(g.cards[j].done, true, "matched")
end)

test("memory: no third card while a pair is showing", function()
    local g = new_game()
    local j = partner(g, 1, false)
    local k = partner(g, j, false)
    flip_at(g, 1, 0); flip_at(g, j, 10)
    flip_at(g, k ~= 1 and k or 18, 20)
    local up = 0
    for _, card in ipairs(g.cards) do if card.up then up = up + 1 end end
    eq(up, 2, "only the pair")
end)

test("memory: finding every pair ends the round with CLEARED", function()
    local g = new_game()
    for _, card in ipairs(g.cards) do card.done = true end
    local a, b
    for i, card in ipairs(g.cards) do
        if card.sym == 1 then card.done = false if a then b = i else a = i end end
    end
    flip_at(g, a, 0); flip_at(g, b, 10)
    eq(g:update(NONE, 10 + 400), "over", "over")
    eq(g.status[1], "CLEARED", "result"); check_status(memory, g)
end)

test("memory: face-down cards are solid 2x2 blocks, the cursor card blinks", function()
    local g = new_game()
    local grid = draw_game(g)
    eq(grid:get(2, 2), "blink", "cursor card (col 2-3, row 2-3)")
    eq(grid:get(5, 2), true, "second card solid"); eq(grid:get(6, 3), true, "second card solid")
    eq(grid:get(4, 2), false, "gap between cards")
end)
