#!/usr/bin/env python3
"""Generate Anode's checked-in signed-distance Prism legend atlas.

Development-only dependencies:
  python -m pip install Pillow==11.3.0 scipy==1.16.1 numpy==2.3.2

The runtime has no Python dependency. Keep GLYPHS, grid dimensions, and the
distance scale mirrored in prism_glyphs.dart and vfd.frag.
"""

from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy.ndimage import distance_transform_edt


ROOT = Path(__file__).resolve().parents[1]
FONT = ROOT / "assets/fonts/BarlowCondensed-MediumItalic.ttf"
OUTPUT = ROOT / "assets/shaders/prism_glyph_sdf.png"
GLYPHS = " ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789/.-+%?:"
CELL = 64
SCALE = 4
COLUMNS = 8
ROWS = 6
SPREAD = 8.0 * SCALE


def render_glyph(glyph: str, font: ImageFont.FreeTypeFont) -> Image.Image:
    high_cell = CELL * SCALE
    if glyph == " ":
        return Image.new("L", (CELL, CELL), 0)
    mask = Image.new("L", (high_cell, high_cell), 0)
    draw = ImageDraw.Draw(mask)
    bounds = draw.textbbox((0, 0), glyph, font=font, stroke_width=0)
    width = bounds[2] - bounds[0]
    height = bounds[3] - bounds[1]
    x = (high_cell - width) / 2 - bounds[0] - 1.5 * SCALE
    y = (high_cell - height) / 2 - bounds[1]
    draw.text((x, y), glyph, font=font, fill=255)

    inside = np.asarray(mask) >= 128
    inside_distance = distance_transform_edt(inside)
    outside_distance = distance_transform_edt(~inside)
    signed = inside_distance - outside_distance
    sdf = np.clip(0.5 + signed / (2.0 * SPREAD), 0.0, 1.0)
    encoded = Image.fromarray(np.uint8(np.rint(sdf * 255)))
    return encoded.resize((CELL, CELL), Image.Resampling.LANCZOS)


def main() -> None:
    font = ImageFont.truetype(str(FONT), 46 * SCALE)
    atlas = Image.new("L", (COLUMNS * CELL, ROWS * CELL), 0)
    for index, glyph in enumerate(GLYPHS):
        x = index % COLUMNS * CELL
        y = index // COLUMNS * CELL
        atlas.paste(render_glyph(glyph, font), (x, y))
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    atlas.save(OUTPUT, optimize=True)


if __name__ == "__main__":
    main()
