#!/usr/bin/env python3
"""Draw the app icon: a rectangle, a circle and a triangle laid over one another.

The three primitives are printed like three inks on paper — each overlap
multiplies, so the shapes darken where they cross instead of hiding one
another. That is what makes all three readable at once, and it is why the
colours are the app's own: paper, the grey of resting text, and the one
signal orange from `RamsTheme`.

Weight is deliberately uneven: the circle is the only filled colour, the
rectangle is a quiet field behind it, and the triangle is a line. Three
equal masses would fight; a field, a ground and a line do not.

    python3 Tools/make-icon.py <out.png>
"""
import sys
from PIL import Image, ImageDraw, ImageChops

SIZE = 1024
SUPERSAMPLE = 4          # the shapes are drawn hard-edged, then averaged down
SCALE = 1.07             # fills the tile without crowding iOS's rounded corner

PAPER  = (0xF4, 0xF3, 0xF0)   # RamsTheme.paper, light
RECT   = (0xC9, 0xC4, 0xBA)   # a shade off RamsTheme.hairline: still legible at 60 px
ORANGE = (0xDE, 0x4E, 0x0A)   # RamsTheme.accent, light
INK    = (0x1A, 0x1A, 0x1A)   # RamsTheme.ink, light

N = SIZE * SUPERSAMPLE
CENTRE = 512.0

RECTANGLE = (300, 247, 724, 841)
CIRCLE    = (242, 274, 782, 814)
TRIANGLE  = [(512, 184), (824, 724), (200, 724)]
LINE_RATIO = 0.875       # inner triangle; the gap between the two is the stroke


def place(value):
    """Scale about the centre, then into supersampled pixels."""
    return int(round((CENTRE + (value - CENTRE) * SCALE) * SUPERSAMPLE))


def stencil(draw_shape):
    mask = Image.new("L", (N, N), 0)
    draw_shape(ImageDraw.Draw(mask))
    return mask


def shrink(points, factor):
    cx = sum(p[0] for p in points) / 3.0
    cy = sum(p[1] for p in points) / 3.0
    return [(cx + (x - cx) * factor, cy + (y - cy) * factor) for x, y in points]


def main(out_path):
    rectangle = stencil(lambda d: d.rectangle([place(v) for v in RECTANGLE], fill=255))
    circle = stencil(lambda d: d.ellipse([place(v) for v in CIRCLE], fill=255))

    outer = stencil(lambda d: d.polygon([(place(x), place(y)) for x, y in TRIANGLE], fill=255))
    inner = stencil(lambda d: d.polygon(
        [(place(x), place(y)) for x, y in shrink(TRIANGLE, LINE_RATIO)], fill=255))
    triangle = ImageChops.subtract(outer, inner)

    art = Image.new("RGB", (N, N), PAPER)
    for mask, colour in ((rectangle, RECT), (circle, ORANGE), (triangle, INK)):
        inked = ImageChops.multiply(art, Image.new("RGB", (N, N), colour))
        art = Image.composite(inked, art, mask)

    # RGB, never RGBA: an app icon carrying an alpha channel is rejected.
    art.resize((SIZE, SIZE), Image.LANCZOS).save(out_path)
    print(f"wrote {out_path}")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "icon.png")
