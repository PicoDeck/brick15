# BRICK-30

**15 classic LCD brick games in one cart** — a mini game collection for [PicoDeck](https://github.com/PicoDeck/picodeck) (ClockworkPi PicoCalc v2.0), styled after the cheap green-LCD brick-game consoles: monochrome gray-green palette, chunky pixels, 7-segment score digits, and square-wave beeps.

## Games

| # | Game | # | Game |
|---|------|---|------|
| 01 | Tetris | 09 | Asteroids |
| 02 | Snake | 10 | Memory |
| 03 | Breakout | 11 | Simon |
| 04 | Space Invaders | 12 | Tic-Tac-Toe (vs AI) |
| 05 | Frogger | 13 | Moon Lander |
| 06 | Racer | 14 | Missile Command |
| 07 | Pong (vs AI) | 15 | Tank |
| 08 | Copter | | |

## Controls (shared)

- **D-pad** — move / steer / navigate
- **Enter** — start / confirm / rotate / fire / serve
- **Up** — rotate (Tetris), thrust, fire (Invaders)
- **F1** — secondary action (fire / rotate / serve)
- **Esc** — back to menu · **Esc** at menu exits to the launcher

High scores are saved per game (persistent across sessions) and shown in the menu.

## Install

Copy the `brick30/` directory to `/apps/brick30/` on the PicoDeck SD card
(or stage it with the `push_app` MCP tool). It appears in the launcher under **BRICK-30**.

`app.json` declares the `audio` requirement (tone beeps).

## Develop

Pure Lua + the `picocalc.*` API — no native code, no assets. Layout:

```
brick30/
  app.json          manifest (id net.picodeck.brick30, category games)
  icon.png          48x48 launcher icon
  main.lua          entry: module loader, game registry, scene loop
  lib/
    loader.lua      load_module (fs.open + load; require/dofile are blocked)
    lcd.lua         palette, 3x5 font, 7-segment digits, tone sequencer, input
    menu.lua        collection menu scene
  games/            one self-contained scene module per game
```

Each game is a factory returning a scene table `{ enter, update, draw, exit }`
(wired through `picocalc.game.scene`). Shared helpers live in `lib/lcd.lua`
(globals `LCD`, `SFX`, `PAD`).

Test with the PicoDeck simulator: stage into `picodeck/simulator/assets/sd_card/apps/`
and run `pytest tests/e2e` or drive `build_sim/picodeck_simulator` directly.
