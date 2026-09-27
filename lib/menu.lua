-- menu.lua — the brick-style game selector. The grid shows the game number
-- in big brick digits over the game's demo; the panel shows its name,
-- record and the chosen SPEED. Needs the LCD, SFX and PAD globals.

local DEMO_MS = 400   -- each demo frame shows this long

local Menu = {}
Menu.__index = Menu

-- deps: { screen, games, scores, runner, scene, clock (-> ms), input }
function Menu.new(deps)
    return setmetatable({ screen = deps.screen, games = deps.games,
                          scores = deps.scores, runner = deps.runner,
                          scene = deps.scene, clock = deps.clock,
                          input = deps.input,
                          sel = 1, speed = 1, quit = false, booted = false }, Menu)
end

function Menu:enter()
    self.input.setRepeat(300, 90)
    self.input.clearState()
    self.screen:repaint()
    if not self.booted then
        self.boot_start = self.clock()
        SFX.start()
    end
end

function Menu:exit()
    self.input.clearState()
end

function Menu:update()
    local pad = PAD.read()
    if not self.booted then return end   -- no input during the power-on curtain
    local n = #self.games
    if pad.repeated.left then
        self.sel = (self.sel - 2) % n + 1
        SFX.select()
    elseif pad.repeated.right then
        self.sel = self.sel % n + 1
        SFX.select()
    elseif pad.repeated.up then
        if self.speed < 9 then self.speed = self.speed + 1 SFX.select() end
    elseif pad.repeated.down then
        if self.speed > 1 then self.speed = self.speed - 1 SFX.select() end
    elseif pad.pressed.esc then
        self.quit = true
    elseif pad.pressed.enter then
        self.runner:start(self.games[self.sel], self.speed)
        self.scene.switch("play")
    end
end

function Menu:draw()
    local now = self.clock()
    local grid, panel = self.screen.grid, self.screen.panel
    local def = self.games[self.sel]

    grid:clear()
    panel.next:clear()
    if not self.booted and grid:curtain(now - self.boot_start) then
        self.booted = true
        grid:clear()
    end
    if self.booted then
        local num = string.format("%02d", self.sel)
        grid:text(string.sub(num, 1, 1), 2, 2)
        grid:text(string.sub(num, 2, 2), 7, 2)
        local frames = def.demo
        grid:stamp(frames[(now // DEMO_MS) % #frames + 1], 1, 9)
    end

    panel:set("label", "BRICK-15")
    panel:set("score", nil)
    panel:set("hi_label", def.order == "low" and "BEST" or "HI")
    panel:set("hi", self.scores:get(def.id))
    panel:set("speed", self.speed)
    panel:set("level", nil)
    panel:set("lives", nil)
    panel:set("name", def.name)
    panel:set_status({ "< > GAME", "UP DN SPEED", "ENTER PLAY" })
    self.screen:present(now)
end

return Menu
