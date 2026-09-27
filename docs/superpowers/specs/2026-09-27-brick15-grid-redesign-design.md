# BRICK-15: 10×20 brick grid redesign

Date: 2026-09-27
Status: approved in conversation (parts 1–4), awaiting written-spec review

## Goal

Make the collection look and feel like the cheap handheld LCD brick games it
imitates. Every game draws only through one fixed 10×20 grid of identical
"bricks", next to a side panel that is laid out the same way in every game.
At the same time, fix the problems found in the visual review: broken
glyphs, unreadable small numbers, the score area overlapping the playfield, a
slow menu, and games where the player can't be told apart from hazards.
Rename the app to BRICK-15.

## Decisions (from the design conversation)

| Topic | Decision |
|---|---|
| Layout | 10×20 grid on the left, fixed side panel on the right, in every game and the menu |
| Games that don't fit the grid | Keep all 15, reinvented as brick versions |
| Menu | Brick-style selector: game number and demo on the grid, SPEED 1–9 chosen with up/down |
| Cell look | Framed brick (outline, gap, filled centre) with faint ghost cells for unlit positions |
| Rename | Full: name, app id, folder, README, icon. Old scores are not migrated |
| Rendering | Retained, diff-based: redraw only changed cells and panel fields, then `flushRegion` |
| Version control | `git init` done; baseline commit `5a500de` is the rollback point |

## 1. Screen layout and look

Screen: 320×320.

### Palette (`lib/lcd.lua`)

- `LCD.BG`: `rgb(158,168,102)`, the LCD background.
- `LCD.DARK`: `rgb(24,32,14)`, lit bricks, text, digits and the frame.
- `LCD.GHOST`: a colour slightly darker than `BG`, starting at `rgb(146,156,94)` and tuned by eye during the Tetris pilot. It is used for unlit bricks and unlit 7-segment segments.
- `MID` and `LIGHT` are removed. Nothing in gameplay uses a mid-tone.

### Grid

- 10 columns × 20 rows. Cell pitch is 15px, so the grid is 150×300.
- Cell (c, r) has its top-left pixel at `(12 + (c-1)*15, 10 + (r-1)*15)`. Column 1 is on the left and row 1 is at the top.
- **Brick:** drawn inside the cell at offset +1 as three fills:
  - 13×13 in the brick colour;
  - 9×9 in `BG` at +2;
  - 5×5 in the brick colour at +4.

  Lit bricks use `DARK` and unlit (ghost) bricks use `GHOST`. Neighbouring bricks are 2px apart.
- **Frame:** a 2px `DARK` rectangle around the grid, with its outer edge at x 8..165 and y 6..313.
- **Cell values:** off, on, or blink. Blinking cells are lit during the "on" half of a shared 2 Hz clock (250 ms on, 250 ms off), so everything blinks in sync.

### Side panel (x 176..312, 136px wide)

The positions are the same in every game and in the menu. Labels behave like printed legends and are always drawn. A field a game doesn't use keeps its ghost segments or ghost bricks, so it never looks missing.

| y | Field | Content |
|---|---|---|
| 8 | Label | `SCORE` in games, `BRICK-15` in the menu (scale-2 text) |
| 22 | SCORE | 6-digit 7-segment, t=4 (24px tall). It also accepts `-` and spaces, e.g. Pong's ` 03-05` |
| 50 | HI | `HI` label, then 6-digit 7-segment, t=3. Memory's label reads `BEST` |
| 76 | NEXT | `NEXT` label, then a 4×4 brick grid at the same 15px pitch at y 90..150 |
| 160 | SPEED | `SPEED` label, then 1-digit 7-segment, t=3 |
| 184 | LEVEL | `LEVEL` label, then 2-digit 7-segment, t=3 |
| 212 | LIVES | `LIVES` label, then 4 bricks at y 226, lit for each life left |
| 252 | Name | Game name, scale-2 text (at most 11 characters) |
| 270, 284, 298 | Status | Up to 3 lines of scale-2 text (at most 17 characters each) |

### Text and numbers

- **Font:** the 3×5 font is only drawn at scale 2 or larger. There is no scale-1 text anywhere.
- **Glyph fixes:**
  - `M` = `101,111,111,101,101`
  - `N` = `110,101,101,101,101`
  - `W` = `101,101,111,111,101`
- **Font drawing:** glyph rows are merged into horizontal runs once at load, so each run is a single `fillRect`.
- **7-segment digits:**
  - Only sizes t=3 and t=4 are allowed. `t // 2` must be at least 1, which fixes the overlapping segments seen at t=1.
  - Every digit position first draws all 7 segments in `GHOST`, then lights the value's segments in `DARK`. This fixes the "0000 10" misread.

### Game over: the curtain

When a round ends, grid rows fill with lit bricks from the bottom up, one row every 30 ms. They then clear from the top down. After that, the panel status reads `GAME OVER` / `ENTER AGAIN` / `ESC MENU`, or `NEW HI` on the first line when the score beats the record. The dark box that covered the playfield is removed.

The same curtain plays once when the app starts.

## 2. Code structure and performance

```
brick15/
  app.json, icon.png, main.lua, README.md
  lib/lcd.lua      palette, font (runs), 7-seg with ghost, SFX, PAD (globals LCD, SFX, PAD, as now)
  lib/grid.lua     Grid.new(cols, rows, x, y): cells, diff rendering, blink, patterns
  lib/panel.lua    side panel: fields, dirty tracking, fixed positions
  lib/scores.lua   high-score cache
  lib/runner.lua   shared play scene: round lifecycle, curtain, records, timing helpers
  lib/menu.lua     brick selector scene
  games/*.lua      rules only
  dev/             tests and smoke script (not needed on the device)
  docs/            specs and plans
```

`lib/loader.lua` is unused; `main.lua` has its own loader. It is deleted.

### Grid (`lib/grid.lua`)

- `Grid.new(cols, rows, x, y)` creates the main grid `(10, 20, 12, 10)` and the panel's NEXT grid `(4, 4, 176, 90)`.
- `g:clear()`, `g:set(c, r, v)` with v = `false`/`true`/`"blink"`, `g:get(c, r)`. Setting a cell outside the grid is ignored, so games can draw sprites that are partly off-screen.
- `g:stamp(pattern, c, r [, v])`: `pattern` is a list of strings with `#` for lit and `.` for skipped, the same style as the font.
- `g:text(str, c, r)`: stamps 3×5 font glyphs as bricks. The menu uses it for the big game number.
- **Rendering:**
  - `g:render(now_ms)` compares each cell's visible state (with blink resolved at `now_ms`) against what that cell last drew. It redraws only the cells that differ, as 3 fills each, and returns the changed pixel row band, or nil if nothing changed.
  - `g:invalidate()` forces a full redraw on the next render. It is used on scene enter.

### Panel (`lib/panel.lua`)

- `panel:set(field, value)` marks a field dirty only if the value actually changed.
- `panel:render()` redraws only the dirty fields. It first clears the field's rectangle to `BG`, then draws the ghost segments or bricks, then the value. It returns the changed row band.
- `panel:invalidate()` forces a full redraw.
- `panel.next` is a 4×4 `Grid` that games draw into.

### Scores (`lib/scores.lua`)

- `scores.load(games)` calls `save.get("hi_<id>")` once per game at startup. This is the only time `save.get` is called.
- `scores.get(id)` returns the cached value, or nil if there isn't one.
- `scores.submit(id, value, order)` takes `order` = `"high"` (the default) or `"low"`. It updates the cache and calls `save.set` only when the value is a new record, and returns true in that case. For `"low"`, a stored value of nil or 0 counts as "no record yet".

### Game module contract

```lua
return {
  id = "snake", name = "SNAKE",
  hint = { "D-PAD STEER" },       -- status lines shown for the first 3 s of a round
  order = "high",                 -- or "low" (Memory)
  demo = { frame1, frame2 },      -- two 10x12 patterns for the menu
  new = function(ctx) return game end,   -- ctx = { speed = 1..9 }
}

game:update(pad, now_ms)  -- pad = { held = PAD.held(), pressed = PAD.pressed() }
                          -- returns "over" when the round ends
game:draw(grid, next)     -- the runner clears both grids first
-- fields the runner copies to the panel after every update:
game.score, game.level, game.lives  -- nil means the field is unused (ghosted)
game.status                         -- nil, or a list of up to 3 strings
```

Games never call `picocalc.display`, `picocalc.game.save`, or `scene.switch`, and never handle Esc. All their positions are whole cells.

### Runner (`lib/runner.lua`)

This is one scene that hosts whichever game is active, replacing the 15 per-game wrapper scenes in `main.lua`.

- **Round start:** calls `new(ctx)`, invalidates the grid and panel, and shows `hint` on the status lines for 3 s unless the game sets `status` itself.
- **Every frame:**
  1. Read the pad. Esc goes to the menu.
  2. Call `game:update`.
  3. Clear the grids and call `game:draw`.
  4. Sync the panel fields.
  5. Render the grid and panel.
  6. If any row band changed, call `display.flushRegion(y0, y1)` over the union of the bands. Otherwise draw and flush nothing.
- **On "over":** submit the score (`SFX.levelup` for a record), then play the curtain. Input is ignored while the curtain plays. The status lines then read: line 1 is `NEW HI` for a record, otherwise the game's own `status[1]` if it set one (e.g. `CLEARED`, `YOU WIN`), otherwise `GAME OVER`; line 2 is `ENTER AGAIN`; line 3 is `ESC MENU`. Enter starts a new round with the same speed; Esc goes to the menu.
- **Timing helper:** `runner.interval(base_ms, speed, level)` = `max(40, base_ms * 0.87^(speed + level - 2))`. Games step their logic on millisecond timers, never on frame counts.
- **Debug:** if `DEBUG` is set in `main.lua`, the runner logs the number of draw calls and flushes every second.

### Why `flushRegion` and not `flush`

`display.flush()` swaps two buffers without copying (`display.c` `display_flush`), so the back buffer holds the frame from two flushes ago. That breaks partial redraws. `display.flushRegion(y0, y1)` sends only those rows and copies the band into the other buffer, so the next partial draw starts from what's on screen.

### Risk to verify

The system menu overlay (F10) may leave the screen dirty when it closes. If it does, the runner and menu call `invalidate()` when they regain control. This gets checked in the simulator during the pilot.

### Alternatives rejected

- **Full redraw every frame using two PNG brick tiles:** simpler, but it adds assets and still redraws panel text every frame.
- **The native `picocalc.graphics.drawPlayfield`:** fast, but it draws flat squares with grid lines, which is the wrong look.

## 3. The games

### Shared rules

- Blinking marks the thing you're aiming for or need to watch: food, cursors, pads, warnings.
- The player always has a shape that no hazard or enemy uses.
- LEVEL rises with progress and feeds `runner.interval`.
- Lives use the panel's LIVES bricks.
- Enter and F1 are the action buttons.

| # | Game | On the grid | Controls | Panel |
|---|---|---|---|---|
| 01 | Tetris | Standard 10×20 well. The falling piece is lit, locked pieces are lit, and a cleared line blinks briefly | ←→ move, ↑/Enter/F1 rotate, ↓ drop | NEXT = next piece; LEVEL = 1 + lines/10 |
| 02 | Snake | 1-brick segments, the grid edge is the wall, the food blinks | D-pad steer | LEVEL every 5 foods |
| 03 | Breakout | 4 rows of single-brick bricks at rows 2–5, 3-brick paddle on row 20, 1-brick ball moving diagonally. The paddle edge angles the ball | ←→ move, Enter/↑ serve | LIVES 3; LEVEL = board |
| 04 | Invaders | 6×3 block of single-brick aliens that moves across and down. Gun is `.#.`/`###` on rows 19–20. Bullets and bombs are single lit bricks | ←→ move, ↑/Enter/F1 fire | LIVES 3; LEVEL = wave |
| 05 | Frogger | Start on row 20, 5 home slots on row 1. Road lanes have 2-brick cars; river lanes have 4–5-brick logs, and the frog rides a log or drowns. The frog blinks | D-pad hop | LIVES 3; LEVEL = homes filled |
| 06 | Racer | Border columns 1 and 10 scroll a dashed pattern. 2 lanes, at cols 3–5 and 6–8. Player car is `.#.`/`###`/`.#.`/`#.#` on rows 17–20; oncoming cars use the same shape upside down | ←→ change lane | LIVES 3; LEVEL from distance |
| 07 | Pong | Vertical. Your 3-brick paddle is on row 20 and the computer's on row 1; the ball is 1 brick. First to 7, then the round ends with `YOU WIN` or `CPU WINS` | ←→ move, Enter/↑ serve | SCORE shows ` 03-05` (you-cpu); HI = most points in a game |
| 08 | Copter | The tunnel scrolls down, with walls from both edges that vary in width, plus occasional blocks inside. 3×2 ship near the bottom | ←→ steer | Score = distance; LEVEL from distance |
| 09 | Asteroids | 3×3 ship with a separate pattern for each of 8 directions. Position moves by fractional velocity snapped to cells, with drift. Rocks are 3×3 blobs that split into 2×2, then 1 brick. Everything wraps | ←→ rotate, ↑ thrust, Enter/F1 fire | LIVES 3; LEVEL = wave |
| 10 | Missile Cmd | 3 cities of 2 bricks each on row 20, at cols 2–3, 5–6 and 8–9. Firing sets off an explosion at the crosshair, with no player missile in flight; 12 shots per wave. Missiles are single bricks stepping diagonally toward a city. The crosshair is a blinking 3×3 plus. The explosion grows 3×3 → 5×5 diamond and destroys missiles inside it | D-pad aim, Enter/F1 fire | LIVES = cities; NEXT = ammo as bricks (drains); LEVEL = wave |
| 11 | Moon Lander | `###`/`#.#` lander. Terrain columns rise from the bottom, with one flat, blinking 3-brick pad. Gravity uses fractional velocity snapped to cells. The lander blinks while descending too fast to land safely | ↑ thrust, ←→ drift | NEXT = fuel (16 bricks, drains); LEVEL = landings |
| 12 | Memory | 18 cards (3 columns × 6 rows) of 2×2 bricks with 1-brick gaps: card columns start at cols 2, 5 and 8, and card rows at rows 2, 5, …, 17. The round ends (`CLEARED`) when every pair is found. Face down is all 4 lit; face up is one of 9 distinct 1–3-brick patterns. The cursor card blinks | D-pad move, Enter/F1 flip | SCORE = turns; HI labelled BEST, lower is better (`order = "low"`) |
| 13 | Simon | Four 4×4 pads arranged as a plus that matches the D-pad: up at cols 4–7 rows 3–6, left at cols 1–4 and right at cols 7–10 on rows 9–12, down at cols 4–7 rows 15–18. Unlit pads are outlines, lit pads are filled, and each has its own tone | D-pad | Status `WATCH` / `YOUR TURN`; SCORE = sequence length |
| 14 | Tic-tac-toe | 3×3 board of 3×3 cells at cols 1–9, rows 6–14. X is `#.#`/`.#.`/`#.#`, O is `###`/`#.#`/`###`. The cursor cell blinks, and so does the winning line. You play against the computer. After a win or draw a new board starts and the streak continues; a loss ends the round | D-pad move, Enter/F1 place | SCORE = current win streak; HI = best streak (new: the old game saved nothing) |
| 15 | Tank | Player tank is a solid 3×3 with a barrel in 4 facings. Enemy tanks have a hollow centre. Walls are single destructible bricks. A 2×2 base sits at the bottom centre. Up to 3 enemies at once | D-pad move, Enter/F1 fire | LIVES 3; LEVEL = wave |

### Accepted tradeoffs

- Tic-tac-toe has no gaps between board cells, because 3×3 + 2 gaps = 11 is wider than the 10-column grid. The X and O shapes define the cells.
- Tank's steel walls merge into ordinary destructible walls.
- Copter changes from one-button thrust to steering left and right.

## 4. Menu, rename, testing

### Menu (`lib/menu.lua`)

- **Grid:** the game number is drawn with `g:text`: the tens digit at cols 2–4 and the units digit at cols 7–9, on rows 2–6. The game's `demo` frames alternate every 400 ms on rows 9–20.
- **Panel:**
  - Label `BRICK-15`, with SCORE ghosted.
  - HI shows the selected game's record; the label reads `BEST` for Memory, and the digits are ghosted when there is no record.
  - SPEED shows the chosen speed, and LEVEL and LIVES are ghosted.
  - The name line shows the game name, and the status lines read `< > GAME` / `UP DN SPEED` / `ENTER PLAY`. The font has no `^`, so hints use `<`, `>` and words.
- **Controls:** ←→ changes game (wrapping), ↑↓ sets speed 1–9, Enter plays, Esc exits the app.
- **Remembering:** the selected game and speed are remembered for the session. Returning from a game lands on the same game.
- **Performance:** the menu uses the same diff rendering, so input is read every frame and a redraw happens only when something changes.
- The startup curtain plays before the menu first appears.

### Rename

- `app.json`: `id` `net.picodeck.brick15`, `name` `BRICK-15`. The description says 15 games, and `homepage` becomes `…/PicoDeck/brick15`.
- `README.md`: rewritten for the new name, layout, controls and file tree.
- `icon.png`: regenerated at 48×48 in the brick style (framed bricks on the LCD green).
- The folder rename `brick30/` → `brick15/` is the last step of the build.
- Scores saved under `/data/net.picodeck.brick30/` are left in place and not migrated.

### Testing

1. **Library unit tests, written first:** `dev/test/run.lua` runs under desktop `lua` (5.4) with a stub `picocalc` that records display calls. It covers:
   - Grid:
     - no draw calls when nothing changed;
     - only changed cells redraw;
     - blink toggles only blinking cells;
     - off-grid `set` is ignored;
     - `stamp` and `text` shapes.
   - Panel: a field redraws only when its value changes; unused fields keep their ghosts.
   - Scores:
     - `save.get` only during `load`;
     - `save.set` only on a record;
     - `"low"` ordering, where 0 means no record.
   - Font and 7-segment:
     - the exact M/N/W patterns;
     - 7-segment rejects t < 3.
   - Game rules: tested where they are pure and cheap, such as Tetris line clear, Snake growth and collision, and Tic-tac-toe win detection.

   Command: `lua dev/test/run.lua`.
2. **Simulator smoke test:** `dev/smoke.py` uses `picodeck/tests/e2e/picodeck_simulator.py`, with the path taken from `PICODECK_ROOT` and defaulting to `../picodeck`.
   - It stages the app into a temporary SD card with `DEBUG` on.
   - It opens every game from the menu, plays scripted inputs, and reaches game over.
   - It fails if any `err` log line appears.
   - It checks the debug log for idle stretches with zero draw calls.
   - It saves 3× screenshots.
3. **Visual critic loop:** re-capture the full screen set and run the independent critic review. Fix and repeat until overall is at least 8/10 and every screen is at least 7/10, for at most 5 rounds, following the visual-critic skill's stop rules.
4. **Hardware check (by you):** try the input feel and game speeds on the real PicoCalc. The simulator runs at desktop speed.

### Build order

1. **Pilot:** the libraries (lcd, grid, panel, scores, runner), then the menu, then Tetris. Unit tests pass, the smoke test passes for Tetris, and the screenshots get checked. Tune `GHOST` here.
2. **The other 14 games.** They are independent once the pilot's contract is settled.
3. **Rename:** `app.json`, README, icon, then the folder.
4. **Critic loop** over the full set.

## Acceptance criteria

1. `games/*.lua` contains no `picocalc.display`, `picocalc.game.save`, or `scene` calls.
2. No text is drawn at scale 1, and no 7-segment digit is drawn at t < 3.
3. M, N and W match the patterns above.
4. A frame with no state change issues zero draw calls and no flush. This is checked by the unit tests and the smoke script's debug log.
5. `save.get` is called only at startup, and `save.set` only on a new record.
6. All 15 games load and play through to game over in the smoke script with no Lua errors.
7. The critic loop passes its gate, or stops under the skill's rules and reports what is left.
8. The app is named BRICK-15, with id `net.picodeck.brick15` and folder `brick15/`.

## Out of scope

- A pause feature.
- New sound effects (the existing SFX set is reused).
- Remembering the menu selection or speed across app launches.
- Migrating the old BRICK-30 high scores.
- Two-player modes.
