need("lib/lcd.lua")

test("font: M, N and W are 5 dots wide so they can't read as H", function()
    local M, N, W = LCD.FONT["M"], LCD.FONT["N"], LCD.FONT["W"]
    eq(table.concat(M, ","), "10001,11011,10101,10001,10001", "M")
    eq(table.concat(N, ","), "10001,11001,10101,10011,10001", "N")
    eq(table.concat(W, ","), "10001,10001,10101,11011,10001", "W")
end)

test("text: wide glyphs advance by their own width", function()
    eq(LCD.textWidth("HI", 2), 14, "two 3-wide glyphs")
    eq(LCD.textWidth("MI", 2), 18, "a 5-wide glyph takes 2 dots more")
    LCD.text("MI", 0, 0, 2, LCD.DARK)
    local maxx = 0
    for _, c in ipairs(CALLS) do maxx = math.max(maxx, c[2] + c[4]) end
    eq(maxx, 18, "drawn width matches textWidth")
end)

test("font: 1 has a flag and a foot, so it can't read as I", function()
    eq(table.concat(LCD.FONT["1"], ","), "010,110,010,010,111", "1")
end)

test("text: one fillRect per horizontal run", function()
    LCD.text("T", 0, 0, 2, LCD.DARK)   -- T = 111 / 010 x4 -> 5 runs
    eq(count_calls("fillRect"), 5, "fillRect calls for T")
    local first = CALLS[1]
    eq(first[2], 0, "x"); eq(first[3], 0, "y"); eq(first[4], 6, "w"); eq(first[5], 2, "h")
end)

test("text: scale below 2 is rejected", function()
    raises(function() LCD.text("A", 0, 0, 1, LCD.DARK) end, "scale 1")
end)

test("textWidth: 4s per char minus trailing gap, 0 for empty", function()
    eq(LCD.textWidth("ABC", 2), 22, "ABC at 2")
    eq(LCD.textWidth("", 2), 0, "empty")
end)

test("segString: numbers zero-pad, strings right-align, nil is blank", function()
    eq(LCD.segString(120, 6), "000120", "number")
    eq(LCD.segString("03-05", 6), " 03-05", "string")
    eq(LCD.segString(nil, 2), "  ", "nil")
    eq(LCD.segString(1234567, 6), "234567", "overflow keeps low digits")
end)

test("seg: t below 3 is rejected", function()
    raises(function() LCD.seg(5, 0, 0, 2, 1) end, "t=2")
end)

test("seg: every position draws 7 ghost segments, then lit ones", function()
    LCD.seg(1, 0, 0, 3, 1)   -- "1" lights b and c
    eq(count_calls("fillRect"), 9, "7 ghost + 2 lit")
    for i = 1, 7 do eq(CALLS[i][6], LCD.GHOST, "ghost colour " .. i) end
    eq(CALLS[8][6], LCD.DARK, "lit colour")
end)

test("seg: nil value draws ghosts only", function()
    LCD.seg(nil, 0, 0, 3, 2)
    eq(count_calls("fillRect"), 14, "2 x 7 ghost segments")
end)

test("PAD.read: held, pressed and repeated masks", function()
    local input = picocalc.input
    local save = { input.getButtons, input.getButtonsPressed, input.getButtonsRepeated }
    input.getButtons = function() return input.BTN_DOWN end
    input.getButtonsPressed = function() return input.BTN_ENTER end
    input.getButtonsRepeated = function() return input.BTN_LEFT | input.BTN_ENTER end
    local pad = PAD.read()
    input.getButtons, input.getButtonsPressed, input.getButtonsRepeated = save[1], save[2], save[3]
    truthy(pad.held.down, "held.down")
    truthy(pad.pressed.enter, "pressed.enter")
    truthy(pad.repeated.left, "repeated.left")
    eq(pad.pressed.left, false, "pressed.left")
end)
