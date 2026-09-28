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
