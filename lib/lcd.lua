-- lcd.lua — shared LCD-brick-game helpers: palette, 3x5 pixel font,
-- 7-segment score digits, tone sequencer, input helpers.
-- Exposes globals: LCD, SFX, PAD.

local disp = picocalc.display
local input = picocalc.input
local audio = picocalc.audio

-- ── Palette (classic gray-green LCD) ─────────────────────────────────────────

LCD = {}
LCD.BG    = disp.rgb(158, 168, 102)   -- LCD background
LCD.DARK  = disp.rgb(24, 32, 14)     -- main pixel color
LCD.MID   = disp.rgb(92, 104, 58)    -- mid shade (frames, dim text)
LCD.LIGHT = disp.rgb(208, 216, 152)   -- highlight

LCD.clear = function() disp.clear(LCD.BG) end

-- ── 3x5 pixel font ────────────────────────────────────────────────────────────

local FONT = {
    ["0"] = { "111", "101", "101", "101", "111" },
    ["1"] = { "010", "010", "010", "010", "010" },
    ["2"] = { "111", "001", "111", "100", "111" },
    ["3"] = { "111", "001", "111", "001", "111" },
    ["4"] = { "101", "101", "111", "001", "001" },
    ["5"] = { "111", "100", "111", "001", "111" },
    ["6"] = { "111", "100", "111", "101", "111" },
    ["7"] = { "111", "001", "001", "001", "001" },
    ["8"] = { "111", "101", "111", "101", "111" },
    ["9"] = { "111", "101", "111", "001", "111" },
    ["A"] = { "010", "101", "111", "101", "101" },
    ["B"] = { "110", "101", "110", "101", "110" },
    ["C"] = { "011", "100", "100", "100", "011" },
    ["D"] = { "110", "101", "101", "101", "110" },
    ["E"] = { "111", "100", "110", "100", "111" },
    ["F"] = { "111", "100", "110", "100", "100" },
    ["G"] = { "011", "100", "101", "101", "011" },
    ["H"] = { "101", "101", "111", "101", "101" },
    ["I"] = { "111", "010", "010", "010", "111" },
    ["J"] = { "001", "001", "001", "101", "010" },
    ["K"] = { "101", "101", "110", "101", "101" },
    ["L"] = { "100", "100", "100", "100", "111" },
    ["M"] = { "101", "111", "101", "101", "101" },
    ["N"] = { "101", "111", "111", "111", "101" },
    ["O"] = { "010", "101", "101", "101", "010" },
    ["P"] = { "111", "101", "111", "100", "100" },
    ["Q"] = { "010", "101", "101", "010", "001" },
    ["R"] = { "111", "101", "110", "101", "101" },
    ["S"] = { "011", "100", "010", "001", "110" },
    ["T"] = { "111", "010", "010", "010", "010" },
    ["U"] = { "101", "101", "101", "101", "111" },
    ["V"] = { "101", "101", "101", "101", "010" },
    ["W"] = { "101", "101", "101", "111", "101" },
    ["X"] = { "101", "101", "010", "101", "101" },
    ["Y"] = { "101", "101", "010", "010", "010" },
    ["Z"] = { "111", "001", "010", "100", "111" },
    [" "] = { "000", "000", "000", "000", "000" },
    ["-"] = { "000", "000", "111", "000", "000" },
    ["."] = { "000", "000", "000", "000", "010" },
    [":"] = { "000", "010", "000", "010", "000" },
    ["/"] = { "001", "001", "010", "100", "100" },
    [">"] = { "100", "010", "001", "010", "100" },
    ["<"] = { "001", "010", "100", "010", "001" },
    ["!"] = { "010", "010", "010", "000", "010" },
}

-- Draw text in the 3x5 font. s = pixel size. Returns width drawn.
function LCD.text(str, x, y, s, color)
    str = string.upper(str)
    x, y, s = math.floor(x), math.floor(y), math.floor(s)
    for i = 1, #str do
        local glyph = FONT[string.sub(str, i, i)]
        if glyph then
            for row = 1, 5 do
                local bits = glyph[row]
                for col = 1, 3 do
                    if string.sub(bits, col, col) == "1" then
                        disp.fillRect(x + (i - 1) * 4 * s + (col - 1) * s,
                                     y + (row - 1) * s, s, s, color)
                    end
                end
            end
        end
    end
    return #str * 4 * s - s
end

function LCD.textWidth(str, s)
    return #str * 4 * math.floor(s) - math.floor(s)
end

function LCD.textCentered(str, y, s, color)
    LCD.text(str, math.floor((320 - LCD.textWidth(str, s)) / 2), y, s, color)
end

function LCD.textCenteredAt(str, cx, y, s, color)
    LCD.text(str, math.floor(cx - LCD.textWidth(str, s) / 2), y, s, color)
end

-- ── 7-segment digits ──────────────────────────────────────────────────────────

local SEG_MAP = {
    ["0"] = { "a", "b", "c", "d", "e", "f" },
    ["1"] = { "b", "c" },
    ["2"] = { "a", "b", "g", "e", "d" },
    ["3"] = { "a", "b", "g", "c", "d" },
    ["4"] = { "f", "g", "b", "c" },
    ["5"] = { "a", "f", "g", "c", "d" },
    ["6"] = { "a", "f", "g", "e", "c", "d" },
    ["7"] = { "a", "b", "c" },
    ["8"] = { "a", "b", "c", "d", "e", "f", "g" },
    ["9"] = { "a", "b", "c", "d", "f", "g" },
    ["-"] = { "g" },
    [" "] = {},
}

local function segRect(seg, x, y, t)
    if seg == "a" then return x + t // 2, y, 2 * t, t end
    if seg == "g" then return x + t // 2, y + 3 * t - t // 2, 2 * t, t end
    if seg == "d" then return x + t // 2, y + 5 * t, 2 * t, t end
    if seg == "f" then return x, y + t // 2, t, 2 * t end
    if seg == "b" then return x + 2 * t, y + t // 2, t, 2 * t end
    if seg == "e" then return x, y + 3 * t + t // 2, t, 2 * t end
    return x + 2 * t, y + 3 * t + t // 2, t, 2 * t  -- c
end

function LCD.segDigit(d, x, y, t, color)
    local segs = SEG_MAP[d]
    if not segs then return end
    for _, s in ipairs(segs) do
        local rx, ry, rw, rh = segRect(s, x, y, t)
        disp.fillRect(rx, ry, rw, rh, color)
    end
end

-- Zero-padded score. advance per digit = 3t + t//2. Returns total width.
function LCD.seg(value, x, y, t, digits, color)
    local n = math.max(0, math.floor(value))
    local str = tostring(math.tointeger(n) or n)
    while #str < digits do str = "0" .. str end
    if #str > digits then str = string.sub(str, -digits) end
    for i = 1, #str do
        LCD.segDigit(string.sub(str, i, i), x + (i - 1) * (3 * t + t // 2), y, t, color)
    end
    return #str * (3 * t + t // 2)
end

-- ── Sound effects (tone sequencer) ───────────────────────────────────────────

SFX = {}
local note_queue = {}
local playing_until = 0

function SFX.tone(freq, dur)
    audio.playTone(freq, dur)
end

-- seq: {freq, dur} or {{freq, dur}, ...} — played one note at a time.
function SFX.play(seq)
    note_queue = {}
    if type(seq[1]) == "number" then
        note_queue[1] = { f = seq[1], d = seq[2] or 80 }
    else
        for i, n in ipairs(seq) do
            note_queue[i] = { f = n[1], d = n[2] or 80 }
        end
    end
end

function SFX.update(now_ms)
    if #note_queue > 0 and now_ms >= playing_until then
        local n = table.remove(note_queue, 1)
        audio.playTone(n.f, n.d)
        playing_until = now_ms + n.d
    end
end

SFX.move    = function() SFX.play({ 220, 40 }) end
SFX.rotate  = function() SFX.play({ 330, 50 }) end
SFX.drop    = function() SFX.play({ 180, 60 }) end
SFX.score   = function() SFX.play({ { 660, 60 }, { 880, 80 } }) end
SFX.hit     = function() SFX.play({ 110, 120 }) end
SFX.start   = function() SFX.play({ { 440, 70 }, { 660, 70 }, { 880, 100 } }) end
SFX.over    = function() SFX.play({ { 440, 120 }, { 330, 120 }, { 220, 220 } }) end
SFX.select  = function() SFX.play({ 520, 40 }) end
SFX.levelup = function() SFX.play({ { 523, 60 }, { 659, 60 }, { 784, 60 }, { 1047, 110 } }) end
SFX.eat     = function() SFX.play({ { 880, 40 }, { 1175, 60 } }) end

-- ── Input helpers ────────────────────────────────────────────────────────────

PAD = {}

local function read_mask(getter)
    local b = getter()
    return {
        up      = b & input.BTN_UP ~= 0,
        down    = b & input.BTN_DOWN ~= 0,
        left    = b & input.BTN_LEFT ~= 0,
        right   = b & input.BTN_RIGHT ~= 0,
        enter   = b & input.BTN_ENTER ~= 0,
        esc     = b & input.BTN_ESC ~= 0,
        f1      = b & input.BTN_F1 ~= 0,
    }
end

function PAD.held()    return read_mask(input.getButtons) end
function PAD.pressed() return read_mask(input.getButtonsPressed) end
