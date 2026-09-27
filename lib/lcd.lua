-- lcd.lua — shared LCD-brick-game helpers: palette, 3x5 pixel font,
-- 7-segment digits with ghost segments, tone sequencer, input helpers.
-- Exposes globals: LCD, SFX, PAD.

local disp = picocalc.display
local input = picocalc.input
local audio = picocalc.audio

-- ── Palette (classic gray-green LCD) ─────────────────────────────────────────

LCD = {}
LCD.BG    = disp.rgb(158, 168, 102)   -- LCD background
LCD.DARK  = disp.rgb(24, 32, 14)      -- lit bricks, text, digits, frame
LCD.GHOST = disp.rgb(146, 156, 94)    -- unlit bricks and segments

LCD.clear = function() disp.clear(LCD.BG) end

-- ── 3x5 pixel font ────────────────────────────────────────────────────────────

local FONT = {
    ["0"] = { "111", "101", "101", "101", "111" },
    ["1"] = { "010", "110", "010", "010", "111" },
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
    ["M"] = { "101", "111", "111", "101", "101" },
    ["N"] = { "110", "101", "101", "101", "101" },
    ["O"] = { "010", "101", "101", "101", "010" },
    ["P"] = { "111", "101", "111", "100", "100" },
    ["Q"] = { "010", "101", "101", "010", "001" },
    ["R"] = { "111", "101", "110", "101", "101" },
    ["S"] = { "011", "100", "010", "001", "110" },
    ["T"] = { "111", "010", "010", "010", "010" },
    ["U"] = { "101", "101", "101", "101", "111" },
    ["V"] = { "101", "101", "101", "101", "010" },
    ["W"] = { "101", "101", "111", "111", "101" },
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
LCD.FONT = FONT

-- Each glyph as horizontal runs { row, col, len } (0-based), so a run of
-- lit dots is one fillRect instead of one per dot.
local RUNS = {}
for ch, rows in pairs(FONT) do
    local runs = {}
    for r = 1, 5 do
        local bits = rows[r]
        local c = 1
        while c <= 3 do
            if string.sub(bits, c, c) == "1" then
                local start = c
                while c <= 3 and string.sub(bits, c, c) == "1" do c = c + 1 end
                runs[#runs + 1] = { r - 1, start - 1, c - start }
            else
                c = c + 1
            end
        end
    end
    RUNS[ch] = runs
end

function LCD.textWidth(str, s)
    if #str == 0 then return 0 end
    return #str * 4 * s - s
end

-- Draw text in the 3x5 font at scale s (2 or more). Returns width drawn.
function LCD.text(str, x, y, s, color)
    assert(s >= 2, "LCD.text: scale must be >= 2")
    str = string.upper(str)
    x, y, s = math.floor(x), math.floor(y), math.floor(s)
    for i = 1, #str do
        local runs = RUNS[string.sub(str, i, i)]
        if runs then
            local gx = x + (i - 1) * 4 * s
            for _, run in ipairs(runs) do
                disp.fillRect(gx + run[2] * s, y + run[1] * s, run[3] * s, s, color)
            end
        end
    end
    return LCD.textWidth(str, s)
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

-- One digit cell: all 7 segments in GHOST, then the character's in DARK.
function LCD.segDigit(ch, x, y, t)
    for _, s in ipairs(SEG_MAP["8"]) do
        local rx, ry, rw, rh = segRect(s, x, y, t)
        disp.fillRect(rx, ry, rw, rh, LCD.GHOST)
    end
    for _, s in ipairs(SEG_MAP[ch] or {}) do
        local rx, ry, rw, rh = segRect(s, x, y, t)
        disp.fillRect(rx, ry, rw, rh, LCD.DARK)
    end
end

-- The characters shown in `digits` positions: numbers zero-padded, strings
-- (digits, '-', ' ') right-aligned, nil blank. Overflow keeps the right end.
function LCD.segString(value, digits)
    local str
    if value == nil then
        str = ""
    elseif type(value) == "number" then
        str = string.format("%0" .. digits .. "d", math.floor(math.max(0, value)))
    else
        str = value
    end
    if #str < digits then str = string.rep(" ", digits - #str) .. str end
    if #str > digits then str = string.sub(str, -digits) end
    return str
end

-- Draw a 7-segment field. t is the segment thickness (3 or more); a digit is
-- 3t wide, 6t tall, and digits advance 3t + t//2. Returns the width drawn.
function LCD.seg(value, x, y, t, digits)
    assert(t >= 3, "LCD.seg: t must be >= 3")
    local str = LCD.segString(value, digits)
    local adv = 3 * t + t // 2
    for i = 1, digits do
        LCD.segDigit(string.sub(str, i, i), x + (i - 1) * adv, y, t)
    end
    return digits * adv - t // 2
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

local function read_mask(b)
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

-- Read the pad once per frame. `repeated` adds auto-repeat edges for held
-- buttons (see picocalc.input.setRepeat); getButtonsRepeated advances the
-- repeat clocks, so call this exactly once per frame.
function PAD.read()
    return {
        held     = read_mask(input.getButtons()),
        pressed  = read_mask(input.getButtonsPressed()),
        repeated = read_mask(input.getButtonsRepeated()),
    }
end
