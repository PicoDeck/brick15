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
