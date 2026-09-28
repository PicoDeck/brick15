-- runner.lua — the "play" scene. Hosts one game at a time and owns what
-- every game shares: Esc to the menu, control hints, the game-over curtain,
-- saving records, retry, and the panel. Needs the LCD, SFX and PAD globals.
--
-- The game contract. games/<id>.lua returns:
--   { id = "snake", name = "SNAKE",        -- name: at most 11 characters
--     hint = { "D-PAD STEER" },            -- 1-3 lines, each at most 17 characters,
--                                          -- shown for the first 3 s of a round
--     messages = { "CLEARED" },            -- every status line the game can show
--     order = "high",                      -- or "low": fewer is better (Memory)
--     demo = { frame1, frame2 },           -- two 10x12 '#' patterns for the menu
--     new = function(ctx) return game end }
-- ctx = { speed = 1..9, now = ms, interval = function(base_ms, level) -> ms }
-- game:update(pad, now_ms)   pad = PAD.read(); return "over" to end the round
-- game:draw(grid, next)      light cells; both grids arrive cleared
-- Fields the runner reads every frame:
--   game.score, game.score_text (optional SCORE display string),
--   game.level, game.lives (nil = unused, shown ghosted),
--   game.status (nil or up to 3 lines; replaces the hint while set). When a
--   game returns "over", status[1] (if set) is the headline instead of
--   GAME OVER, so set it to the end-of-round message or nil first.
-- Games never call picocalc.display, picocalc.game.save or scene, and never
-- handle Esc; every position is a whole cell.

local HINT_MS = 3000

local Runner = {}
Runner.__index = Runner

-- Step interval for a game's main timer: shrinks 13% per speed or level
-- step above 1, never below 40 ms.
function Runner.interval(base_ms, speed, level)
    return math.max(40, base_ms * 0.87 ^ ((speed or 1) + (level or 1) - 2))
end

-- deps: { screen, scores, scene (picocalc.game.scene), clock (-> ms), input }
function Runner.new(deps)
    return setmetatable({ screen = deps.screen, scores = deps.scores,
                          scene = deps.scene, clock = deps.clock,
                          input = deps.input, speed = 1 }, Runner)
end

-- Called by the menu just before it switches to the "play" scene.
function Runner:start(def, speed)
    self.def, self.speed = def, speed
end

function Runner:new_round()
    local now = self.clock()
    local speed = self.speed
    self.game = self.def.new({
        speed = speed,
        now = now,
        interval = function(base_ms, level) return Runner.interval(base_ms, speed, level) end,
    })
    self.state = "play"
    self.round_start = now
    self.record = false
    SFX.start()
end

function Runner:enter()
    self.input.setRepeat(170, 50)
    self.input.clearState()
    self.screen:repaint()
    self:new_round()
end

function Runner:exit()
    self.input.clearState()
end

function Runner:update()
    local now = self.clock()
    local pad = PAD.read()
    if pad.pressed.esc then
        self.scene.switch("menu")
        return
    end
    if self.state == "play" then
        if self.game:update(pad, now) == "over" then
            self.record = self.scores:submit(self.def.id, self.game.score or 0, self.def.order)
            if self.record then SFX.levelup() else SFX.over() end
            self.state = "curtain"
            self.curtain_start = now
        end
    elseif self.state == "over" then
        if pad.pressed.enter then self:new_round() end
    end
end

function Runner:status_lines(now)
    local game = self.game
    if self.state == "play" then
        if game.status then return game.status end
        if now - self.round_start < HINT_MS then return self.def.hint end
        return nil
    end
    local first = (self.record and "NEW HI") or (game.status and game.status[1]) or "GAME OVER"
    if self.state == "curtain" then return { first } end
    return { first, "ENTER AGAIN", "ESC MENU" }
end

function Runner:draw()
    local now = self.clock()
    local grid, panel = self.screen.grid, self.screen.panel
    local game, def = self.game, self.def

    grid:clear()
    panel.next:clear()
    if self.state ~= "over" then game:draw(grid, panel.next) end
    if self.state == "curtain" and grid:curtain(now - self.curtain_start) then
        self.state = "over"
        grid:clear()
        panel.next:clear()
    end

    panel:set("label", "SCORE")
    panel:set("score", game.score_text or game.score)
    panel:set("hi_label", def.order == "low" and "BEST" or "HI")
    panel:set("hi", self.scores:get(def.id))
    panel:set("speed", self.speed)
    panel:set("level", game.level)
    panel:set("lives", game.lives)
    panel:set("name", def.name)
    panel:set_status(self:status_lines(now))
    self.screen:present(now)
end

return Runner
