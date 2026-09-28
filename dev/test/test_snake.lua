need("dev/test/game_helpers.lua")
local snake = need("games/snake.lua")

local function new_game()
    local g = snake.new(game_ctx())
    g.food = { x = 1, y = 1 }          -- out of the way unless a test moves it
    return g
end

test("snake: meets the game contract", function()
    check_contract(snake, "snake", "SNAKE")
end)

test("snake: starts 3 long heading right, score 0, level 1", function()
    local g = new_game()
    eq(#g.body, 3, "length"); eq(g.dir.x, 1, "heading right")
    eq(g.score, 0, "score"); eq(g.level, 1, "level"); eq(g.lives, nil, "no lives")
end)

test("snake: moves one cell per interval", function()
    local g = new_game()
    local x = g.body[1].x
    g:update(NONE, 299)
    eq(g.body[1].x, x, "not yet")
    g:update(NONE, 300)
    eq(g.body[1].x, x + 1, "one step")
end)

test("snake: turning takes effect on the next step, reversing is ignored", function()
    local g = new_game()
    local head = g.body[1]
    g:update(press("left"), 10)         -- reverse: ignored
    g:update(press("up"), 20)
    g:update(NONE, 300)
    eq(g.body[1].x, head.x, "same column"); eq(g.body[1].y, head.y - 1, "moved up")
end)

test("snake: two quick presses inside one step can't reverse the snake", function()
    local g = new_game()                 -- heading right
    local head = g.body[1]
    g:update(press("up"), 10)
    g:update(press("left"), 20)          -- would reverse into the body after "up"
    g:update(NONE, 300)
    eq(g.body[1].x, head.x, "went up, not back left"); eq(g.body[1].y, head.y - 1, "up")
end)

test("snake: eating food grows the snake and scores 10 x level", function()
    local g = new_game()
    local head = g.body[1]
    g.food = { x = head.x + 1, y = head.y }
    g:update(NONE, 300)
    eq(#g.body, 4, "grew"); eq(g.score, 10, "score")
    truthy(g.food.x ~= head.x + 1 or g.food.y ~= head.y, "new food placed")
end)

test("snake: new food never lands on the snake", function()
    local g = new_game()
    for _ = 1, 200 do
        g:place_food()
        for _, s in ipairs(g.body) do
            truthy(s.x ~= g.food.x or s.y ~= g.food.y, "food on snake")
        end
    end
end)

test("snake: five foods raise the level", function()
    local g = new_game()
    g.eaten = 4
    local head = g.body[1]
    g.food = { x = head.x + 1, y = head.y }
    g:update(NONE, 300)
    eq(g.level, 2, "level 2")
end)

test("snake: hitting the wall ends the round", function()
    local g = new_game()
    local result
    for t = 1, 20 do
        result = g:update(NONE, t * 300)
        if result then break end
    end
    eq(result, "over", "over")
end)

test("snake: running into itself ends the round", function()
    local g = new_game()
    g.body = { { x = 5, y = 5 }, { x = 4, y = 5 }, { x = 4, y = 6 }, { x = 5, y = 6 }, { x = 6, y = 6 } }
    g.dir, g.next_dir = { x = 0, y = 1 }, { x = 0, y = 1 }
    eq(g:update(NONE, 300), "over", "bit itself")
end)

test("snake: draw lights the body and blinks the food", function()
    local g = new_game()
    g.food = { x = 9, y = 3 }
    local grid = draw_game(g)
    eq(grid:get(9, 3), "blink", "food blinks")
    for _, s in ipairs(g.body) do eq(grid:get(s.x, s.y), true, "body") end
end)
