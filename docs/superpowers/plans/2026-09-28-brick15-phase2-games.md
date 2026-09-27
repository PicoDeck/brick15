# BRICK-15 Phase 2 (Games, Rename, Critic Loop) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port games 02–15 onto the proven 10×20 grid engine, rename the app to BRICK-15, pass the independent visual-critic gate, and check the spec's 8 acceptance criteria.

**Architecture:**
- **Engine:** phase 1 built it and it's unchanged. Games are rules-only modules that light cells on a `Grid` and expose `score`/`level`/`lives`/`status`, and the shared `Runner` scene handles everything else.
- **Games:** each game gets its own unit tests (desktop Lua), which include a shared contract check. It then joins `GAME_IDS` and is played by the simulator smoke test.
- **Finish:** the rename, then a visual-critic loop over the full screen set, then the acceptance check. The folder rename is the very last step.

**Tech Stack:**
- Lua 5.4 on the PicoDeck `picocalc.*` API.
- Desktop `lua` 5.4 for the unit tests.
- Python 3 + Pillow + the PicoDeck simulator client for the smoke test and the icon.

**Spec:** `docs/superpowers/specs/2026-09-27-brick15-grid-redesign-design.md`. Section 3 has the per-game table, and section 4 covers the rename and testing.

**Builds on:** the phase 1 plan (`docs/superpowers/plans/2026-09-27-brick15-phase1-pilot.md`), executed on branch `brick15-grid`. Keep working on that branch.

## Global Constraints

- All phase 1 Global Constraints still apply: palette, grid geometry, text scale ≥ 2, 7-seg t ≥ 3, `flushRegion` only, `save.get` only at startup, scene adapters.
- **Game contract** (now documented at the top of `lib/runner.lua`):
  - `{ id, name (≤ 11 chars), hint (1–3 lines ≤ 17 chars), messages (every status line the game can show), order ("high"|"low"), demo (2 frames of 10×12), new(ctx) }`.
  - `ctx = { speed, now, interval(base_ms, level) }`.
  - `game:update(pad, now)` returns `"over"` to end a round, and `game:draw(grid, next)` draws it.
  - The runner reads the fields `score`, `score_text`, `level`, `lives` and `status`.
- **Status rule:**
  - While `status` is set, it replaces the hint.
  - When a game returns `"over"`, `status[1]` (if set) is the headline instead of GAME OVER. A game must therefore set `status` to its end-of-round message, or nil, before returning `"over"`.
  - Every string a game can put in `status` is listed in `messages`, which `check_contract` validates.
- **Game files** use no `picocalc` at all, and nothing matching `.esc`: sound goes through the `SFX` global and randomness through `math.random`. `dev/test/test_app.lua` checks this.
- **Menu order and numbering:** 01 tetris, 02 snake, 03 breakout, 04 invaders, 05 frogger, 06 racer, 07 pong, 08 copter, 09 asteroids, 10 memory, 11 simon, 12 tictactoe, 13 moonlander, 14 missile, 15 tank. The number in each game file's header comment matches.
- **Rename:**
  - `app.json` id is `net.picodeck.brick15` and the name is `BRICK-15`; `version` stays `1.0.0`, because the new id is a new app to the launcher.
  - `homepage` becomes `https://github.com/PicoDeck/brick15`.
  - The folder moves `brick30/` → `brick15/` last.
  - Old scores under `/data/net.picodeck.brick30/` are not migrated.
- **Hardware:** no real-device testing unless the Claude agent `nova-rail-sdk-design` is idle (check with ListAgents). Otherwise, stay on the simulator and report the check as outstanding.
- **Temp files:** screenshots and other temporary output go in the session scratchpad, written `<scratchpad>` in the commands below, not `/tmp`.

## Review Focus

These input classes or failure modes are implied by the spec but not covered by the main rule tests. Each has a test in the owning task.

1. **Two quick presses inside one Snake step** must not reverse the snake into itself (for example Up then Left while heading right). Test in Task 2.
2. **The Breakout ball driven into a corner** must bounce out on both axes and stay on the grid. Test in Task 3.
3. **The Copter tunnel** must always leave a way through for the 3-wide ship, at every level. Test in Task 8, over 3,000 generated rows.
4. **Racer traffic** must never block both lanes at once; new cars keep at least 3 clear rows between them. Test in Task 7.
5. **Tank's map must let tanks move.** The player can drive out of the start position, which a closed wall row once trapped during plan validation. An enemy must never spawn on top of the player's tank. Tests in Task 15.

## File Structure

| File | Responsibility |
|---|---|
| `lib/runner.lua` (comment only) | Documents the game contract and the status rule |
| `dev/test/game_helpers.lua` (new) | `game_ctx`, `pad`/`press`/`hold`/`NONE`, `draw_game`, `count_lit`, `check_text`, `check_contract`, `check_status` |
| `dev/smoke.py` (rewrite) | Reads the screen to detect game over, supports `--only`, has PLAY/FINISH steps for all 15 games, and solves Memory |
| `games/<id>.lua` × 14 (rewrite) | One rules-only module per game |
| `dev/test/test_<id>.lua` × 14 (new) | Rule tests per game |
| `main.lua` | `GAME_IDS` grows by one per game task |
| `dev/test/test_app.lua` (new) | Acceptance checks: manifest, game list, games touch no `picocalc`, contract for all 15 |
| `app.json`, `README.md`, `icon.png`, `dev/make_icon.py` | The rename |

---

### Task 1: Contract doc, game test helpers, smoke test for 15 games

**Files:**
- Modify: `lib/runner.lua` (header comment only)
- Create: `dev/test/game_helpers.lua`
- Rewrite: `dev/smoke.py`

**Interfaces:**
- Consumes: phase 1's `Grid`, `LCD.FONT`, the test harness globals (`test`, `eq`, `truthy`, `need`), and the `Runner`.
- Produces:
  - **Test helpers** (globals) for every game test:
    - `game_ctx(speed)`, where `interval` returns `base_ms` unchanged;
    - `pad(spec)`: a pressed key is also held and repeated, and a repeated key is also held;
    - `press(key)`, `hold(key)`, `NONE`;
    - `draw_game(game)` → grid, next;
    - `count_lit(grid)`, `check_text(lines)`, `check_contract(mod, id, name)`, `check_status(mod, game)`.
  - **`dev/smoke.py`:** `PLAY`/`FINISH` tables keyed by game id, and `--only id,id`.

- [ ] **Step 1: Document the contract at the top of `lib/runner.lua`**

Replace the first three comment lines of `lib/runner.lua` with:

```lua
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
```

- [ ] **Step 2: Write `dev/test/game_helpers.lua`**

```lua
-- game_helpers.lua — shared builders and checks for game rule tests.
-- Load with need("dev/test/game_helpers.lua"); defines globals.

need("lib/lcd.lua")
Grid = need("lib/grid.lua")

-- ctx as the runner builds it, with an interval that ignores speed/level
-- so tests can reason in the game's base milliseconds.
function game_ctx(speed)
    return { speed = speed or 1, now = 0,
             interval = function(base_ms) return base_ms end }
end

-- pad{ pressed = { "left" }, held = { "up" } }. Like the device, a pressed
-- key is also held and repeated that frame.
function pad(spec)
    local p = { held = {}, pressed = {}, repeated = {} }
    for kind, keys in pairs(spec or {}) do
        for _, k in ipairs(keys) do
            p[kind][k] = true
            if kind == "pressed" then p.held[k] = true p.repeated[k] = true end
            if kind == "repeated" then p.held[k] = true end
        end
    end
    return p
end
NONE = pad()

function press(key) return pad({ pressed = { key } }) end
function hold(key) return pad({ held = { key } }) end

-- Draw a game onto fresh grids; returns the 10x20 grid and the 4x4 NEXT grid.
function draw_game(game)
    local g, n = Grid.new(10, 20, 0, 0), Grid.new(4, 4, 0, 0)
    game:draw(g, n)
    return g, n
end

function count_lit(grid)
    local n = 0
    for r = 1, grid.rows do
        for c = 1, grid.cols do
            if grid:get(c, r) then n = n + 1 end
        end
    end
    return n
end

-- Panel text: at most 17 characters a line, only characters the font has.
function check_text(lines)
    for _, l in ipairs(lines) do
        truthy(#l <= 17, "at most 17 characters: " .. l)
        for ch in string.upper(l):gmatch(".") do
            truthy(LCD.FONT[ch], "font has '" .. ch .. "' (" .. l .. ")")
        end
    end
end

-- The game contract every module must meet (see lib/runner.lua). `messages`
-- lists every status line the game can show; each must fit the panel.
function check_contract(mod, id, name)
    eq(mod.id, id, "id")
    eq(mod.name, name, "name")
    truthy(mod.order == "high" or mod.order == "low", "order")
    eq(type(mod.new), "function", "new")
    eq(#mod.demo, 2, "two demo frames")
    for _, f in ipairs(mod.demo) do
        eq(#f, 12, "demo rows")
        for _, row in ipairs(f) do eq(#row, 10, "demo row width: " .. row) end
    end
    truthy(#mod.name <= 11, "name at most 11 characters")
    truthy(#mod.hint >= 1 and #mod.hint <= 3, "1-3 hint lines")
    check_text({ mod.name })
    check_text(mod.hint)
    check_text(mod.messages or {})
end

-- A status the game shows must be one it declares in `messages`.
function check_status(mod, game)
    for _, line in ipairs(game.status or {}) do
        local known = false
        for _, m in ipairs(mod.messages or {}) do known = known or m == line end
        truthy(known, "status '" .. line .. "' is listed in messages")
    end
end
```

- [ ] **Step 3: Rewrite `dev/smoke.py`**

```python
#!/usr/bin/env python3
"""Simulator smoke test: play every game from the menu and save screenshots.

Usage (from anywhere):
    python3 dev/smoke.py [--out DIR] [--only tetris,snake]

Needs a built PicoDeck simulator. PICODECK_ROOT points at the picodeck
checkout (default: ../picodeck next to this app's folder). The app is staged
into a temporary SD card with DEBUG switched on; the real app is untouched.

Fails (exit 1) if a game fails to load, on any Lua error, if a game never
reaches its game-over screen, if that screen still draws while idle, or if
the screen isn't restored after the F10 system menu.
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
FINISH_TIMEOUT = 150              # seconds a game gets to reach game over

# Scripted play per game id, run once after the game starts, before the
# gameplay screenshot. Steps: ("press", key) / ("hold", key, secs) / ("wait", secs).
PLAY = {
    "tetris": [("wait", 0.5), ("press", "right"), ("press", "up"), ("hold", "down", 1.0),
               ("press", "left"), ("press", "left"), ("hold", "down", 1.0), ("wait", 0.3)],
    "snake": [("wait", 0.3), ("press", "up"), ("wait", 0.8), ("press", "left"), ("wait", 0.6)],
    "breakout": [("press", "enter"), ("hold", "left", 0.3), ("wait", 1.2)],
    "invaders": [("hold", "left", 0.4), ("press", "up"), ("wait", 0.3), ("press", "up"), ("wait", 0.2)],
    "frogger": [("wait", 0.8), ("press", "up"), ("wait", 0.3), ("press", "up"), ("wait", 0.4)],
    "racer": [("wait", 2.0), ("press", "right"), ("wait", 1.0)],
    "pong": [("press", "enter"), ("wait", 1.2)],
    "copter": [("wait", 1.0), ("press", "left"), ("wait", 0.5)],
    "asteroids": [("press", "right"), ("hold", "up", 0.4), ("press", "enter"), ("wait", 0.1),
                  ("press", "enter"), ("wait", 0.1)],
    "memory": [("wait", 0.3), ("press", "enter"), ("press", "right"), ("press", "enter"), ("wait", 0.3)],
    "simon": [("wait", 3.0)],
    "tictactoe": [("press", "enter"), ("wait", 0.8), ("press", "up"), ("wait", 0.3)],
    "moonlander": [("hold", "up", 0.5), ("wait", 0.6)],
    "missile": [("wait", 2.5), ("hold", "left", 0.3), ("press", "enter"), ("wait", 0.15)],
    "tank": [("hold", "up", 0.6), ("press", "enter"), ("wait", 0.1)],
}
def ttt_walk():
    """Tic-tac-toe: walk the cursor through all 9 cells (1-2-3-6-5-4-7-8-9),
    pressing Enter on each. Taken cells ignore it, so the board always fills,
    and this poor order lets a blocking CPU win within a few boards."""
    steps = [("press", "up"), ("press", "up"), ("press", "left"), ("press", "left")]
    for move in (None, "right", "right", "down", "left", "left", "down", "right", "right"):
        if move:
            steps.append(("press", move))
        steps += [("press", "enter"), ("wait", 0.6)]
    return steps


# Steps repeated until the game-over screen shows (or FINISH_TIMEOUT).
# "solve": the game can't be lost, so the smoke test wins it (Memory).
FINISH = {
    "tetris": [("hold", "down", 5.0)],
    "snake": [("wait", 1.0)],
    "breakout": [("press", "enter"), ("hold", "left", 0.6), ("wait", 1.0),
                 ("hold", "right", 0.6), ("wait", 1.0)],
    "invaders": [("wait", 2.0)],
    "frogger": [("press", "up"), ("wait", 0.2)],
    "racer": [("wait", 2.0)],
    "pong": [("press", "enter"), ("wait", 2.5)],
    "copter": [("wait", 1.0)],
    "asteroids": [("hold", "up", 0.5), ("wait", 1.5)],
    "memory": "solve",
    "simon": [("wait", 3.0)],
    "tictactoe": ttt_walk(),
    "moonlander": [("wait", 2.0)],
    "missile": [("wait", 2.0)],
    "tank": [("hold", "up", 0.5), ("wait", 1.5)],
}


def dark(p):
    return p[0] < 60


class Smoke:
    def __init__(self, out, only):
        self.out = Path(out)
        self.out.mkdir(parents=True, exist_ok=True)
        self.only = only
        self.failures = []
        self.n = 0

    def run_steps(self, steps, stop=None):
        """Play the steps; with `stop`, check it before each step and quit
        early when it is true (so Enter can't restart a finished round)."""
        for step in steps:
            if stop and stop():
                return
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

    def over_screen(self, img):
        """Empty grid (the curtain has cleared it) and a 2nd status line."""
        for r in range(20):
            for c in range(10):
                if dark(img.getpixel((12 + c * 15 + 7, 10 + r * 15 + 7))):
                    return False
        return any(dark(img.getpixel((x, y))) for x in range(176, 312) for y in range(284, 294))

    def is_game_over(self):
        if not self.over_screen(self.grab()):
            return False
        time.sleep(0.3)                           # rule out a blink-off moment
        return self.over_screen(self.grab())

    def finish(self, gid):
        steps = FINISH.get(gid) or [("wait", 2.0)]
        if steps == "solve":
            self.solve_memory()
            steps = [("wait", 1.0)]
        deadline = time.time() + FINISH_TIMEOUT
        over_now = lambda: self.over_screen(self.grab())
        while time.time() < deadline:
            if self.is_game_over():
                return True
            self.run_steps(steps, stop=over_now)
        return False

    def solve_memory(self):
        """Memory ends only when every pair is found: read the faces off the
        screen two cards at a time, then match the pairs."""
        cursor = 1

        def origin(i):                            # grid cell of card i's top-left brick
            return (2, 5, 8)[(i - 1) % 3], 2 + ((i - 1) // 3) * 3

        def face(img, i):
            x, y = origin(i)
            return tuple(dark(img.getpixel((12 + (x - 1 + dx) * 15 + 7, 10 + (y - 1 + dy) * 15 + 7)))
                         for dy in (0, 1) for dx in (0, 1))

        def flip(i):
            nonlocal cursor
            dr, dc = (i - 1) // 3 - (cursor - 1) // 3, (i - 1) % 3 - (cursor - 1) % 3
            for _ in range(abs(dr)):
                self.sim.keypress("down" if dr > 0 else "up")
                time.sleep(0.1)
            for _ in range(abs(dc)):
                self.sim.keypress("right" if dc > 0 else "left")
                time.sleep(0.1)
            cursor = i
            self.sim.keypress("enter")
            time.sleep(0.1)

        time.sleep(1.0)                           # let PLAY's pair settle
        self.sim.keypress("left")                 # PLAY left the cursor on card 2
        time.sleep(0.1)
        faces, done = {}, set()
        for i in range(1, 19, 2):
            flip(i)
            flip(i + 1)
            # the cursor card blinks: OR a few samples across a blink phase
            a, b = (False,) * 4, (False,) * 4
            for _ in range(6):
                img = self.grab()
                a = tuple(p or q for p, q in zip(a, face(img, i)))
                b = tuple(p or q for p, q in zip(b, face(img, i + 1)))
                time.sleep(0.05)
            faces[i], faces[i + 1] = a, b
            time.sleep(1.0)                       # the pair turns back or goes
            if a == b:
                done |= {i, i + 1}
        by_face = {}
        for i, f in faces.items():
            if i not in done:
                by_face.setdefault(f, []).append(i)
        for cards in by_face.values():
            if len(cards) == 2:
                flip(cards[0])
                flip(cards[1])
                time.sleep(0.7)

    def check_idle(self, gid):
        """Two whole seconds of debug counters on the game-over screen: all zero."""
        seq = self.sim.get_log_buffer(tail=1).get("next_seq", 0)
        time.sleep(2.5)
        lines = [l["text"] for l in self.sim.get_log_lines(since_seq=seq)
                 if "[brick15] draws=" in l["text"]]
        tail = lines[-2:]
        if len(tail) < 2 or any("draws=0 flushes=0" not in t for t in tail):
            self.failures.append(f"{gid}: idle game-over screen still drawing: {tail}")

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
        shutil.copytree(APP_DIR, app, ignore=shutil.ignore_patterns(".git", "dev", "docs", ".superpowers"))
        main_lua = app / "main.lua"
        main_lua.write_text(main_lua.read_text().replace("local DEBUG = false", "local DEBUG = true", 1))

        game_ids = re.search(r"GAME_IDS = \{([^}]*)\}", main_lua.read_text(), re.S).group(1)
        game_ids = re.findall(r'"([a-z]+)"', game_ids)

        self.sim = PicodeckSimulator(sd_card_path=str(sd), headless=True)
        self.sim.start()
        try:
            time.sleep(1.0)
            self.sim.launch_app(APP_DIR.name)
            time.sleep(3.0)                       # power-on curtain, then the menu
            # A game that fails to load is left out of the menu, which would
            # shift every later game onto the wrong script: stop here.
            skipped = [l["text"] for l in self.sim.get_log_lines() if "[brick15] skipped" in l["text"]]
            if skipped:
                self.failures += [f"game failed to load: {t}" for t in skipped]
                return self.report(game_ids)
            self.shot("menu")
            self.sim.keypress("up")
            time.sleep(0.3)
            self.shot("menu-speed-2")
            self.sim.keypress("down")
            time.sleep(0.2)

            menu_checked = False
            for i, gid in enumerate(game_ids):
                if i > 0:
                    self.sim.keypress("right")    # next game in the menu
                    time.sleep(0.3)
                if self.only and gid not in self.only:
                    continue
                self.sim.keypress("enter")
                time.sleep(0.5)
                self.shot(f"{gid}-hint")
                self.run_steps(PLAY.get(gid, [("wait", 1.5)]))
                self.shot(f"{gid}-gameplay")
                if not self.finish(gid):
                    self.failures.append(f"{gid}: never reached the game-over screen")
                else:
                    self.shot(f"{gid}-game-over")
                    self.check_idle(gid)
                    if not menu_checked:
                        self.check_system_menu()
                        menu_checked = True
                self.sim.keypress("esc")          # back to the menu
                time.sleep(0.6)

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
        return self.report(game_ids)

    def report(self, game_ids):
        if self.failures:
            print("\nSMOKE FAILED")
            for f in self.failures:
                print(" -", f)
            return 1
        ran = [g for g in game_ids if not self.only or g in self.only]
        print(f"\nSMOKE OK ({len(ran)} games) — screenshots in {self.out}")
        return 0


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=str(Path(tempfile.gettempdir()) / "brick-smoke-shots"))
    ap.add_argument("--only", default="", help="comma-separated game ids to play")
    args = ap.parse_args()
    only = {g for g in args.only.split(",") if g}
    sys.exit(Smoke(args.out, only).main())
```

- [ ] **Step 4: Run the unit tests and the smoke test (Tetris only so far)**

Run:
```bash
lua dev/test/run.lua
PICODECK_ROOT=../picodeck python3 dev/smoke.py --out <scratchpad>/p2-shots
```
Expected:
- `72 tests, 0 failed`.
- `SMOKE OK (1 games)`, with screenshots `01-menu`, `02-menu-speed-2`, `03-tetris-hint`, `04-tetris-gameplay`, `05-tetris-game-over` and `06-menu-after-play`.
- `05-tetris-game-over` shows an empty grid with GAME OVER / ENTER AGAIN / ESC MENU. That confirms the screen-based game-over detection.

- [ ] **Step 5: Commit**

```bash
git add lib/runner.lua dev/test/game_helpers.lua dev/smoke.py
git commit -m "Document the game contract; add game test helpers; smoke test detects game over and plays all 15 games"
```

---

### Task 2: Game 02, Snake

Eat the blinking food, don't hit the walls or yourself.

**Files:**
- Create: `dev/test/test_snake.lua`
- Rewrite: `games/snake.lua`
- Modify: `main.lua` (`GAME_IDS`)

**Interfaces:**
- Consumes: the game contract and the Task 1 test helpers.
- Produces:
  - The module `games/snake.lua`, with `id = "snake"`.
  - Game fields the tests use: `body` (list of {x,y}, head first), `dir`, `next_dir`, `food`, `eaten`, `next_step`, `game:place_food()`.

- [ ] **Step 1: Write the failing tests**

Create `dev/test/test_snake.lua`:

```lua
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
```

- [ ] **Step 2: Run them against the old game to see them fail**

Run: `lua dev/test/run.lua dev/test/test_snake.lua`
Expected: every test fails against the old BRICK-30 module, starting with `FAIL  snake: meets the game contract`. The last line is `11 tests, 11 failed`.

- [ ] **Step 3: Rewrite `games/snake.lua`**

Replace the whole file with:

```lua
-- snake.lua — game 02: eat the blinking food, don't hit the walls or yourself.
-- Game contract: see lib/runner.lua. Needs the SFX global.

local COLS, ROWS = 10, 20
local STEP_MS = 300        -- one cell per step at speed 1, level 1
local FOODS_PER_LEVEL = 5

local DEMO = {
    {
        "..........",
        "..........",
        "..######..",
        "..#.......",
        "..#.......",
        "..#####...",
        "..........",
        "......#...",
        "..........",
        "..........",
        "..........",
        "..........",
    },
    {
        "..........",
        "..........",
        "...#####..",
        "..##......",
        "..#.......",
        "..######..",
        "..........",
        "......#...",
        "..........",
        "..........",
        "..........",
        "..........",
    },
}

local function new(ctx)
    local game = {
        score = 0, level = 1, eaten = 0,
        body = { { x = 5, y = 10 }, { x = 4, y = 10 }, { x = 3, y = 10 } },
        dir = { x = 1, y = 0 },
    }
    game.next_dir = game.dir
    game.next_step = ctx.now + ctx.interval(STEP_MS, game.level)

    local function on_body(x, y)
        for _, s in ipairs(game.body) do
            if s.x == x and s.y == y then return true end
        end
        return false
    end

    -- A random free cell; false when the snake fills the field.
    function game:place_food()
        local free = {}
        for y = 1, ROWS do
            for x = 1, COLS do
                if not on_body(x, y) then free[#free + 1] = { x = x, y = y } end
            end
        end
        if #free == 0 then return false end
        self.food = free[math.random(#free)]
        return true
    end

    local TURNS = {
        up = { x = 0, y = -1 }, down = { x = 0, y = 1 },
        left = { x = -1, y = 0 }, right = { x = 1, y = 0 },
    }

    function game:update(pad, now)
        for key, d in pairs(TURNS) do
            -- turns must be at right angles to the heading: no reversing
            -- into yourself, even with two presses inside one step
            if pad.pressed[key] and d.x * self.dir.x + d.y * self.dir.y == 0 then
                self.next_dir = d
            end
        end
        if now < self.next_step then return nil end
        self.next_step = now + ctx.interval(STEP_MS, self.level)
        self.dir = self.next_dir

        local head = self.body[1]
        local nx, ny = head.x + self.dir.x, head.y + self.dir.y
        if nx < 1 or nx > COLS or ny < 1 or ny > ROWS then return "over" end
        local eating = self.food and nx == self.food.x and ny == self.food.y
        if not eating then table.remove(self.body) end   -- the tail moves on
        if on_body(nx, ny) then return "over" end
        table.insert(self.body, 1, { x = nx, y = ny })

        if eating then
            self.eaten = self.eaten + 1
            self.score = self.score + 10 * self.level
            self.level = self.eaten // FOODS_PER_LEVEL + 1
            SFX.eat()
            if not self:place_food() then
                self.status = { "CLEARED" }
                return "over"
            end
        end
        return nil
    end

    function game:draw(grid)
        for _, s in ipairs(self.body) do grid:set(s.x, s.y, true) end
        if self.food then grid:set(self.food.x, self.food.y, "blink") end
    end

    game:place_food()
    return game
end

return {
    id = "snake",
    name = "SNAKE",
    hint = { "D-PAD STEER" },
    messages = { "CLEARED" },
    order = "high",
    demo = DEMO,
    new = new,
}
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `lua dev/test/run.lua dev/test/test_snake.lua`
Expected: `11 tests, 0 failed`

- [ ] **Step 5: Add the game to the menu**

In `main.lua`, replace the `GAME_IDS` table (it currently ends with `"tetris"`) with:

```lua
local GAME_IDS = {
    "tetris", "snake",
}
```

- [ ] **Step 6: Run the whole suite and the smoke test for this game**

Run:
```bash
lua dev/test/run.lua
PICODECK_ROOT=../picodeck python3 dev/smoke.py --only snake --out <scratchpad>/p2-snake
```
Expected:
- The whole suite passes.
- `SMOKE OK (1 games)`, with `snake-hint`, `snake-gameplay` and `snake-game-over` screenshots; its FINISH steps lose it.
- Look at the gameplay screenshot: it should match the spec's section 3 row for this game.

- [ ] **Step 7: Commit**

```bash
git add games/snake.lua dev/test/test_snake.lua main.lua
git commit -m "snake: port to the grid game contract"
```

---

### Task 3: Game 03, Breakout

Knock out 4 rows of bricks with a 1-brick ball.

**Files:**
- Create: `dev/test/test_breakout.lua`
- Rewrite: `games/breakout.lua`
- Modify: `main.lua` (`GAME_IDS`)

**Interfaces:**
- Consumes: the game contract and the Task 1 test helpers.
- Produces:
  - The module `games/breakout.lua`, with `id = "breakout"`.
  - Game fields the tests use: `bricks[r][c]`, `paddle` (left cell), `ball` {x,y,dx,dy}, `serving`, `next_step`.

- [ ] **Step 1: Write the failing tests**

Create `dev/test/test_breakout.lua`:

```lua
need("dev/test/game_helpers.lua")
local breakout = need("games/breakout.lua")

local function new_game() return breakout.new(game_ctx()) end

-- Put the ball in play at (x, y) moving (dx, dy), due to move at `now`.
local function launch(g, x, y, dx, dy, now)
    g.serving = false
    g.ball = { x = x, y = y, dx = dx, dy = dy }
    g.next_step = now or 0
end

test("breakout: meets the game contract", function()
    check_contract(breakout, "breakout", "BREAKOUT")
end)

test("breakout: 40 bricks on rows 2-5, 3 lives, ball waiting on the paddle", function()
    local g = new_game()
    local n = 0
    for r = 2, 5 do for c = 1, 10 do if g.bricks[r][c] then n = n + 1 end end end
    eq(n, 40, "bricks"); eq(g.lives, 3, "lives"); eq(g.serving, true, "serving")
    eq(g.ball.y, 19, "ball above the paddle")
end)

test("breakout: the waiting ball follows the paddle, Enter serves it", function()
    local g = new_game()
    g:update(press("left"), 1)
    eq(g.ball.x, g.paddle + 1, "ball over paddle centre")
    g:update(press("enter"), 2)
    eq(g.serving, false, "served"); eq(g.ball.dy, -1, "going up")
end)

test("breakout: the ball bounces off the side wall", function()
    local g = new_game()
    launch(g, 1, 10, -1, -1)
    g:update(NONE, 0)
    eq(g.ball.dx, 1, "reflected"); eq(g.ball.x, 2, "moved right")
end)

test("breakout: a ball driven into a corner bounces out of it", function()
    local g = new_game()
    for r = 2, 5 do for c = 1, 10 do g.bricks[r][c] = false end end
    g.bricks[5][5] = true                -- keep the board alive
    launch(g, 1, 1, -1, -1)
    g:update(NONE, 0)
    eq(g.ball.dx, 1, "off the side"); eq(g.ball.dy, 1, "off the top")
    truthy(g.ball.x >= 1 and g.ball.y >= 1, "still on the grid")
end)

test("breakout: hitting a brick removes it, scores and bounces", function()
    local g = new_game()
    launch(g, 3, 6, 1, -1)       -- next cell up is (3,5), a brick
    g:update(NONE, 0)
    eq(g.bricks[5][3], false, "brick gone")
    eq(g.score, 10, "score"); eq(g.ball.dy, 1, "bounced down")
end)

test("breakout: the paddle bounces the ball, its edge angles it", function()
    local g = new_game()
    g.paddle = 4                 -- cells 4-6
    launch(g, 5, 19, 1, 1)
    g:update(NONE, 0)
    eq(g.ball.dy, -1, "bounced up")
    launch(g, 3, 19, 1, 1)       -- will land on cell 4, the left edge
    g:update(NONE, 0)
    eq(g.ball.dx, -1, "left edge sends it left")
end)

test("breakout: missing the ball costs a life and re-serves", function()
    local g = new_game()
    g.paddle = 1
    launch(g, 8, 19, 1, 1)
    g:update(NONE, 0)
    eq(g.lives, 2, "life lost"); eq(g.serving, true, "serving again")
end)

test("breakout: losing the last life ends the round", function()
    local g = new_game()
    g.paddle, g.lives = 1, 1
    launch(g, 8, 19, 1, 1)
    eq(g:update(NONE, 0), "over", "over")
end)

test("breakout: clearing every brick starts the next board", function()
    local g = new_game()
    for r = 2, 5 do for c = 1, 10 do g.bricks[r][c] = false end end
    g.bricks[5][3] = true
    launch(g, 3, 6, 1, -1)
    g:update(NONE, 0)
    eq(g.level, 2, "level 2"); eq(g.serving, true, "serve the new board")
    eq(g.bricks[2][1], true, "bricks back")
end)

test("breakout: draw shows bricks, the 3-brick paddle and the ball", function()
    local g = new_game()
    local grid = draw_game(g)
    eq(count_lit(grid), 40 + 3 + 1, "lit cells")
end)
```

- [ ] **Step 2: Run them against the old game to see them fail**

Run: `lua dev/test/run.lua dev/test/test_breakout.lua`
Expected: every test fails against the old BRICK-30 module, starting with `FAIL  breakout: meets the game contract`. The last line is `11 tests, 11 failed`.

- [ ] **Step 3: Rewrite `games/breakout.lua`**

Replace the whole file with:

```lua
-- breakout.lua — game 03: knock out 4 rows of bricks with a 1-brick ball.
-- Game contract: see lib/runner.lua. Needs the SFX global.

local COLS, ROWS = 10, 20
local BRICK_ROWS = { 2, 3, 4, 5 }
local PADDLE_W = 3
local STEP_MS = 150        -- ball speed at speed 1, level 1

local DEMO = {
    {
        "##########",
        "##########",
        "###..#####",
        "##########",
        "..........",
        "..........",
        "....#.....",
        "..........",
        "..........",
        "..........",
        "..........",
        "...###....",
    },
    {
        "##########",
        "##########",
        "###..#####",
        "##########",
        "..........",
        "..........",
        "..........",
        "..........",
        "......#...",
        "..........",
        "..........",
        "....###...",
    },
}

local function new(ctx)
    local game = { score = 0, level = 1, lives = 3, paddle = 4 }   -- paddle = left cell

    local function fill_bricks()
        game.bricks = {}
        for r = 1, ROWS do
            game.bricks[r] = {}
            for c = 1, COLS do game.bricks[r][c] = false end
        end
        for _, r in ipairs(BRICK_ROWS) do
            for c = 1, COLS do game.bricks[r][c] = true end
        end
    end

    local function serve_position()
        game.serving = true
        game.ball = { x = game.paddle + 1, y = ROWS - 1, dx = 1, dy = -1 }
    end

    local function bricks_left()
        for _, r in ipairs(BRICK_ROWS) do
            for c = 1, COLS do
                if game.bricks[r][c] then return true end
            end
        end
        return false
    end

    local function hit_brick(x, y)
        if y >= 1 and y <= ROWS and x >= 1 and x <= COLS and game.bricks[y][x] then
            game.bricks[y][x] = false
            game.score = game.score + 10 * game.level
            SFX.hit()
            return true
        end
        return false
    end

    -- One ball step. Returns "lost" when the ball gets past the paddle.
    local function step_ball()
        local b = game.ball
        if b.x + b.dx < 1 or b.x + b.dx > COLS then b.dx = -b.dx SFX.move() end
        if b.y + b.dy < 1 then b.dy = 1 SFX.move() end

        -- bricks: straight up/down first, then sideways, then the corner
        if hit_brick(b.x, b.y + b.dy) then b.dy = -b.dy return end
        if hit_brick(b.x + b.dx, b.y) then b.dx = -b.dx return end
        if hit_brick(b.x + b.dx, b.y + b.dy) then b.dx, b.dy = -b.dx, -b.dy return end

        -- paddle on the bottom row
        if b.dy == 1 and b.y + 1 == ROWS then
            local nx = b.x + b.dx
            local p = game.paddle
            if nx >= p and nx <= p + PADDLE_W - 1 then
                b.dy = -1
                if nx == p then b.dx = -1 elseif nx == p + PADDLE_W - 1 then b.dx = 1 end
                SFX.rotate()
                return
            end
        end

        b.x, b.y = b.x + b.dx, b.y + b.dy
        if b.y >= ROWS then return "lost" end   -- reached the paddle row uncaught
    end

    function game:update(pad, now)
        if pad.repeated.left and self.paddle > 1 then self.paddle = self.paddle - 1 end
        if pad.repeated.right and self.paddle < COLS - PADDLE_W + 1 then self.paddle = self.paddle + 1 end

        if self.serving then
            self.ball.x = self.paddle + 1
            if pad.pressed.enter or pad.pressed.up or pad.pressed.f1 then
                self.serving = false
                self.next_step = now + ctx.interval(STEP_MS, self.level)
            end
            return nil
        end

        if now < self.next_step then return nil end
        self.next_step = now + ctx.interval(STEP_MS, self.level)

        if step_ball() == "lost" then
            self.lives = self.lives - 1
            if self.lives <= 0 then return "over" end
            SFX.hit()
            serve_position()
            return nil
        end
        if not bricks_left() then
            self.level = self.level + 1
            SFX.levelup()
            fill_bricks()
            serve_position()
        end
        return nil
    end

    function game:draw(grid)
        for _, r in ipairs(BRICK_ROWS) do
            for c = 1, COLS do
                if self.bricks[r][c] then grid:set(c, r, true) end
            end
        end
        for i = 0, PADDLE_W - 1 do grid:set(self.paddle + i, ROWS, true) end
        grid:set(self.ball.x, self.ball.y, true)
    end

    fill_bricks()
    serve_position()
    return game
end

return {
    id = "breakout",
    name = "BREAKOUT",
    hint = { "< > MOVE", "ENTER SERVE" },
    order = "high",
    demo = DEMO,
    new = new,
}
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `lua dev/test/run.lua dev/test/test_breakout.lua`
Expected: `11 tests, 0 failed`

- [ ] **Step 5: Add the game to the menu**

In `main.lua`, replace the `GAME_IDS` table (it currently ends with `"snake"`) with:

```lua
local GAME_IDS = {
    "tetris", "snake", "breakout",
}
```

- [ ] **Step 6: Run the whole suite and the smoke test for this game**

Run:
```bash
lua dev/test/run.lua
PICODECK_ROOT=../picodeck python3 dev/smoke.py --only breakout --out <scratchpad>/p2-breakout
```
Expected:
- The whole suite passes.
- `SMOKE OK (1 games)`, with `breakout-hint`, `breakout-gameplay` and `breakout-game-over` screenshots; its FINISH steps lose it.
- Look at the gameplay screenshot: it should match the spec's section 3 row for this game.

- [ ] **Step 7: Commit**

```bash
git add games/breakout.lua dev/test/test_breakout.lua main.lua
git commit -m "breakout: port to the grid game contract"
```

---

### Task 4: Game 04, Invaders

Shoot the marching block before it reaches you.

**Files:**
- Create: `dev/test/test_invaders.lua`
- Rewrite: `games/invaders.lua`
- Modify: `main.lua` (`GAME_IDS`)

**Interfaces:**
- Consumes: the game contract and the Task 1 test helpers.
- Produces:
  - The module `games/invaders.lua`, with `id = "invaders"`.
  - Game fields the tests use: `aliens` ({c,r,alive}), `ox`/`oy` (block origin), `march_dir`, `gun`, `bullet`, `bombs`, `next_march`/`next_bullet`/`next_bomb`/`next_bombs`, `game:alien_pos(a)`.

- [ ] **Step 1: Write the failing tests**

Create `dev/test/test_invaders.lua`:

```lua
need("dev/test/game_helpers.lua")
local invaders = need("games/invaders.lua")

local function new_game()
    local g = invaders.new(game_ctx())
    g.next_bomb = math.huge            -- no bombs unless a test adds them
    return g
end

local function alive(g)
    local n = 0
    for _, a in ipairs(g.aliens) do if a.alive then n = n + 1 end end
    return n
end

test("invaders: meets the game contract", function()
    check_contract(invaders, "invaders", "INVADERS")
end)

test("invaders: a 6x3 block of aliens, gun at the bottom, 3 lives", function()
    local g = new_game()
    eq(#g.aliens, 18, "aliens"); eq(alive(g), 18, "all alive")
    eq(g.lives, 3, "lives"); eq(g.gun, 5, "gun centre column")
end)

test("invaders: the block marches sideways, then drops and turns at the edge", function()
    local g = new_game()
    local x0 = g.ox
    g:update(NONE, g.next_march)
    eq(g.ox, x0 + 1, "stepped right")
    g.ox = 10 - 6 + 1                   -- right edge of the block at column 10
    local y0 = g.oy
    g:update(NONE, g.next_march)
    eq(g.oy, y0 + 1, "dropped a row"); eq(g.march_dir, -1, "now marching left")
end)

test("invaders: only one bullet at a time", function()
    local g = new_game()
    g:update(press("up"), 1)
    truthy(g.bullet, "fired")
    local first = g.bullet
    g:update(press("up"), 2)
    eq(g.bullet, first, "second shot ignored")
end)

test("invaders: a bullet kills the alien it reaches and scores", function()
    local g = new_game()
    local a = g.aliens[13]              -- bottom row, first column
    local ax, ay = g:alien_pos(a)
    g.bullet = { x = ax, y = ay + 1 }
    g.next_bullet = 0
    g:update(NONE, 0)
    eq(a.alive, false, "alien dead"); eq(g.bullet, nil, "bullet used")
    eq(g.score, 10, "score")
end)

test("invaders: a bomb on the gun costs a life", function()
    local g = new_game()
    g.bombs = { { x = g.gun, y = 18 } }
    g.next_bombs = 0
    g:update(NONE, 0)
    eq(g.lives, 2, "life lost"); eq(#g.bombs, 0, "bombs cleared")
end)

test("invaders: losing the last life ends the round", function()
    local g = new_game()
    g.lives = 1
    g.bombs = { { x = g.gun, y = 18 } }
    g.next_bombs = 0
    eq(g:update(NONE, 0), "over", "over")
end)

test("invaders: aliens reaching the gun rows end the round", function()
    local g = new_game()
    g.oy = 16                           -- bottom alien row at 18 after the drop
    g.ox, g.march_dir = 5, 1
    eq(g:update(NONE, g.next_march), "over", "invaded")
end)

test("invaders: clearing the wave starts the next one a level up", function()
    local g = new_game()
    for i = 1, 17 do g.aliens[i].alive = false end
    local a = g.aliens[18]
    local ax, ay = g:alien_pos(a)
    g.bullet, g.next_bullet = { x = ax, y = ay + 1 }, 0
    g:update(NONE, 0)
    eq(g.level, 2, "level 2"); eq(alive(g), 18, "new wave")
end)

test("invaders: draw shows 18 aliens and the 4-cell gun", function()
    local g = new_game()
    eq(count_lit(draw_game(g)), 18 + 4, "lit")
end)
```

- [ ] **Step 2: Run them against the old game to see them fail**

Run: `lua dev/test/run.lua dev/test/test_invaders.lua`
Expected: every test fails against the old BRICK-30 module, starting with `FAIL  invaders: meets the game contract`. The last line is `10 tests, 10 failed`.

- [ ] **Step 3: Rewrite `games/invaders.lua`**

Replace the whole file with:

```lua
-- invaders.lua — game 04: shoot the marching block before it reaches you.
-- Game contract: see lib/runner.lua. Needs the SFX global.

local COLS, ROWS = 10, 20
local BLOCK_W, BLOCK_H = 6, 3
local GUN_ROW = 19                -- gun is .#. on row 19, ### on row 20
local MARCH_MS = 600              -- block step at speed 1, level 1, full block
local BULLET_MS = 40
local BOMB_MS = 150               -- bomb fall step
local BOMB_EVERY_MS = 900         -- a new bomb at most this often
local MAX_BOMBS = 3

local DEMO = {
    {
        "..........",
        "######....",
        "######....",
        "######....",
        "..........",
        "..........",
        "..#.......",
        "..........",
        "..........",
        "..........",
        "....#.....",
        "...###....",
    },
    {
        "..........",
        ".######...",
        ".######...",
        ".######...",
        "..........",
        "....#.....",
        "..........",
        "..........",
        "..#.......",
        "....#.....",
        "....#.....",
        "...###....",
    },
}

local function new(ctx)
    local game = { score = 0, level = 1, lives = 3, gun = 5, bombs = {} }

    local function new_wave(now)
        game.aliens = {}
        for r = 1, BLOCK_H do
            for c = 1, BLOCK_W do
                game.aliens[#game.aliens + 1] = { c = c, r = r, alive = true }
            end
        end
        game.ox, game.oy = 1, 2          -- grid position of block cell (1,1)
        game.march_dir = 1
        game.bullet, game.bombs = nil, {}
        game.next_march = now + ctx.interval(MARCH_MS, game.level)
        game.next_bomb = now + BOMB_EVERY_MS
        game.next_bombs = now + BOMB_MS
    end

    function game:alien_pos(a)
        return self.ox + a.c - 1, self.oy + a.r - 1
    end

    local function alive_count()
        local n = 0
        for _, a in ipairs(game.aliens) do if a.alive then n = n + 1 end end
        return n
    end

    -- Columns of the live block's leftmost/rightmost aliens, and its lowest row.
    local function extent()
        local minx, maxx, maxy = COLS + 1, 0, 0
        for _, a in ipairs(game.aliens) do
            if a.alive then
                local x, y = game:alien_pos(a)
                minx, maxx, maxy = math.min(minx, x), math.max(maxx, x), math.max(maxy, y)
            end
        end
        return minx, maxx, maxy
    end

    local function gun_hit(x, y)
        return (y == GUN_ROW and x == game.gun)
            or (y == GUN_ROW + 1 and x >= game.gun - 1 and x <= game.gun + 1)
    end

    local function march_interval()
        -- the block speeds up as it thins out
        local frac = 0.4 + 0.6 * alive_count() / (BLOCK_W * BLOCK_H)
        return math.max(80, ctx.interval(MARCH_MS, game.level) * frac)
    end

    function game:update(pad, now)
        if pad.repeated.left and self.gun > 2 then self.gun = self.gun - 1 end
        if pad.repeated.right and self.gun < COLS - 1 then self.gun = self.gun + 1 end
        if (pad.pressed.up or pad.pressed.enter or pad.pressed.f1) and not self.bullet then
            self.bullet = { x = self.gun, y = GUN_ROW - 1 }
            self.next_bullet = now + BULLET_MS
            SFX.move()
        end

        -- player bullet
        if self.bullet and now >= self.next_bullet then
            self.next_bullet = now + BULLET_MS
            local b = self.bullet
            b.y = b.y - 1
            for _, a in ipairs(self.aliens) do
                local x, y = self:alien_pos(a)
                if a.alive and x == b.x and y == b.y then
                    a.alive = false
                    self.bullet = nil
                    self.score = self.score + 10 * self.level
                    SFX.hit()
                    break
                end
            end
            if self.bullet and b.y < 1 then self.bullet = nil end
            if alive_count() == 0 then
                self.level = self.level + 1
                SFX.levelup()
                new_wave(now)
                return nil
            end
        end

        -- march
        if now >= self.next_march then
            self.next_march = now + march_interval()
            local minx, maxx = extent()
            if (self.march_dir == 1 and maxx >= COLS) or (self.march_dir == -1 and minx <= 1) then
                self.oy = self.oy + 1
                self.march_dir = -self.march_dir
            else
                self.ox = self.ox + self.march_dir
            end
            local _, _, maxy = extent()
            if maxy >= GUN_ROW - 1 then return "over" end
        end

        -- new bomb from the lowest alien of a random live column
        if now >= self.next_bomb and #self.bombs < MAX_BOMBS then
            self.next_bomb = now + BOMB_EVERY_MS
            local lowest = {}
            for _, a in ipairs(self.aliens) do
                if a.alive and (not lowest[a.c] or a.r > lowest[a.c].r) then lowest[a.c] = a end
            end
            local cols = {}
            for _, a in pairs(lowest) do cols[#cols + 1] = a end
            if #cols > 0 then
                local x, y = self:alien_pos(cols[math.random(#cols)])
                self.bombs[#self.bombs + 1] = { x = x, y = y + 1 }
            end
        end

        -- bombs fall
        if now >= self.next_bombs then
            self.next_bombs = now + BOMB_MS
            local kept = {}
            for _, b in ipairs(self.bombs) do
                b.y = b.y + 1
                if gun_hit(b.x, b.y) then
                    self.lives = self.lives - 1
                    SFX.over()
                    self.bombs, self.bullet = {}, nil
                    if self.lives <= 0 then return "over" end
                    return nil
                end
                if b.y <= ROWS then kept[#kept + 1] = b end
            end
            self.bombs = kept
        end
        return nil
    end

    function game:draw(grid)
        for _, a in ipairs(self.aliens) do
            if a.alive then grid:set(self:alien_pos(a)) end
        end
        grid:stamp({ ".#.", "###" }, self.gun - 1, GUN_ROW)
        if self.bullet then grid:set(self.bullet.x, self.bullet.y, true) end
        for _, b in ipairs(self.bombs) do grid:set(b.x, b.y, true) end
    end

    new_wave(ctx.now)
    return game
end

return {
    id = "invaders",
    name = "INVADERS",
    hint = { "< > MOVE", "UP FIRE" },
    order = "high",
    demo = DEMO,
    new = new,
}
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `lua dev/test/run.lua dev/test/test_invaders.lua`
Expected: `10 tests, 0 failed`

- [ ] **Step 5: Add the game to the menu**

In `main.lua`, replace the `GAME_IDS` table (it currently ends with `"breakout"`) with:

```lua
local GAME_IDS = {
    "tetris", "snake", "breakout", "invaders",
}
```

- [ ] **Step 6: Run the whole suite and the smoke test for this game**

Run:
```bash
lua dev/test/run.lua
PICODECK_ROOT=../picodeck python3 dev/smoke.py --only invaders --out <scratchpad>/p2-invaders
```
Expected:
- The whole suite passes.
- `SMOKE OK (1 games)`, with `invaders-hint`, `invaders-gameplay` and `invaders-game-over` screenshots; its FINISH steps lose it.
- Look at the gameplay screenshot: it should match the spec's section 3 row for this game.

- [ ] **Step 7: Commit**

```bash
git add games/invaders.lua dev/test/test_invaders.lua main.lua
git commit -m "invaders: port to the grid game contract"
```

---

### Task 5: Game 05, Frogger

Cross the road, ride the logs, fill the 5 homes.

**Files:**
- Create: `dev/test/test_frogger.lua`
- Rewrite: `games/frogger.lua`
- Modify: `main.lua` (`GAME_IDS`)

**Interfaces:**
- Consumes: the game contract and the Task 1 test helpers.
- Produces:
  - The module `games/frogger.lua`, with `id = "frogger"`.
  - Game fields the tests use: `fx`/`fy`, `best`, `homes[col]`, `lanes[row]` {kind, pattern, offset, dir, ms, next_shift}.

- [ ] **Step 1: Write the failing tests**

Create `dev/test/test_frogger.lua`:

```lua
need("dev/test/game_helpers.lua")
local frogger = need("games/frogger.lua")

local function new_game()
    local g = frogger.new(game_ctx())
    for _, lane in pairs(g.lanes) do lane.next_shift = math.huge end   -- freeze traffic
    return g
end

-- Replace one lane's contents with a fixed pattern (offset 0).
local function set_lane(g, row, pattern)
    g.lanes[row].pattern, g.lanes[row].offset = pattern, 0
end

test("frogger: meets the game contract", function()
    check_contract(frogger, "frogger", "FROGGER")
end)

test("frogger: frog starts on row 20, 3 lives, 5 empty homes", function()
    local g = new_game()
    eq(g.fy, 20, "start row"); eq(g.lives, 3, "lives")
    local empty = 0
    for _, filled in pairs(g.homes) do if not filled then empty = empty + 1 end end
    eq(empty, 5, "homes")
end)

test("frogger: a hop moves one cell and scores the first time a row is reached", function()
    local g = new_game()
    set_lane(g, 18, "..........")
    g:update(press("up"), 1)
    eq(g.fy, 19, "hopped"); eq(g.score, 10, "new row scores")
    g:update(press("down"), 2)
    g:update(press("up"), 3)
    eq(g.score, 10, "no score for a row already reached")
end)

test("frogger: a car on the frog costs a life and resets the frog", function()
    local g = new_game()
    set_lane(g, 18, "##........")
    g.fx, g.fy = 1, 19
    g:update(press("up"), 1)         -- hop onto the car at column 1
    eq(g.lives, 2, "life lost"); eq(g.fy, 20, "back at the start")
end)

test("frogger: landing in the river off a log drowns", function()
    local g = new_game()
    set_lane(g, 7, "#####.....")
    g.fx, g.fy = 8, 8
    g:update(press("up"), 1)
    eq(g.lives, 2, "drowned")
end)

test("frogger: a log carries the frog when its lane moves", function()
    local g = new_game()
    set_lane(g, 7, "#####.....")
    g.lanes[7].dir = 1
    g.fx, g.fy = 3, 7
    g.lanes[7].next_shift = 0
    g:update(NONE, 0)
    eq(g.fx, 4, "carried right"); eq(g.lives, 3, "still alive")
end)

test("frogger: being carried off the edge drowns", function()
    local g = new_game()
    set_lane(g, 7, "#........#")
    g.lanes[7].dir = 1
    g.fx, g.fy = 10, 7
    g.lanes[7].next_shift = 0
    g:update(NONE, 0)
    eq(g.lives, 2, "carried off")
end)

test("frogger: an empty home scores 50 and fills; a wall kills", function()
    local g = new_game()
    set_lane(g, 2, "##########")
    g.fx, g.fy = 3, 2
    g:update(press("up"), 1)
    eq(g.homes[3], true, "home filled"); eq(g.fy, 20, "new frog")
    truthy(g.score >= 50, "scored")
    g.fx, g.fy = 4, 2
    g:update(press("up"), 2)
    eq(g.lives, 2, "wall kills")
end)

test("frogger: filling all 5 homes raises the level and empties them", function()
    local g = new_game()
    set_lane(g, 2, "##########")
    for _, c in ipairs({ 1, 3, 5, 7 }) do g.homes[c] = true end
    g.fx, g.fy = 9, 2
    g:update(press("up"), 1)
    eq(g.level, 2, "level 2"); eq(g.homes[1], false, "homes emptied")
end)

test("frogger: losing the last life ends the round", function()
    local g = new_game()
    g.lives = 1
    set_lane(g, 18, "##########")
    g.fy = 19
    eq(g:update(press("up"), 1), "over", "over")
end)

test("frogger: road cars are 2 long, river logs 4-5 long", function()
    local g = new_game()
    for row, lane in pairs(g.lanes) do
        -- patterns wrap around: rotate so the pattern starts with a gap
        local p = lane.pattern
        local i = p:find("%.")
        p = p:sub(i) .. p:sub(1, i - 1)
        for run in p:gmatch("#+") do
            if lane.kind == "road" then eq(#run, 2, "car length row " .. row)
            else truthy(#run >= 4 and #run <= 5, "log length row " .. row) end
        end
    end
end)
```

- [ ] **Step 2: Run them against the old game to see them fail**

Run: `lua dev/test/run.lua dev/test/test_frogger.lua`
Expected: every test fails against the old BRICK-30 module, starting with `FAIL  frogger: meets the game contract`. The last line is `11 tests, 11 failed`.

- [ ] **Step 3: Rewrite `games/frogger.lua`**

Replace the whole file with:

```lua
-- frogger.lua — game 05: cross the road, ride the logs, fill the 5 homes.
-- Rows: 1 homes, 2-7 river, 8-9 bank, 10-18 road, 19-20 start.
-- Game contract: see lib/runner.lua. Needs the SFX global.

local COLS, ROWS = 10, 20
local START_X, START_Y = 5, 20
local HOME_COLS = { 1, 3, 5, 7, 9 }   -- walls stand on the even columns

-- Each lane is a 10-cell loop ('#' = log or car) that shifts one cell every
-- `ms` in `dir`. Cars are 2 long, logs 4-5 long.
local LANES = {
    [2]  = { kind = "river", pattern = "#####.....", dir = -1, ms = 700 },
    [3]  = { kind = "river", pattern = "####.####.", dir = 1,  ms = 900 },
    [4]  = { kind = "river", pattern = "#####.....", dir = -1, ms = 600 },
    [5]  = { kind = "river", pattern = "####.####.", dir = 1,  ms = 800 },
    [6]  = { kind = "river", pattern = "#####.....", dir = -1, ms = 750 },
    [7]  = { kind = "river", pattern = "####.####.", dir = 1,  ms = 650 },
    [10] = { kind = "road",  pattern = "##....##..", dir = 1,  ms = 500 },
    [11] = { kind = "road",  pattern = "##........", dir = -1, ms = 350 },
    [12] = { kind = "road",  pattern = "##...##...", dir = 1,  ms = 700 },
    [13] = { kind = "road",  pattern = "##........", dir = -1, ms = 450 },
    [14] = { kind = "road",  pattern = "##....##..", dir = 1,  ms = 600 },
    [15] = { kind = "road",  pattern = "##...##...", dir = -1, ms = 800 },
    [16] = { kind = "road",  pattern = "##........", dir = 1,  ms = 400 },
    [17] = { kind = "road",  pattern = "##....##..", dir = -1, ms = 550 },
    [18] = { kind = "road",  pattern = "##........", dir = 1,  ms = 650 },
}

local DEMO = {
    {
        "#.#.#.#.#.",
        "#####.....",
        "..####.###",
        "..........",
        "##....##..",
        "....##....",
        "##...##...",
        "..........",
        "..........",
        "..........",
        "..........",
        "....#.....",
    },
    {
        "#.#.#.#.#.",
        ".#####....",
        ".####.###.",
        "..........",
        ".##....##.",
        "...##.....",
        ".##...##..",
        "..........",
        "..........",
        "..........",
        "....#.....",
        "..........",
    },
}

local function occupied(lane, c)
    local i = (c - 1 - lane.offset) % COLS + 1
    return string.sub(lane.pattern, i, i) == "#"
end

local function new(ctx)
    local game = { score = 0, level = 1, lives = 3, homes = {}, lanes = {} }
    for _, c in ipairs(HOME_COLS) do game.homes[c] = false end
    for row, def in pairs(LANES) do
        game.lanes[row] = { kind = def.kind, pattern = def.pattern, dir = def.dir, ms = def.ms,
                            offset = math.random(0, COLS - 1),
                            next_shift = ctx.now + ctx.interval(def.ms, 1) }
    end

    local function reset_frog()
        game.fx, game.fy = START_X, START_Y
        game.best = START_Y           -- furthest row reached by this frog
    end

    local function hazard()
        local lane = game.lanes[game.fy]
        if not lane then return false end
        if lane.kind == "road" then return occupied(lane, game.fx) end
        return not occupied(lane, game.fx)          -- river: must be on a log
    end

    local function die()
        game.lives = game.lives - 1
        SFX.over()
        if game.lives <= 0 then return "over" end
        reset_frog()
        return nil
    end

    local function reach_home(c)
        if game.homes[c] ~= false then return die() end   -- wall or filled home
        game.homes[c] = true
        game.score = game.score + 50 * game.level
        SFX.score()
        local all = true
        for _, filled in pairs(game.homes) do all = all and filled end
        if all then
            game.level = game.level + 1
            game.score = game.score + 100
            for _, h in ipairs(HOME_COLS) do game.homes[h] = false end
            SFX.levelup()
        end
        reset_frog()
        return nil
    end

    local HOPS = { { "up", 0, -1 }, { "down", 0, 1 }, { "left", -1, 0 }, { "right", 1, 0 } }

    function game:update(pad, now)
        for _, h in ipairs(HOPS) do
            if pad.pressed[h[1]] then
                local nx = math.max(1, math.min(COLS, self.fx + h[2]))
                local ny = math.max(1, math.min(ROWS, self.fy + h[3]))
                if ny == 1 then return reach_home(nx) end
                self.fx, self.fy = nx, ny
                SFX.move()
                if self.fy < self.best then
                    self.best = self.fy
                    self.score = self.score + 10
                end
                if hazard() then return die() end
                break
            end
        end

        for row, lane in pairs(self.lanes) do
            if now >= lane.next_shift then
                lane.next_shift = now + ctx.interval(lane.ms, self.level)
                lane.offset = (lane.offset + lane.dir) % COLS
                if lane.kind == "river" and self.fy == row then
                    self.fx = self.fx + lane.dir
                    if self.fx < 1 or self.fx > COLS then return die() end
                end
            end
        end
        if hazard() then return die() end
        return nil
    end

    function game:draw(grid)
        for c = 1, COLS do
            if self.homes[c] ~= false then grid:set(c, 1, true) end   -- walls and filled homes
        end
        for row, lane in pairs(self.lanes) do
            for c = 1, COLS do
                if occupied(lane, c) then grid:set(c, row, true) end
            end
        end
        grid:set(self.fx, self.fy, "blink")
    end

    reset_frog()
    return game
end

return {
    id = "frogger",
    name = "FROGGER",
    hint = { "D-PAD HOP", "RIDE THE LOGS" },
    order = "high",
    demo = DEMO,
    new = new,
}
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `lua dev/test/run.lua dev/test/test_frogger.lua`
Expected: `11 tests, 0 failed`

- [ ] **Step 5: Add the game to the menu**

In `main.lua`, replace the `GAME_IDS` table (it currently ends with `"invaders"`) with:

```lua
local GAME_IDS = {
    "tetris", "snake", "breakout", "invaders", "frogger",
}
```

- [ ] **Step 6: Run the whole suite and the smoke test for this game**

Run:
```bash
lua dev/test/run.lua
PICODECK_ROOT=../picodeck python3 dev/smoke.py --only frogger --out <scratchpad>/p2-frogger
```
Expected:
- The whole suite passes.
- `SMOKE OK (1 games)`, with `frogger-hint`, `frogger-gameplay` and `frogger-game-over` screenshots; its FINISH steps lose it.
- Look at the gameplay screenshot: it should match the spec's section 3 row for this game.

- [ ] **Step 7: Commit**

```bash
git add games/frogger.lua dev/test/test_frogger.lua main.lua
git commit -m "frogger: port to the grid game contract"
```

---

### Task 6: Game 06, Racer

Switch lanes to dodge oncoming cars.

**Files:**
- Create: `dev/test/test_racer.lua`
- Rewrite: `games/racer.lua`
- Modify: `main.lua` (`GAME_IDS`)

**Interfaces:**
- Consumes: the game contract and the Task 1 test helpers.
- Produces:
  - The module `games/racer.lua`, with `id = "racer"`.
  - Game fields the tests use: `lane` (1|2), `cars` ({lane,y}), `distance`, `scroll`, `next_step`, `crash_until`.

- [ ] **Step 1: Write the failing tests**

Create `dev/test/test_racer.lua`:

```lua
need("dev/test/game_helpers.lua")
local racer = need("games/racer.lua")

local function new_game() return racer.new(game_ctx()) end

test("racer: meets the game contract", function()
    check_contract(racer, "racer", "RACER")
end)

test("racer: starts in the left lane with 3 lives", function()
    local g = new_game()
    eq(g.lane, 1, "left lane"); eq(g.lives, 3, "lives"); eq(g.score, 0, "score")
end)

test("racer: left and right switch lanes", function()
    local g = new_game()
    g:update(press("right"), 1)
    eq(g.lane, 2, "right lane")
    g:update(press("right"), 2)
    eq(g.lane, 2, "no third lane")
    g:update(press("left"), 3)
    eq(g.lane, 1, "back left")
end)

test("racer: each step moves traffic down a row and adds distance", function()
    local g = new_game()
    g.cars = { { lane = 2, y = 5 } }
    g:update(NONE, g.next_step)
    eq(g.cars[1].y, 6, "car moved"); eq(g.score, 1, "distance")
end)

test("racer: a car in your lane at your rows costs a life", function()
    local g = new_game()
    g.cars = { { lane = 1, y = 13 } }      -- rows 14-17 after the step: touches row 17
    g:update(NONE, g.next_step)
    eq(g.lives, 2, "crashed"); eq(#g.cars, 0, "road cleared")
end)

test("racer: a car in the other lane passes safely and scores a bonus", function()
    local g = new_game()
    g.cars = { { lane = 2, y = 20 } }
    g:update(NONE, g.next_step)
    eq(g.lives, 3, "no crash")
    for _, c in ipairs(g.cars) do eq(c.y, -3, "only a newly spawned car is left") end
    eq(g.score, 1 + 10, "distance + pass bonus")
end)

test("racer: losing the last life ends the round", function()
    local g = new_game()
    g.lives = 1
    g.cars = { { lane = 1, y = 13 } }
    eq(g:update(NONE, g.next_step), "over", "over")
end)

test("racer: new cars keep at least 3 clear rows between them", function()
    local g = new_game()
    local now = 0
    for _ = 1, 400 do
        now = g.next_step
        g.lane = 3                           -- park off-road so nothing crashes
        g:update(NONE, now)
        table.sort(g.cars, function(a, b) return a.y < b.y end)
        for i = 2, #g.cars do
            truthy(g.cars[i].y - g.cars[i - 1].y >= 7, "gap between cars")
        end
    end
end)

test("racer: every 100 rows of distance is a level", function()
    local g = new_game()
    g.score, g.distance = 99, 99
    g.cars = {}
    g:update(NONE, g.next_step)
    eq(g.level, 2, "level 2")
end)

test("racer: the player car is the upright shape at rows 17-20", function()
    local g = new_game()
    g.cars = {}
    local grid = draw_game(g)
    eq(grid:get(4, 17), true, "nose"); eq(grid:get(3, 17), false, "beside nose")
    eq(grid:get(3, 20), true, "left wheel"); eq(grid:get(4, 20), false, "between wheels")
end)
```

- [ ] **Step 2: Run them against the old game to see them fail**

Run: `lua dev/test/run.lua dev/test/test_racer.lua`
Expected: every test fails against the old BRICK-30 module, starting with `FAIL  racer: meets the game contract`. The last line is `10 tests, 10 failed`.

- [ ] **Step 3: Rewrite `games/racer.lua`**

Replace the whole file with:

```lua
-- racer.lua — game 06: switch lanes to dodge oncoming cars.
-- Game contract: see lib/runner.lua. Needs the SFX global.

local ROWS = 20
local LANE_COL = { 3, 6 }         -- left column of each lane's 3-wide car
local PLAYER_ROW = 17             -- the player's car fills rows 17-20
local STEP_MS = 160               -- road speed at speed 1, level 1
local SPACING = 7                 -- rows from one car's top to the next's
local SPAWN_Y = -3                -- new cars start just above the screen
local CRASH_MS = 800              -- the road stops this long after a crash
local ROWS_PER_LEVEL = 100

local PLAYER = { ".#.", "###", ".#.", "#.#" }
local ONCOMING = { "#.#", ".#.", "###", ".#." }   -- upside down: facing you

local DEMO = {
    {
        "#...#.#..#",
        "#....#...#",
        ".....###..",
        ".....#....",
        "#........#",
        "#........#",
        "..........",
        "..........",
        "#...#....#",
        "#..###...#",
        "....#.....",
        "...#.#....",
    },
    {
        "..........",
        "#...#.#..#",
        "#....#...#",
        ".....###..",
        "......#...",
        "#........#",
        "#........#",
        "..........",
        "..........",
        "#.....#..#",
        "#....###.#",
        "......#...",
    },
}

local function new(ctx)
    local game = { score = 0, level = 1, lives = 3, lane = 1, distance = 0,
                   cars = {}, scroll = 0 }
    game.next_step = ctx.now + ctx.interval(STEP_MS, game.level)

    local function crash(now)
        game.lives = game.lives - 1
        SFX.over()
        game.cars = {}
        game.crash_until = now + CRASH_MS
        if game.lives <= 0 then return "over" end
        return nil
    end

    local function hits_player(car)
        return car.lane == game.lane and car.y + 3 >= PLAYER_ROW and car.y <= ROWS
    end

    function game:update(pad, now)
        if pad.pressed.left and self.lane > 1 then self.lane = self.lane - 1 SFX.move() end
        if pad.pressed.right and self.lane < #LANE_COL then self.lane = self.lane + 1 SFX.move() end

        if self.crash_until and now < self.crash_until then return nil end
        self.crash_until = nil
        for _, car in ipairs(self.cars) do
            if hits_player(car) then return crash(now) end   -- you steered into it
        end
        if now < self.next_step then return nil end
        self.next_step = now + ctx.interval(STEP_MS, self.level)

        self.scroll = self.scroll + 1
        self.distance = self.distance + 1
        self.score = self.score + 1
        self.level = self.distance // ROWS_PER_LEVEL + 1

        local kept, top = {}, math.huge
        for _, car in ipairs(self.cars) do
            car.y = car.y + 1
            if car.y > ROWS then
                self.score = self.score + 10         -- passed it
            else
                kept[#kept + 1] = car
                top = math.min(top, car.y)
            end
        end
        self.cars = kept
        for _, car in ipairs(self.cars) do
            if hits_player(car) then return crash(now) end
        end
        if top - SPAWN_Y >= SPACING then            -- room for a new car above
            self.cars[#self.cars + 1] = { lane = math.random(#LANE_COL), y = SPAWN_Y }
        end
        return nil
    end

    function game:draw(grid)
        for r = 1, ROWS do
            if (r + self.scroll) % 4 < 2 then
                grid:set(1, r, true)
                grid:set(10, r, true)
            end
        end
        for _, car in ipairs(self.cars) do grid:stamp(ONCOMING, LANE_COL[car.lane], car.y) end
        local v = self.crash_until and "blink" or true
        if LANE_COL[self.lane] then grid:stamp(PLAYER, LANE_COL[self.lane], PLAYER_ROW, v) end
    end

    return game
end

return {
    id = "racer",
    name = "RACER",
    hint = { "< > CHANGE LANE" },
    order = "high",
    demo = DEMO,
    new = new,
}
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `lua dev/test/run.lua dev/test/test_racer.lua`
Expected: `10 tests, 0 failed`

- [ ] **Step 5: Add the game to the menu**

In `main.lua`, replace the `GAME_IDS` table (it currently ends with `"frogger"`) with:

```lua
local GAME_IDS = {
    "tetris", "snake", "breakout", "invaders", "frogger",
    "racer",
}
```

- [ ] **Step 6: Run the whole suite and the smoke test for this game**

Run:
```bash
lua dev/test/run.lua
PICODECK_ROOT=../picodeck python3 dev/smoke.py --only racer --out <scratchpad>/p2-racer
```
Expected:
- The whole suite passes.
- `SMOKE OK (1 games)`, with `racer-hint`, `racer-gameplay` and `racer-game-over` screenshots; its FINISH steps lose it.
- Look at the gameplay screenshot: it should match the spec's section 3 row for this game.

- [ ] **Step 7: Commit**

```bash
git add games/racer.lua dev/test/test_racer.lua main.lua
git commit -m "racer: port to the grid game contract"
```

---

### Task 7: Game 07, Pong

Vertical Pong against the CPU, first to 7.

**Files:**
- Create: `dev/test/test_pong.lua`
- Rewrite: `games/pong.lua`
- Modify: `main.lua` (`GAME_IDS`)

**Interfaces:**
- Consumes: the game contract and the Task 1 test helpers.
- Produces:
  - The module `games/pong.lua`, with `id = "pong"`.
  - Game fields the tests use: `player`/`cpu` (left cells), `cpu_points`, `ball`, `serving`, `next_step`, `next_ai`, `score_text`.

- [ ] **Step 1: Write the failing tests**

Create `dev/test/test_pong.lua`:

```lua
need("dev/test/game_helpers.lua")
local pong = need("games/pong.lua")

local function new_game()
    local g = pong.new(game_ctx())
    g.next_ai = math.huge                  -- CPU paddle still unless a test moves it
    return g
end

local function launch(g, x, y, dx, dy)
    g.serving = false
    g.ball = { x = x, y = y, dx = dx, dy = dy }
    g.next_step = 0
end

test("pong: meets the game contract", function()
    check_contract(pong, "pong", "PONG")
end)

test("pong: starts 00-00 with the ball on your paddle", function()
    local g = new_game()
    eq(g.score, 0, "score"); eq(g.score_text, "00-00", "shown score")
    eq(g.serving, true, "serving"); eq(g.ball.y, 19, "on the paddle")
end)

test("pong: Enter serves the ball upwards", function()
    local g = new_game()
    g:update(press("enter"), 1)
    eq(g.serving, false, "served"); eq(g.ball.dy, -1, "up")
end)

test("pong: the ball bounces off the side walls", function()
    local g = new_game()
    launch(g, 10, 10, 1, -1)
    g:update(NONE, 0)
    eq(g.ball.dx, -1, "reflected"); eq(g.ball.x, 9, "moved left")
end)

test("pong: your paddle returns the ball, its edge angles it", function()
    local g = new_game()
    g.player = 4                           -- cells 4-6
    launch(g, 4, 19, 1, 1)                 -- lands on 5, the middle
    g:update(NONE, 0)
    eq(g.ball.dy, -1, "returned"); eq(g.ball.dx, 1, "middle keeps direction")
    launch(g, 7, 19, -1, 1)                -- lands on 6, the right edge
    g:update(NONE, 0)
    eq(g.ball.dx, 1, "right edge sends it right")
end)

test("pong: missing the ball gives the CPU a point", function()
    local g = new_game()
    g.player = 1
    launch(g, 8, 19, 1, 1)
    g:update(NONE, 0)
    eq(g.cpu_points, 1, "cpu point"); eq(g.score_text, "00-01", "shown")
    eq(g.serving, true, "serve again")
end)

test("pong: getting past the CPU scores for you", function()
    local g = new_game()
    g.cpu = 1
    launch(g, 8, 2, 1, -1)
    g:update(NONE, 0)
    eq(g.score, 1, "your point"); eq(g.score_text, "01-00", "shown")
end)

test("pong: first to 7 ends the round with the result", function()
    local g = new_game()
    g.score, g.cpu = 6, 1
    launch(g, 8, 2, 1, -1)
    eq(g:update(NONE, 0), "over", "over"); eq(g.status[1], "YOU WIN", "result")
    check_status(pong, g)
    local h = new_game()
    h.cpu_points, h.player = 6, 1
    launch(h, 8, 19, 1, 1)
    eq(h:update(NONE, 0), "over", "over"); eq(h.status[1], "CPU WINS", "result")
    check_status(pong, h)
end)

test("pong: the CPU paddle chases a ball coming its way", function()
    local g = new_game()
    g.cpu = 4                              -- centre column 5
    launch(g, 9, 8, 1, -1)
    g.next_step, g.next_ai = math.huge, 0
    g:update(NONE, 0)
    eq(g.cpu, 5, "moved toward the ball")
end)
```

- [ ] **Step 2: Run them against the old game to see them fail**

Run: `lua dev/test/run.lua dev/test/test_pong.lua`
Expected: every test fails against the old BRICK-30 module, starting with `FAIL  pong: meets the game contract`. The last line is `9 tests, 9 failed`.

- [ ] **Step 3: Rewrite `games/pong.lua`**

Replace the whole file with:

```lua
-- pong.lua — game 07: vertical Pong against the CPU, first to 7.
-- Your paddle is on row 20, the CPU's on row 1.
-- Game contract: see lib/runner.lua. Needs the SFX global.

local COLS, ROWS = 10, 20
local PADDLE_W = 3
local WIN_POINTS = 7
local STEP_MS = 120               -- ball speed at speed 1
local AI_MS = 170                 -- CPU paddle speed at speed 1

local DEMO = {
    {
        "...###....",
        "..........",
        "..........",
        ".....#....",
        "..........",
        "..........",
        "..........",
        "..........",
        "..........",
        "..........",
        "..........",
        "....###...",
    },
    {
        "....###...",
        "..........",
        "..........",
        "..........",
        "..........",
        "..........",
        "..........",
        "..#.......",
        "..........",
        "..........",
        "..........",
        "...###....",
    },
}

local function new(ctx)
    -- score = your points (the record); score_text shows "you-cpu"
    local game = { score = 0, cpu_points = 0, player = 4, cpu = 4 }
    game.next_ai = ctx.now + ctx.interval(AI_MS, 1)

    local function refresh()
        game.score_text = string.format("%02d-%02d", game.score, game.cpu_points)
    end

    local function serve_position()
        game.serving = true
        game.ball = { x = game.player + 1, y = ROWS - 1, dx = 1, dy = -1 }
    end

    local function covers(left, x) return x >= left and x <= left + PADDLE_W - 1 end

    -- Bounce off a paddle whose left cell is `left`, landing at column nx.
    local function paddle_bounce(b, left, nx)
        b.dy = -b.dy
        if nx == left then b.dx = -1 elseif nx == left + PADDLE_W - 1 then b.dx = 1 end
        SFX.rotate()
    end

    local function point(for_player)
        if for_player then game.score = game.score + 1 SFX.score()
        else game.cpu_points = game.cpu_points + 1 SFX.hit() end
        refresh()
        if game.score >= WIN_POINTS then game.status = { "YOU WIN" } return "over" end
        if game.cpu_points >= WIN_POINTS then game.status = { "CPU WINS" } return "over" end
        serve_position()
        return nil
    end

    local function step_ball()
        local b = game.ball
        if b.x + b.dx < 1 or b.x + b.dx > COLS then b.dx = -b.dx end
        local nx = b.x + b.dx
        if b.dy == 1 and b.y + 1 == ROWS then
            if covers(game.player, nx) then paddle_bounce(b, game.player, nx) return nil end
            return point(false)
        end
        if b.dy == -1 and b.y - 1 == 1 then
            if covers(game.cpu, nx) then paddle_bounce(b, game.cpu, nx) return nil end
            return point(true)
        end
        b.x, b.y = nx, b.y + b.dy
        return nil
    end

    function game:update(pad, now)
        if pad.repeated.left and self.player > 1 then self.player = self.player - 1 end
        if pad.repeated.right and self.player < COLS - PADDLE_W + 1 then self.player = self.player + 1 end

        -- CPU: chase a ball heading its way, otherwise drift back to the middle
        if now >= self.next_ai then
            self.next_ai = now + ctx.interval(AI_MS, 1)
            local target = (self.ball.dy == -1 and not self.serving) and self.ball.x or 5
            local centre = self.cpu + 1
            if target < centre and self.cpu > 1 then self.cpu = self.cpu - 1
            elseif target > centre and self.cpu < COLS - PADDLE_W + 1 then self.cpu = self.cpu + 1 end
        end

        if self.serving then
            self.ball.x = self.player + 1
            if pad.pressed.enter or pad.pressed.up or pad.pressed.f1 then
                self.serving = false
                self.ball.dx = math.random(2) == 1 and -1 or 1
                self.next_step = now + ctx.interval(STEP_MS, 1)
            end
            return nil
        end
        if now < self.next_step then return nil end
        self.next_step = now + ctx.interval(STEP_MS, 1)
        return step_ball()
    end

    function game:draw(grid)
        for i = 0, PADDLE_W - 1 do
            grid:set(self.player + i, ROWS, true)
            grid:set(self.cpu + i, 1, true)
        end
        grid:set(self.ball.x, self.ball.y, true)
    end

    refresh()
    serve_position()
    return game
end

return {
    id = "pong",
    name = "PONG",
    hint = { "< > MOVE", "ENTER SERVE", "FIRST TO 7" },
    messages = { "YOU WIN", "CPU WINS" },
    order = "high",
    demo = DEMO,
    new = new,
}
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `lua dev/test/run.lua dev/test/test_pong.lua`
Expected: `9 tests, 0 failed`

- [ ] **Step 5: Add the game to the menu**

In `main.lua`, replace the `GAME_IDS` table (it currently ends with `"racer"`) with:

```lua
local GAME_IDS = {
    "tetris", "snake", "breakout", "invaders", "frogger",
    "racer", "pong",
}
```

- [ ] **Step 6: Run the whole suite and the smoke test for this game**

Run:
```bash
lua dev/test/run.lua
PICODECK_ROOT=../picodeck python3 dev/smoke.py --only pong --out <scratchpad>/p2-pong
```
Expected:
- The whole suite passes.
- `SMOKE OK (1 games)`, with `pong-hint`, `pong-gameplay` and `pong-game-over` screenshots; its FINISH steps lose it.
- Look at the gameplay screenshot: it should match the spec's section 3 row for this game.

- [ ] **Step 7: Commit**

```bash
git add games/pong.lua dev/test/test_pong.lua main.lua
git commit -m "pong: port to the grid game contract"
```

---

### Task 8: Game 08, Copter (vertical tunnel)

Steer through a tunnel that scrolls down at you.

**Files:**
- Create: `dev/test/test_copter.lua`
- Rewrite: `games/copter.lua`
- Modify: `main.lua` (`GAME_IDS`)

**Interfaces:**
- Consumes: the game contract and the Task 1 test helpers.
- Produces:
  - The module `games/copter.lua`, with `id = "copter"`.
  - Game fields the tests use: `rows` ({left,right,block}), `x`, `gen_left`/`gen_width`, `next_step`, `game:scroll()`.

- [ ] **Step 1: Write the failing tests**

Create `dev/test/test_copter.lua`:

```lua
need("dev/test/game_helpers.lua")
local copter = need("games/copter.lua")

local function new_game() return copter.new(game_ctx()) end

-- Free columns of a tunnel row, as a set.
local function free_cols(row)
    local free = {}
    for c = row.left + 1, 10 - row.right do
        if c ~= row.block then free[c] = true end
    end
    return free
end

local function longest_run(free)
    local best, run = 0, 0
    for c = 1, 10 do
        if free[c] then run = run + 1 best = math.max(best, run) else run = 0 end
    end
    return best
end

test("copter: meets the game contract", function()
    check_contract(copter, "copter", "COPTER")
end)

test("copter: starts in an open tunnel with the ship at column 5", function()
    local g = new_game()
    eq(#g.rows, 20, "tunnel rows"); eq(g.x, 5, "ship column"); eq(g.score, 0, "score")
end)

test("copter: the tunnel scrolls down one row per step and counts distance", function()
    local g = new_game()
    local top = g.rows[1]
    g:update(NONE, g.next_step)
    eq(g.rows[2], top, "old top row moved down"); eq(g.score, 1, "distance")
end)

test("copter: left and right steer, the ship stays on screen", function()
    local g = new_game()
    for _, row in ipairs(g.rows) do row.left, row.right, row.block = 0, 0, nil end
    g:update(pad({ repeated = { "left" } }), 1)
    eq(g.x, 4, "steered left")
    for _ = 1, 10 do g:update(pad({ repeated = { "left" } }), 1) end
    eq(g.x, 2, "stops at the edge")
end)

test("copter: steering into the wall ends the round", function()
    local g = new_game()
    for _, row in ipairs(g.rows) do row.left, row.right, row.block = 3, 3, nil end  -- gap 4-7
    g.x = 5
    eq(g:update(pad({ repeated = { "left" } }), 1), "over", "hit the wall")
end)

test("copter: the tunnel always leaves a way through", function()
    local g = new_game()
    for step = 1, 3000 do
        g.x = nil                               -- no ship: just generate tunnel
        g:scroll()
        local a, b = g.rows[1], g.rows[2]       -- new row and the one below it
        local fa, fb = free_cols(a), free_cols(b)
        truthy(longest_run(fa) >= 3, "3-wide opening at step " .. step)
        -- the nose (above) and the 3-wide body (below) must fit somewhere
        local ok = false
        for x = 2, 9 do
            if fa[x] and fb[x - 1] and fb[x] and fb[x + 1] then ok = true end
        end
        truthy(ok, "passable at step " .. step)
        if step % 60 == 0 then g.level = g.level + 1 end
    end
end)

test("copter: the gap narrows with level but never below 3", function()
    local g = new_game()
    g.level = 9
    for _ = 1, 200 do g.x = nil g:scroll() end
    local row = g.rows[1]
    eq(10 - row.left - row.right, 3, "narrowest gap")
end)

test("copter: every 60 rows of distance is a level", function()
    local g = new_game()
    g.score = 59
    for _, row in ipairs(g.rows) do row.left, row.right, row.block = 0, 0, nil end
    g.gen_left, g.gen_width = 0, 10
    g:update(NONE, g.next_step)
    eq(g.level, 2, "level 2")
end)

test("copter: draw shows walls and the .#./### ship", function()
    local g = new_game()
    local grid = draw_game(g)
    eq(grid:get(5, 18), true, "nose"); eq(grid:get(4, 18), false, "beside nose")
    eq(grid:get(4, 19), true, "body left"); eq(grid:get(6, 19), true, "body right")
    eq(grid:get(1, 1), true, "left wall")
end)
```

- [ ] **Step 2: Run them against the old game to see them fail**

Run: `lua dev/test/run.lua dev/test/test_copter.lua`
Expected: every test fails against the old BRICK-30 module, starting with `FAIL  copter: meets the game contract`. The last line is `9 tests, 9 failed`.

- [ ] **Step 3: Rewrite `games/copter.lua`**

Replace the whole file with:

```lua
-- copter.lua — game 08: steer through a tunnel that scrolls down at you.
-- Game contract: see lib/runner.lua. Needs the SFX global.

local COLS, ROWS = 10, 20
local SHIP = { ".#.", "###" }     -- nose on row 18, body on row 19
local SHIP_ROW = 18
local STEP_MS = 220               -- scroll speed at speed 1, level 1
local ROWS_PER_LEVEL = 60
local MIN_GAP = 3
local BLOCK_MIN_GAP = 6           -- blocks only appear in gaps this wide
local BLOCK_CHANCE = 0.12

local DEMO = {
    {
        "##.....###",
        "##.....###",
        "###.....##",
        "###..#..##",
        "###.....##",
        "####.....#",
        "###.....##",
        "###.....##",
        "##.....###",
        "##..#..###",
        "##.###.###",
        "##.....###",
    },
    {
        "##.....###",
        "##.....###",
        "##.....###",
        "###.....##",
        "###..#..##",
        "###.....##",
        "####.....#",
        "###.....##",
        "###.....##",
        "##.#...###",
        "######.###",
        "##.....###",
    },
}

local function new(ctx)
    local game = { score = 0, level = 1, x = 5, rows = {} }
    for r = 1, ROWS do game.rows[r] = { left = 1, right = 2 } end
    game.gen_left, game.gen_width = 1, 7             -- the gap of the newest row
    game.next_step = ctx.now + ctx.interval(STEP_MS, game.level)

    local function target_width()
        return math.max(MIN_GAP, 8 - game.level)
    end

    -- Next tunnel row: per row, EITHER the gap changes width by one OR it
    -- shifts by one, never both, so a 3-wide ship can always follow it.
    local function next_row()
        local left, width = game.gen_left, game.gen_width
        local want = target_width()
        if width ~= want then
            if width > want then
                width = width - 1
                if math.random(2) == 1 then left = left + 1 end
            else
                width = width + 1
                if left > 0 and math.random(2) == 1 then left = left - 1 end
            end
        else
            local shift = math.random(-1, 1)
            if left + shift >= 0 and left + shift + width <= COLS then left = left + shift end
        end
        left = math.max(0, math.min(COLS - width, left))
        game.gen_left, game.gen_width = left, width
        local row = { left = left, right = COLS - left - width }
        if width >= BLOCK_MIN_GAP and math.random() < BLOCK_CHANCE then
            -- one cell in from either wall, leaving a wide free run
            row.block = math.random(2) == 1 and left + 2 or left + width - 1
        end
        return row
    end

    function game:scroll()
        table.remove(self.rows)
        table.insert(self.rows, 1, next_row())
    end

    local function blocked(c, r)
        local row = game.rows[r]
        return c <= row.left or c > COLS - row.right or c == row.block
    end

    local function crashed()
        if blocked(game.x, SHIP_ROW) then return true end
        for c = game.x - 1, game.x + 1 do
            if blocked(c, SHIP_ROW + 1) then return true end
        end
        return false
    end

    function game:update(pad, now)
        if pad.repeated.left and self.x > 2 then self.x = self.x - 1 end
        if pad.repeated.right and self.x < COLS - 1 then self.x = self.x + 1 end
        if crashed() then return "over" end

        if now < self.next_step then return nil end
        self.next_step = now + ctx.interval(STEP_MS, self.level)
        self:scroll()
        self.score = self.score + 1
        self.level = self.score // ROWS_PER_LEVEL + 1
        if crashed() then return "over" end
        return nil
    end

    function game:draw(grid)
        for r, row in ipairs(self.rows) do
            for c = 1, row.left do grid:set(c, r, true) end
            for c = COLS - row.right + 1, COLS do grid:set(c, r, true) end
            if row.block then grid:set(row.block, r, true) end
        end
        grid:stamp(SHIP, self.x - 1, SHIP_ROW)
    end

    return game
end

return {
    id = "copter",
    name = "COPTER",
    hint = { "< > STEER" },
    order = "high",
    demo = DEMO,
    new = new,
}
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `lua dev/test/run.lua dev/test/test_copter.lua`
Expected: `9 tests, 0 failed`

- [ ] **Step 5: Add the game to the menu**

In `main.lua`, replace the `GAME_IDS` table (it currently ends with `"pong"`) with:

```lua
local GAME_IDS = {
    "tetris", "snake", "breakout", "invaders", "frogger",
    "racer", "pong", "copter",
}
```

- [ ] **Step 6: Run the whole suite and the smoke test for this game**

Run:
```bash
lua dev/test/run.lua
PICODECK_ROOT=../picodeck python3 dev/smoke.py --only copter --out <scratchpad>/p2-copter
```
Expected:
- The whole suite passes.
- `SMOKE OK (1 games)`, with `copter-hint`, `copter-gameplay` and `copter-game-over` screenshots; its FINISH steps lose it.
- Look at the gameplay screenshot: it should match the spec's section 3 row for this game.

- [ ] **Step 7: Commit**

```bash
git add games/copter.lua dev/test/test_copter.lua main.lua
git commit -m "copter: port to the grid game contract"
```

---

### Task 9: Game 09, Asteroids

Rotate, thrust and shoot the rocks apart.

**Files:**
- Create: `dev/test/test_asteroids.lua`
- Rewrite: `games/asteroids.lua`
- Modify: `main.lua` (`GAME_IDS`)

**Interfaces:**
- Consumes: the game contract and the Task 1 test helpers.
- Produces:
  - The module `games/asteroids.lua`, with `id = "asteroids"`.
  - Game fields the tests use: `x`/`y`/`vx`/`vy`/`dir`, `rocks` ({size,x,y,dx,dy}), `bullets`, `safe_until`, `next_tick`/`next_bullet`/`next_rock`.

- [ ] **Step 1: Write the failing tests**

Create `dev/test/test_asteroids.lua`:

```lua
need("dev/test/game_helpers.lua")
local asteroids = need("games/asteroids.lua")

local function new_game()
    local g = asteroids.new(game_ctx())
    g.rocks = {}                           -- tests place their own rocks
    g.next_rock = math.huge
    g.safe_until = 0                       -- no start-of-wave invulnerability
    return g
end

local function rock(size, x, y, dx, dy)
    return { size = size, x = x, y = y, dx = dx or 1, dy = dy or 0 }
end

test("asteroids: meets the game contract", function()
    check_contract(asteroids, "asteroids", "ASTEROIDS")
end)

test("asteroids: a wave starts with big rocks away from the ship, 3 lives", function()
    local g = asteroids.new(game_ctx())
    eq(g.lives, 3, "lives"); eq(g.dir, 1, "facing up")
    eq(#g.rocks, 3, "three big rocks")
    for _, r in ipairs(g.rocks) do eq(r.size, 3, "big") end
end)

test("asteroids: left and right rotate through 8 directions", function()
    local g = new_game()
    g:update(press("right"), 1)
    eq(g.dir, 2, "up-right")
    g:update(press("left"), 2); g:update(press("left"), 3)
    eq(g.dir, 8, "up-left")
end)

test("asteroids: thrust accelerates the ship the way it faces", function()
    local g = new_game()
    g.dir = 3                              -- right
    local x = g.x
    for t = 1, 10 do g:update(hold("up"), t * 50) end
    truthy(g.x > x, "moved right"); truthy(g.vx > 0, "velocity right")
end)

test("asteroids: the ship wraps around the edges", function()
    local g = new_game()
    g.x, g.vx = 10.9, 0.5
    g:update(NONE, g.next_tick)
    truthy(g.x < 2, "came back on the left: " .. g.x)
end)

test("asteroids: at most 3 bullets at once", function()
    local g = new_game()
    for t = 1, 5 do g:update(press("enter"), t) end
    eq(#g.bullets, 3, "bullets")
end)

test("asteroids: a bullet destroys a small rock and scores 100", function()
    local g = new_game()
    g.rocks = { rock(1, 5, 3), rock(1, 1, 18) }   -- the second keeps the wave going
    g.bullets = { { x = 5, y = 4, dx = 0, dy = -1, left = 5 } }
    g.next_bullet = 0
    g:update(NONE, 0)
    eq(#g.rocks, 1, "rock gone"); eq(g.score, 100, "score")
end)

test("asteroids: a big rock splits into two medium rocks", function()
    local g = new_game()
    g.rocks = { rock(3, 4, 2) }            -- cells rows 2-4
    g.bullets = { { x = 5, y = 5, dx = 0, dy = -1, left = 5 } }
    g.next_bullet = 0
    g:update(NONE, 0)
    eq(#g.rocks, 2, "split"); eq(g.rocks[1].size, 2, "medium"); eq(g.score, 20, "score")
    truthy(g.rocks[1].dx ~= g.rocks[2].dx or g.rocks[1].dy ~= g.rocks[2].dy, "fly apart")
end)

test("asteroids: a rock hitting the ship costs a life, then a safe respawn", function()
    local g = new_game()
    g.rocks = { rock(2, 5, 10, 0, 1), rock(1, 1, 18) }   -- second rock keeps the wave alive
    g:update(NONE, 1)
    eq(g.lives, 2, "hit")
    truthy(g.safe_until > 1, "invulnerable for a while")
    g:update(NONE, 2)
    eq(g.lives, 2, "no second hit while invulnerable")
end)

test("asteroids: losing the last life ends the round", function()
    local g = new_game()
    g.lives = 1
    g.rocks = { rock(2, 5, 10, 0, 1) }
    eq(g:update(NONE, 1), "over", "over")
end)

test("asteroids: clearing the rocks starts the next wave a level up", function()
    local g = new_game()
    g.rocks = { rock(1, 5, 3) }
    g.bullets = { { x = 5, y = 4, dx = 0, dy = -1, left = 5 } }
    g.next_bullet = 0
    g:update(NONE, 0)
    eq(g.level, 2, "level 2"); eq(#g.rocks, 4, "3 + 1 big rocks")
end)

test("asteroids: the ship blinks while it is invulnerable", function()
    local g = new_game()
    g.rocks = { rock(1, 1, 18) }
    g.safe_until = 1000
    g:update(NONE, 10)
    local grid = draw_game(g)
    eq(grid:get(5, 9), "blink", "nose blinks")
end)

test("asteroids: draw wraps rock cells across the edges", function()
    local g = new_game()
    g.rocks = { rock(2, 10, 20) }          -- cells (10,20) (1,20) (10,1) (1,1)
    g.x, g.y = 5.5, 10.5
    local grid = draw_game(g)
    eq(grid:get(1, 1), true, "wrapped corner"); eq(grid:get(10, 20), true, "own corner")
end)
```

- [ ] **Step 2: Run them against the old game to see them fail**

Run: `lua dev/test/run.lua dev/test/test_asteroids.lua`
Expected: every test fails against the old BRICK-30 module, starting with `FAIL  asteroids: meets the game contract`. The last line is `13 tests, 13 failed`.

- [ ] **Step 3: Rewrite `games/asteroids.lua`**

Replace the whole file with:

```lua
-- asteroids.lua — game 09: rotate, thrust and shoot the rocks apart.
-- Everything wraps around the grid edges.
-- Game contract: see lib/runner.lua. Needs the SFX global.

local COLS, ROWS = 10, 20
local TICK_MS = 50                -- ship physics tick
local ACCEL = 0.06                -- cells/tick added per tick of thrust
local MAX_SPEED = 0.5             -- cells/tick
local FRICTION = 0.96
local BULLET_MS = 45
local BULLET_RANGE = 10           -- cells a bullet flies
local MAX_BULLETS = 3
local ROCK_MS = 450               -- rock step at speed 1, level 1
local SAFE_MS = 2000              -- invulnerable after a respawn
local ROCK_SCORE = { [3] = 20, [2] = 50, [1] = 100 }

-- Directions clockwise from up; the ship pattern for each.
local DIRS = {
    { 0, -1, { ".#.", "###", "#.#" } },   -- up
    { 1, -1, { "..#", "##.", ".#." } },   -- up-right
    { 1, 0,  { "##.", ".##", "##." } },   -- right
    { 1, 1,  { ".#.", "##.", "..#" } },   -- down-right
    { 0, 1,  { "#.#", "###", ".#." } },   -- down
    { -1, 1, { ".#.", ".##", "#.." } },   -- down-left
    { -1, 0, { ".##", "##.", ".##" } },   -- left
    { -1, -1, { "#..", ".##", ".#." } },  -- up-left
}

local ROCK_SHAPES = {
    [3] = { "##.", "###", ".##" },
    [2] = { "##", "##" },
    [1] = { "#" },
}

-- Big rocks start in the corners and edges, away from the ship.
local SPAWNS = { { 1, 1 }, { 8, 1 }, { 1, 17 }, { 8, 17 }, { 4, 1 } }

local DEMO = {
    {
        "##........",
        "###.....##",
        ".##.....##",
        "..........",
        "....#.....",
        "..........",
        "....#.....",
        "...###....",
        "...#.#....",
        "..........",
        "......##..",
        "......###.",
    },
    {
        ".##.......",
        ".###....##",
        "..##....##",
        "....#.....",
        "..........",
        "..........",
        "....#.....",
        "...###....",
        "...#.#....",
        "..........",
        ".......##.",
        ".......###",
    },
}

local function wrap_c(c) return (c - 1) % COLS + 1 end
local function wrap_r(r) return (r - 1) % ROWS + 1 end

local function new(ctx)
    local game = { score = 0, level = 1, lives = 3, bullets = {}, rocks = {} }

    local function place_ship()
        game.x, game.y, game.vx, game.vy, game.dir = 5.5, 10.5, 0, 0, 1
    end

    local function new_wave()
        game.rocks = {}
        for i = 1, math.min(#SPAWNS, 2 + game.level) do
            local dx, dy
            repeat dx, dy = math.random(-1, 1), math.random(-1, 1) until dx ~= 0 or dy ~= 0
            game.rocks[i] = { size = 3, x = SPAWNS[i][1], y = SPAWNS[i][2], dx = dx, dy = dy }
        end
    end

    -- Cells (wrapped) of a pattern whose top-left is (x, y), as "c,r" keys.
    local function cells(pattern, x, y, out)
        out = out or {}
        for dy = 1, #pattern do
            for dx = 1, #pattern[dy] do
                if string.sub(pattern[dy], dx, dx) == "#" then
                    out[wrap_c(x + dx - 1) .. "," .. wrap_r(y + dy - 1)] = true
                end
            end
        end
        return out
    end

    local function ship_cells()
        return cells(DIRS[game.dir][3], math.floor(game.x) - 1, math.floor(game.y) - 1)
    end

    local function rock_cells(rock)
        return cells(ROCK_SHAPES[rock.size], rock.x, rock.y)
    end

    local function split(i)
        local rock = table.remove(game.rocks, i)
        game.score = game.score + ROCK_SCORE[rock.size]
        SFX.hit()
        if rock.size > 1 then
            -- the halves fly off at right angles to the parent
            local a = { size = rock.size - 1, x = rock.x, y = rock.y, dx = -rock.dy, dy = rock.dx }
            local b = { size = rock.size - 1, x = rock.x, y = rock.y, dx = rock.dy, dy = -rock.dx }
            table.insert(game.rocks, a)
            table.insert(game.rocks, b)
        end
    end

    -- Remove bullets that sit on a rock, splitting that rock.
    local function bullets_vs_rocks()
        local kept = {}
        for _, b in ipairs(game.bullets) do
            local hit = false
            for i, rock in ipairs(game.rocks) do
                if rock_cells(rock)[b.x .. "," .. b.y] then split(i) hit = true break end
            end
            if not hit then kept[#kept + 1] = b end
        end
        game.bullets = kept
    end

    local function ship_hit(now)
        if now < game.safe_until then return nil end
        local mine = ship_cells()
        for _, rock in ipairs(game.rocks) do
            for key in pairs(rock_cells(rock)) do
                if mine[key] then
                    game.lives = game.lives - 1
                    SFX.over()
                    if game.lives <= 0 then return "over" end
                    place_ship()
                    game.safe_until = now + SAFE_MS
                    return nil
                end
            end
        end
        return nil
    end

    function game:update(pad, now)
        self.now = now
        if pad.repeated.left then self.dir = (self.dir - 2) % 8 + 1 end
        if pad.repeated.right then self.dir = self.dir % 8 + 1 end
        if (pad.pressed.enter or pad.pressed.f1) and #self.bullets < MAX_BULLETS then
            local d = DIRS[self.dir]
            self.bullets[#self.bullets + 1] = {
                x = wrap_c(math.floor(self.x) + d[1]), y = wrap_r(math.floor(self.y) + d[2]),
                dx = d[1], dy = d[2], left = BULLET_RANGE }
            SFX.move()
        end

        if now >= self.next_tick then
            self.next_tick = now + TICK_MS
            if pad.held.up then
                local d = DIRS[self.dir]
                self.vx, self.vy = self.vx + d[1] * ACCEL, self.vy + d[2] * ACCEL
            end
            local speed = math.sqrt(self.vx * self.vx + self.vy * self.vy)
            if speed > MAX_SPEED then
                self.vx, self.vy = self.vx * MAX_SPEED / speed, self.vy * MAX_SPEED / speed
            end
            self.vx, self.vy = self.vx * FRICTION, self.vy * FRICTION
            self.x = (self.x + self.vx - 1) % COLS + 1
            self.y = (self.y + self.vy - 1) % ROWS + 1
        end

        if now >= self.next_bullet then
            self.next_bullet = now + BULLET_MS
            local kept = {}
            for _, b in ipairs(self.bullets) do
                b.x, b.y, b.left = wrap_c(b.x + b.dx), wrap_r(b.y + b.dy), b.left - 1
                if b.left > 0 then kept[#kept + 1] = b end
            end
            self.bullets = kept
        end
        bullets_vs_rocks()

        if now >= self.next_rock then
            self.next_rock = now + ctx.interval(ROCK_MS, self.level)
            for _, rock in ipairs(self.rocks) do
                rock.x, rock.y = wrap_c(rock.x + rock.dx), wrap_r(rock.y + rock.dy)
            end
            bullets_vs_rocks()
        end

        if #self.rocks == 0 then
            self.level = self.level + 1
            SFX.levelup()
            new_wave()
            self.safe_until = now + SAFE_MS
            return nil
        end
        return ship_hit(now)
    end

    function game:draw(grid)
        for _, rock in ipairs(self.rocks) do
            for key in pairs(rock_cells(rock)) do
                local c, r = key:match("(%d+),(%d+)")
                grid:set(tonumber(c), tonumber(r), true)
            end
        end
        for _, b in ipairs(self.bullets) do grid:set(b.x, b.y, true) end
        local v = (self.now and self.now < self.safe_until) and "blink" or true
        for key in pairs(ship_cells()) do
            local c, r = key:match("(%d+),(%d+)")
            grid:set(tonumber(c), tonumber(r), v)
        end
    end

    place_ship()
    new_wave()
    game.safe_until = ctx.now + SAFE_MS
    game.next_tick = ctx.now + TICK_MS
    game.next_bullet = ctx.now + BULLET_MS
    game.next_rock = ctx.now + ctx.interval(ROCK_MS, game.level)
    return game
end

return {
    id = "asteroids",
    name = "ASTEROIDS",
    hint = { "< > TURN", "UP THRUST", "ENTER FIRE" },
    order = "high",
    demo = DEMO,
    new = new,
}
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `lua dev/test/run.lua dev/test/test_asteroids.lua`
Expected: `13 tests, 0 failed`

- [ ] **Step 5: Add the game to the menu**

In `main.lua`, replace the `GAME_IDS` table (it currently ends with `"copter"`) with:

```lua
local GAME_IDS = {
    "tetris", "snake", "breakout", "invaders", "frogger",
    "racer", "pong", "copter", "asteroids",
}
```

- [ ] **Step 6: Run the whole suite and the smoke test for this game**

Run:
```bash
lua dev/test/run.lua
PICODECK_ROOT=../picodeck python3 dev/smoke.py --only asteroids --out <scratchpad>/p2-asteroids
```
Expected:
- The whole suite passes.
- `SMOKE OK (1 games)`, with `asteroids-hint`, `asteroids-gameplay` and `asteroids-game-over` screenshots; its FINISH steps lose it.
- Look at the gameplay screenshot: it should match the spec's section 3 row for this game.

- [ ] **Step 7: Commit**

```bash
git add games/asteroids.lua dev/test/test_asteroids.lua main.lua
git commit -m "asteroids: port to the grid game contract"
```

---

### Task 10: Game 10, Memory

Find the 9 pairs in as few turns as possible.

**Files:**
- Create: `dev/test/test_memory.lua`
- Rewrite: `games/memory.lua`
- Modify: `main.lua` (`GAME_IDS`)

**Interfaces:**
- Consumes: the game contract and the Task 1 test helpers.
- Produces:
  - The module `games/memory.lua`, with `id = "memory"`.
  - Game fields the tests use: `cards` ({sym,up,done}), `cursor`, `first`, `showing`; module field `FACES`.

- [ ] **Step 1: Write the failing tests**

Create `dev/test/test_memory.lua`:

```lua
need("dev/test/game_helpers.lua")
local memory = need("games/memory.lua")

local function new_game() return memory.new(game_ctx()) end

-- Index of another card with the same symbol as card i (or a different one).
local function partner(g, i, same)
    for j, card in ipairs(g.cards) do
        if j ~= i and (card.sym == g.cards[i].sym) == same and not card.done then return j end
    end
end

local function flip_at(g, i, now)
    g.cursor = i
    return g:update(press("enter"), now)
end

test("memory: meets the game contract", function()
    check_contract(memory, "memory", "MEMORY")
    eq(memory.order, "low", "fewer turns is better")
end)

test("memory: 18 face-down cards, 9 symbols in pairs", function()
    local g = new_game()
    eq(#g.cards, 18, "cards")
    local count = {}
    for _, card in ipairs(g.cards) do
        eq(card.up, false, "face down")
        count[card.sym] = (count[card.sym] or 0) + 1
    end
    for sym = 1, 9 do eq(count[sym], 2, "pair of " .. sym) end
end)

test("memory: the 9 face patterns are distinct, 1-3 bricks of a 2x2", function()
    local seen = {}
    for _, p in ipairs(memory.FACES) do
        local key = table.concat(p, "|")
        truthy(not seen[key], "distinct " .. key); seen[key] = true
        local n = select(2, key:gsub("#", ""))
        truthy(n >= 1 and n <= 3, "1-3 bricks " .. key)
    end
end)

test("memory: the cursor moves across the 3x6 layout and stops at the edges", function()
    local g = new_game()
    eq(g.cursor, 1, "top-left")
    g:update(pad({ repeated = { "right" } }), 1)
    eq(g.cursor, 2, "right")
    g:update(pad({ repeated = { "down" } }), 2)
    eq(g.cursor, 5, "down a row")
    g.cursor = 3
    g:update(pad({ repeated = { "right" } }), 3)
    eq(g.cursor, 3, "right edge")
end)

test("memory: a mismatched pair costs a turn and turns back over", function()
    local g = new_game()
    local j = partner(g, 1, false)
    flip_at(g, 1, 0)
    flip_at(g, j, 10)
    eq(g.score, 1, "one turn")
    eq(g.cards[1].up, true, "still showing")
    g:update(NONE, 10 + 900)
    eq(g.cards[1].up, false, "face down again"); eq(g.cards[j].up, false, "face down again")
end)

test("memory: a matched pair is removed", function()
    local g = new_game()
    local j = partner(g, 1, true)
    flip_at(g, 1, 0)
    flip_at(g, j, 10)
    g:update(NONE, 10 + 400)
    eq(g.cards[1].done, true, "matched"); eq(g.cards[j].done, true, "matched")
end)

test("memory: no third card while a pair is showing", function()
    local g = new_game()
    local j = partner(g, 1, false)
    local k = partner(g, j, false)
    flip_at(g, 1, 0); flip_at(g, j, 10)
    flip_at(g, k ~= 1 and k or 18, 20)
    local up = 0
    for _, card in ipairs(g.cards) do if card.up then up = up + 1 end end
    eq(up, 2, "only the pair")
end)

test("memory: finding every pair ends the round with CLEARED", function()
    local g = new_game()
    for _, card in ipairs(g.cards) do card.done = true end
    local a, b
    for i, card in ipairs(g.cards) do
        if card.sym == 1 then card.done = false if a then b = i else a = i end end
    end
    flip_at(g, a, 0); flip_at(g, b, 10)
    eq(g:update(NONE, 10 + 400), "over", "over")
    eq(g.status[1], "CLEARED", "result"); check_status(memory, g)
end)

test("memory: face-down cards are solid 2x2 blocks, the cursor card blinks", function()
    local g = new_game()
    local grid = draw_game(g)
    eq(grid:get(2, 2), "blink", "cursor card (col 2-3, row 2-3)")
    eq(grid:get(5, 2), true, "second card solid"); eq(grid:get(6, 3), true, "second card solid")
    eq(grid:get(4, 2), false, "gap between cards")
end)
```

- [ ] **Step 2: Run them against the old game to see them fail**

Run: `lua dev/test/run.lua dev/test/test_memory.lua`
Expected: every test fails against the old BRICK-30 module, starting with `FAIL  memory: meets the game contract`. The last line is `9 tests, 9 failed`.

- [ ] **Step 3: Rewrite `games/memory.lua`**

Replace the whole file with:

```lua
-- memory.lua — game 10: find the 9 pairs in as few turns as possible.
-- 18 cards (3 across, 6 down) of 2x2 bricks; face down they are solid.
-- Game contract: see lib/runner.lua. Needs the SFX global.

local CARD_COLS, CARD_ROWS = 3, 6
local CARD_X = { 2, 5, 8 }        -- left column of each card column
local SHOW_MISS_MS = 900          -- a mismatched pair stays up this long
local SHOW_MATCH_MS = 400         -- a matched pair shows this long, then goes

-- The 9 faces: every 2-brick pattern of a 2x2 plus three 3-brick ones.
local FACES = {
    { "##", ".." }, { "..", "##" }, { "#.", "#." }, { ".#", ".#" },
    { "#.", ".#" }, { ".#", "#." },
    { "##", "#." }, { "##", ".#" }, { "#.", "##" },
}

local DEMO = {
    {
        ".##.##.##.",
        ".##.##.##.",
        "..........",
        ".##.#..##.",
        ".##..#.##.",
        "..........",
        ".##.##.##.",
        ".##.##.##.",
        "..........",
        ".##.##.##.",
        ".##.##.##.",
        "..........",
    },
    {
        ".##.##.##.",
        ".##.##.##.",
        "..........",
        ".##.#..##.",
        ".##..#.##.",
        "..........",
        ".##.##.#..",
        ".##.##..#.",
        "..........",
        ".##.##.##.",
        ".##.##.##.",
        "..........",
    },
}

local function card_pos(i)
    local col = (i - 1) % CARD_COLS + 1
    local row = (i - 1) // CARD_COLS + 1
    return CARD_X[col], 2 + (row - 1) * 3
end

local function new(ctx)
    local game = { score = 0, cursor = 1, cards = {} }

    local syms = {}
    for s = 1, #FACES do syms[#syms + 1] = s syms[#syms + 1] = s end
    for i = #syms, 2, -1 do                           -- shuffle
        local j = math.random(i)
        syms[i], syms[j] = syms[j], syms[i]
    end
    for i, s in ipairs(syms) do game.cards[i] = { sym = s, up = false, done = false } end

    local function all_done()
        for _, card in ipairs(game.cards) do if not card.done then return false end end
        return true
    end

    function game:update(pad, now)
        -- a pair on show: wait, then remove it or turn it back over
        if self.showing then
            if now < self.showing.until_ms then return nil end
            local a, b = self.cards[self.showing[1]], self.cards[self.showing[2]]
            if a.sym == b.sym then a.done, b.done = true, true
            else a.up, b.up = false, false end
            self.showing = nil
            if all_done() then
                self.status = { "CLEARED" }
                return "over"
            end
            return nil
        end

        local c = (self.cursor - 1) % CARD_COLS
        if pad.repeated.left and c > 0 then self.cursor = self.cursor - 1 end
        if pad.repeated.right and c < CARD_COLS - 1 then self.cursor = self.cursor + 1 end
        if pad.repeated.up and self.cursor > CARD_COLS then self.cursor = self.cursor - CARD_COLS end
        if pad.repeated.down and self.cursor <= CARD_COLS * (CARD_ROWS - 1) then
            self.cursor = self.cursor + CARD_COLS
        end

        local card = self.cards[self.cursor]
        if (pad.pressed.enter or pad.pressed.f1) and not card.done and not card.up then
            card.up = true
            SFX.select()
            if self.first then
                self.score = self.score + 1                    -- one turn = two cards
                local match = self.cards[self.first].sym == card.sym
                self.showing = { self.first, self.cursor,
                                 until_ms = now + (match and SHOW_MATCH_MS or SHOW_MISS_MS) }
                if match then SFX.score() else SFX.hit() end
                self.first = nil
            else
                self.first = self.cursor
            end
        end
        return nil
    end

    function game:draw(grid)
        for i, card in ipairs(self.cards) do
            if not card.done then
                local x, y = card_pos(i)
                local v = (i == self.cursor) and "blink" or true
                if card.up then grid:stamp(FACES[card.sym], x, y, v)
                else grid:stamp({ "##", "##" }, x, y, v) end
            end
        end
        -- the cursor on an empty slot still shows where it is
        if self.cards[self.cursor].done then
            local x, y = card_pos(self.cursor)
            grid:set(x, y, "blink")
        end
    end

    return game
end

return {
    id = "memory",
    name = "MEMORY",
    hint = { "D-PAD MOVE", "ENTER FLIP", "FEWEST TURNS WIN" },
    messages = { "CLEARED" },
    order = "low",
    demo = DEMO,
    new = new,
    FACES = FACES,
}
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `lua dev/test/run.lua dev/test/test_memory.lua`
Expected: `9 tests, 0 failed`

- [ ] **Step 5: Add the game to the menu**

In `main.lua`, replace the `GAME_IDS` table (it currently ends with `"asteroids"`) with:

```lua
local GAME_IDS = {
    "tetris", "snake", "breakout", "invaders", "frogger",
    "racer", "pong", "copter", "asteroids", "memory",
}
```

- [ ] **Step 6: Run the whole suite and the smoke test for this game**

Run:
```bash
lua dev/test/run.lua
PICODECK_ROOT=../picodeck python3 dev/smoke.py --only memory --out <scratchpad>/p2-memory
```
Expected:
- The whole suite passes.
- `SMOKE OK (1 games)`, with `memory-hint`, `memory-gameplay` and `memory-game-over` screenshots; the solver in `dev/smoke.py` wins it.
- Look at the gameplay screenshot: it should match the spec's section 3 row for this game.

- [ ] **Step 7: Commit**

```bash
git add games/memory.lua dev/test/test_memory.lua main.lua
git commit -m "memory: port to the grid game contract"
```

---

### Task 11: Game 11, Simon

Watch the pads light up, then repeat the sequence.

**Files:**
- Create: `dev/test/test_simon.lua`
- Rewrite: `games/simon.lua`
- Modify: `main.lua` (`GAME_IDS`)

**Interfaces:**
- Consumes: the game contract and the Task 1 test helpers.
- Produces:
  - The module `games/simon.lua`, with `id = "simon"`.
  - Game fields the tests use: `seq`, `state` (intro|show|input|pause), `lit`, `input_i`, `last_input`; module field `PADS`.

- [ ] **Step 1: Write the failing tests**

Create `dev/test/test_simon.lua`:

```lua
need("dev/test/game_helpers.lua")
local simon = need("games/simon.lua")

local function new_game() return simon.new(game_ctx()) end

-- Advance time until the game is waiting for input.
local function until_input(g, now)
    for _ = 1, 200 do
        if g.state == "input" then return now end
        now = now + 50
        g:update(NONE, now)
    end
    error("never reached input")
end

test("simon: meets the game contract", function()
    check_contract(simon, "simon", "SIMON")
end)

test("simon: shows the hint first, then WATCH, then YOUR TURN", function()
    local g = new_game()
    eq(g.status, nil, "hint shows during the intro")
    eq(#g.seq, 1, "one pad to remember")
    local now = 0
    repeat now = now + 50 g:update(NONE, now) until g.state == "show"
    eq(g.status[1], "WATCH", "watching"); check_status(simon, g)
    until_input(g, now)
    eq(g.status[1], "YOUR TURN", "your turn"); check_status(simon, g)
end)

test("simon: presses are ignored while the sequence plays", function()
    local g = new_game()
    local now = 0
    repeat now = now + 50 g:update(NONE, now) until g.state == "show"
    local wrong = g.seq[1] == "up" and "down" or "up"
    eq(g:update(press(wrong), now + 1), nil, "not a mistake")
    eq(g.state, "show", "still showing")
end)

test("simon: repeating the sequence scores it and adds a pad", function()
    local g = new_game()
    local now = until_input(g, 0)
    g:update(press(g.seq[1]), now + 10)
    eq(g.score, 1, "scored")
    for _ = 1, 40 do now = now + 50 g:update(NONE, now) end
    eq(#g.seq, 2, "sequence grew")
end)

test("simon: a wrong pad ends the round with WRONG", function()
    local g = new_game()
    local now = until_input(g, 0)
    local wrong = g.seq[1] == "up" and "down" or "up"
    eq(g:update(press(wrong), now + 10), "over", "over")
    eq(g.status[1], "WRONG", "headline"); check_status(simon, g)
end)

test("simon: waiting too long ends the round with TOO SLOW", function()
    local g = new_game()
    local now = until_input(g, 0)
    eq(g:update(NONE, now + 4001), "over", "over")
    eq(g.status[1], "TOO SLOW", "headline"); check_status(simon, g)
end)

test("simon: the four pads sit in a plus that matches the d-pad", function()
    eq(simon.PADS.up.x, 4); eq(simon.PADS.up.y, 3)
    eq(simon.PADS.left.x, 1); eq(simon.PADS.left.y, 9)
    eq(simon.PADS.right.x, 7); eq(simon.PADS.right.y, 9)
    eq(simon.PADS.down.x, 4); eq(simon.PADS.down.y, 15)
end)

test("simon: unlit pads are outlines, a lit pad is filled", function()
    local g = new_game()
    local grid = draw_game(g)
    eq(grid:get(4, 3), true, "outline corner"); eq(grid:get(5, 4), false, "hollow middle")
    eq(count_lit(grid), 4 * 12, "four outlines")
    g.lit = "up"
    grid = draw_game(g)
    eq(grid:get(5, 4), true, "filled when lit")
end)
```

- [ ] **Step 2: Run them against the old game to see them fail**

Run: `lua dev/test/run.lua dev/test/test_simon.lua`
Expected: every test fails against the old BRICK-30 module, starting with `FAIL  simon: meets the game contract`. The last line is `8 tests, 8 failed`.

- [ ] **Step 3: Rewrite `games/simon.lua`**

Replace the whole file with:

```lua
-- simon.lua — game 11: watch the pads light up, then repeat the sequence.
-- The four pads form a plus that matches the d-pad.
-- Game contract: see lib/runner.lua. Needs the SFX global.

local INTRO_MS = 2000             -- the hint shows before the first sequence
local ON_MS = 450                 -- each pad lights this long at speed 1
local GAP_MS = 200
local PRESS_MS = 250              -- a pressed pad stays lit this long
local ROUND_PAUSE_MS = 700
local TIMEOUT_MS = 4000           -- no press for this long ends the round

local PADS = {
    up    = { x = 4, y = 3,  tone = 440 },
    left  = { x = 1, y = 9,  tone = 220 },
    right = { x = 7, y = 9,  tone = 330 },
    down  = { x = 4, y = 15, tone = 262 },
}
local NAMES = { "up", "left", "right", "down" }
local OUTLINE = { "####", "#..#", "#..#", "####" }
local FILLED = { "####", "####", "####", "####" }

local DEMO = {
    {
        "...####...",
        "...####...",
        "...####...",
        "...####...",
        "..........",
        "..........",
        "####..####",
        "#..#..#..#",
        "#..#..#..#",
        "####..####",
        "..........",
        "..........",
    },
    {
        "...####...",
        "...#..#...",
        "...#..#...",
        "...####...",
        "..........",
        "..........",
        "####..####",
        "#..#..####",
        "#..#..####",
        "####..####",
        "..........",
        "..........",
    },
}

local function new(ctx)
    local game = { score = 0, seq = {}, state = "intro" }

    local function add_pad() game.seq[#game.seq + 1] = NAMES[math.random(#NAMES)] end

    local function light(name, now, ms)
        game.lit, game.lit_until = name, now + ms
        SFX.tone(PADS[name].tone, ms)
    end

    local function start_show(now)
        game.state = "show"
        game.status = { "WATCH" }
        game.show_i = 0
        game.next_show = now
    end

    function game:update(pad, now)
        if self.lit and now >= self.lit_until then self.lit = nil end

        if self.state == "intro" or self.state == "pause" then
            if now >= self.wait_until then start_show(now) end
            return nil
        end

        if self.state == "show" then
            if now < self.next_show then return nil end
            self.show_i = self.show_i + 1
            if self.show_i > #self.seq then
                self.state = "input"
                self.status = { "YOUR TURN" }
                self.input_i = 1
                self.last_input = now
                return nil
            end
            local on = ctx.interval(ON_MS, 1)
            light(self.seq[self.show_i], now, on)
            self.next_show = now + on + GAP_MS
            return nil
        end

        -- input
        for _, name in ipairs(NAMES) do
            if pad.pressed[name] then
                self.last_input = now
                light(name, now, PRESS_MS)
                if name ~= self.seq[self.input_i] then
                    self.status = { "WRONG" }
                    return "over"
                end
                self.input_i = self.input_i + 1
                if self.input_i > #self.seq then
                    self.score = #self.seq
                    add_pad()
                    self.state = "pause"
                    self.status = nil
                    self.wait_until = now + ROUND_PAUSE_MS
                end
                return nil
            end
        end
        if now - self.last_input > TIMEOUT_MS then
            self.status = { "TOO SLOW" }
            return "over"
        end
        return nil
    end

    function game:draw(grid)
        for name, p in pairs(PADS) do
            grid:stamp(name == self.lit and FILLED or OUTLINE, p.x, p.y)
        end
    end

    add_pad()
    game.wait_until = ctx.now + INTRO_MS
    return game
end

return {
    id = "simon",
    name = "SIMON",
    hint = { "WATCH THE PADS", "THEN REPEAT", "WITH THE D-PAD" },
    messages = { "WATCH", "YOUR TURN", "WRONG", "TOO SLOW" },
    order = "high",
    demo = DEMO,
    new = new,
    PADS = PADS,
}
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `lua dev/test/run.lua dev/test/test_simon.lua`
Expected: `8 tests, 0 failed`

- [ ] **Step 5: Add the game to the menu**

In `main.lua`, replace the `GAME_IDS` table (it currently ends with `"memory"`) with:

```lua
local GAME_IDS = {
    "tetris", "snake", "breakout", "invaders", "frogger",
    "racer", "pong", "copter", "asteroids", "memory",
    "simon",
}
```

- [ ] **Step 6: Run the whole suite and the smoke test for this game**

Run:
```bash
lua dev/test/run.lua
PICODECK_ROOT=../picodeck python3 dev/smoke.py --only simon --out <scratchpad>/p2-simon
```
Expected:
- The whole suite passes.
- `SMOKE OK (1 games)`, with `simon-hint`, `simon-gameplay` and `simon-game-over` screenshots; its FINISH steps lose it.
- Look at the gameplay screenshot: it should match the spec's section 3 row for this game.

- [ ] **Step 7: Commit**

```bash
git add games/simon.lua dev/test/test_simon.lua main.lua
git commit -m "simon: port to the grid game contract"
```

---

### Task 12: Game 12, Tic-tac-toe

X against the CPU's O. Wins build a streak;

**Files:**
- Create: `dev/test/test_tictactoe.lua`
- Rewrite: `games/tictactoe.lua`
- Modify: `main.lua` (`GAME_IDS`)

**Interfaces:**
- Consumes: the game contract and the Task 1 test helpers.
- Produces:
  - The module `games/tictactoe.lua`, with `id = "tictactoe"`.
  - Game fields the tests use: `board[1..9]` (" "|"X"|"O"), `cursor`, `cpu_at`, `result_until`, `win_line`, `mistake`, `lost`; module field `cpu_move(board, mistake)`.

- [ ] **Step 1: Write the failing tests**

Create `dev/test/test_tictactoe.lua`:

```lua
need("dev/test/game_helpers.lua")
local ttt = need("games/tictactoe.lua")

local function new_game()
    local g = ttt.new(game_ctx())
    g.mistake = 0                          -- the CPU always plays its best move
    return g
end

local function board(g, s)                 -- s: 9 chars of "X", "O" or "."
    for i = 1, 9 do
        local ch = s:sub(i, i)
        g.board[i] = ch == "." and " " or ch
    end
end

local function place(g, i, now)
    g.cursor = i
    return g:update(press("enter"), now)
end

test("tictactoe: meets the game contract", function()
    check_contract(ttt, "tictactoe", "TIC-TAC-TOE")
end)

test("tictactoe: empty board, cursor in the centre, streak 0", function()
    local g = new_game()
    eq(g.cursor, 5, "centre"); eq(g.score, 0, "streak")
    for i = 1, 9 do eq(g.board[i], " ", "empty") end
end)

test("tictactoe: the cursor moves within the 3x3 board", function()
    local g = new_game()
    g:update(pad({ repeated = { "up" } }), 1)
    eq(g.cursor, 2, "up"); g:update(pad({ repeated = { "up" } }), 2)
    eq(g.cursor, 2, "top edge"); g:update(pad({ repeated = { "left" } }), 3)
    eq(g.cursor, 1, "left")
end)

test("tictactoe: you place X, the CPU answers after a moment", function()
    local g = new_game()
    place(g, 1, 0)
    eq(g.board[1], "X", "placed")
    g:update(NONE, 399)
    local o = 0 for i = 1, 9 do if g.board[i] == "O" then o = o + 1 end end
    eq(o, 0, "CPU still thinking")
    g:update(NONE, 400)
    o = 0 for i = 1, 9 do if g.board[i] == "O" then o = o + 1 end end
    eq(o, 1, "CPU moved")
end)

test("tictactoe: you can't play on a taken cell", function()
    local g = new_game()
    board(g, "O........")
    place(g, 1, 0)
    eq(g.board[1], "O", "unchanged"); eq(g.cpu_at, nil, "no CPU turn")
end)

test("tictactoe: the CPU takes a winning move", function()
    local g = new_game()
    board(g, "OO.XX....")
    eq(ttt.cpu_move(g.board, 0), 3, "completes its row")
end)

test("tictactoe: the CPU blocks your winning move", function()
    local g = new_game()
    board(g, "XX..O....")
    eq(ttt.cpu_move(g.board, 0), 3, "blocks")
end)

test("tictactoe: a win adds to the streak and deals a new board", function()
    local g = new_game()
    board(g, "XX.OO....")
    place(g, 3, 0)
    eq(g.score, 1, "streak"); eq(g.status[1], "YOU WIN", "result"); check_status(ttt, g)
    g:update(NONE, 1200)
    eq(g.board[1], " ", "new board"); eq(g.status, nil, "result cleared")
end)

test("tictactoe: a draw keeps the streak", function()
    local g = new_game()
    g.score = 2
    board(g, "XOXXOOOX.")
    place(g, 9, 0)
    eq(g.status[1], "DRAW", "result"); eq(g.score, 2, "streak kept")
end)

test("tictactoe: a CPU win ends the round", function()
    local g = new_game()
    board(g, "OO.XX...X")
    place(g, 7, 0)                         -- a wasted move; the CPU completes 1-2-3
    g:update(NONE, 400)
    eq(g.status[1], "CPU WINS", "result"); check_status(ttt, g)
    eq(g:update(NONE, 400 + 1200), "over", "over")
end)

test("tictactoe: X and O are drawn as 3x3 marks in their cells", function()
    local g = new_game()
    board(g, "X.......O")
    g.cursor = 5
    local grid = draw_game(g)
    eq(grid:get(1, 6), true, "X corner"); eq(grid:get(2, 6), false, "X gap"); eq(grid:get(2, 7), true, "X centre")
    eq(grid:get(8, 13), false, "O hollow"); eq(grid:get(7, 12), true, "O ring")
    eq(grid:get(5, 10), "blink", "cursor on the empty centre cell")
end)
```

- [ ] **Step 2: Run them against the old game to see them fail**

Run: `lua dev/test/run.lua dev/test/test_tictactoe.lua`
Expected: every test fails against the old BRICK-30 module, starting with `FAIL  tictactoe: meets the game contract`. The last line is `11 tests, 11 failed`.

- [ ] **Step 3: Rewrite `games/tictactoe.lua`**

Replace the whole file with:

```lua
-- tictactoe.lua — game 12: X against the CPU's O. Wins build a streak;
-- a loss ends the round. The board is 3x3 cells of 3x3 bricks.
-- Game contract: see lib/runner.lua. Needs the SFX global.

local BOARD_X, BOARD_Y = 1, 6     -- top-left brick of cell 1
local CPU_MS = 400                -- the CPU "thinks" this long
local RESULT_MS = 1200            -- a finished board shows this long
local X_MARK = { "#.#", ".#.", "#.#" }
local O_MARK = { "###", "#.#", "###" }
local LINES = {
    { 1, 2, 3 }, { 4, 5, 6 }, { 7, 8, 9 },
    { 1, 4, 7 }, { 2, 5, 8 }, { 3, 6, 9 },
    { 1, 5, 9 }, { 3, 5, 7 },
}

local DEMO = {
    {
        "..........",
        "..........",
        "#.####.#..",
        ".##.#..#..",
        "#.####.#..",
        "..........",
        "..........",
        "...#.#....",
        "....#.....",
        "...#.#....",
        "..........",
        "..........",
    },
    {
        "..........",
        "..........",
        "#.####.#..",
        ".##.#..#..",
        "#.####.#..",
        "...###....",
        "...#.#....",
        "...####.#.",
        "....#..#..",
        "...#.##.#.",
        "..........",
        "..........",
    },
}

local function winner(board)
    for _, l in ipairs(LINES) do
        local a = board[l[1]]
        if a ~= " " and a == board[l[2]] and a == board[l[3]] then return a, l end
    end
    return nil
end

local function full(board)
    for i = 1, 9 do if board[i] == " " then return false end end
    return true
end

-- The CPU's move: win, block, centre, a corner, a side; with chance
-- `mistake` it plays a random free cell instead.
local function cpu_move(board, mistake)
    local free = {}
    for i = 1, 9 do if board[i] == " " then free[#free + 1] = i end end
    if math.random() < mistake then return free[math.random(#free)] end
    for _, mark in ipairs({ "O", "X" }) do
        for _, i in ipairs(free) do
            board[i] = mark
            local w = winner(board)
            board[i] = " "
            if w then return i end
        end
    end
    for _, i in ipairs({ 5, 1, 3, 7, 9, 2, 4, 6, 8 }) do
        if board[i] == " " then return i end
    end
end

local function new(ctx)
    local game = { score = 0, cursor = 5, board = {} }
    game.mistake = math.max(0, 0.35 - 0.04 * (ctx.speed - 1))

    local function clear_board()
        for i = 1, 9 do game.board[i] = " " end
        game.win_line, game.status, game.result_until, game.cpu_at = nil, nil, nil, nil
    end

    -- After a move: a finished board shows its result for a moment.
    local function settle(now)
        local w, line = winner(game.board)
        if w == "X" then
            game.score = game.score + 1
            game.status, game.win_line = { "YOU WIN" }, line
            SFX.score()
        elseif w == "O" then
            game.status, game.win_line = { "CPU WINS" }, line
            game.lost = true
            SFX.over()
        elseif full(game.board) then
            game.status = { "DRAW" }
            SFX.select()
        else
            return false
        end
        game.result_until = now + RESULT_MS
        return true
    end

    function game:update(pad, now)
        if self.result_until then
            if now < self.result_until then return nil end
            if self.lost then return "over" end
            clear_board()
            return nil
        end
        if self.cpu_at then
            if now < self.cpu_at then return nil end
            self.cpu_at = nil
            self.board[cpu_move(self.board, self.mistake)] = "O"
            SFX.move()
            settle(now)
            return nil
        end

        local r, c = (self.cursor - 1) // 3, (self.cursor - 1) % 3
        if pad.repeated.up and r > 0 then self.cursor = self.cursor - 3 end
        if pad.repeated.down and r < 2 then self.cursor = self.cursor + 3 end
        if pad.repeated.left and c > 0 then self.cursor = self.cursor - 1 end
        if pad.repeated.right and c < 2 then self.cursor = self.cursor + 1 end
        if (pad.pressed.enter or pad.pressed.f1) and self.board[self.cursor] == " " then
            self.board[self.cursor] = "X"
            SFX.select()
            if not settle(now) then self.cpu_at = now + CPU_MS end
        end
        return nil
    end

    function game:draw(grid)
        local blink = {}
        for _, i in ipairs(self.win_line or {}) do blink[i] = true end
        for i = 1, 9 do
            local x = BOARD_X + ((i - 1) % 3) * 3
            local y = BOARD_Y + ((i - 1) // 3) * 3
            local mark = self.board[i]
            local v = blink[i] and "blink" or true
            if mark == "X" then grid:stamp(X_MARK, x, y, v)
            elseif mark == "O" then grid:stamp(O_MARK, x, y, v) end
            if i == self.cursor and not self.result_until then
                if mark == " " then grid:stamp({ "###", "###", "###" }, x, y, "blink")
                else grid:stamp(mark == "X" and X_MARK or O_MARK, x, y, "blink") end
            end
        end
    end

    clear_board()
    return game
end

return {
    id = "tictactoe",
    name = "TIC-TAC-TOE",
    hint = { "D-PAD MOVE", "ENTER PLACE X" },
    messages = { "YOU WIN", "DRAW", "CPU WINS" },
    order = "high",
    demo = DEMO,
    new = new,
    cpu_move = cpu_move,
}
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `lua dev/test/run.lua dev/test/test_tictactoe.lua`
Expected: `11 tests, 0 failed`

- [ ] **Step 5: Add the game to the menu**

In `main.lua`, replace the `GAME_IDS` table (it currently ends with `"simon"`) with:

```lua
local GAME_IDS = {
    "tetris", "snake", "breakout", "invaders", "frogger",
    "racer", "pong", "copter", "asteroids", "memory",
    "simon", "tictactoe",
}
```

- [ ] **Step 6: Run the whole suite and the smoke test for this game**

Run:
```bash
lua dev/test/run.lua
PICODECK_ROOT=../picodeck python3 dev/smoke.py --only tictactoe --out <scratchpad>/p2-tictactoe
```
Expected:
- The whole suite passes.
- `SMOKE OK (1 games)`, with `tictactoe-hint`, `tictactoe-gameplay` and `tictactoe-game-over` screenshots; its FINISH steps lose it.
- Look at the gameplay screenshot: it should match the spec's section 3 row for this game.

- [ ] **Step 7: Commit**

```bash
git add games/tictactoe.lua dev/test/test_tictactoe.lua main.lua
git commit -m "tictactoe: port to the grid game contract"
```

---

### Task 13: Game 13, Moon Lander

Land gently on the blinking pad.

**Files:**
- Create: `dev/test/test_moonlander.lua`
- Rewrite: `games/moonlander.lua`
- Modify: `main.lua` (`GAME_IDS`)

**Interfaces:**
- Consumes: the game contract and the Task 1 test helpers.
- Produces:
  - The module `games/moonlander.lua`, with `id = "moonlander"`.
  - Game fields the tests use: `x`/`y`/`vx`/`vy`, `fuel`, `heights[c]`, `pad` (left column), `landings`, `next_tick`.

- [ ] **Step 1: Write the failing tests**

Create `dev/test/test_moonlander.lua`:

```lua
need("dev/test/game_helpers.lua")
local lander = need("games/moonlander.lua")

local function new_game()
    local g = lander.new(game_ctx())
    -- flat ground 2 high, pad at columns 4-6 at height 2
    for c = 1, 10 do g.heights[c] = 2 end
    g.pad = 4
    return g
end

-- Run physics ticks until the lander touches down (or n ticks pass).
local function fly(g, p, n)
    local result
    local lives, landings = g.lives, g.landings
    for _ = 1, n or 400 do
        result = g:update(p or NONE, g.next_tick)
        if result or g.landings > landings or g.lives < lives then break end
    end
    return result
end

test("moonlander: meets the game contract", function()
    check_contract(lander, "moonlander", "MOON LANDER")
end)

test("moonlander: starts at the top with full fuel and 3 lives", function()
    local g = lander.new(game_ctx())
    eq(g.lives, 3, "lives"); eq(g.fuel, 160, "fuel"); eq(math.floor(g.y), 1, "top")
    local h = g.heights[g.pad]
    eq(g.heights[g.pad + 1], h, "pad flat"); eq(g.heights[g.pad + 2], h, "pad flat")
end)

test("moonlander: gravity pulls the lander down faster and faster", function()
    local g = new_game()
    g:update(NONE, g.next_tick)
    local v1 = g.vy
    for _ = 1, 5 do g:update(NONE, g.next_tick) end
    truthy(g.vy > v1 and v1 > 0, "accelerating")
end)

test("moonlander: thrust pushes up and burns fuel", function()
    local g = new_game()
    g.y = 10                                      -- mid-air: row 1 is the ceiling
    for _ = 1, 5 do g:update(hold("up"), g.next_tick) end
    truthy(g.vy < 0, "rising"); eq(g.fuel, 155, "fuel used")
end)

test("moonlander: no thrust once the fuel is gone", function()
    local g = new_game()
    g.fuel = 0
    g:update(hold("up"), g.next_tick)
    truthy(g.vy > 0, "still falling"); eq(g.fuel, 0, "empty")
end)

test("moonlander: a slow landing on the pad scores and starts the next level", function()
    local g = new_game()
    g.x, g.y, g.vx, g.vy = 5.5, 16.2, 0, 0.05     -- just above the pad, slow
    fly(g)
    eq(g.landings, 1, "landed"); eq(g.level, 2, "level 2")
    truthy(g.score > 0, "scored"); eq(math.floor(g.y), 1, "new lander at the top")
end)

test("moonlander: touching down off the pad is a crash", function()
    local g = new_game()
    g.x, g.y, g.vx, g.vy = 8.5, 16.2, 0, 0.05     -- columns 7-9: not the pad
    fly(g)
    eq(g.lives, 2, "crashed")
end)

test("moonlander: hitting the pad too fast is a crash", function()
    local g = new_game()
    g.x, g.y, g.vx, g.vy = 5.5, 14, 0, 0.5
    fly(g)
    eq(g.lives, 2, "too fast")
end)

test("moonlander: losing the last life ends the round", function()
    local g = new_game()
    g.lives = 1
    g.x, g.y, g.vx, g.vy = 8.5, 16.2, 0, 0.05
    eq(fly(g), "over", "over")
end)

test("moonlander: the lander blinks while it is too fast to land", function()
    local g = new_game()
    g.vy = 0.5
    local grid = draw_game(g)
    eq(grid:get(math.floor(g.x), math.floor(g.y)), "blink", "warning")
    g.vy = 0.05
    grid = draw_game(g)
    eq(grid:get(math.floor(g.x), math.floor(g.y)), true, "steady when safe")
end)

test("moonlander: NEXT shows the fuel, one brick per 10 units", function()
    local g = new_game()
    g.fuel = 95
    local _, nextg = draw_game(g)
    eq(count_lit(nextg), 10, "ceil(95 / 10) bricks")
end)

test("moonlander: the pad blinks, the rest of the ground is solid", function()
    local g = new_game()
    local grid = draw_game(g)
    eq(grid:get(5, 19), "blink", "pad top"); eq(grid:get(5, 20), true, "under the pad")
    eq(grid:get(1, 19), true, "ground")
end)
```

- [ ] **Step 2: Run them against the old game to see them fail**

Run: `lua dev/test/run.lua dev/test/test_moonlander.lua`
Expected: every test fails against the old BRICK-30 module, starting with `FAIL  moonlander: meets the game contract`. The last line is `12 tests, 12 failed`.

- [ ] **Step 3: Rewrite `games/moonlander.lua`**

Replace the whole file with:

```lua
-- moonlander.lua — game 13: land gently on the blinking pad.
-- The lander blinks while it is falling too fast to land safely.
-- Game contract: see lib/runner.lua. Needs the SFX global.

local COLS, ROWS = 10, 20
local LANDER = { "###", "#.#" }
local TICK_MS = 60                -- physics tick at speed 1
local GRAVITY = 0.012             -- cells/tick added per tick at level 1
local THRUST = 0.03
local SIDE = 0.015
local MAX_VX, MAX_UP, MAX_DOWN = 0.3, 0.4, 0.6
local SAFE_VY, SAFE_VX = 0.15, 0.1
local FUEL = 160                  -- ticks of burn; NEXT shows one brick per 10
local REFUEL = 40                 -- fuel added after each landing

local DEMO = {
    {
        "..........",
        "...###....",
        "...#.#....",
        "..........",
        "..........",
        "..........",
        "..........",
        "..........",
        "#.........",
        "##...###.#",
        "###..###.#",
        "####.#####",
    },
    {
        "..........",
        "..........",
        "..........",
        "..........",
        "....###...",
        "....#.#...",
        "..........",
        "..........",
        "#.........",
        "##...###.#",
        "###..###.#",
        "####.#####",
    },
}

local function new(ctx)
    local game = { score = 0, level = 1, lives = 3, landings = 0, fuel = FUEL, heights = {} }

    local function new_ground()
        for c = 1, COLS do game.heights[c] = math.random(2, 6) end
        game.pad = math.random(1, COLS - 2)
        local h = math.random(1, 3)
        for c = game.pad, game.pad + 2 do game.heights[c] = h end
    end

    local function new_lander()
        game.x, game.y = 5.5, 1
        game.vx, game.vy = (math.random() - 0.5) * 0.1, 0
    end

    local function top_row(c) return ROWS + 1 - game.heights[c] end

    -- Touching down: work out whether it was a landing or a crash.
    local function touch_down(left)
        local on_pad = left == game.pad
        if on_pad and game.vy <= SAFE_VY and math.abs(game.vx) <= SAFE_VX then
            game.landings = game.landings + 1
            game.level = game.landings + 1
            game.score = game.score + (50 + game.fuel // 2) * game.level
            game.fuel = math.min(FUEL, game.fuel + REFUEL)
            SFX.levelup()
            new_ground()
            new_lander()
            return nil
        end
        game.lives = game.lives - 1
        SFX.over()
        if game.lives <= 0 then return "over" end
        new_lander()
        return nil
    end

    function game:update(pad, now)
        if now < self.next_tick then return nil end
        self.next_tick = now + ctx.interval(TICK_MS, 1)

        self.vy = self.vy + GRAVITY * (1 + 0.15 * (self.level - 1))
        if self.fuel > 0 then
            if pad.held.up then self.vy = self.vy - THRUST self.fuel = self.fuel - 1 end
            if pad.held.left then self.vx = self.vx - SIDE self.fuel = math.max(0, self.fuel - 1) end
            if pad.held.right then self.vx = self.vx + SIDE self.fuel = math.max(0, self.fuel - 1) end
        end
        self.vx = math.max(-MAX_VX, math.min(MAX_VX, self.vx))
        self.vy = math.max(-MAX_UP, math.min(MAX_DOWN, self.vy))
        self.x = self.x + self.vx
        if self.x < 2 then self.x, self.vx = 2, 0 end
        if self.x >= COLS then self.x, self.vx = COLS - 0.001, 0 end
        self.y = self.y + self.vy
        if self.y < 1 then self.y, self.vy = 1, 0 end

        -- the lander's bottom row reaching the row above the ground is touchdown
        local left = math.floor(self.x) - 1
        local ground = math.huge
        for c = left, left + 2 do ground = math.min(ground, top_row(c)) end
        if math.floor(self.y) + 1 >= ground - 1 then
            self.y = ground - 2
            return touch_down(left)
        end
        return nil
    end

    function game:draw(grid, next)
        for c = 1, COLS do
            local top = top_row(c)
            for r = top, ROWS do grid:set(c, r, true) end
            if c >= self.pad and c <= self.pad + 2 then grid:set(c, top, "blink") end
        end
        local v = self.vy > SAFE_VY and "blink" or true
        grid:stamp(LANDER, math.floor(self.x) - 1, math.floor(self.y), v)
        for i = 1, math.ceil(self.fuel / 10) do
            next:set((i - 1) % 4 + 1, (i - 1) // 4 + 1, true)
        end
    end

    new_ground()
    new_lander()
    game.next_tick = ctx.now + ctx.interval(TICK_MS, 1)
    return game
end

return {
    id = "moonlander",
    name = "MOON LANDER",
    hint = { "UP THRUST", "< > DRIFT", "LAND SLOWLY" },
    order = "high",
    demo = DEMO,
    new = new,
}
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `lua dev/test/run.lua dev/test/test_moonlander.lua`
Expected: `12 tests, 0 failed`

- [ ] **Step 5: Add the game to the menu**

In `main.lua`, replace the `GAME_IDS` table (it currently ends with `"tictactoe"`) with:

```lua
local GAME_IDS = {
    "tetris", "snake", "breakout", "invaders", "frogger",
    "racer", "pong", "copter", "asteroids", "memory",
    "simon", "tictactoe", "moonlander",
}
```

- [ ] **Step 6: Run the whole suite and the smoke test for this game**

Run:
```bash
lua dev/test/run.lua
PICODECK_ROOT=../picodeck python3 dev/smoke.py --only moonlander --out <scratchpad>/p2-moonlander
```
Expected:
- The whole suite passes.
- `SMOKE OK (1 games)`, with `moonlander-hint`, `moonlander-gameplay` and `moonlander-game-over` screenshots; its FINISH steps lose it.
- Look at the gameplay screenshot: it should match the spec's section 3 row for this game.

- [ ] **Step 7: Commit**

```bash
git add games/moonlander.lua dev/test/test_moonlander.lua main.lua
git commit -m "moonlander: port to the grid game contract"
```

---

### Task 14: Game 14, Missile Command

Protect 3 cities from falling missiles.

**Files:**
- Create: `dev/test/test_missile.lua`
- Rewrite: `games/missile.lua`
- Modify: `main.lua` (`GAME_IDS`)

**Interfaces:**
- Consumes: the game contract and the Task 1 test helpers.
- Produces:
  - The module `games/missile.lua`, with `id = "missile"`.
  - Game fields the tests use: `cx`/`cy`, `ammo`, `cities` ({x,alive}), `missiles` ({x0,x,y,tx}), `explosions` ({x,y,t0}), `spawned`, `wave_total`, `next_step`/`next_spawn`; module field `radius(e, now)`.

- [ ] **Step 1: Write the failing tests**

Create `dev/test/test_missile.lua`:

```lua
need("dev/test/game_helpers.lua")
local missile = need("games/missile.lua")

local function new_game()
    local g = missile.new(game_ctx())
    g.next_spawn = math.huge               -- no new missiles unless a test adds them
    return g
end

-- A missile from (x0, 1) aimed at (tx, 20), currently at row y.
local function incoming(x0, tx, y)
    local m = { x0 = x0, tx = tx, y = y or 1 }
    m.x = x0
    return m
end

test("missile: meets the game contract", function()
    check_contract(missile, "missile", "MISSILE CMD")
end)

test("missile: 3 cities, 12 shots, crosshair mid-screen", function()
    local g = new_game()
    eq(g.lives, 3, "cities as lives"); eq(g.ammo, 12, "ammo")
    eq(g.cx, 5, "crosshair x"); eq(g.cy, 10, "crosshair y")
end)

test("missile: the crosshair moves with the d-pad and stays on the sky", function()
    local g = new_game()
    g:update(pad({ repeated = { "up" } }), 1)
    eq(g.cy, 9, "moved up")
    for _ = 1, 30 do g:update(pad({ repeated = { "down" } }), 1) end
    eq(g.cy, 17, "stops above the ground")
end)

test("missile: firing spends a shot and explodes at the crosshair", function()
    local g = new_game()
    g:update(press("enter"), 100)
    eq(g.ammo, 11, "shot spent"); eq(#g.explosions, 1, "explosion")
    eq(g.explosions[1].x, 5, "at crosshair x"); eq(g.explosions[1].y, 10, "at crosshair y")
end)

test("missile: no shots left means no explosion", function()
    local g = new_game()
    g.ammo = 0
    g:update(press("enter"), 1)
    eq(#g.explosions, 0, "nothing")
end)

test("missile: an explosion grows from radius 1 to 2 and then fades", function()
    local g = new_game()
    g:update(press("enter"), 0)
    local e = g.explosions[1]
    eq(missile.radius(e, 100), 1, "starts small")
    eq(missile.radius(e, 200), 2, "grows")
    eq(missile.radius(e, 350), 1, "shrinks")
    eq(missile.radius(e, 500), nil, "gone")
end)

test("missile: a missile inside the blast is destroyed and scores", function()
    local g = new_game()
    g.missiles = { incoming(6, 6, 11) }     -- (6,11): 2 cells from (5,10)
    g.explosions = { { x = 5, y = 10, t0 = 0 } }
    g.next_step = math.huge
    g:update(NONE, 200)                      -- radius 2
    eq(#g.missiles, 0, "destroyed"); eq(g.score, 25, "score")
end)

test("missile: missiles step down one row toward their target", function()
    local g = new_game()
    g.missiles = { incoming(1, 10, 1) }
    g:update(NONE, g.next_step)
    eq(g.missiles[1].y, 2, "down a row")
    truthy(g.missiles[1].x >= 1 and g.missiles[1].x <= 2, "drifting toward its target")
end)

test("missile: a missile landing on a city destroys it", function()
    local g = new_game()
    g.missiles = { incoming(2, 2, 19) }
    g:update(NONE, g.next_step)
    eq(g.lives, 2, "city lost"); eq(#g.missiles, 0, "missile gone")
end)

test("missile: losing the last city ends the round", function()
    local g = new_game()
    g.cities[2].alive, g.cities[3].alive = false, false
    g.missiles = { incoming(2, 2, 19) }
    eq(g:update(NONE, g.next_step), "over", "over")
end)

test("missile: a finished wave scores a bonus and refills the shots", function()
    local g = new_game()
    g.spawned, g.ammo = g.wave_total, 4
    g.missiles, g.explosions = {}, {}
    g:update(NONE, 1)
    eq(g.level, 2, "next wave"); eq(g.ammo, 12, "refilled")
    eq(g.score, 3 * 50 + 4 * 5, "bonus for cities and spare shots")
end)

test("missile: the NEXT box shows one brick per shot", function()
    local g = new_game()
    g.ammo = 5
    local _, nextg = draw_game(g)
    eq(count_lit(nextg), 5, "5 shots")
end)
```

- [ ] **Step 2: Run them against the old game to see them fail**

Run: `lua dev/test/run.lua dev/test/test_missile.lua`
Expected: every test fails against the old BRICK-30 module, starting with `FAIL  missile: meets the game contract`. The last line is `12 tests, 12 failed`.

- [ ] **Step 3: Rewrite `games/missile.lua`**

Replace the whole file with:

```lua
-- missile.lua — game 14: protect 3 cities from falling missiles.
-- Aim the crosshair and set off explosions in the missiles' path.
-- Game contract: see lib/runner.lua. Needs the SFX global.

local COLS, ROWS = 10, 20
local CITY_COLS = { 2, 5, 8 }     -- each city is 2 bricks: col and col+1, row 20
local AMMO = 12
local MISSILE_MS = 450            -- missile step at speed 1, level 1
local SPAWN_MS = 1400             -- a new missile at most this often
local MAX_ON_SCREEN = 3
local BLAST = { { 150, 1 }, { 300, 2 }, { 450, 1 } }   -- age limit, radius

local DEMO = {
    {
        "#.........",
        ".#.......#",
        "..#.....#.",
        "........#.",
        "...#......",
        "..###.....",
        "...#......",
        "..........",
        "..........",
        "..........",
        "..........",
        ".##.##.##.",
    },
    {
        "..........",
        "#.........",
        ".#........",
        "..#.....#.",
        "...#...#..",
        "..###.....",
        ".#####....",
        "..###.....",
        "...#......",
        "..........",
        "..........",
        ".##.##.##.",
    },
}

-- Blast radius of explosion `e` at time `now`, or nil once it has faded.
local function radius(e, now)
    local age = now - e.t0
    for _, stage in ipairs(BLAST) do
        if age < stage[1] then return stage[2] end
    end
    return nil
end

local function new(ctx)
    local game = { score = 0, level = 1, ammo = AMMO, cx = 5, cy = 10,
                   missiles = {}, explosions = {}, cities = {} }
    for i, c in ipairs(CITY_COLS) do game.cities[i] = { x = c, alive = true } end

    local function start_wave(now)
        game.wave_total = 6 + 2 * game.level
        game.spawned = 0
        game.ammo = AMMO
        game.next_spawn = now + ctx.interval(SPAWN_MS, game.level)
    end

    local function cities_left()
        local n = 0
        for _, city in ipairs(game.cities) do if city.alive then n = n + 1 end end
        return n
    end

    local function spawn()
        local targets = {}
        for _, city in ipairs(game.cities) do
            if city.alive then
                targets[#targets + 1] = city.x
                targets[#targets + 1] = city.x + 1
            end
        end
        local x0 = math.random(COLS)
        game.missiles[#game.missiles + 1] = { x0 = x0, x = x0, y = 1, tx = targets[math.random(#targets)] }
        game.spawned = game.spawned + 1
    end

    local function blasted(m, now)
        for _, e in ipairs(game.explosions) do
            local r = radius(e, now)
            if r and math.abs(m.x - e.x) + math.abs(m.y - e.y) <= r then return true end
        end
        return false
    end

    local function land(m)
        for _, city in ipairs(game.cities) do
            if city.alive and (m.x == city.x or m.x == city.x + 1) then
                city.alive = false
                SFX.hit()
            end
        end
    end

    function game:update(pad, now)
        if pad.repeated.left and self.cx > 2 then self.cx = self.cx - 1 end
        if pad.repeated.right and self.cx < COLS - 1 then self.cx = self.cx + 1 end
        if pad.repeated.up and self.cy > 2 then self.cy = self.cy - 1 end
        if pad.repeated.down and self.cy < ROWS - 3 then self.cy = self.cy + 1 end
        if (pad.pressed.enter or pad.pressed.f1) and self.ammo > 0 then
            self.ammo = self.ammo - 1
            self.explosions[#self.explosions + 1] = { x = self.cx, y = self.cy, t0 = now }
            SFX.drop()
        end

        -- fade explosions, destroy missiles caught in one
        local live = {}
        for _, e in ipairs(self.explosions) do
            if radius(e, now) then live[#live + 1] = e end
        end
        self.explosions = live
        local kept = {}
        for _, m in ipairs(self.missiles) do
            if blasted(m, now) then
                self.score = self.score + 25 * self.level
                SFX.score()
            else
                kept[#kept + 1] = m
            end
        end
        self.missiles = kept

        if now >= self.next_step then
            self.next_step = now + ctx.interval(MISSILE_MS, self.level)
            kept = {}
            for _, m in ipairs(self.missiles) do
                m.y = m.y + 1
                m.x = m.x0 + math.floor((m.tx - m.x0) * (m.y - 1) / (ROWS - 1) + 0.5)
                if m.y >= ROWS then land(m) else kept[#kept + 1] = m end
            end
            self.missiles = kept
            self.lives = cities_left()
            if self.lives == 0 then return "over" end
        end

        if self.spawned < self.wave_total and #self.missiles < MAX_ON_SCREEN
           and now >= self.next_spawn then
            self.next_spawn = now + ctx.interval(SPAWN_MS, self.level)
            spawn()
        end

        if self.spawned >= self.wave_total and #self.missiles == 0 and #self.explosions == 0 then
            self.score = self.score + 50 * cities_left() + 5 * self.ammo
            self.level = self.level + 1
            SFX.levelup()
            start_wave(now)
        end
        return nil
    end

    function game:draw(grid, next)
        for _, city in ipairs(self.cities) do
            if city.alive then
                grid:set(city.x, ROWS, true)
                grid:set(city.x + 1, ROWS, true)
            end
        end
        for _, m in ipairs(self.missiles) do grid:set(m.x, m.y, true) end
        local now = self.now or 0
        for _, e in ipairs(self.explosions) do
            local r = radius(e, now) or 0
            for dy = -r, r do
                for dx = -r, r do
                    if math.abs(dx) + math.abs(dy) <= r then grid:set(e.x + dx, e.y + dy, true) end
                end
            end
        end
        grid:stamp({ ".#.", "###", ".#." }, self.cx - 1, self.cy - 1, "blink")
        for i = 1, self.ammo do next:set((i - 1) % 4 + 1, (i - 1) // 4 + 1, true) end
    end

    game.lives = cities_left()
    game.next_step = ctx.now + ctx.interval(MISSILE_MS, game.level)
    start_wave(ctx.now)
    return game
end

return {
    id = "missile",
    name = "MISSILE CMD",
    hint = { "D-PAD AIM", "ENTER FIRE" },
    order = "high",
    demo = DEMO,
    new = new,
    radius = radius,
}
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `lua dev/test/run.lua dev/test/test_missile.lua`
Expected: `12 tests, 0 failed`

- [ ] **Step 5: Add the game to the menu**

In `main.lua`, replace the `GAME_IDS` table (it currently ends with `"moonlander"`) with:

```lua
local GAME_IDS = {
    "tetris", "snake", "breakout", "invaders", "frogger",
    "racer", "pong", "copter", "asteroids", "memory",
    "simon", "tictactoe", "moonlander", "missile",
}
```

- [ ] **Step 6: Run the whole suite and the smoke test for this game**

Run:
```bash
lua dev/test/run.lua
PICODECK_ROOT=../picodeck python3 dev/smoke.py --only missile --out <scratchpad>/p2-missile
```
Expected:
- The whole suite passes.
- `SMOKE OK (1 games)`, with `missile-hint`, `missile-gameplay` and `missile-game-over` screenshots; its FINISH steps lose it.
- Look at the gameplay screenshot: it should match the spec's section 3 row for this game.

- [ ] **Step 7: Commit**

```bash
git add games/missile.lua dev/test/test_missile.lua main.lua
git commit -m "missile: port to the grid game contract"
```

---

### Task 15: Game 15, Tank

Destroy the enemy tanks and protect your base.

**Files:**
- Create: `dev/test/test_tank.lua`
- Rewrite: `games/tank.lua`
- Modify: `main.lua` (`GAME_IDS`)

**Interfaces:**
- Consumes: the game contract and the Task 1 test helpers.
- Produces:
  - The module `games/tank.lua`, with `id = "tank"`.
  - Game fields the tests use: `player` {x,y,dir}, `enemies`, `bullets` ({x,y,dx,dy,owner,from}), `walls[r][c]`, `base_alive`, `wave_total`/`spawned`/`killed`, `next_bullet`/`next_enemy`/`next_spawn`.

- [ ] **Step 1: Write the failing tests**

Create `dev/test/test_tank.lua`:

```lua
need("dev/test/game_helpers.lua")
local tank = need("games/tank.lua")

local function new_game()
    local g = tank.new(game_ctx())
    g.next_spawn, g.next_enemy = math.huge, math.huge   -- a quiet field for tests
    return g
end

local function shot(x, y, dx, dy, owner)
    return { x = x, y = y, dx = dx, dy = dy, owner = owner or "enemy" }
end

test("tank: meets the game contract", function()
    check_contract(tank, "tank", "TANK")
end)

test("tank: you start bottom-left facing up, 3 lives, base intact", function()
    local g = new_game()
    eq(g.player.x, 1, "x"); eq(g.player.y, 18, "y"); eq(g.player.dir, "up", "facing")
    eq(g.lives, 3, "lives"); eq(g.base_alive, true, "base")
end)

test("tank: the d-pad turns and moves one cell, walls block", function()
    local g = new_game()
    g:update(pad({ repeated = { "up" } }), 1)
    eq(g.player.y, 17, "moved up")
    g:update(pad({ repeated = { "right" } }), 2)
    eq(g.player.dir, "right", "turned"); eq(g.player.x, 1, "wall at column 4 blocks")
end)

test("tank: you can drive out of the start, up the left lane", function()
    local g = new_game()
    for t = 1, 20 do g:update(pad({ repeated = { "up" } }), t) end
    truthy(g.player.y <= 7, "drove up past the lower walls, reached y=" .. g.player.y)
end)

test("tank: one shot at a time, fired from the barrel", function()
    local g = new_game()
    g:update(press("enter"), 1)
    eq(#g.bullets, 1, "fired")
    eq(g.bullets[1].x, 2, "barrel column"); eq(g.bullets[1].y, 17, "just ahead")
    g:update(press("enter"), 2)
    eq(#g.bullets, 1, "second shot ignored")
end)

test("tank: a shot knocks out one wall brick", function()
    local g = new_game()
    g.bullets = { shot(4, 17, 0, 1, "player") }   -- next cell (4,18) is a wall
    g.next_bullet = 0
    g:update(NONE, 0)
    eq(g.walls[18][4], false, "brick gone"); eq(#g.bullets, 0, "shot used")
end)

test("tank: your shot destroys an enemy tank and scores 100", function()
    local g = new_game()
    g.enemies = { { x = 1, y = 7, dir = "down" } }     -- box cols 1-3, rows 7-9
    g.bullets = { shot(2, 5, 0, 1, "player") }         -- column 2 is clear
    g.next_bullet = 0
    g:update(NONE, 0); g:update(NONE, 100)
    eq(#g.enemies, 0, "destroyed"); eq(g.score, 100, "score")
end)

test("tank: an enemy shot costs you a life and sends you back to the start", function()
    local g = new_game()
    g.player.y = 12
    g.bullets = { shot(2, 10, 0, 1) }
    g.next_bullet = 0
    g:update(NONE, 0); g:update(NONE, 100)
    eq(g.lives, 2, "hit"); eq(g.player.y, 18, "back at the start")
end)

test("tank: an enemy shot on the base ends the round with BASE LOST", function()
    local g = new_game()
    g.bullets = { shot(5, 18, 0, 1) }             -- (5,18) is a wall: clear it first
    g.walls[18][5] = false
    g.next_bullet = 0
    eq(g:update(NONE, 0), "over", "over")
    eq(g.status[1], "BASE LOST", "headline"); check_status(tank, g)
end)

test("tank: losing the last life ends the round", function()
    local g = new_game()
    g.lives = 1
    g.player.y = 12
    g.bullets = { shot(2, 11, 0, 1) }
    g.next_bullet = 0
    eq(g:update(NONE, 0), "over", "over")
end)

test("tank: destroying the whole wave starts the next with fresh walls", function()
    local g = new_game()
    g.walls[5][1] = false
    g.killed, g.spawned = g.wave_total - 1, g.wave_total
    g.enemies = { { x = 1, y = 7, dir = "down" } }
    g.bullets = { shot(2, 6, 0, 1, "player") }
    g.next_bullet = 0
    g:update(NONE, 0)
    eq(g.level, 2, "level 2"); eq(g.walls[5][1], true, "walls restored")
end)

test("tank: an enemy never spawns on top of your tank", function()
    local g = new_game()
    g.player.x, g.player.y = 1, 1       -- sitting on a spawn point
    for i = 1, 60 do
        g.next_spawn = 0
        g:update(NONE, i)
        for _, e in ipairs(g.enemies) do
            truthy(math.abs(e.x - g.player.x) >= 3 or math.abs(e.y - g.player.y) >= 3, "overlap")
        end
        g.enemies = {}
    end
end)

test("tank: your tank is solid, enemy tanks are hollow", function()
    local g = new_game()
    g.enemies = { { x = 4, y = 1, dir = "down" } }
    local grid = draw_game(g)
    eq(grid:get(2, 19), true, "player centre")
    eq(grid:get(5, 2), false, "enemy centre hollow")
    eq(grid:get(5, 3), true, "enemy barrel down")
end)
```

- [ ] **Step 2: Run them against the old game to see them fail**

Run: `lua dev/test/run.lua dev/test/test_tank.lua`
Expected: every test fails against the old BRICK-30 module, starting with `FAIL  tank: meets the game contract`. The last line is `13 tests, 13 failed`.

- [ ] **Step 3: Rewrite `games/tank.lua`**

Replace the whole file with:

```lua
-- tank.lua — game 15: destroy the enemy tanks and protect your base.
-- Tanks are 3x3: yours is solid, the enemy's is hollow.
-- Game contract: see lib/runner.lua. Needs the SFX global.

local COLS, ROWS = 10, 20
local START_X, START_Y = 1, 18
local BASE = { { 5, 19 }, { 6, 19 }, { 5, 20 }, { 6, 20 } }
local SPAWNS = { { 1, 1 }, { 4, 1 }, { 8, 1 } }
local MAX_ENEMIES = 3
local ENEMY_MS = 450              -- enemy move at speed 1, level 1
local SPAWN_MS = 2000
local BULLET_MS = 60
local FIRE_CHANCE = 0.3

-- '#' walls; every wall row leaves 3-wide gaps so 3x3 tanks can pass.
local MAP = {
    "..........", "..........", "..........", "..........",
    "#...##...#", "#...##...#",
    "..........", "..........", "..........",
    "...####...", "...####...",
    "..........", "..........", "..........",
    "...####...", "...####...",
    "..........",
    "...####...", "...#..#...", "...#..#...",
}

local DIRS = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }
local PLAYER = {
    up = { ".#.", "###", "#.#" }, down = { "#.#", "###", ".#." },
    left = { ".##", "##.", ".##" }, right = { "##.", ".##", "##." },
}
local ENEMY = {
    up = { ".#.", "#.#", "#.#" }, down = { "#.#", "#.#", ".#." },
    left = { ".##", "#..", ".##" }, right = { "##.", "..#", "##." },
}
local ENEMY_TURNS = { "down", "down", "left", "right", "up" }   -- they drift toward you

local DEMO = {
    {
        "#.#.......",
        "#.#.......",
        ".#........",
        "......#...",
        "#...##...#",
        "#...##...#",
        "..........",
        "..........",
        "....#.....",
        ".#........",
        "###.####..",
        "#.#.#..#..",
    },
    {
        "..........",
        "#.#.......",
        "#.#.......",
        ".#........",
        "#...##...#",
        "#...##...#",
        "..........",
        "....#.....",
        "..........",
        ".#........",
        "###.####..",
        "#.#.#..#..",
    },
}

local function new(ctx)
    local game = { score = 0, level = 1, lives = 3, enemies = {}, bullets = {} }

    local function reset_walls()
        game.walls = {}
        for r = 1, ROWS do
            game.walls[r] = {}
            for c = 1, COLS do game.walls[r][c] = string.sub(MAP[r], c, c) == "#" end
        end
    end

    local function reset_player()
        game.player = { x = START_X, y = START_Y, dir = "up" }
    end

    local function start_wave(now)
        reset_walls()
        reset_player()
        game.enemies, game.bullets = {}, {}
        game.wave_total = 4 + 2 * game.level
        game.spawned, game.killed = 0, 0
        game.next_spawn = now + 500
    end

    local function is_base(c, r)
        for _, b in ipairs(BASE) do if b[1] == c and b[2] == r then return true end end
        return false
    end

    local function in_box(t, c, r)
        return c >= t.x and c <= t.x + 2 and r >= t.y and r <= t.y + 2
    end

    -- Can tank t (ignoring itself) have its top-left at (x, y)?
    local function free_box(t, x, y)
        if x < 1 or y < 1 or x + 2 > COLS or y + 2 > ROWS then return false end
        for r = y, y + 2 do
            for c = x, x + 2 do
                if game.walls[r][c] or (game.base_alive and is_base(c, r)) then return false end
            end
        end
        local tanks = { game.player }
        for _, e in ipairs(game.enemies) do tanks[#tanks + 1] = e end
        for _, o in ipairs(tanks) do
            if o ~= t and math.abs(o.x - x) < 3 and math.abs(o.y - y) < 3 then return false end
        end
        return true
    end

    local function drive(t, dir)
        t.dir = dir
        local d = DIRS[dir]
        if free_box(t, t.x + d[1], t.y + d[2]) then
            t.x, t.y = t.x + d[1], t.y + d[2]
            return true
        end
        return false
    end

    local function fire(t, owner)
        local d = DIRS[t.dir]
        -- the barrel is the middle of the facing side; the shot starts beyond it
        game.bullets[#game.bullets + 1] = {
            x = t.x + 1 + d[1] * 2, y = t.y + 1 + d[2] * 2,
            dx = d[1], dy = d[2], owner = owner, from = t }
    end

    local function player_shot_live()
        for _, b in ipairs(game.bullets) do if b.owner == "player" then return true end end
        return false
    end

    -- Resolve bullet b at its cell. Returns "gone", "over" or nil (keep flying).
    local function hit(b, now)
        if b.x < 1 or b.x > COLS or b.y < 1 or b.y > ROWS then return "gone" end
        if game.walls[b.y][b.x] then
            game.walls[b.y][b.x] = false
            SFX.hit()
            return "gone"
        end
        if game.base_alive and is_base(b.x, b.y) then
            game.base_alive = false
            game.status = { "BASE LOST" }
            SFX.over()
            return "over"
        end
        if b.owner == "player" then
            for i, e in ipairs(game.enemies) do
                if in_box(e, b.x, b.y) then
                    table.remove(game.enemies, i)
                    game.killed = game.killed + 1
                    game.score = game.score + 100 * game.level
                    SFX.score()
                    return "gone"
                end
            end
        elseif in_box(game.player, b.x, b.y) then
            game.lives = game.lives - 1
            SFX.over()
            if game.lives <= 0 then return "over" end
            reset_player()
            return "gone"
        end
        return nil
    end

    function game:update(pad, now)
        for dir in pairs(DIRS) do
            if pad.repeated[dir] then drive(self.player, dir) break end
        end
        if (pad.pressed.enter or pad.pressed.f1) and not player_shot_live() then
            fire(self.player, "player")
            SFX.move()
            local b = self.bullets[#self.bullets]
            local r = hit(b, now)
            if r == "over" then return "over" end
            if r == "gone" then table.remove(self.bullets) end
        end

        if now >= self.next_bullet then
            self.next_bullet = now + BULLET_MS
            local kept = {}
            for _, b in ipairs(self.bullets) do
                b.x, b.y = b.x + b.dx, b.y + b.dy
                local r = hit(b, now)
                if r == "over" then return "over" end
                if r ~= "gone" then kept[#kept + 1] = b end
            end
            self.bullets = kept
        end

        if self.killed >= self.wave_total then
            self.level = self.level + 1
            SFX.levelup()
            start_wave(now)
            return nil
        end

        if now >= self.next_spawn and self.spawned < self.wave_total and #self.enemies < MAX_ENEMIES then
            self.next_spawn = now + SPAWN_MS
            local s = SPAWNS[math.random(#SPAWNS)]
            local e = { x = s[1], y = s[2], dir = "down" }
            if free_box(e, e.x, e.y) then
                self.enemies[#self.enemies + 1] = e
                self.spawned = self.spawned + 1
            end
        end

        if now >= self.next_enemy then
            self.next_enemy = now + ctx.interval(ENEMY_MS, self.level)
            for _, e in ipairs(self.enemies) do
                if math.random() < 0.25 or not drive(e, e.dir) then
                    drive(e, ENEMY_TURNS[math.random(#ENEMY_TURNS)])
                end
                local has_shot = false
                for _, b in ipairs(self.bullets) do has_shot = has_shot or b.from == e end
                if not has_shot and math.random() < FIRE_CHANCE then fire(e, "enemy") end
            end
        end
        return nil
    end

    function game:draw(grid)
        for r = 1, ROWS do
            for c = 1, COLS do
                if self.walls[r][c] then grid:set(c, r, true) end
            end
        end
        if self.base_alive then
            for _, b in ipairs(BASE) do grid:set(b[1], b[2], "blink") end
        end
        for _, e in ipairs(self.enemies) do grid:stamp(ENEMY[e.dir], e.x, e.y) end
        grid:stamp(PLAYER[self.player.dir], self.player.x, self.player.y)
        for _, b in ipairs(self.bullets) do grid:set(b.x, b.y, true) end
    end

    game.base_alive = true
    start_wave(ctx.now)
    game.next_bullet = ctx.now + BULLET_MS
    game.next_enemy = ctx.now + ctx.interval(ENEMY_MS, game.level)
    return game
end

return {
    id = "tank",
    name = "TANK",
    hint = { "D-PAD DRIVE", "ENTER FIRE", "GUARD THE BASE" },
    messages = { "BASE LOST" },
    order = "high",
    demo = DEMO,
    new = new,
}
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `lua dev/test/run.lua dev/test/test_tank.lua`
Expected: `13 tests, 0 failed`

- [ ] **Step 5: Add the game to the menu**

In `main.lua`, replace the `GAME_IDS` table (it currently ends with `"missile"`) with:

```lua
local GAME_IDS = {
    "tetris", "snake", "breakout", "invaders", "frogger",
    "racer", "pong", "copter", "asteroids", "memory",
    "simon", "tictactoe", "moonlander", "missile", "tank",
}
```

- [ ] **Step 6: Run the whole suite and the smoke test for this game**

Run:
```bash
lua dev/test/run.lua
PICODECK_ROOT=../picodeck python3 dev/smoke.py --only tank --out <scratchpad>/p2-tank
```
Expected:
- The whole suite passes.
- `SMOKE OK (1 games)`, with `tank-hint`, `tank-gameplay` and `tank-game-over` screenshots; its FINISH steps lose it.
- Look at the gameplay screenshot: it should match the spec's section 3 row for this game.

- [ ] **Step 7: Commit**

```bash
git add games/tank.lua dev/test/test_tank.lua main.lua
git commit -m "tank: port to the grid game contract"
```

---



### Task 16: Rename to BRICK-15, with acceptance tests

**Files:**
- Create: `dev/test/test_app.lua`, `dev/make_icon.py`
- Modify: `app.json`, `README.md`, `icon.png` (regenerated)

**Interfaces:**
- Consumes: all 15 game modules (Tasks 2–15) and `check_contract` (Task 1).
- Produces: the BRICK-15 manifest, README and icon.

- [ ] **Step 1: Write the failing acceptance tests**

Create `dev/test/test_app.lua`:

```lua
-- Whole-app checks for the spec's acceptance criteria that don't need a device.

local function read(path)
    local f = assert(io.open(path, "r"))
    local s = f:read("a")
    f:close()
    return s
end

local MENU_ORDER = {
    "tetris", "snake", "breakout", "invaders", "frogger",
    "racer", "pong", "copter", "asteroids", "memory",
    "simon", "tictactoe", "moonlander", "missile", "tank",
}

test("app: the manifest is BRICK-15", function()
    local manifest = read("app.json")
    truthy(manifest:find('"id": "net.picodeck.brick15"', 1, true), "id")
    truthy(manifest:find('"name": "BRICK-15"', 1, true), "name")
    truthy(not manifest:lower():find("brick30", 1, true), "no BRICK-30 left")
end)

test("app: main.lua loads all 15 games in menu order", function()
    local list = read("main.lua"):match("GAME_IDS = (%b{})")
    local ids = {}
    for id in list:gmatch('"([%w]+)"') do ids[#ids + 1] = id end
    eq(#ids, 15, "games")
    for i, id in ipairs(MENU_ORDER) do
        eq(ids[i], id, "game " .. i)
        truthy(io.open("games/" .. id .. ".lua"), "games/" .. id .. ".lua exists")
    end
end)

test("app: games draw only through the grid", function()
    for _, id in ipairs(MENU_ORDER) do
        local src = read("games/" .. id .. ".lua")
        -- no display, save or scene calls, and no Esc handling
        truthy(not src:find("picocalc", 1, true), id .. ": uses picocalc directly")
        truthy(not src:find("%.esc"), id .. ": handles Esc")
    end
end)

test("app: every game module meets the contract", function()
    need("dev/test/game_helpers.lua")
    for _, id in ipairs(MENU_ORDER) do
        local mod = need("games/" .. id .. ".lua")
        eq(mod.id, id, "id of games/" .. id)
        check_contract(mod, id, mod.name)
    end
end)
```

- [ ] **Step 2: Run them to see the manifest test fail**

Run: `lua dev/test/run.lua dev/test/test_app.lua`
Expected: `FAIL  app: the manifest is BRICK-15`, then `4 tests, 1 failed`. The other three already pass, because all 15 games exist.

- [ ] **Step 3: Rewrite `app.json`**

```json
{
  "id": "net.picodeck.brick15",
  "name": "BRICK-15",
  "description": "15 classic LCD brick games on one 10x20 brick grid: Tetris, Snake, Breakout, Invaders, Frogger, Racer, Pong, Copter, Asteroids, Memory, Simon, Tic-Tac-Toe, Moon Lander, Missile Command and Tank.",
  "version": "1.0.0",
  "author": "PicoDeck",
  "category": "games",
  "min_firmware": "0.1.0",
  "requirements": ["audio"],
  "homepage": "https://github.com/PicoDeck/brick15"
}
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `lua dev/test/run.lua dev/test/test_app.lua`
Expected: `4 tests, 0 failed`

- [ ] **Step 5: Rewrite `README.md`**

````markdown
# BRICK-15

**15 classic LCD brick games in one cart** for [PicoDeck](https://github.com/PicoDeck/picodeck) (ClockworkPi PicoCalc v2.0), built to look like the cheap handheld brick-game consoles. Every game plays on one 10×20 grid of framed LCD bricks, with faint "ghost" bricks where nothing is lit, next to a side panel laid out the same way in every game. Scores use 7-segment digits, and the sound is square-wave beeps.

## Games

| # | Game | # | Game |
|---|------|---|------|
| 01 | Tetris | 09 | Asteroids |
| 02 | Snake | 10 | Memory |
| 03 | Breakout | 11 | Simon |
| 04 | Invaders | 12 | Tic-Tac-Toe (vs CPU) |
| 05 | Frogger | 13 | Moon Lander |
| 06 | Racer | 14 | Missile Command |
| 07 | Pong (vs CPU) | 15 | Tank |
| 08 | Copter | | |

Each game shows its controls on the panel for the first few seconds of a round.

## Menu

- **Left / Right:** choose a game. The grid shows its number and a short demo.
- **Up / Down:** set SPEED 1–9 (how fast the game starts).
- **Enter:** play.
- **Esc:** exit to the launcher.

## In a game

- **D-pad:** move, steer or aim.
- **Enter / F1:** the action button: rotate, fire, serve, flip or place.
- **Esc:** back to the menu.

When a round ends, the grid fills and clears like a curtain. Then Enter plays again, and Esc returns to the menu. High scores are saved per game. Memory saves your fewest turns and shows it as BEST.

## The panel

The panel is the same in every game:
- SCORE and HI (or BEST);
- NEXT: the next piece in Tetris, fuel in Moon Lander, shots left in Missile Command;
- SPEED and LEVEL;
- LIVES;
- the game's name and up to 3 status lines.

A field a game doesn't use stays ghosted.

## Install

Copy the app folder to `/apps/brick15/` on the PicoDeck SD card, or stage it with the `push_app` MCP tool. It appears in the launcher as **BRICK-15**. The `dev/` and `docs/` folders aren't needed on the device.

`app.json` declares the `audio` requirement (tone beeps).

## Develop

Pure Lua and the `picocalc.*` API: no native code, no assets.

```
brick15/
  app.json          manifest (id net.picodeck.brick15, category games)
  icon.png          48x48 launcher icon (dev/make_icon.py draws it)
  main.lua          entry: module loader, game list, scene wiring, main loop
  lib/
    lcd.lua         palette, 3x5 font, 7-segment digits, tone sequencer, PAD.read
    grid.lua        the brick matrix: redraws only cells that changed
    panel.lua       the side panel: redraws only fields that changed
    screen.lua      owns grid + panel; flushes only the changed rows
    scores.lua      high scores, read once, saved only on a new record
    runner.lua      the play scene shared by every game
    menu.lua        the brick-style game selector
  games/            one rules-only module per game (contract: lib/runner.lua)
  dev/
    test/           desktop unit tests: lua dev/test/run.lua
    smoke.py        simulator smoke test: python3 dev/smoke.py [--only tetris,snake]
    make_icon.py    regenerates icon.png
  docs/             design spec and implementation plans
```

- **Unit tests:** `lua dev/test/run.lua` needs Lua 5.4.
- **Smoke test:** `python3 dev/smoke.py` needs a built PicoDeck simulator (`make simulator` in the picodeck repo) and Pillow. It looks for the picodeck checkout at `../picodeck`; set `PICODECK_ROOT` to use another location.
````

- [ ] **Step 6: Write `dev/make_icon.py` and regenerate the icon**

```python
#!/usr/bin/env python3
"""Draw icon.png (48x48): "15" in lit LCD bricks over a field of ghost bricks.

Usage: python3 dev/make_icon.py   (writes icon.png in the app folder)
Colours match lib/lcd.lua: BG, DARK and GHOST.
"""
from pathlib import Path
from PIL import Image, ImageDraw

BG, DARK, GHOST = (158, 168, 102), (24, 32, 14), (146, 156, 94)
PITCH = 6                     # 6px cells: 5x5 framed brick + 1px gap
COLS, ROWS = 7, 7             # brick field; "1" at cols 0-2, "5" at cols 4-6, rows 1-5
ORIGIN = (3, 3)               # top-left of the field inside the 2px frame

ONE = ["010", "110", "010", "010", "111"]
FIVE = ["111", "100", "111", "001", "111"]


def brick(d, x, y, colour):
    d.rectangle([x, y, x + 4, y + 4], outline=colour)          # 5x5 outline
    d.rectangle([x + 2, y + 2, x + 2, y + 2], fill=colour)     # 1px centre


def main():
    img = Image.new("RGB", (48, 48), BG)
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, 47, 47], outline=DARK)
    d.rectangle([1, 1, 46, 46], outline=DARK)
    lit = set()
    for glyph, col0 in ((ONE, 0), (FIVE, 4)):
        for r, bits in enumerate(glyph):
            for c, bit in enumerate(bits):
                if bit == "1":
                    lit.add((col0 + c, 1 + r))
    for r in range(ROWS):
        for c in range(COLS):
            x, y = ORIGIN[0] + c * PITCH + 1, ORIGIN[1] + r * PITCH + 1
            brick(d, x, y, DARK if (c, r) in lit else GHOST)
    out = Path(__file__).resolve().parents[1] / "icon.png"
    img.save(out)
    print("wrote", out)


if __name__ == "__main__":
    main()
```

Run: `python3 dev/make_icon.py`
Expected: `wrote …/icon.png`. The icon is 48×48 and shows "15" in lit framed bricks over ghost bricks, inside a 2px dark frame, on the LCD green. Open it and check it by eye.

- [ ] **Step 7: Run the whole suite and commit**

Run: `lua dev/test/run.lua`
Expected: `225 tests, 0 failed`

```bash
git add dev/test/test_app.lua dev/make_icon.py app.json README.md icon.png
git commit -m "Rename to BRICK-15: manifest, README, brick-style icon, acceptance tests"
```

---

### Task 17: Full smoke run and the visual-critic loop

**Files:**
- Modify: whatever the critic's findings require (each fix test-first).

**Interfaces:**
- Consumes: the whole app.
- Produces:
  - The critic reports.
  - A passing gate (overall ≥ 8 and every screen ≥ 7), or a stop reported under the visual-critic skill's rules.

- [ ] **Step 1: Run the full smoke test**

Run: `PICODECK_ROOT=../picodeck python3 dev/smoke.py --out <scratchpad>/p2-shots`
Expected: `SMOKE OK (15 games)`. Every game reaches its game-over screen; Memory gets there by being solved. There are 48 screenshots:
- `01-menu`, `02-menu-speed-2`;
- a hint, gameplay and game-over shot per game;
- `48-menu-after-play`.

If a game never reaches game over, first check that its FINISH steps can really lose that game. Then fix the game or the steps, test-first for game changes.

- [ ] **Step 2: Build the critic's screen set**

Load the visual-critic skill (`Skill: visual-critic`) and follow it exactly.
- **Screenshots:** copy these into a fresh scratchpad directory:
  - the menu (`01-menu`) and the menu after play;
  - all 15 `*-gameplay` shots;
  - the game-over shots for Tetris, Pong, Memory and Tank.
- **Manifest:** write `manifest.md` with one line per file: what screen and state it is, and that the image is a 3× nearest-neighbour upscale of the 320×320 display. Name only what is visible, never the intent.

- [ ] **Step 3: Dispatch the critic**

Follow the skill's routing:
- If `HERDR_ENV=1` and `wt` is on PATH, delegate to a non-Claude agent on its strongest model. As of 2026-09-27 that was `wt delegate agy "<brief>" --model gemini-3.1-pro-high`.
- Otherwise use a fresh `general-purpose` subagent on `opus`.

The brief is exactly four parts: `game`, the directory and manifest paths, the full text of the skill's `critic-prompt.md`, and the report path.

Before acting on any finding, check it against the pixels. In the phase 1 review a Gemini critic reported a GAME OVER panel drawn over by sprites that didn't exist. A finding you disagree with is one of the skill's stop-and-ask cases.

- [ ] **Step 4: Loop until the gate passes (at most 5 rounds)**

For each round:
1. Fix the highest-severity findings. Every behaviour change gets a failing unit test first.
2. Re-run `lua dev/test/run.lua` and the full smoke test.
3. Rebuild the whole screen set and re-dispatch the critic.

Stop and ask your human partner when:
- a fix needs a design decision;
- the same issue survives two rounds;
- you disagree with the critic;
- the score drops.

Commit each round's fixes with a message naming the findings.

- [ ] **Step 5: Hand the final critic report over unedited**

Keep the last report's path. It goes, unedited, into the final message to your human partner.

---

### Task 18: Acceptance check and the folder rename

**Files:**
- Move: the app folder `brick30/` → `brick15/` (the very last action).

**Interfaces:**
- Consumes: everything.
- Produces: evidence for each of the spec's acceptance criteria, and the renamed folder.

- [ ] **Step 1: Check each acceptance criterion with evidence**

Run each command and read the output:

| # | Criterion | Evidence |
|---|---|---|
| 1 | Games never call display, save or scene | `lua dev/test/run.lua dev/test/test_app.lua` passes ("games draw only through the grid"), and `grep -n "picocalc" games/*.lua` prints nothing |
| 2 | No scale-1 text, no t < 3 digits | `LCD.text` and `LCD.seg` assert on it (`test_lcd`), and the full smoke run hits every draw path without an error |
| 3 | The M, N, W (and 1) glyphs | `test_lcd`: "font: M, N and W use the fixed patterns" |
| 4 | Idle frames draw and flush nothing | `test_screen`/`test_runner`/`test_menu` idle tests, plus the smoke test's idle check on all 15 game-over screens |
| 5 | `save.get` only at startup, `save.set` only on a record | `grep -rn "save.get\|save.set" lib games main.lua` shows them only in `lib/scores.lua` and `main.lua`'s `Scores.new` call; `test_scores` |
| 6 | All 15 games play to game over with no Lua errors | Task 17's `SMOKE OK (15 games)` |
| 7 | The critic gate passes | Task 17's final report |
| 8 | Named BRICK-15, id `net.picodeck.brick15` | `test_app`: "the manifest is BRICK-15"; the folder rename below |

- [ ] **Step 2: Commit anything outstanding**

```bash
git status --short
```
Expected: clean. Commit any stragglers with a message saying what they are.

- [ ] **Step 3: Rename the folder (last action)**

Tell your human partner first:
- **Working directory:** this session's working directory is the folder being renamed.
- **Claude memory:** it is keyed by folder path (`~/.claude/projects/-home-keith-Projects-PicoDeck-brick30/`), so memories saved for this project won't load under the new path unless that directory is copied to `-home-keith-Projects-PicoDeck-brick15`.

Then:

```bash
cd /home/keith/Projects/PicoDeck && mv brick30 brick15
```
Expected: `/home/keith/Projects/PicoDeck/brick15` exists with its `.git`, and `git -C /home/keith/Projects/PicoDeck/brick15 status` works. No commit is needed: git doesn't track its own folder name.
