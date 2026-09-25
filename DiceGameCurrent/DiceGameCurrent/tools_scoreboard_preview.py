"""Renders the Baseball Dice scoreboard so its alignment can be looked at.

The panel's labels went out of position once already, because the two draw
helpers were switched from advance metrics to ink metrics — a change that
is right for a renderer sizing its own canvas and wrong for one placing
text inside a canvas somebody else sized. Reading the code did not catch
it; a picture does immediately.

This is the same reason `tools_motif_preview.py` exists, and it renders a
PNG for the same reason: there is no renderer in this container, and a PNG
can at least be looked at.

    python3 tools_scoreboard_preview.py            # advance (shipped)
    python3 tools_scoreboard_preview.py --ink      # the broken version

Text is drawn as a block per glyph rather than in a real face — the point
is WHERE things sit, not what they look like. A block is honest about its
own advance box, which is exactly the thing being checked.
"""
import os
import re
import struct
import sys
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
SWIFT = os.path.join(HERE, "SwiftFiles", "BaseballField.swift")

WIDTH, HEIGHT = 820, 1100


def swift_constants():
    """Every `static let x: CGFloat = n` the panel is built from."""
    text = open(SWIFT).read()
    out = {}
    for m in re.finditer(r'static let (\w+):\s*CGFloat\s*=\s*(-?\d+(?:\.\d+)?)', text):
        out[m.group(1)] = float(m.group(2))
    return out


C = swift_constants()
BOARD_X, BOARD_Y, BOARD_W = C["boardX"], C["boardY"], C["boardW"]
PAD, HEAD_H = C["boardPad"], C["headHeight"]
GRID_GAP, ROW_H = C["gridGap"], C["rowHeight"]
OUTS_GAP, OUTS_H = C["outsGap"], C["outsHeight"]


def metrics():
    grid_top = BOARD_Y + HEAD_H + GRID_GAP
    rows_bottom = grid_top + 2 * ROW_H
    outs_top = rows_bottom + OUTS_GAP
    return grid_top, rows_bottom, outs_top, (outs_top + OUTS_H + PAD) - BOARD_Y


# --- a canvas -------------------------------------------------------------

class Canvas:
    def __init__(self, w, h, bg=(24, 24, 24)):
        self.w, self.h = w, h
        self.px = [[bg] * w for _ in range(h)]

    def rect(self, x, y, w, h, colour, fill=True):
        x0, y0 = int(x), int(y)
        x1, y1 = int(x + w), int(y + h)
        for yy in range(max(0, y0), min(self.h, y1)):
            for xx in range(max(0, x0), min(self.w, x1)):
                if fill or yy in (y0, y1 - 1) or xx in (x0, x1 - 1):
                    self.px[yy][xx] = colour

    def circle(self, cx, cy, r, colour, fill=True):
        for yy in range(max(0, int(cy - r)), min(self.h, int(cy + r) + 1)):
            for xx in range(max(0, int(cx - r)), min(self.w, int(cx + r) + 1)):
                d = ((xx - cx) ** 2 + (yy - cy) ** 2) ** 0.5
                if (d <= r) if fill else (r - 1.6 <= d <= r):
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


# --- text, as advance boxes ----------------------------------------------
#
# A glyph is a filled block 0.52em wide on a 1.0em line, with the ink
# sitting inside it the way a real glyph does: inset from the left, and
# from the top by the ascender. That inset is precisely what ink metrics
# would remove and advance metrics keep, so the two modes differ here in
# the same way they differ on device.

ADV = 0.52          # advance width per glyph, in em
INK_X = 0.09        # left side bearing, in em
INK_TOP = 0.26      # gap from the line's top to the ink, in em
INK_H = 0.50        # ink height, in em


def text_boxes(text, size):
    """(advance size, ink rect relative to the text origin)."""
    adv = (len(text) * ADV * size, size)
    ink = (INK_X * size, INK_TOP * size,
           max(0.0, len(text) * ADV - INK_X * 2) * size, INK_H * size)
    return adv, ink


def draw_text(canvas, text, origin=None, centre=None, size=12,
              colour=(255, 255, 255), use_ink=False):
    adv, ink = text_boxes(text, size)
    if centre is not None:
        if use_ink:
            x = centre[0] - ink[2] / 2 - ink[0]
            y = centre[1] - ink[3] / 2 - ink[1]
        else:
            x = centre[0] - adv[0] / 2
            y = centre[1] - adv[1] / 2
    else:
        x, y = origin
        if use_ink:
            x -= ink[0]
            y -= ink[1]
    for i, _ in enumerate(text):
        canvas.rect(x + (i * ADV + INK_X) * size, y + INK_TOP * size,
                    (ADV - INK_X * 1.6) * size, INK_H * size, colour)


# --- the panel ------------------------------------------------------------

def render(path, use_ink=False, innings=6, line_score=None, outs=2,
           current=3):
    line_score = line_score or [[0, 1, 0, 2, 0, 0], [1, 0, 3, 0, 0, 0]]
    c = Canvas(WIDTH, HEIGHT, bg=(123, 160, 126))
    grid_top, rows_bottom, outs_top, height = metrics()

    def px(v): return v * WIDTH
    def py(v): return v * HEIGHT

    c.rect(px(BOARD_X), py(BOARD_Y), px(BOARD_W), py(height), (17, 17, 17))

    label_w = 0.050
    grid_x = BOARD_X + label_w
    cell_w = (BOARD_W - label_w - 0.012) / innings

    draw_text(c, "INNING", centre=(px(BOARD_X + BOARD_W / 2), py(BOARD_Y + 0.023)),
              size=px(0.028), use_ink=use_ink)

    header_y = py(grid_top - GRID_GAP / 2)
    for i in range(innings):
        draw_text(c, str(i + 1),
                  centre=(px(grid_x + cell_w * (i + 0.5)), header_y),
                  size=px(0.024), use_ink=use_ink)

    for row, name in enumerate(["V", "H"]):
        top = grid_top + row * ROW_H
        draw_text(c, name,
                  centre=(px(BOARD_X + label_w / 2), py(top + ROW_H * 0.42)),
                  size=px(0.028), use_ink=use_ink)
        for i in range(innings):
            bx, by = px(grid_x + cell_w * i), py(top)
            bw, bh = px(cell_w), py(ROW_H * 0.84)
            c.rect(bx, by, bw, bh,
                   (243, 217, 164) if i + 1 == current else (233, 233, 233))
            c.rect(bx, by, bw, bh, (17, 17, 17), fill=False)
            if i < len(line_score[row]):
                draw_text(c, str(line_score[row][i]),
                          centre=(bx + bw / 2, by + bh / 2),
                          size=px(0.026), colour=(17, 17, 17), use_ink=use_ink)

    centre_y = py(outs_top + OUTS_H / 2)
    draw_text(c, "OUTS", centre=(px(BOARD_X + 0.094), centre_y),
              size=px(0.030), use_ink=use_ink)
    for i in range(3):
        cx = px(BOARD_X + 0.175 + i * 0.072)
        if i < outs:
            c.circle(cx, centre_y, px(0.024), (217, 70, 62))
        c.circle(cx, centre_y, px(0.024), (255, 255, 255), fill=False)

    # Crop to the panel with a margin, so the picture is the thing checked.
    top = int(py(BOARD_Y) - 20)
    bottom = int(py(BOARD_Y + height) + 20)
    left, right = int(px(BOARD_X) - 20), int(px(BOARD_X + BOARD_W) + 20)
    crop = Canvas(right - left, bottom - top)
    crop.px = [row[left:right] for row in c.px[top:bottom]]
    crop.write(path)
    return path


if __name__ == "__main__":
    ink = "--ink" in sys.argv
    out = os.environ.get("BOARD_OUT", ".")
    name = "scoreboard-ink.png" if ink else "scoreboard-advance.png"
    print("wrote", render(os.path.join(out, name), use_ink=ink))
