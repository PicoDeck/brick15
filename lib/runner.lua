-- runner.lua — the "play" scene. Hosts one game at a time and owns what
-- every game shares: Esc to the menu, control hints, the game-over curtain,
-- saving records, retry, and the panel. Needs the LCD, SFX and PAD globals.
--
-- The game contract. games/<id>.lua returns:
--   { id = "snake", name = "SNAKE",        -- name: at most 11 characters
--     hint = { "D-PAD STEER" },            -- 1-3 lines, each at most 17 characters,
--                                          -- shown whenever the game sets no status
--     messages = { "CLEARED" },            -- every status line the game can show
--     order = "high",                      -- or "low": fewer is better (Memory)
--     demo = { frame1, frame2 },           -- two 10x12 '#' patterns for the menu
--     new = function(ctx) return game end }
-- ctx = { speed = 1..9, now = ms, interval = function(base_ms, level) -> ms }
-- game:update(pad, now_ms)   pad = PAD.read(); return "over" to end the round
-- game:draw(grid, next)      light cells; both grids arrive cleared
-- Fields the runner reads every frame:
--   game.score, game.score_text (optional SCORE display string),
--   game.score_label (optional legend instead of SCORE, e.g. "TURNS"),
--   game.level, game.lives (nil = unused, shown ghosted),
--   game.next_label (optional legend for the NEXT box, e.g. "FUEL"),
--   game.status (nil or up to 3 lines; replaces the hint while set). When a
--   game returns "over", status[1] (if set) is the headline instead of
--   GAME OVER, so set it to the end-of-round message or nil first.
-- Games never call picocalc.display, picocalc.game.save or scene, and never
-- handle Esc; every position is a whole cell.

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

-- Status lines: the game's own status, else its controls hint. After a
-- round: the headline (the game's result or GAME OVER), then any new
-- record, then how to play again.
function Runner:status_lines()
    local game = self.game
    if self.state == "play" then return game.status or self.def.hint end
    local headline = (game.status and game.status[1]) or "GAME OVER"
    local record = self.record and (self.def.order == "low" and "NEW BEST" or "NEW HI") or nil
    if self.state == "curtain" then return { headline, record } end
    if record then return { headline, record, "ENTER AGAIN" } end
    return { headline, "ENTER AGAIN", "ESC MENU" }
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

    panel:set("label", game.score_label or "SCORE")
    panel:set("score", game.score_text or game.score)
    panel:set("hi_label", def.order == "low" and "BEST" or "HI")
    panel:set("hi", self.scores:get(def.id))
    panel:set("speed", self.speed)
    panel:set("level", game.level)
    panel:set("lives", game.lives)
    panel:set("next_label", game.next_label or "NEXT")
    panel:set("name", def.name)
    panel:set_status(self:status_lines())
    self.screen:present(now)
end

return Runner
