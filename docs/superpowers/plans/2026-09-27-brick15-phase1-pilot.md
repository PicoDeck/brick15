# BRICK-15 Phase 1 (Pilot) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the shared 10×20 brick-grid engine (grid, side panel, diff rendering, score cache, play runner, brick-style menu) and port Tetris onto it as the pilot game. The other 14 games are switched off until phase 2 converts them.

**Architecture:**
- **Games:** each game is a rules-only module that lights cells on a 10×20 `Grid` and exposes `score`/`level`/`lives`/`status` fields.
- **Menu and runner:** a shared `Runner` scene hosts the active game (Esc, hints, game-over curtain, records, retry), and a `Menu` scene is the brick-style selector.
- **Rendering:** both scenes draw through one `Screen`. It redraws only the cells and panel fields that changed and sends them with `display.flushRegion`, so a frame where nothing changed costs nothing.

**Tech Stack:**
- Lua 5.4 on the PicoDeck `picocalc.*` API (no native code, no assets).
- Desktop `lua` 5.4 for the unit tests.
- Python 3 + Pillow + the PicoDeck simulator client (`picodeck/tests/e2e/picodeck_simulator.py`) for the smoke test.

**Spec:** `docs/superpowers/specs/2026-09-27-brick15-grid-redesign-design.md`. Read it before starting: section 1 has the layout numbers, section 2 the module design.

**Scope:**
- **Phase 1 (this plan):** spec build-order step 1, the pilot.
- **Phase 2 (games 02–15, rename, critic loop):** written as its own plan in Task 11, once this plan's contract has been proven in the simulator.

## Global Constraints

- **Screen:** 320×320. Grid is 10 columns × 20 rows, 15px pitch, top-left pixel `(12, 10)`. Panel left edge x = 176.
- **Palette:**
  - `LCD.BG = rgb(158,168,102)`, `LCD.DARK = rgb(24,32,14)`, `LCD.GHOST = rgb(146,156,94)` (GHOST may be tuned in Task 10).
  - No other colours.
  - `LCD.MID` and `LCD.LIGHT` are removed.
- **Text:** the 3×5 font is only drawn at scale 2 or more.
  - M = `101,111,111,101,101`
  - N = `110,101,101,101,101`
  - W = `101,101,111,111,101`
  - 1 = `010,110,010,010,111`
- **Numbers:** 7-segment digits only at t = 3 or 4, always over ghost "8" segments.
- **Brick:** 3 fills inside a 15px cell: 13×13 at +1, 9×9 BG at +2, 5×5 at +4.
- **Game modules:** `games/*.lua` never call `picocalc.display`, `picocalc.game.save` or `picocalc.game.scene`, and never handle Esc. All positions are whole cells.
- **Flushing:** the app flushes only with `display.flushRegion(y0, y1)`, never `display.flush()`.
- **Frames:** a frame with no state change issues zero draw calls and no flush.
- **Saves:** `save.get` is called only at startup (`Scores.new`), and `save.set` only on a new record. Save slots are `hi_<game id>` = `{ v = <number> }`.
- **Scene callbacks:** `picocalc.game.scene` calls `enter/update/draw/exit` as plain functions with no `self` (`update` gets `dt`). Scene objects are therefore wrapped by `as_scene` in `main.lua`.
- **Errors:** scene errors print `[SCENE] Error …` to the simulator's stdout, not to the log buffer. `picocalc.sys.log` writes to the log buffer.
- **Branch:** work on branch `brick15-grid` (create it from `master` before Task 1). `master` keeps the working BRICK-30 until phase 2 is merged.

## Review Focus

These input classes or failure modes are implied by the spec but not covered by the main tests. Each now has a test in the task that owns the code.

1. **Esc during the game-over curtain** must still return to the menu. Test in Task 6.
2. **Enter pressed while the curtain plays** must not restart or skip the round. Test in Task 6.
3. **A game name or hint that doesn't fit the panel,** or uses a character the font lacks, would draw off-panel or leave gaps. Name ≤ 11 characters, hint lines ≤ 17, font glyphs only. Test in Task 7, and every phase 2 game repeats it.
4. **A damaged save slot** (non-number or missing `v`) must read as "no record" rather than crash the comparison. Test in Task 5.
5. **The F10 system menu opened mid-round** leaves a dimmed screen behind. The next frame after a stall of more than 250 ms must repaint everything. Tested in Task 4 (unit) and Task 9 (simulator).

## File Structure

| File | Responsibility |
|---|---|
| `lib/lcd.lua` (rewrite) | Globals `LCD` (palette, font with runs, 7-seg with ghosts), `SFX` (tones), `PAD` (`PAD.read()` → held/pressed/repeated) |
| `lib/grid.lua` (new) | `Grid`: cell matrix, stamp/text/curtain helpers, frame, diff `render(now)` → changed row band |
| `lib/panel.lua` (new) | `Panel`: fixed side-panel fields, dirty tracking, NEXT and LIVES sub-grids |
| `lib/screen.lua` (new) | `Screen`: owns grid + panel; full repaint on demand or after a stall; `flushRegion` of the changed band |
| `lib/scores.lua` (new) | `Scores`: read every `hi_<id>` once, `get`, `submit` (high/low order) |
| `lib/runner.lua` (new) | `Runner`: the play scene — round lifecycle, hints, curtain, records, retry, panel sync, `Runner.interval` |
| `lib/menu.lua` (rewrite) | `Menu`: power-on curtain, game number + demo, speed 1–9, start/quit |
| `games/tetris.lua` (rewrite) | Tetris rules on the game contract |
| `main.lua` (rewrite) | Loader, game list (`{ "tetris" }` for now), debug counters, scene adapters, main loop |
| `lib/loader.lua` (delete) | Unused duplicate of `main.lua`'s loader |
| `dev/test/run.lua` + `dev/test/test_*.lua` (new) | Desktop unit tests with a stub `picocalc` |
| `dev/smoke.py` (new) | Simulator smoke test + screenshots |

## The game contract (what Tasks 6–8 build and phase 2 relies on)

```lua
-- games/<id>.lua returns:
{
  id = "tetris", name = "TETRIS",          -- name <= 11 chars
  hint = { "< > MOVE", "UP ROTATE" },      -- 1-3 lines, each <= 17 chars; shown first 3 s
  order = "high",                           -- or "low" (fewer is better, e.g. Memory)
  demo = { frame1, frame2 },                -- 10-col x 12-row patterns ('#' lit) for the menu
  new = function(ctx) return game end,
}
-- ctx = { speed = 1..9, now = ms, interval = function(base_ms, level) -> ms }
game:update(pad, now_ms)   -- pad = PAD.read(); return "over" to end the round
game:draw(grid, next)      -- runner clears both first; grid 10x20, next 4x4
-- fields read by the runner every frame:
game.score, game.score_text (optional display string, e.g. " 03-05"),
game.level, game.lives (nil = unused/ghosted),
game.status (nil or list of up to 3 strings; overrides the hint; status[1]
             replaces "GAME OVER" when the round ends)
```

---

### Task 1: Test harness and `lib/lcd.lua` rewrite

**Files:**
- Create: `dev/test/run.lua`, `dev/test/test_lcd.lua`
- Rewrite: `lib/lcd.lua`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - **Test harness:** globals for every later test file: `test(name, fn)`, `eq(a, b, what)`, `truthy(v, what)`, `raises(fn, what)`, `need(path)` (loads a module once), `CALLS` (recorded display calls `{ name, args... }`), `reset_calls()`, `count_calls(name)`, `SAVES` and `SAVE_LOG` (stub save slots, reset per test).
  - **`LCD` values:** `LCD.BG`, `LCD.DARK`, `LCD.GHOST`, `LCD.FONT[ch]` (5 strings of 3 bits).
  - **`LCD` functions:**
    - `LCD.clear()`
    - `LCD.text(str, x, y, s, color)` (asserts s ≥ 2) → width
    - `LCD.textWidth(str, s)`
    - `LCD.segString(value, digits)` → string
    - `LCD.seg(value, x, y, t, digits)` (asserts t ≥ 3) → width
    - `LCD.segDigit(ch, x, y, t)`
  - **`SFX`:** `SFX.play`, `SFX.update(now)`, `SFX.move/rotate/drop/score/hit/start/over/select/levelup/eat`.
  - **`PAD`:** `PAD.read()` → `{ held = mask, pressed = mask, repeated = mask }`, where each mask has booleans `up down left right enter esc f1`.

- [ ] **Step 1: Create the branch**

```bash
git checkout -b brick15-grid
```

- [ ] **Step 2: Write the test harness**

Create `dev/test/run.lua`:

```lua
-- run.lua — desktop test runner for the Lua libraries and game rules.
-- Run from the app root:  lua dev/test/run.lua
-- A stub `picocalc` records display calls so tests can count draws.

CALLS = {}
SAVES = {}      -- stub SD card: slot name -> table
SAVE_LOG = {}   -- every stub save call, in order: { "get"|"set", name }

local function record(name)
    return function(...) CALLS[#CALLS + 1] = { name, ... } end
end

picocalc = {
    display = {
        rgb = function(r, g, b) return (r << 16) | (g << 8) | b end,
        clear = record("clear"),
        fillRect = record("fillRect"),
        drawRect = record("drawRect"),
        flush = record("flush"),
        flushRegion = record("flushRegion"),
    },
    input = {
        BTN_UP = 1, BTN_DOWN = 2, BTN_LEFT = 4, BTN_RIGHT = 8,
        BTN_ENTER = 16, BTN_ESC = 32, BTN_F1 = 64,
        getButtons = function() return 0 end,
        getButtonsPressed = function() return 0 end,
        getButtonsRepeated = function() return 0 end,
        setRepeat = function() end,
        clearState = function() end,
    },
    audio = { playTone = function() end },
    game = {
        save = {
            get = function(name)
                SAVE_LOG[#SAVE_LOG + 1] = { "get", name }
                return SAVES[name]
            end,
            set = function(name, value)
                SAVE_LOG[#SAVE_LOG + 1] = { "set", name }
                SAVES[name] = value
            end,
        },
    },
}

function reset_calls() CALLS = {} end

function count_calls(name)
    local n = 0
    for _, c in ipairs(CALLS) do
        if c[1] == name then n = n + 1 end
    end
    return n
end

-- ── Tiny test framework ─────────────────────────────────────────────────────

local tests = {}

function test(name, fn) tests[#tests + 1] = { name = name, fn = fn } end

function eq(actual, expected, what)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", what or "value",
            tostring(expected), tostring(actual)), 2)
    end
end

function truthy(v, what)
    if not v then error((what or "value") .. ": expected truthy, got " .. tostring(v), 2) end
end

function raises(fn, what)
    local ok = pcall(fn)
    if ok then error((what or "call") .. ": expected an error", 2) end
end

-- Load a library once; test files call need("lib/grid.lua") etc.
-- lcd.lua sets the LCD, SFX and PAD globals the way main.lua relies on.
local LOADED = {}
function need(path)
    if LOADED[path] == nil then LOADED[path] = dofile(path) or true end
    return LOADED[path]
end

local files = {}
for _, f in ipairs(arg) do files[#files + 1] = f end
if #files == 0 then
    local p = io.popen("ls dev/test/test_*.lua")
    for f in p:lines() do files[#files + 1] = f end
    p:close()
end
for _, f in ipairs(files) do dofile(f) end

local fails = 0
for _, t in ipairs(tests) do
    reset_calls()
    SAVES, SAVE_LOG = {}, {}
    local ok, err = pcall(t.fn)
    if ok then
        print("PASS  " .. t.name)
    else
        fails = fails + 1
        print("FAIL  " .. t.name .. "\n      " .. tostring(err))
    end
end
print(string.format("\n%d tests, %d failed", #tests, fails))
os.exit(fails == 0 and 0 or 1)
```

- [ ] **Step 3: Write the failing tests**

Create `dev/test/test_lcd.lua`:

```lua
need("lib/lcd.lua")

test("font: M, N and W use the fixed patterns", function()
    local M, N, W = LCD.FONT["M"], LCD.FONT["N"], LCD.FONT["W"]
    eq(table.concat(M, ","), "101,111,111,101,101", "M")
    eq(table.concat(N, ","), "110,101,101,101,101", "N")
    eq(table.concat(W, ","), "101,101,111,111,101", "W")
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
```

- [ ] **Step 4: Run them to see them fail**

Run: `lua dev/test/run.lua dev/test/test_lcd.lua`

Expected: FAIL lines against the old `lcd.lua`, e.g. `FAIL  font: M, N and W use the fixed patterns`, and `segString`/`PAD.read` failing with "attempt to call a nil value". The last line reads `N tests, N failed` with N > 0.

- [ ] **Step 5: Rewrite `lib/lcd.lua`**

Replace the whole file with:

```lua
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
```

- [ ] **Step 6: Run the tests to see them pass**

Run: `lua dev/test/run.lua dev/test/test_lcd.lua`
Expected: `10 tests, 0 failed`

- [ ] **Step 7: Commit**

```bash
git add dev/test/run.lua dev/test/test_lcd.lua lib/lcd.lua
git commit -m "lcd: ghost palette, fixed glyphs, run-based text, ghost 7-seg, PAD.read"
```

Note: the old games and old `main.lua` still use `LCD.MID` and scale-1 text, so the app doesn't run again until Task 9. Only the unit tests are the deliverable until then.

---

### Task 2: `lib/grid.lua`

**Files:**
- Create: `lib/grid.lua`, `dev/test/test_grid.lua`

**Interfaces:**
- Consumes: `LCD.BG`, `LCD.DARK`, `LCD.GHOST`, `LCD.FONT` (Task 1).
- Produces:
  - `Grid.new(cols, rows, x, y)`
  - `Grid.PITCH` (15), `Grid.CURTAIN_STEP` (30 ms)
  - `Grid.blink_on(now)`, `Grid.draw_brick(px, py, color)`
  - `g:clear()`, `g:set(c, r, v)` (v: `false`/`true`/`"blink"`, default `true`; off-grid is ignored; fractional coordinates are floored), `g:get(c, r)`
  - `g:stamp(pattern, c, r, v)`, `g:text(str, c, r, v)`
  - `g:curtain(elapsed_ms)` → true once finished
  - `g:draw_frame()`, `g:invalidate()`
  - `g:render(now)` → `y0, y1` or nil
  - Fields `g.cols`, `g.rows`, `g.x`, `g.y`.

- [ ] **Step 1: Write the failing tests**

Create `dev/test/test_grid.lua`:

```lua
need("lib/lcd.lua")
local Grid = need("lib/grid.lua")

test("grid: first render draws every cell as a ghost brick", function()
    local g = Grid.new(10, 20, 12, 10)
    local y0, y1 = g:render(0)
    eq(count_calls("fillRect"), 200 * 3, "3 fills per brick")
    eq(CALLS[1][6], LCD.GHOST, "ghost colour")
    eq(y0, 10, "band top"); eq(y1, 10 + 20 * 15 - 1, "band bottom")
end)

test("grid: render with no change draws nothing", function()
    local g = Grid.new(10, 20, 12, 10)
    g:render(0)
    reset_calls()
    local y0 = g:render(0)
    eq(count_calls("fillRect"), 0, "fills")
    eq(y0, nil, "band")
end)

test("grid: only changed cells redraw, band covers their rows", function()
    local g = Grid.new(10, 20, 12, 10)
    g:render(0)
    reset_calls()
    g:set(3, 5, true)
    local y0, y1 = g:render(0)
    eq(count_calls("fillRect"), 3, "one brick")
    eq(CALLS[1][2], 12 + 2 * 15 + 1, "brick x")
    eq(CALLS[1][3], 10 + 4 * 15 + 1, "brick y")
    eq(CALLS[1][6], LCD.DARK, "lit colour")
    eq(y0, 10 + 4 * 15, "band top"); eq(y1, 10 + 5 * 15 - 1, "band bottom")
end)

test("grid: clear then set the same cell is not a change", function()
    local g = Grid.new(4, 4, 0, 0)
    g:set(1, 1, true)
    g:render(0)
    reset_calls()
    g:clear()
    g:set(1, 1, true)
    g:render(0)
    eq(count_calls("fillRect"), 0, "fills")
end)

test("grid: blink cells follow the shared 250 ms phase", function()
    local g = Grid.new(4, 4, 0, 0)
    g:set(2, 2, "blink")
    g:render(0)                -- on phase
    reset_calls()
    g:render(100)              -- still on
    eq(count_calls("fillRect"), 0, "no change inside a phase")
    g:render(250)              -- off phase
    eq(count_calls("fillRect"), 3, "one brick goes ghost")
    eq(CALLS[1][6], LCD.GHOST, "ghost colour")
end)

test("grid: set and get ignore cells outside the grid", function()
    local g = Grid.new(10, 20, 0, 0)
    g:set(0, 1, true); g:set(11, 1, true); g:set(1, 0, true); g:set(1, 21, true)
    eq(g:get(0, 1), false, "off-grid get")
    for r = 1, 20 do for c = 1, 10 do eq(g:get(c, r), false, "cell") end end
end)

test("grid: fractional coordinates snap down to whole cells", function()
    local g = Grid.new(10, 20, 0, 0)
    g:set(3.7, 4.2, true)
    eq(g:get(3, 4), true, "snapped cell")
end)

test("grid: stamp lights # cells and skips . cells", function()
    local g = Grid.new(10, 20, 0, 0)
    g:stamp({ ".#.", "###" }, 4, 19)
    eq(g:get(4, 19), false, "dot"); eq(g:get(5, 19), true, "top")
    eq(g:get(4, 20), true, "bl"); eq(g:get(6, 20), true, "br")
end)

test("grid: text stamps 3x5 glyphs with a 1-cell gap", function()
    local g = Grid.new(10, 20, 0, 0)
    g:text("11", 1, 1)
    eq(g:get(2, 1), true, "first 1"); eq(g:get(6, 5), true, "second 1")
    eq(g:get(1, 1), false, "glyph edge")
end)

test("grid: invalidate forces a full redraw", function()
    local g = Grid.new(4, 4, 0, 0)
    g:render(0)
    reset_calls()
    g:invalidate()
    g:render(0)
    eq(count_calls("fillRect"), 16 * 3, "every brick")
end)

test("grid: curtain fills from the bottom, then clears from the top", function()
    local g = Grid.new(10, 20, 0, 0)
    eq(g:curtain(0), false, "running")
    eq(g:get(1, 20), true, "bottom row filled first"); eq(g:get(1, 19), false, "row above not yet")
    g:clear(); g:curtain(19 * Grid.CURTAIN_STEP)
    eq(g:get(1, 1), true, "top row filled at the end of the fill")
    g:clear(); g:curtain(20 * Grid.CURTAIN_STEP)
    eq(g:get(1, 1), false, "clearing starts at the top"); eq(g:get(1, 2), true, "rest still full")
    g:clear()
    eq(g:curtain(40 * Grid.CURTAIN_STEP), true, "done")
    eq(g:get(1, 20), false, "empty when done")
end)

test("grid: draw_frame is two DARK rectangles 4px and 3px out", function()
    local g = Grid.new(10, 20, 12, 10)
    g:draw_frame()
    eq(count_calls("drawRect"), 2, "rects")
    eq(CALLS[1][2], 8, "x"); eq(CALLS[1][3], 6, "y"); eq(CALLS[1][4], 158, "w"); eq(CALLS[1][5], 308, "h")
end)
```

- [ ] **Step 2: Run them to see them fail**

Run: `lua dev/test/run.lua dev/test/test_grid.lua`
Expected: the runner stops with `cannot open lib/grid.lua`

- [ ] **Step 3: Write `lib/grid.lua`**

```lua
-- grid.lua — a matrix of LCD bricks that redraws only what changed.
-- Cells are false (unlit), true (lit) or "blink" (lit on the shared 2 Hz
-- phase). Column 1 is the left edge, row 1 the top. Needs the LCD global.

local disp = picocalc.display

local PITCH = 15
local CURTAIN_STEP = 30   -- ms per row of the game-over / power-on curtain

local Grid = {}
Grid.__index = Grid
Grid.PITCH = PITCH
Grid.CURTAIN_STEP = CURTAIN_STEP

function Grid.new(cols, rows, x, y)
    local g = setmetatable({ cols = cols, rows = rows, x = x, y = y,
                             cells = {}, shown = {} }, Grid)
    g:clear()
    return g
end

-- Blinking cells are lit for the first 250 ms of every 500 ms.
function Grid.blink_on(now)
    return (now // 250) % 2 == 0
end

-- A 13x13 framed brick inside a 15x15 cell at (px, py).
function Grid.draw_brick(px, py, color)
    disp.fillRect(px + 1, py + 1, 13, 13, color)
    disp.fillRect(px + 3, py + 3, 9, 9, LCD.BG)
    disp.fillRect(px + 5, py + 5, 5, 5, color)
end

function Grid:clear()
    local cells = self.cells
    for i = 1, self.cols * self.rows do cells[i] = false end
end

function Grid:set(c, r, v)
    c, r = math.floor(c), math.floor(r)
    if c < 1 or c > self.cols or r < 1 or r > self.rows then return end
    if v == nil then v = true end
    self.cells[(r - 1) * self.cols + c] = v
end

function Grid:get(c, r)
    c, r = math.floor(c), math.floor(r)
    if c < 1 or c > self.cols or r < 1 or r > self.rows then return false end
    return self.cells[(r - 1) * self.cols + c]
end

-- pattern: list of strings, '#' = set to v (default lit), anything else skipped.
function Grid:stamp(pattern, c, r, v)
    for dy = 1, #pattern do
        local line = pattern[dy]
        for dx = 1, #line do
            if string.sub(line, dx, dx) == "#" then
                self:set(c + dx - 1, r + dy - 1, v)
            end
        end
    end
end

-- 3x5 font glyphs as bricks, one empty column between characters.
function Grid:text(str, c, r, v)
    str = string.upper(str)
    for i = 1, #str do
        local glyph = LCD.FONT[string.sub(str, i, i)]
        if glyph then
            for dy = 1, 5 do
                for dx = 1, 3 do
                    if string.sub(glyph[dy], dx, dx) == "1" then
                        self:set(c + (i - 1) * 4 + dx - 1, r + dy - 1, v)
                    end
                end
            end
        end
    end
end

-- Overlay the curtain `elapsed` ms after it started: rows fill from the
-- bottom, then clear from the top. Returns true once it has finished.
function Grid:curtain(elapsed)
    local step = elapsed // CURTAIN_STEP
    local rows = self.rows
    if step < rows then
        for r = rows - step, rows do
            for c = 1, self.cols do self:set(c, r, true) end
        end
        return false
    end
    local cleared = step - rows + 1
    for r = 1, rows do
        for c = 1, self.cols do self:set(c, r, r > cleared) end
    end
    return cleared >= rows
end

-- The 2px DARK frame around the grid (drawn by Screen on a full repaint).
function Grid:draw_frame()
    local w, h = self.cols * PITCH, self.rows * PITCH
    disp.drawRect(self.x - 4, self.y - 4, w + 8, h + 8, LCD.DARK)
    disp.drawRect(self.x - 3, self.y - 3, w + 6, h + 6, LCD.DARK)
end

-- Forget what is on screen so the next render redraws every cell.
function Grid:invalidate()
    local shown = self.shown
    for i = 1, self.cols * self.rows do shown[i] = nil end
end

-- Redraw every cell whose visible state differs from what it last drew.
-- Returns the pixel rows touched (y0, y1), or nil if nothing changed.
function Grid:render(now)
    local on = Grid.blink_on(now)
    local cells, shown, cols = self.cells, self.shown, self.cols
    local y0, y1
    for r = 1, self.rows do
        for c = 1, cols do
            local i = (r - 1) * cols + c
            local v = cells[i]
            local lit = v == true or (v == "blink" and on)
            if shown[i] ~= lit then
                local px = self.x + (c - 1) * PITCH
                local py = self.y + (r - 1) * PITCH
                Grid.draw_brick(px, py, lit and LCD.DARK or LCD.GHOST)
                shown[i] = lit
                if not y0 then y0 = py end
                y1 = py + PITCH - 1
            end
        end
    end
    return y0, y1
end

return Grid
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `lua dev/test/run.lua dev/test/test_grid.lua`
Expected: `12 tests, 0 failed`

- [ ] **Step 5: Commit**

```bash
git add lib/grid.lua dev/test/test_grid.lua
git commit -m "grid: brick matrix with diff rendering, blink, stamp, text, curtain"
```

---

### Task 3: `lib/panel.lua`

**Files:**
- Create: `lib/panel.lua`, `dev/test/test_panel.lua`

**Interfaces:**
- Consumes: `Grid.new` (Task 2); `LCD.text`, `LCD.seg` (Task 1).
- Produces:
  - `Panel.new(Grid)`, `Panel.X` (176)
  - `p:set(key, value)`: keys are `label score hi hi_label speed level lives name status1 status2 status3`, and a key is marked dirty only when its value changes.
  - `p:set_status(lines_or_nil)`, `p:invalidate()`
  - `p:render(now)` → `y0, y1` or nil
  - Fields `p.values`, `p.next` (4×4 `Grid` at 176,90), `p.lives` (4×1 `Grid` at 176,226).

- [ ] **Step 1: Write the failing tests**

Create `dev/test/test_panel.lua`:

```lua
need("lib/lcd.lua")
local Grid = need("lib/grid.lua")
local Panel = need("lib/panel.lua")

local function fresh()
    local p = Panel.new(Grid)
    p:render(0)      -- first render paints everything
    reset_calls()
    return p
end

test("panel: first render clears the panel area and draws legends", function()
    local p = Panel.new(Grid)
    local y0, y1 = p:render(0)
    eq(CALLS[1][1], "fillRect", "first call clears")
    eq(CALLS[1][2], Panel.X, "clear x")
    eq(y0, 0, "band top"); eq(y1, 319, "band bottom")
end)

test("panel: nothing changed means nothing drawn", function()
    local p = fresh()
    local y0 = p:render(0)
    eq(#CALLS, 0, "calls"); eq(y0, nil, "band")
end)

test("panel: setting the same value again is not a change", function()
    local p = fresh()
    p:set("score", 120); p:render(0); reset_calls()
    p:set("score", 120)
    eq(p:render(0), nil, "band")
    eq(#CALLS, 0, "calls")
end)

test("panel: a changed field redraws only its own rows", function()
    local p = fresh()
    p:set("score", 120)
    local y0, y1 = p:render(0)
    eq(y0, 22, "score top"); eq(y1, 22 + 24 - 1, "score bottom")
    eq(CALLS[1][6], LCD.BG, "field cleared first")
    for _, c in ipairs(CALLS) do
        truthy(c[3] >= 22 and c[3] < 46, "draw stays inside the score rows")
    end
end)

test("panel: an unused field (nil) still draws ghost segments", function()
    local p = fresh()
    p:set("level", 3); p:render(0); reset_calls()
    p:set("level", nil); p:render(0)
    eq(count_calls("fillRect"), 1 + 2 * 7, "clear + 2 ghost digits")
end)

test("panel: lives light that many of the 4 bricks", function()
    local p = fresh()
    p:set("lives", 2)
    p:render(0)
    eq(p.lives:get(2, 1), true, "life 2"); eq(p.lives:get(3, 1), false, "life 3")
    eq(count_calls("fillRect"), 2 * 3, "two bricks lit")
end)

test("panel: status takes up to three lines", function()
    local p = fresh()
    p:set_status({ "GAME OVER", "ENTER AGAIN" })
    eq(p.values.status1, "GAME OVER", "line 1")
    eq(p.values.status2, "ENTER AGAIN", "line 2")
    eq(p.values.status3, "", "line 3 blank")
    p:set_status(nil)
    eq(p.values.status1, "", "cleared")
end)

test("panel: the NEXT grid renders with the panel", function()
    local p = fresh()
    p.next:set(1, 1, true)
    local y0, y1 = p:render(0)
    eq(y0, 90, "next top"); eq(y1, 104, "next bottom")
end)

test("panel: invalidate repaints everything", function()
    local p = fresh()
    p:invalidate()
    local y0, y1 = p:render(0)
    eq(y0, 0, "top"); eq(y1, 319, "bottom")
    truthy(count_calls("fillRect") > 100, "full repaint")
end)
```

- [ ] **Step 2: Run them to see them fail**

Run: `lua dev/test/run.lua dev/test/test_panel.lua`
Expected: the runner stops with `cannot open lib/panel.lua`

- [ ] **Step 3: Write `lib/panel.lua`**

```lua
-- panel.lua — the side panel, laid out the same in every game and the menu.
-- Fields redraw only when their value changes; unused fields (nil) keep
-- their ghost segments or bricks. Needs the LCD global.

local disp = picocalc.display

local X = 176            -- panel left edge
local W = 320 - X        -- 144px to the screen edge (content uses 136)
local DIGITS_X = X + 48  -- SPEED / LEVEL digits sit right of their legend

local Panel = {}
Panel.__index = Panel
Panel.X = X

local function text(v, y) LCD.text(v or "", X, y, 2, LCD.DARK) end

-- Each field: the keys that dirty it, the rectangle it owns, how to draw it.
local FIELDS = {
    { keys = { "label" }, x = X, y = 8, w = W, h = 10,
      draw = function(v) text(v.label, 8) end },
    { keys = { "score" }, x = X, y = 22, w = W, h = 24,
      draw = function(v) LCD.seg(v.score, X, 22, 4, 6) end },
    { keys = { "hi", "hi_label" }, x = X, y = 50, w = W, h = 18,
      draw = function(v)
          text(v.hi_label or "HI", 54)
          LCD.seg(v.hi, X + 40, 50, 3, 6)
      end },
    { keys = { "speed" }, x = DIGITS_X, y = 160, w = W - 48, h = 18,
      draw = function(v) LCD.seg(v.speed, DIGITS_X, 160, 3, 1) end },
    { keys = { "level" }, x = DIGITS_X, y = 184, w = W - 48, h = 18,
      draw = function(v) LCD.seg(v.level, DIGITS_X, 184, 3, 2) end },
    { keys = { "name" }, x = X, y = 252, w = W, h = 10,
      draw = function(v) text(v.name, 252) end },
    { keys = { "status1" }, x = X, y = 270, w = W, h = 10,
      draw = function(v) text(v.status1, 270) end },
    { keys = { "status2" }, x = X, y = 284, w = W, h = 10,
      draw = function(v) text(v.status2, 284) end },
    { keys = { "status3" }, x = X, y = 298, w = W, h = 10,
      draw = function(v) text(v.status3, 298) end },
}

-- Printed legends: drawn once per full repaint.
local LEGENDS = { { "NEXT", 76 }, { "SPEED", 164 }, { "LEVEL", 188 }, { "LIVES", 212 } }

function Panel.new(Grid)
    local p = setmetatable({ values = {}, dirty = {}, full = true }, Panel)
    p.next = Grid.new(4, 4, X, 90)
    p.lives = Grid.new(4, 1, X, 226)
    return p
end

function Panel:set(key, value)
    if self.values[key] ~= value then
        self.values[key] = value
        self.dirty[key] = true
    end
end

-- lines: nil or a list of up to 3 strings (at most 17 characters each).
function Panel:set_status(lines)
    lines = lines or {}
    for i = 1, 3 do self:set("status" .. i, lines[i] or "") end
end

function Panel:invalidate()
    self.full = true
end

-- Draw what changed. Returns the pixel rows touched (y0, y1) or nil.
function Panel:render(now)
    local y0, y1
    local function touch(a, b)
        if not y0 or a < y0 then y0 = a end
        if not y1 or b > y1 then y1 = b end
    end

    local full = self.full
    if full then
        disp.fillRect(X, 0, W, 320, LCD.BG)
        for _, l in ipairs(LEGENDS) do text(l[1], l[2]) end
        self.next:invalidate()
        self.lives:invalidate()
        touch(0, 319)
        self.full = false
    end

    for _, f in ipairs(FIELDS) do
        local dirty = full
        for _, k in ipairs(f.keys) do
            if self.dirty[k] then dirty = true end
        end
        if dirty then
            disp.fillRect(f.x, f.y, f.w, f.h, LCD.BG)
            f.draw(self.values)
            touch(f.y, f.y + f.h - 1)
        end
    end
    self.dirty = {}

    local n = self.values.lives
    for i = 1, 4 do self.lives:set(i, 1, n ~= nil and i <= n) end
    local a, b = self.next:render(now)
    if a then touch(a, b) end
    a, b = self.lives:render(now)
    if a then touch(a, b) end
    return y0, y1
end

return Panel
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `lua dev/test/run.lua dev/test/test_panel.lua`
Expected: `9 tests, 0 failed`

- [ ] **Step 5: Commit**

```bash
git add lib/panel.lua dev/test/test_panel.lua
git commit -m "panel: fixed side panel with per-field dirty redraw"
```

---

### Task 4: `lib/screen.lua`

**Files:**
- Create: `lib/screen.lua`, `dev/test/test_screen.lua`

**Interfaces:**
- Consumes: a `Grid` (Task 2) and a `Panel` (Task 3); `LCD.clear` (Task 1); the display's `flushRegion`.
- Produces:
  - `Screen.new(disp, grid, panel)`, `s:repaint()`
  - `s:present(now)` → true if anything was drawn. A gap of more than 250 ms since the last present forces a full repaint.
  - Fields `s.grid`, `s.panel`.

- [ ] **Step 1: Write the failing tests**

Create `dev/test/test_screen.lua`:

```lua
need("lib/lcd.lua")
local Grid = need("lib/grid.lua")
local Panel = need("lib/panel.lua")
local Screen = need("lib/screen.lua")

local function new_screen()
    local grid = Grid.new(10, 20, 12, 10)
    return Screen.new(picocalc.display, grid, Panel.new(Grid)), grid
end

local function flushes()
    local out = {}
    for _, c in ipairs(CALLS) do
        if c[1] == "flushRegion" then out[#out + 1] = { c[2], c[3] } end
        if c[1] == "flush" then out[#out + 1] = { "full" } end
    end
    return out
end

test("screen: first present clears, frames and flushes the whole screen", function()
    local s = new_screen()
    s:present(0)
    eq(CALLS[1][1], "clear", "clears first")
    eq(count_calls("drawRect"), 2, "frame")
    local f = flushes()
    eq(#f, 1, "one flush"); eq(f[1][1], 0, "from 0"); eq(f[1][2], 319, "to 319")
end)

test("screen: an unchanged frame draws and flushes nothing", function()
    local s = new_screen()
    s:present(0)
    reset_calls()
    s:present(16)
    eq(#CALLS, 0, "no calls at all")
end)

test("screen: a changed cell flushes only its rows", function()
    local s, grid = new_screen()
    s:present(0)
    reset_calls()
    grid:set(1, 1, true)
    s:present(16)
    local f = flushes()
    eq(#f, 1, "one flush"); eq(f[1][1], 10, "top"); eq(f[1][2], 24, "bottom")
end)

test("screen: never uses the buffer-swapping full flush", function()
    local s, grid = new_screen()
    s:present(0); grid:set(2, 2, true); s:present(16)
    eq(count_calls("flush"), 0, "display.flush calls")
end)

test("screen: a stall longer than 250 ms repaints everything", function()
    local s = new_screen()
    s:present(0)
    s:present(16)
    reset_calls()
    s:present(16 + 251)
    eq(CALLS[1][1], "clear", "full repaint after the system menu")
end)

test("screen: repaint() forces a full repaint on the next present", function()
    local s = new_screen()
    s:present(0)
    reset_calls()
    s:repaint()
    s:present(16)
    local f = flushes()
    eq(f[1][1], 0, "from 0"); eq(f[1][2], 319, "to 319")
end)
```

- [ ] **Step 2: Run them to see them fail**

Run: `lua dev/test/run.lua dev/test/test_screen.lua`
Expected: the runner stops with `cannot open lib/screen.lua`

- [ ] **Step 3: Write `lib/screen.lua`**

```lua
-- screen.lua — owns the grid and the panel, and puts only what changed on
-- the LCD. Shared by the menu and the play runner. Needs the LCD global.
--
-- display.flush() swaps two framebuffers without copying, so a partial
-- redraw would land on a frame from two flushes ago. display.flushRegion
-- sends just the changed rows and copies them into the other buffer, which
-- keeps both buffers identical and partial redraws correct.

local STALL_MS = 250   -- a longer gap between frames means the OS (e.g. the
                       -- F10 system menu) had the screen: repaint it all

local Screen = {}
Screen.__index = Screen

function Screen.new(disp, grid, panel)
    return setmetatable({ disp = disp, grid = grid, panel = panel,
                          full = true, last = nil }, Screen)
end

function Screen:repaint()
    self.full = true
end

-- Render the grid and panel; flush the changed rows. Returns true if
-- anything was drawn.
function Screen:present(now)
    if self.last and now - self.last > STALL_MS then self.full = true end
    self.last = now

    local y0, y1
    if self.full then
        LCD.clear()
        self.grid:draw_frame()
        self.grid:invalidate()
        self.panel:invalidate()
        y0, y1 = 0, 319
        self.full = false
    end

    local a, b = self.grid:render(now)
    if a then
        if not y0 or a < y0 then y0 = a end
        if not y1 or b > y1 then y1 = b end
    end
    a, b = self.panel:render(now)
    if a then
        if not y0 or a < y0 then y0 = a end
        if not y1 or b > y1 then y1 = b end
    end

    if y0 then self.disp.flushRegion(y0, y1) end
    return y0 ~= nil
end

return Screen
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `lua dev/test/run.lua dev/test/test_screen.lua`
Expected: `6 tests, 0 failed`

- [ ] **Step 5: Commit**

```bash
git add lib/screen.lua dev/test/test_screen.lua
git commit -m "screen: repaint on demand or after a stall, flushRegion of changed rows"
```

---

### Task 5: `lib/scores.lua`

**Files:**
- Create: `lib/scores.lua`, `dev/test/test_scores.lua`

**Interfaces:**
- Consumes: a save object with `get(name)` / `set(name, table)` (`picocalc.game.save`, or the stub).
- Produces:
  - `Scores.new(save, games)`, where `games` is a list of `{ id = ... }`.
  - `s:get(id)` → number or nil.
  - `s:submit(id, value, order)` → true on a new record, saving `hi_<id>` = `{ v = value }`.

- [ ] **Step 1: Write the failing tests**

Create `dev/test/test_scores.lua`:

```lua
local Scores = need("lib/scores.lua")
local save = picocalc.game.save

local GAMES = { { id = "tetris" }, { id = "memory" } }

local function gets() local n = 0 for _, e in ipairs(SAVE_LOG) do if e[1] == "get" then n = n + 1 end end return n end
local function sets() local n = 0 for _, e in ipairs(SAVE_LOG) do if e[1] == "set" then n = n + 1 end end return n end

test("scores: load reads each game's slot exactly once", function()
    SAVES.hi_tetris = { v = 500 }
    local s = Scores.new(save, GAMES)
    eq(gets(), 2, "reads at load")
    eq(s:get("tetris"), 500, "cached"); eq(s:get("memory"), nil, "no record")
    s:get("tetris"); s:get("tetris")
    eq(gets(), 2, "get never touches the SD card")
end)

test("scores: a higher score is a record and is saved", function()
    SAVES.hi_tetris = { v = 500 }
    local s = Scores.new(save, GAMES)
    eq(s:submit("tetris", 400, "high"), false, "lower is not a record")
    eq(sets(), 0, "nothing written")
    eq(s:submit("tetris", 600, "high"), true, "higher is a record")
    eq(sets(), 1, "written once"); eq(SAVES.hi_tetris.v, 600, "stored")
    eq(s:get("tetris"), 600, "cache updated")
end)

test("scores: zero is never a record", function()
    local s = Scores.new(save, GAMES)
    eq(s:submit("tetris", 0, "high"), false, "zero")
    eq(sets(), 0, "nothing written")
end)

test("scores: low order keeps the smallest, 0 or nil means no record yet", function()
    SAVES.hi_memory = { v = 0 }
    local s = Scores.new(save, GAMES)
    eq(s:submit("memory", 30, "low"), true, "first result is a record")
    eq(s:submit("memory", 35, "low"), false, "more turns is worse")
    eq(s:submit("memory", 22, "low"), true, "fewer turns is better")
    eq(s:get("memory"), 22, "best")
end)

test("scores: a damaged slot reads as no record and can be beaten", function()
    SAVES.hi_tetris = { v = "abc" }
    SAVES.hi_memory = {}
    local s = Scores.new(save, GAMES)
    eq(s:get("tetris"), nil, "string value"); eq(s:get("memory"), nil, "missing value")
    eq(s:submit("tetris", 10, "high"), true, "first real score is a record")
end)

test("scores: a stored 0 in low order shows as no record", function()
    SAVES.hi_memory = { v = 0 }
    local s = Scores.new(save, GAMES)
    eq(s:get("memory"), nil, "0 reads as nil")
end)
```

- [ ] **Step 2: Run them to see them fail**

Run: `lua dev/test/run.lua dev/test/test_scores.lua`
Expected: the runner stops with `cannot open lib/scores.lua`

- [ ] **Step 3: Write `lib/scores.lua`**

```lua
-- scores.lua — high scores, read from the SD card once at startup and
-- written back only when a record is beaten. Slots are "hi_<game id>".

local Scores = {}
Scores.__index = Scores

-- save: picocalc.game.save (or a stub); games: list of { id = ... }.
function Scores.new(save, games)
    local s = setmetatable({ save = save, cache = {} }, Scores)
    for _, g in ipairs(games) do
        local rec = save.get("hi_" .. g.id)
        local v = type(rec) == "table" and rec.v or nil
        -- 0 means "no record" ("low" games need that); anything that isn't a
        -- positive number is a damaged slot and is treated the same way.
        if type(v) ~= "number" or v <= 0 then v = nil end
        s.cache[g.id] = v
    end
    return s
end

-- The record, or nil if there is none yet.
function Scores:get(id)
    return self.cache[id]
end

-- order: "high" (default, bigger is better) or "low" (fewer is better).
-- Returns true, and saves, only when value beats the record.
function Scores:submit(id, value, order)
    if not value or value <= 0 then return false end
    local best = self.cache[id]
    local better
    if order == "low" then
        better = best == nil or value < best
    else
        better = best == nil or value > best
    end
    if better then
        self.cache[id] = value
        self.save.set("hi_" .. id, { v = value })
    end
    return better
end

return Scores
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `lua dev/test/run.lua dev/test/test_scores.lua`
Expected: `6 tests, 0 failed`

- [ ] **Step 5: Commit**

```bash
git add lib/scores.lua dev/test/test_scores.lua
git commit -m "scores: read records once, save only new records"
```

---

### Task 6: `lib/runner.lua`

**Files:**
- Create: `lib/runner.lua`, `dev/test/test_runner.lua`

**Interfaces:**
- Consumes:
  - `Screen` (Task 4), `Scores` (Task 5), `Grid:curtain` (Task 2)
  - `PAD.read`, `SFX.start/over/levelup` (Task 1)
  - an `input` table with `setRepeat`/`clearState`
  - a `scene` table with `switch(name)`
- Produces:
  - `Runner.interval(base_ms, speed, level)` = `max(40, base_ms * 0.87^(speed + level - 2))`.
  - `Runner.new({ screen, scores, scene, clock, input })`.
  - `r:start(def, speed)`, called by the menu before switching to `"play"`.
  - `r:enter()`, `r:exit()`, `r:update()`, `r:draw()`.
  - `r.state` is `"play"`, `"curtain"` or `"over"`.
  - The game contract above: the `ctx` passed to `def.new`, and the fields the runner reads.

- [ ] **Step 1: Write the failing tests**

Create `dev/test/test_runner.lua`:

```lua
need("lib/lcd.lua")
local Grid = need("lib/grid.lua")
local Panel = need("lib/panel.lua")
local Screen = need("lib/screen.lua")
local Scores = need("lib/scores.lua")
local Runner = need("lib/runner.lua")

local input = picocalc.input

-- A fake game: ends its round when `over_next` is set.
local function fake_def(opts)
    opts = opts or {}
    local def = { id = "fake", name = "FAKE", hint = { "HINT LINE" },
                  order = opts.order or "high", demo = {}, made = 0 }
    def.new = function(ctx)
        def.made = def.made + 1
        def.ctx = ctx
        local game = { score = opts.score or 0, level = 1, lives = 3 }
        function game:update(pad, now)
            if def.over_next then def.over_next = false return "over" end
        end
        function game:draw(grid, next) grid:set(1, 1, true) end
        return game
    end
    return def
end

local T = 0
local function setup(def)
    T = 0
    local grid = Grid.new(10, 20, 12, 10)
    local screen = Screen.new(picocalc.display, grid, Panel.new(Grid))
    local switched = {}
    local r = Runner.new({
        screen = screen,
        scores = Scores.new(picocalc.game.save, { def }),
        scene = { switch = function(name) switched[#switched + 1] = name end },
        clock = function() return T end,
        input = input,
    })
    r:start(def, 3)
    r:enter()
    return r, screen, switched
end

local function with_pressed(mask, fn)
    local old = input.getButtonsPressed
    input.getButtonsPressed = function() return mask end
    fn()
    input.getButtonsPressed = old
end

local function frame(r, dt)
    T = T + (dt or 16)
    r:update()
    r:draw()
end

test("runner: interval shrinks with speed and level, floor 40 ms", function()
    eq(Runner.interval(800, 1, 1), 800, "speed 1 level 1")
    eq(math.floor(Runner.interval(800, 2, 1)), 696, "speed 2")
    eq(math.floor(Runner.interval(800, 1, 2)), 696, "level 2")
    eq(Runner.interval(800, 9, 30), 40, "floor")
end)

test("runner: a round gets the chosen speed and an interval helper", function()
    local def = fake_def()
    setup(def)
    eq(def.made, 1, "one game made")
    eq(def.ctx.speed, 3, "speed passed")
    eq(math.floor(def.ctx.interval(800, 1)), math.floor(Runner.interval(800, 3, 1)), "interval uses speed")
end)

test("runner: the hint shows for the first 3 s of a round", function()
    local def = fake_def()
    local r, screen = setup(def)
    frame(r)
    eq(screen.panel.values.status1, "HINT LINE", "hint")
    T = 3001; frame(r, 0)
    eq(screen.panel.values.status1, "", "hint gone")
end)

test("runner: Esc returns to the menu", function()
    local r, _, switched = setup(fake_def())
    with_pressed(input.BTN_ESC, function() frame(r) end)
    eq(switched[1], "menu", "switched")
end)

test("runner: game over plays the curtain, then shows the over status", function()
    local def = fake_def()
    local r, screen = setup(def)
    frame(r)
    def.over_next = true
    frame(r)
    eq(r.state, "curtain", "curtain starts")
    eq(screen.panel.values.status1, "GAME OVER", "line 1 during curtain")
    for _ = 1, 100 do frame(r, 30) end
    eq(r.state, "over", "curtain finished")
    eq(screen.panel.values.status2, "ENTER AGAIN", "line 2")
    eq(screen.panel.values.status3, "ESC MENU", "line 3")
    eq(screen.grid:get(1, 1), false, "grid cleared after the curtain")
end)

test("runner: Esc during the curtain still returns to the menu", function()
    local def = fake_def()
    local r, _, switched = setup(def)
    def.over_next = true
    frame(r)
    with_pressed(input.BTN_ESC, function() frame(r) end)
    eq(switched[1], "menu", "switched")
end)

test("runner: Enter during the curtain does not restart the round", function()
    local def = fake_def()
    local r = setup(def)
    def.over_next = true
    frame(r)
    with_pressed(input.BTN_ENTER, function() frame(r) end)
    eq(def.made, 1, "still the first round")
    eq(r.state, "curtain", "curtain continues")
end)

test("runner: a beaten record says NEW HI and is saved", function()
    local def = fake_def({ score = 50 })
    local r, screen = setup(def)
    def.over_next = true
    frame(r)
    eq(screen.panel.values.status1, "NEW HI", "record")
    eq(SAVES.hi_fake.v, 50, "saved")
end)

test("runner: Enter after game over starts a new round", function()
    local def = fake_def()
    local r = setup(def)
    def.over_next = true
    frame(r)
    for _ = 1, 100 do frame(r, 30) end
    with_pressed(input.BTN_ENTER, function() frame(r) end)
    eq(def.made, 2, "second round")
    eq(r.state, "play", "playing again")
end)

test("runner: the game-over screen draws nothing while idle", function()
    local def = fake_def()
    local r = setup(def)
    def.over_next = true
    frame(r)
    for _ = 1, 100 do frame(r, 30) end
    reset_calls()
    frame(r); frame(r)
    eq(count_calls("fillRect"), 0, "no draws")
    eq(count_calls("flushRegion"), 0, "no flushes")
end)

test("runner: lower-is-better games label the record BEST", function()
    local r, screen = setup(fake_def({ order = "low" }))
    frame(r)
    eq(screen.panel.values.hi_label, "BEST", "label")
end)
```

- [ ] **Step 2: Run them to see them fail**

Run: `lua dev/test/run.lua dev/test/test_runner.lua`
Expected: the runner stops with `cannot open lib/runner.lua`

- [ ] **Step 3: Write `lib/runner.lua`**

```lua
-- runner.lua — the "play" scene. Hosts one game at a time and owns what
-- every game shares: Esc to the menu, control hints, the game-over curtain,
-- saving records, retry, and the panel. Needs the LCD, SFX and PAD globals.

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
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `lua dev/test/run.lua dev/test/test_runner.lua`
Expected: `11 tests, 0 failed`

- [ ] **Step 5: Commit**

```bash
git add lib/runner.lua dev/test/test_runner.lua
git commit -m "runner: shared play scene with hints, curtain, records and retry"
```

---

### Task 7: Tetris on the game contract

**Files:**
- Rewrite: `games/tetris.lua`
- Create: `dev/test/test_tetris.lua`

**Interfaces:**
- Consumes: the game contract (Task 6), the `Grid` API (Task 2), `SFX` (Task 1).
- Produces: a module `{ id = "tetris", name = "TETRIS", hint, order = "high", demo, new, PIECES }`. Its game table exposes `score`, `level`, `lines`, `well[r][c]`, `piece`, `ptype`, `rot`, `px`, `py`, `next_type`, `next_fall` and `flash` (the tests set these directly).

- [ ] **Step 1: Write the failing tests**

Create `dev/test/test_tetris.lua`:

```lua
need("lib/lcd.lua")
local Grid = need("lib/grid.lua")
local tetris = need("games/tetris.lua")

local NONE = { held = {}, pressed = {}, repeated = {} }

local function new_game()
    return tetris.new({ speed = 1, now = 0,
                        interval = function(base_ms) return base_ms end })
end

local function fill_row(game, r, except_from, except_to)
    for c = 1, 10 do
        game.well[r][c] = not (c >= except_from and c <= except_to)
    end
end

test("tetris: module metadata follows the game contract", function()
    eq(tetris.id, "tetris", "id"); eq(tetris.name, "TETRIS", "name")
    eq(tetris.order, "high", "order")
    eq(#tetris.demo, 2, "two demo frames")
    for _, f in ipairs(tetris.demo) do
        eq(#f, 12, "12 rows")
        for _, row in ipairs(f) do eq(#row, 10, "10 columns") end
    end
    truthy(#tetris.hint >= 1 and #tetris.hint <= 3, "1-3 hint lines")
end)

test("tetris: name and hint fit the panel and use only font glyphs", function()
    truthy(#tetris.name <= 11, "name at most 11 characters")
    local lines = { tetris.name }
    for _, h in ipairs(tetris.hint) do
        truthy(#h <= 17, "hint line at most 17 characters: " .. h)
        lines[#lines + 1] = h
    end
    for _, l in ipairs(lines) do
        for ch in string.upper(l):gmatch(".") do
            truthy(LCD.FONT[ch], "font has '" .. ch .. "' (" .. l .. ")")
        end
    end
end)

test("tetris: a new game starts at score 0, level 1, no lives field", function()
    local g = new_game()
    eq(g.score, 0, "score"); eq(g.level, 1, "level"); eq(g.lives, nil, "lives unused")
end)

test("tetris: the piece falls one row per interval", function()
    local g = new_game()
    local y = g.py
    g:update(NONE, 799)
    eq(g.py, y, "not yet")
    g:update(NONE, 800)
    eq(g.py, y + 1, "one row down")
end)

test("tetris: a full row flashes, then clears and scores 100 x level", function()
    local g = new_game()
    fill_row(g, 20, 1, 4)                   -- gap in cols 1-4
    g.ptype, g.rot = 1, 1                    -- I piece, flat: cells (0..3, 1)
    g.piece = tetris.PIECES[1][1]
    g.px, g.py = 1, 19                       -- occupies row 20, cols 1-4
    g.next_fall = 0
    g:update(NONE, 0)                        -- can't fall: locks
    truthy(g.flash, "row flashes")
    g:update(NONE, 299)
    truthy(g.flash, "still flashing")
    g:update(NONE, 300)
    eq(g.flash, nil, "flash over")
    eq(g.score, 100, "score")
    for c = 1, 10 do eq(g.well[20][c], false, "bottom row empty") end
end)

test("tetris: ten lines raise the level", function()
    local g = new_game()
    g.lines = 9
    fill_row(g, 20, 1, 4)
    g.piece, g.ptype, g.rot = tetris.PIECES[1][1], 1, 1
    g.px, g.py, g.next_fall = 1, 19, 0
    g:update(NONE, 0); g:update(NONE, 300)
    eq(g.level, 2, "level 2")
end)

test("tetris: a blocked spawn ends the round", function()
    local g = new_game()
    for r = 1, 3 do fill_row(g, r, 10, 10) end            -- spawn area full, col 10 open
    g.piece, g.ptype, g.rot = tetris.PIECES[2][1], 2, 1   -- O piece
    g.px, g.py, g.next_fall = 1, 19, 0                    -- resting on the floor
    eq(g:update(NONE, 0), "over", "round over")
end)

test("tetris: left moves the piece, walls stop it", function()
    local g = new_game()
    local x = g.px
    g:update({ held = {}, pressed = {}, repeated = { left = true } }, 1)
    eq(g.px, x - 1, "moved left")
    for _ = 1, 10 do g:update({ held = {}, pressed = {}, repeated = { left = true } }, 1) end
    local minx = 99
    for _, c in ipairs(g.piece) do minx = math.min(minx, g.px + c[1]) end
    eq(minx, 1, "stopped at the wall")
end)

test("tetris: draw puts the piece on the grid and the next piece in NEXT", function()
    local g = new_game()
    local grid, nextg = Grid.new(10, 20, 0, 0), Grid.new(4, 4, 0, 0)
    g:draw(grid, nextg)
    local lit = 0
    for r = 1, 20 do for c = 1, 10 do if grid:get(c, r) then lit = lit + 1 end end end
    eq(lit, 4, "four piece cells")
    local nlit = 0
    for r = 1, 4 do for c = 1, 4 do if nextg:get(c, r) then nlit = nlit + 1 end end end
    eq(nlit, 4, "next piece shown")
end)
```

- [ ] **Step 2: Run them to see them fail**

Run: `lua dev/test/run.lua dev/test/test_tetris.lua`
Expected: FAIL lines against the old `games/tetris.lua`, e.g. `FAIL  tetris: module metadata follows the game contract`.

- [ ] **Step 3: Rewrite `games/tetris.lua`**

Replace the whole file with:

```lua
-- tetris.lua — game 01: falling blocks in the 10x20 well.
-- Game contract: see lib/runner.lua. Needs the SFX global.

local COLS, ROWS = 10, 20
local FALL_MS = 800        -- gravity at speed 1, level 1
local DROP_MS = 40         -- gravity while Down is held
local FLASH_MS = 300       -- a cleared row blinks this long before it goes

-- Cell offsets {x, y} (0-based) for each rotation of each piece.
local PIECES = {
    { { {0,1},{1,1},{2,1},{3,1} }, { {2,0},{2,1},{2,2},{2,3} } }, -- I
    { { {0,0},{1,0},{0,1},{1,1} } },                                     -- O
    { { {1,0},{0,1},{1,1},{2,1} }, { {1,0},{0,1},{1,1},{1,2} },
      { {0,1},{1,1},{2,1},{1,2} }, { {1,0},{1,1},{2,1},{1,2} } },      -- T
    { { {1,0},{2,0},{0,1},{1,1} }, { {1,0},{1,1},{2,1},{2,2} } },      -- S
    { { {0,0},{1,0},{1,1},{2,1} }, { {2,0},{1,1},{2,1},{1,2} } },      -- Z
    { { {0,0},{0,1},{1,1},{2,1} }, { {1,0},{2,0},{1,1},{1,2} },
      { {0,1},{1,1},{2,1},{2,2} }, { {1,0},{1,1},{0,2},{1,2} } },      -- J
    { { {2,0},{0,1},{1,1},{2,1} }, { {1,0},{1,1},{1,2},{2,2} },
      { {0,1},{1,1},{2,1},{0,2} }, { {0,0},{1,0},{1,1},{1,2} } },      -- L
}

local LINE_SCORE = { 100, 300, 500, 800 }

local DEMO = {
    {
        "....##....",
        "....##....",
        "..........",
        "..........",
        "..........",
        "..........",
        "..........",
        "..........",
        "#.........",
        "##.....#..",
        "###.#.####",
        "####.#####",
    },
    {
        "..........",
        "..........",
        "..........",
        "..........",
        "..........",
        "..........",
        "..........",
        "....##....",
        "#...##....",
        "##.....#..",
        "###.#.####",
        "####.#####",
    },
}

local function new(ctx)
    local game = { score = 0, level = 1, lines = 0 }

    game.well = {}
    for r = 1, ROWS do
        game.well[r] = {}
        for c = 1, COLS do game.well[r][c] = false end
    end

    local function collides(cells, x, y)
        for _, c in ipairs(cells) do
            local cx, cy = x + c[1], y + c[2]
            if cx < 1 or cx > COLS or cy > ROWS then return true end
            if cy >= 1 and game.well[cy][cx] then return true end
        end
        return false
    end

    -- Returns false when the new piece has nowhere to go (round over).
    local function spawn()
        game.ptype = game.next_type
        game.rot = 1
        game.piece = PIECES[game.ptype][1]
        game.px, game.py = 4, 1
        game.next_type = math.random(#PIECES)
        return not collides(game.piece, game.px, game.py)
    end

    local function try_move(dx, dy)
        if collides(game.piece, game.px + dx, game.py + dy) then return false end
        game.px, game.py = game.px + dx, game.py + dy
        return true
    end

    local function rotate()
        local defs = PIECES[game.ptype]
        local rot = game.rot % #defs + 1
        for _, dx in ipairs({ 0, -1, 1, -2, 2 }) do
            if not collides(defs[rot], game.px + dx, game.py) then
                game.rot, game.piece = rot, defs[rot]
                game.px = game.px + dx
                SFX.rotate()
                return
            end
        end
    end

    -- Lock the piece into the well; full rows start flashing.
    local function lock(now)
        for _, c in ipairs(game.piece) do
            local x, y = game.px + c[1], game.py + c[2]
            if y >= 1 then game.well[y][x] = true end
        end
        game.piece = nil
        local full = {}
        for r = 1, ROWS do
            local all = true
            for c = 1, COLS do
                if not game.well[r][c] then all = false break end
            end
            if all then full[#full + 1] = r end
        end
        if #full > 0 then
            game.flash = { rows = full, until_ms = now + FLASH_MS }
        else
            SFX.drop()
        end
    end

    -- Remove the flashed rows, score them, and bring in the next piece.
    local function clear_rows()
        local rows = game.flash.rows
        for i = #rows, 1, -1 do table.remove(game.well, rows[i]) end
        for _ = 1, #rows do
            local fresh = {}
            for c = 1, COLS do fresh[c] = false end
            table.insert(game.well, 1, fresh)
        end
        game.lines = game.lines + #rows
        game.score = game.score + LINE_SCORE[#rows] * game.level
        game.level = game.lines // 10 + 1
        if #rows == 4 then SFX.levelup() else SFX.score() end
        game.flash = nil
    end

    function game:update(pad, now)
        self.now = now
        if self.flash then
            if now < self.flash.until_ms then return nil end
            clear_rows()
            if not spawn() then return "over" end
            self.next_fall = now + ctx.interval(FALL_MS, self.level)
            return nil
        end

        if pad.repeated.left then try_move(-1, 0) end
        if pad.repeated.right then try_move(1, 0) end
        if pad.pressed.up or pad.pressed.enter or pad.pressed.f1 then rotate() end

        if now >= self.next_fall then
            local step = pad.held.down and DROP_MS or ctx.interval(FALL_MS, self.level)
            self.next_fall = now + step
            if not try_move(0, 1) then
                lock(now)
                if not self.flash and not spawn() then return "over" end
            end
        elseif pad.held.down and self.next_fall - now > DROP_MS then
            self.next_fall = now + DROP_MS
        end
        return nil
    end

    function game:draw(grid, next)
        local flashing = {}
        if self.flash then
            local on = ((self.now or 0) // 75) % 2 == 0
            for _, r in ipairs(self.flash.rows) do flashing[r] = on end
        end
        for r = 1, ROWS do
            for c = 1, COLS do
                if self.well[r][c] then
                    local v = true
                    if flashing[r] ~= nil then v = flashing[r] end
                    grid:set(c, r, v)
                end
            end
        end
        if self.piece then
            for _, c in ipairs(self.piece) do
                grid:set(self.px + c[1], self.py + c[2], true)
            end
        end
        for _, c in ipairs(PIECES[self.next_type][1]) do
            next:set(c[1] + 1, c[2] + 1, true)
        end
    end

    game.next_type = math.random(#PIECES)
    spawn()
    game.next_fall = ctx.now + ctx.interval(FALL_MS, game.level)
    return game
end

return {
    id = "tetris",
    name = "TETRIS",
    hint = { "< > MOVE", "UP ROTATE", "DOWN DROP" },
    order = "high",
    demo = DEMO,
    new = new,
    PIECES = PIECES,
}
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `lua dev/test/run.lua dev/test/test_tetris.lua`
Expected: `9 tests, 0 failed`

- [ ] **Step 5: Commit**

```bash
git add games/tetris.lua dev/test/test_tetris.lua
git commit -m "tetris: port to the grid game contract"
```

---

### Task 8: `lib/menu.lua` brick selector

**Files:**
- Rewrite: `lib/menu.lua`
- Create: `dev/test/test_menu.lua`

**Interfaces:**
- Consumes:
  - `Screen` (Task 4), `Scores` (Task 5), `Grid:curtain/text/stamp` (Task 2)
  - `r:start(def, speed)` (Task 6)
  - `PAD.read`, `SFX.start/select` (Task 1)
- Produces:
  - `Menu.new({ screen, games, scores, runner, scene, clock, input })`.
  - `m:enter()`, `m:exit()`, `m:update()`, `m:draw()`.
  - Fields `m.sel`, `m.speed`, `m.booted`, and `m.quit`, which `main.lua` polls.

- [ ] **Step 1: Write the failing tests**

Create `dev/test/test_menu.lua`:

```lua
need("lib/lcd.lua")
local Grid = need("lib/grid.lua")
local Panel = need("lib/panel.lua")
local Screen = need("lib/screen.lua")
local Scores = need("lib/scores.lua")
local Menu = need("lib/menu.lua")

local input = picocalc.input
local T = 0
local BOOT = 40 * Grid.CURTAIN_STEP   -- long enough for the power-on curtain

local function def(id, order)
    return { id = id, name = string.upper(id), hint = {}, order = order or "high",
             demo = { { "#" }, { ".#" } }, new = function() end }
end

local function setup(games)
    T = 0
    games = games or { def("aaa"), def("bbb"), def("ccc", "low") }
    local grid = Grid.new(10, 20, 12, 10)
    local screen = Screen.new(picocalc.display, grid, Panel.new(Grid))
    local runner = { started = nil }
    function runner:start(d, speed) self.started = { def = d, speed = speed } end
    local switched = {}
    local m = Menu.new({
        screen = screen, games = games,
        scores = Scores.new(picocalc.game.save, games),
        runner = runner,
        scene = { switch = function(name) switched[#switched + 1] = name end },
        clock = function() return T end,
        input = input,
    })
    m:enter()
    return m, screen, runner, switched
end

local function frame(m, dt)
    T = T + (dt or 16)
    m:update()
    m:draw()
end

local function boot(m)
    for _ = 1, BOOT // 30 + 2 do frame(m, 30) end
end

local function with(getter, mask, fn)
    local old = input[getter]
    input[getter] = function() return mask end
    fn()
    input[getter] = old
end

test("menu: the power-on curtain plays first and blocks input", function()
    local m = setup()
    frame(m)
    eq(m.booted, false, "booting")
    with("getButtonsRepeated", input.BTN_RIGHT, function() frame(m) end)
    eq(m.sel, 1, "input ignored during the curtain")
    boot(m)
    eq(m.booted, true, "booted")
end)

test("menu: shows the game number as big brick digits", function()
    local m, screen = setup()
    boot(m)
    -- "0" at cols 2-4 (top row 111), "1" at cols 7-9 (top row 010)
    eq(screen.grid:get(2, 2), true, "0 top-left"); eq(screen.grid:get(3, 3), false, "0 hollow")
    eq(screen.grid:get(8, 2), true, "1 stem"); eq(screen.grid:get(7, 2), false, "1 left blank")
end)

test("menu: left and right change game and wrap around", function()
    local m = setup()
    boot(m)
    with("getButtonsRepeated", input.BTN_LEFT, function() frame(m) end)
    eq(m.sel, 3, "wrapped to last")
    with("getButtonsRepeated", input.BTN_RIGHT, function() frame(m) end)
    eq(m.sel, 1, "wrapped to first")
end)

test("menu: up and down set speed within 1-9", function()
    local m = setup()
    boot(m)
    with("getButtonsRepeated", input.BTN_DOWN, function() frame(m) end)
    eq(m.speed, 1, "floor 1")
    for _ = 1, 12 do with("getButtonsRepeated", input.BTN_UP, function() frame(m) end) end
    eq(m.speed, 9, "ceiling 9")
end)

test("menu: Enter starts the selected game at the chosen speed", function()
    local m, _, runner, switched = setup()
    boot(m)
    with("getButtonsRepeated", input.BTN_RIGHT, function() frame(m) end)
    with("getButtonsRepeated", input.BTN_UP, function() frame(m) end)
    with("getButtonsPressed", input.BTN_ENTER, function() frame(m) end)
    eq(runner.started.def.id, "bbb", "game"); eq(runner.started.speed, 2, "speed")
    eq(switched[1], "play", "scene")
end)

test("menu: Esc asks to quit", function()
    local m = setup()
    boot(m)
    with("getButtonsPressed", input.BTN_ESC, function() frame(m) end)
    eq(m.quit, true, "quit")
end)

test("menu: panel shows the record, BEST for low-order games", function()
    SAVES.hi_ccc = { v = 12 }
    local m, screen = setup()
    boot(m)
    with("getButtonsRepeated", input.BTN_LEFT, function() frame(m) end)
    eq(screen.panel.values.hi_label, "BEST", "label"); eq(screen.panel.values.hi, 12, "value")
    eq(screen.panel.values.label, "BRICK-15", "title")
end)

test("menu: nothing is drawn between demo frames", function()
    local m = setup()
    boot(m)
    T = (T // 400 + 1) * 400   -- start of a demo frame
    frame(m, 0)
    reset_calls()
    frame(m, 16); frame(m, 16)
    eq(count_calls("fillRect"), 0, "no draws")
end)

test("menu: coming back from a game keeps the selection and skips the curtain", function()
    local m = setup()
    boot(m)
    with("getButtonsRepeated", input.BTN_RIGHT, function() frame(m) end)
    m:exit(); m:enter()
    frame(m)
    eq(m.sel, 2, "same game"); eq(m.booted, true, "no second curtain")
end)
```

- [ ] **Step 2: Run them to see them fail**

Run: `lua dev/test/run.lua dev/test/test_menu.lua`
Expected: FAIL lines against the old `lib/menu.lua`. It calls `PAD.pressed`, which no longer exists, so expect e.g. "attempt to call a nil value (field 'pressed')".

- [ ] **Step 3: Rewrite `lib/menu.lua`**

Replace the whole file with:

```lua
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
```

- [ ] **Step 4: Run the whole suite**

Run: `lua dev/test/run.lua`
Expected: `72 tests, 0 failed`

- [ ] **Step 5: Commit**

```bash
git add lib/menu.lua dev/test/test_menu.lua
git commit -m "menu: brick-style selector with power-on curtain, demo and speed"
```

---

### Task 9: Wire `main.lua`, remove the dead loader, add the smoke test

**Files:**
- Rewrite: `main.lua`
- Delete: `lib/loader.lua`
- Create: `dev/smoke.py`

**Interfaces:**
- Consumes: every module from Tasks 1–8.
- Produces:
  - A running app with one game (Tetris).
  - `local DEBUG = false` on its own line in `main.lua`. The smoke test flips it to `true` in its staged copy, and with DEBUG on the app logs `[brick15] draws=N flushes=N` every second.
  - `GAME_IDS = { ... }` in `main.lua`, which the smoke test parses to know which games to play.
  - `dev/smoke.py`, with its `PLAY` / `FINISH` step tables per game id. Phase 2 adds an entry for each game.

- [ ] **Step 1: Rewrite `main.lua`**

Replace the whole file with:

```lua
-- BRICK-15 — 15 classic LCD brick games in one cart for PicoDeck.
-- Entry point: loads lib + games, wires the menu and play scenes, runs the loop.

local DEBUG = false   -- true: log draw and flush counts every second

local pc = picocalc

math.randomseed(pc.sys.getTimeMs())

-- ── Module loader (require/dofile are blocked) ───────────────────────────────

local function load_module(name)
    local path = APP_DIR .. "/" .. name .. ".lua"
    local handle = pc.fs.open(path, "r")
    if not handle then
        error("Cannot open module: " .. path)
    end
    local chunks = {}
    while true do
        local chunk = pc.fs.read(handle, 4096)
        if not chunk or #chunk == 0 then break end
        chunks[#chunks + 1] = chunk
    end
    pc.fs.close(handle)
    return load(table.concat(chunks), "@" .. name .. ".lua")()
end

-- ── Shared lib (lcd sets globals LCD, SFX, PAD) ─────────────────────────────

load_module("lib/lcd")
local Grid = load_module("lib/grid")
local Panel = load_module("lib/panel")
local Screen = load_module("lib/screen")
local Scores = load_module("lib/scores")
local Runner = load_module("lib/runner")
local Menu = load_module("lib/menu")

-- ── Games, in menu order; a game that fails to load is left out ─────────────

local GAME_IDS = { "tetris" }

local games = {}
for _, id in ipairs(GAME_IDS) do
    local ok, def = pcall(load_module, "games/" .. id)
    if ok then
        games[#games + 1] = def
    else
        pc.sys.log("[brick15] skipped " .. id .. ": " .. tostring(def))
    end
end
if #games == 0 then error("BRICK-15: no games loaded") end

-- ── Debug counters ───────────────────────────────────────────────────────────

local stats = { draws = 0, flushes = 0, since = pc.sys.getTimeMs() }
if DEBUG then
    local disp = pc.display
    for _, fn in ipairs({ "fillRect", "drawRect", "clear" }) do
        local raw = disp[fn]
        disp[fn] = function(...) stats.draws = stats.draws + 1 return raw(...) end
    end
    local raw_flush = disp.flushRegion
    disp.flushRegion = function(...) stats.flushes = stats.flushes + 1 return raw_flush(...) end
end

-- ── Scenes ───────────────────────────────────────────────────────────────────

local grid = Grid.new(10, 20, 12, 10)
local screen = Screen.new(pc.display, grid, Panel.new(Grid))
local scores = Scores.new(pc.game.save, games)
local clock = pc.sys.getTimeMs

local runner = Runner.new({ screen = screen, scores = scores, scene = pc.game.scene,
                            clock = clock, input = pc.input })
local menu = Menu.new({ screen = screen, games = games, scores = scores, runner = runner,
                        scene = pc.game.scene, clock = clock, input = pc.input })

-- The scene manager calls enter/update/draw/exit as plain functions (no self),
-- so each object gets a small adapter.
local function as_scene(obj)
    return {
        enter = function() obj:enter() end,
        exit = function() obj:exit() end,
        update = function() obj:update() end,
        draw = function() obj:draw() end,
    }
end

pc.game.scene.add("play", as_scene(runner))
pc.game.scene.add("menu", as_scene(menu))
pc.game.scene.switch("menu")

-- ── Main loop ───────────────────────────────────────────────────────────────

while true do
    pc.input.update()
    pc.game.scene.update()
    pc.game.scene.draw()
    local now = pc.sys.getTimeMs()
    SFX.update(now)
    if DEBUG and now - stats.since >= 1000 then
        pc.sys.log(string.format("[brick15] draws=%d flushes=%d", stats.draws, stats.flushes))
        stats.draws, stats.flushes, stats.since = 0, 0, now
    end
    if menu.quit then return end
    pc.sys.sleep(16)
end
```

- [ ] **Step 2: Delete the unused loader**

```bash
git rm lib/loader.lua
```

- [ ] **Step 3: Write `dev/smoke.py`**

```python
#!/usr/bin/env python3
"""Simulator smoke test: play every game from the menu and save screenshots.

Usage (from anywhere):
    python3 dev/smoke.py [--out DIR]

Needs a built PicoDeck simulator. PICODECK_ROOT points at the picodeck
checkout (default: ../picodeck next to this app's folder). The app is staged
into a temporary SD card with DEBUG switched on; the real app is untouched.

Fails (exit 1) on any Lua error in the log, if an idle game-over screen still
draws, or if the screen isn't restored after the F10 system menu.
"""
import argparse
import io
import os
import re
import shutil
import sys
import tempfile
import time
from pathlib import Path

APP_DIR = Path(__file__).resolve().parents[1]
PICODECK = Path(os.environ.get("PICODECK_ROOT", APP_DIR.parent / "picodeck")).resolve()
sys.path.insert(0, str(PICODECK / "tests" / "e2e"))

from picodeck_simulator import PicodeckSimulator  # noqa: E402
from PIL import Image, ImageChops  # noqa: E402

SCALE = 3

# Scripted play per game id: a list of ("press", key) / ("hold", key, secs) /
# ("wait", secs) steps, played after the game starts.
PLAY = {
    "tetris": [("wait", 0.5), ("press", "right"), ("press", "up"), ("hold", "down", 1.0),
               ("press", "left"), ("press", "left"), ("hold", "down", 1.0), ("wait", 0.3)],
}
# How to reach game over quickly from a fresh round.
FINISH = {
    "tetris": [("hold", "down", 30.0)],
}


class Smoke:
    def __init__(self, out):
        self.out = Path(out)
        self.out.mkdir(parents=True, exist_ok=True)
        self.failures = []
        self.n = 0

    def run_steps(self, steps):
        for step in steps:
            if step[0] == "press":
                self.sim.keypress(step[1])
                time.sleep(0.12)
            elif step[0] == "hold":
                self.sim.call("inject_button", {"button": step[1], "action": "press"})
                time.sleep(step[2])
                self.sim.call("inject_button", {"button": step[1], "action": "release"})
            elif step[0] == "wait":
                time.sleep(step[1])

    def grab(self):
        return Image.open(io.BytesIO(self.sim.screenshot())).convert("RGB")

    def shot(self, name):
        self.n += 1
        img = self.grab()
        img = img.resize((img.width * SCALE, img.height * SCALE), Image.NEAREST)
        path = self.out / f"{self.n:02d}-{name}.png"
        img.save(path)
        print("saved", path.name)

    def log_since(self, seq):
        return self.sim.get_log_lines(since_seq=seq)

    def check_idle(self, since):
        """The last two debug lines must show no draws and no flushes."""
        lines = [l["text"] for l in self.log_since(since) if "[brick15] draws=" in l["text"]]
        tail = lines[-2:]
        busy = [t for t in tail if not re.search(r"draws=0 flushes=0", t)]
        if len(tail) < 2 or busy:
            self.failures.append(f"idle game-over screen still drawing: {tail}")

    def check_system_menu(self):
        before = self.grab()
        self.sim.keypress("menu")
        time.sleep(0.8)
        self.sim.keypress("esc")
        time.sleep(0.8)
        after = self.grab()
        if ImageChops.difference(before, after).getbbox() is not None:
            self.failures.append("screen not restored after the F10 system menu")

    def main(self):
        stage = Path(tempfile.mkdtemp(prefix="brick-smoke-"))
        sd = stage / "sd"
        shutil.copytree(PICODECK / "simulator" / "assets" / "sd_card", sd)
        app = sd / "apps" / APP_DIR.name
        shutil.copytree(APP_DIR, app, ignore=shutil.ignore_patterns(".git", "dev", "docs"))
        main_lua = app / "main.lua"
        main_lua.write_text(main_lua.read_text().replace("local DEBUG = false", "local DEBUG = true", 1))

        game_ids = re.search(r"GAME_IDS = \{([^}]*)\}", main_lua.read_text()).group(1)
        game_ids = re.findall(r'"([a-z]+)"', game_ids)

        self.sim = PicodeckSimulator(sd_card_path=str(sd), headless=True)
        self.sim.start()
        try:
            time.sleep(1.0)
            self.sim.launch_app(APP_DIR.name)
            time.sleep(3.0)                       # power-on curtain, then the menu
            self.shot("menu")
            self.sim.keypress("up")
            time.sleep(0.3)
            self.shot("menu-speed-2")
            self.sim.keypress("down")
            time.sleep(0.2)

            for i, gid in enumerate(game_ids):
                self.sim.keypress("enter")
                time.sleep(0.5)
                self.shot(f"{gid}-hint")
                self.run_steps(PLAY.get(gid, [("wait", 1.5)]))
                self.shot(f"{gid}-gameplay")
                self.run_steps(FINISH.get(gid, [("wait", 30.0)]))
                time.sleep(2.0)                   # curtain
                seq = self.sim.get_log_buffer(tail=1).get("next_seq", 0)
                time.sleep(2.5)                   # idle on the game-over screen
                self.shot(f"{gid}-game-over")
                self.check_idle(seq)
                if i == 0:
                    self.check_system_menu()
                self.sim.keypress("esc")          # back to the menu
                time.sleep(0.6)
                self.sim.keypress("right")        # next game
                time.sleep(0.3)

            self.shot("menu-after-play")
            self.sim.keypress("esc")              # quit the app
            outcome = self.sim.wait_for_exit(timeout=10)
            if outcome.get("result") != "returned":
                self.failures.append(f"app did not exit cleanly: {outcome}")

            errors = [l["text"] for l in self.sim.get_log_lines() if l["src"] == "err"]
            # Errors inside scene callbacks only reach the simulator's stdout.
            errors += [t for t in self.sim._stdout_tail if "[SCENE] Error" in t]
            if errors:
                self.failures.append("Lua errors:\n  " + "\n  ".join(errors))
        finally:
            self.sim.stop()
            shutil.rmtree(stage, ignore_errors=True)

        if self.failures:
            print("\nSMOKE FAILED")
            for f in self.failures:
                print(" -", f)
            return 1
        print(f"\nSMOKE OK ({len(game_ids)} games) — screenshots in {self.out}")
        return 0


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=str(Path(tempfile.gettempdir()) / "brick-smoke-shots"))
    sys.exit(Smoke(ap.parse_args().out).main())
```

- [ ] **Step 4: Run the unit tests and the smoke test**

The simulator must be built first (`make simulator` in the picodeck repo creates `build_sim/picodeck_simulator`).

Run:
```bash
lua dev/test/run.lua
PICODECK_ROOT=../picodeck python3 dev/smoke.py --out /tmp/brick-smoke-shots
```
Expected:
- `72 tests, 0 failed`.
- The smoke test saves 6 screenshots (`01-menu` … `06-menu-after-play`), then prints `SMOKE OK (1 games)`.
- Any `SMOKE FAILED` line names the check that failed:
  - Lua errors, including `[SCENE] Error` lines from stdout;
  - an idle screen still drawing;
  - the F10 system menu leaving the screen dirty;
  - the app not exiting cleanly on Esc.

- [ ] **Step 5: Commit**

```bash
git add main.lua dev/smoke.py
git commit -m "main: wire menu and runner scenes, debug counters; add simulator smoke test"
```

---

### Task 10: Pilot checkpoint (human)

**Files:**
- Possibly modify: `lib/lcd.lua` (only the `LCD.GHOST` line)

**Interfaces:**
- Consumes: the Task 9 screenshots.
- Produces: an approved look for the ghost colour and panel, recorded in the commit message if anything changed.

- [ ] **Step 1: Show the human the screenshots**

Open `/tmp/brick-smoke-shots/01-menu.png`, `04-tetris-gameplay.png` and `05-tetris-game-over.png` and share them. Ask:
- Is the ghost grid visible but quiet enough?
- Does the panel read well?
- If they have the device: does input feel responsive on the real PicoCalc?

- [ ] **Step 2: Apply the requested tuning, if any**

The only planned knob is the ghost colour in `lib/lcd.lua`:

```lua
LCD.GHOST = disp.rgb(146, 156, 94)    -- unlit bricks and segments
```

Move it towards `LCD.BG` (158,168,102) to make the ghosts quieter, or away from it to make them stronger. Keep all three channels shifted by the same amount so the hue stays LCD-green. Any other change they ask for goes back through the spec: update the spec first, then this plan.

- [ ] **Step 3: Re-run and commit if changed**

```bash
lua dev/test/run.lua
PICODECK_ROOT=../picodeck python3 dev/smoke.py --out /tmp/brick-smoke-shots
git add lib/lcd.lua
git commit -m "lcd: tune ghost colour after pilot review"
```

---

### Task 11: Write the phase 2 plan

**Files:**
- Create: `docs/superpowers/plans/YYYY-MM-DD-brick15-phase2-games.md` (the date the plan is written)

**Interfaces:**
- Consumes:
  - The spec's section 3 (the per-game table) and section 4 (rename, testing).
  - The proven game contract and the `Grid`/`Runner` APIs from this plan.
  - `dev/smoke.py`'s `PLAY`/`FINISH` tables.
- Produces: the phase 2 plan.

- [ ] **Step 1: Invoke superpowers:writing-plans for phase 2**

The phase 2 plan must cover:
1. One task per game, 02–15, in menu order. Each task adds a `dev/test/test_<id>.lua` that includes the name/hint/glyph test from `test_tetris.lua`, and rule tests for the game's core mechanic. It also adds the id to `GAME_IDS` in `main.lua`, and `PLAY`/`FINISH` entries in `dev/smoke.py`.
2. The rename:
   - `app.json`: id `net.picodeck.brick15`, name `BRICK-15`, a description with 15 games, homepage `…/PicoDeck/brick15`.
   - A README rewrite.
   - A regenerated brick-style `icon.png`.
   - The folder rename `brick30/` → `brick15/` as the very last step.
3. The visual-critic loop over the full screen set until overall ≥ 8 and every screen ≥ 7 (at most 5 rounds).
4. A final check against the spec's 8 acceptance criteria.

- [ ] **Step 2: Hand the phase 2 plan to the human for review before executing it**
