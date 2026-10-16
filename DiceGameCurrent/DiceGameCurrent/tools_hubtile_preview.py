"""Draws a hub tile so the name's width against the icon can be looked at.

"Make the text match the width of the icons" is not answerable from
arithmetic — it depends on how wide a given name actually sets. This draws
the tile at real device widths with the real names, using the same
block-glyph stand-in `tools_scoreboard_preview.py` uses: a block is honest
about its own advance, which is the thing being measured.

    python3 tools_hubtile_preview.py
"""
import os
import re
import struct
import sys
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from tools_hublayout_verify import layout, label_formula   # noqa: E402
from tools_swiftconst import constant, source              # noqa: E402

# Mean advance per character, measured over the NAMES below rather than
# estimated — parse each face's hmtx and cmap and average what these exact
# strings actually cost:
#
#   Poppins Regular         0.535 em
#   Poppins SemiBold        0.551 em   <- the hub labels
#
# This preview exists to predict whether a name spans its icon, and an ADV
# that is too small under-predicts wrapping, so it is measured rather than
# estimated — the value here was once 0.46, optimistic by 8% against the
# face it was written for.
ADV = 0.55
NAMES = ["Baseball Dice", "Rolls", "Jackpot", "HOG", "Generals",
         "Three Thousand", "F.Y.D.", "Royal UR",
         "Rollbots", "Boneheads", "Free Roll"]


def constants():
    text = source("GameHubView.swift")
    c = {n: constant(text, n) for n in
         ("gutter", "columnGap", "columnCount", "maxTile", "inset", "gap")}
    c.update(label_formula(text))
    return c


class Canvas:
    def __init__(self, w, h, bg):
        self.w, self.h = w, h
        self.px = [[bg] * w for _ in range(h)]

    def rect(self, x, y, w, h, colour):
        for yy in range(max(0, int(y)), min(self.h, int(y + h))):
            for xx in range(max(0, int(x)), min(self.w, int(x + w))):
                self.px[yy][xx] = colour

    def write(self, path):
        raw = bytearray()
        for row in self.px:
            raw.append(0)
            for r, g, b in row:
                raw += bytes((r, g, b))
        def chunk(tag, data):
            c = struct.pack(">I", len(data)) + tag + data
            return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        png = b"\x89PNG\r\n\x1a\n"
        png += chunk(b"IHDR", struct.pack(">IIBBBBB", self.w, self.h, 8, 2, 0, 0, 0))
        png += chunk(b"IDAT", zlib.compress(bytes(raw), 6))
        png += chunk(b"IEND", b"")
        open(path, "wb").write(png)


def wrap(name, font, max_width):
    """Two lines at most, the way lineLimit(2) does."""
    words = name.split()
    if len(words) < 2 or len(name) * ADV * font <= max_width:
        return [name]
    best, mid = None, len(words) // 2
    for split in range(1, len(words)):
        a = " ".join(words[:split])
        b = " ".join(words[split:])
        score = abs(len(a) - len(b)) + abs(split - mid)
        if best is None or score < best[0]:
            best = (score, [a, b])
    return best[1]


def render(path, width, scale=2):
    c = constants()
    count, tile, icon, font = layout(c, width)
    label = font * c["labelLines"]

    cols, rows = 2, 6
    grid_w = tile * cols + c["columnGap"]
    cw = int((grid_w + c["gutter"] * 2) * scale)
    ch = int((tile * rows + 24) * scale)
    canvas = Canvas(cw, ch, (139, 96, 57))            # the timber

    for index, name in enumerate(NAMES):
        col, row = index % 2, index // 2
        x = (c["gutter"] + col * (tile + c["columnGap"])) * scale
        y = (12 + row * tile) * scale

        # The tile's bounds, as a faint guide only — nothing is drawn
        # around a tile on device any more.
        for t in range(2):
            canvas.rect(x + t, y + t, tile * scale - t * 2, 1, (150, 110, 72))
            canvas.rect(x + t, y + tile * scale - t, tile * scale - t * 2, 1,
                        (150, 110, 72))

        ix = x + (tile - icon) / 2 * scale
        iy = y + c["inset"] * scale
        canvas.rect(ix, iy, icon * scale, icon * scale, (34, 34, 34))

        lines = wrap(name, font, icon)
        ly = iy + (icon + c["gap"]) * scale
        for li, line in enumerate(lines):
            shrink = min(1.0, icon / max(1.0, len(line) * ADV * font))
            size = font * max(0.6, shrink)
            w = len(line) * ADV * size
            lx = x + (tile - w) / 2 * scale
            for gi in range(len(line)):
                if line[gi] == " ":
                    continue
                canvas.rect(lx + (gi * ADV + 0.06) * size * scale,
                            ly + li * size * 1.2 * scale,
                            (ADV - 0.14) * size * scale, size * 0.62 * scale,
                            (255, 255, 255))
    canvas.write(path)
    return path, tile, icon, font


if __name__ == "__main__":
    out = os.environ.get("TILE_OUT", ".")
    for w in (320, 393):
        p, tile, icon, font = render(os.path.join(out, "hubtile-%d.png" % w), w)
        print("wrote %s  tile %.0f, icon %.0f, name %.1fpt" % (p, tile, icon, font))
