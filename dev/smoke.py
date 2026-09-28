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
