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
        return self.report(game_ids)

    def report(self, game_ids):
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
