-- menu.lua — the BRICK-30 collection menu scene.
-- Expects globals: LCD, SFX, PAD, disp, picocalc.

local disp = picocalc.display
local save = picocalc.game.save
local scene_mgr = picocalc.game.scene

local function new(games)
    local sel = 1
    local scene = {}
    scene.quit = false

    function scene:enter()
        picocalc.input.setRepeat(350, 90)
        SFX.play({ { 440, 60 }, { 660, 60 }, { 880, 90 } })
    end

    function scene:update()
        local p = PAD.pressed()
        if p.up then
            sel = sel - 1
            if sel < 1 then sel = #games end
            SFX.select()
        elseif p.down then
            sel = sel + 1
            if sel > #games then sel = 1 end
            SFX.select()
        elseif p.esc then
            scene.quit = true
        elseif p.enter then
            SFX.start()
            picocalc.input.clearState()
            scene_mgr.switch("game_" .. games[sel].id)
        end
    end

    function scene:draw()
        LCD.clear()
        disp.drawRect(4, 4, 312, 312, LCD.MID)
        disp.drawRect(8, 8, 304, 304, LCD.MID)

        LCD.textCentered("BRICK-30", 14, 3, LCD.DARK)
        LCD.textCentered("15 GAMES 1 CART", 34, 1, LCD.MID)

        for i, g in ipairs(games) do
            local y = 48 + (i - 1) * 16
            local color
            if i == sel then
                disp.fillRect(10, y - 2, 300, 14, LCD.DARK)
                color = LCD.BG
            else
                color = LCD.DARK
            end
            LCD.text(g.num .. " " .. g.name, 16, y, 2, color)
            local hi = (save.get("hi_" .. g.id) or {}).v or 0
            local hi_str = "HI " .. hi
            LCD.text(hi_str, 304 - LCD.textWidth(hi_str, 2), y, 2, color)
        end

        LCD.textCentered("D-PAD SELECT  ENTER PLAY  ESC QUIT", 302, 1, LCD.MID)
        disp.flush()
    end

    return scene
end

return { new = new }
