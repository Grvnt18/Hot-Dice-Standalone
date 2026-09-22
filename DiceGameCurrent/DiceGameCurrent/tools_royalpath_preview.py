"""Renders the Royal Path board to an SVG, from the same arithmetic the
shipped SwiftUI draws it with.

There is no Swift toolchain, iOS SDK or display in this container, so board
art cannot be checked by building it. This mirrors RoyalPathLayout and the
markings in RoyalPathBoardView.swift — the same tile/gap/margin ratios, the
same square list, the same motif geometry — so the proportions, the missing
bridge corners and the rosette placement can at least be looked at before
the iPad sees them.

It is a preview, not a pixel match: the SVG uses flat fills where the app
uses its faceted low-poly texture and tiled timber.

    python3 tools_royalpath_preview.py > board.svg
"""
import math
import sys

INK = "#1B2A4A"
PETAL_RED = "#DB362C"
TILE = "#F4EDDF"
FRAME = "#6C4B2C"          # the app's #8B6039 timber under 22% black
SEAT_COLOR = {0: PETAL_RED, 1: INK}

ROWS, COLUMNS = 3, 8
ROSETTES = {(1, 1), (3, 1), (2, 4), (1, 7), (3, 7)}
SQUARES = [
    (r, c) for r in range(1, ROWS + 1) for c in range(1, COLUMNS + 1)
    if not (c in (5, 6) and r != 2)
]
BOTTOM_PATH = [
    (3, 4), (3, 3), (3, 2), (3, 1), (2, 1), (2, 2), (2, 3), (2, 4),
    (2, 5), (2, 6), (2, 7), (1, 7), (1, 8), (2, 8), (3, 8), (3, 7),
]


def decor(square):
    if square in ROSETTES:
        return "rosette"
    if square == (2, 1):
        return "squaresGrid"
    if square in {(2, 3), (2, 6)}:
        return "dottedField"
    if square in {(1, 8), (3, 8)}:
        return "zigzagFive"
    if square in {(1, 2), (3, 2), (1, 4), (3, 4), (2, 7)}:
        return "eyes"
    return "fiveDots"


class Layout:
    """RoyalPathLayout."""

    def __init__(self, width):
        self.tile = width / 8.92
        self.gap = self.tile * 0.08
        self.margin = self.tile * 0.18
        self.width = self.tile * 8.92
        self.height = self.tile * 3.52

    def rect(self, square):
        row, column = square
        return (
            self.margin + (column - 1) * (self.tile + self.gap),
            self.margin + (row - 1) * (self.tile + self.gap),
            self.tile,
            self.tile,
        )


def inset(rect, dx, dy):
    x, y, w, h = rect
    return (x + dx, y + dy, w - dx * 2, h - dy * 2)


def ring(cx, cy, r):
    return (
        f'<circle cx="{cx:.1f}" cy="{cy:.1f}" r="{r:.1f}" fill="none" '
        f'stroke="{INK}" stroke-width="{max(1, r * 0.24):.1f}"/>'
        f'<circle cx="{cx:.1f}" cy="{cy:.1f}" r="{r * 0.48:.1f}" fill="{INK}"/>'
    )


def zigzag(x0, y0, x1, y1, teeth, amp):
    dx, dy = (x1 - x0) / teeth, (y1 - y0) / teeth
    length = max(math.hypot(dx, dy), 1e-4)
    nx, ny = -dy / length * amp, dx / length * amp
    points = [(x0, y0)]
    for step in range(1, teeth + 1):
        x, y = x0 + dx * step, y0 + dy * step
        sign = 1 if step % 2 == 0 else -1
        points.append((x - dx / 2 + nx * sign, y - dy / 2 + ny * sign))
        points.append((x, y))
    d = " ".join(("M" if i == 0 else "L") + f"{p[0]:.1f},{p[1]:.1f}"
                 for i, p in enumerate(points))
    return d


def marking(kind, rect):
    x, y, w, h = rect
    px = lambda f: x + w * f
    py = lambda f: y + h * f
    out = []

    if kind == "rosette":
        cx, cy = x + w / 2, y + h / 2
        outer, inner = w * 0.50, w * 0.50 * 0.46
        points = []
        for i in range(16):
            a = i * math.pi / 8 - math.pi / 2
            r = outer if i % 2 == 0 else inner
            points.append(f"{cx + math.cos(a) * r:.1f},{cy + math.sin(a) * r:.1f}")
        out.append(f'<polygon points="{" ".join(points)}" fill="#FFFFFF" '
                   f'fill-opacity="0.9" stroke="{INK}" stroke-width="{w * 0.03:.1f}"/>')
        for i in range(8):
            a = i * math.pi / 4 - math.pi / 2
            spread = math.pi / 8
            pts = [
                (cx, cy),
                (cx + math.cos(a - spread) * inner, cy + math.sin(a - spread) * inner),
                (cx + math.cos(a) * outer * 0.92, cy + math.sin(a) * outer * 0.92),
                (cx + math.cos(a + spread) * inner, cy + math.sin(a + spread) * inner),
            ]
            fill = PETAL_RED if i % 2 == 0 else INK
            out.append('<polygon points="%s" fill="%s"/>' % (
                " ".join(f"{p[0]:.1f},{p[1]:.1f}" for p in pts), fill))
        out.append(f'<circle cx="{cx:.1f}" cy="{cy:.1f}" r="{w * 0.06:.1f}" '
                   f'fill="#FFFFFF" fill-opacity="0.9"/>')

    elif kind == "eyes":
        line = max(1, w * 0.022)
        for fx in (0.26, 0.74):
            for fy in (0.28, 0.72):
                cx, cy = px(fx), py(fy)
                hh, bulge = h * 0.19, w * 0.14
                out.append(
                    f'<path d="M{cx:.1f},{cy - hh:.1f} '
                    f'Q{cx + bulge:.1f},{cy:.1f} {cx:.1f},{cy + hh:.1f} '
                    f'Q{cx - bulge:.1f},{cy:.1f} {cx:.1f},{cy - hh:.1f}" '
                    f'fill="none" stroke="{INK}" stroke-width="{line:.1f}"/>')
                out.append(f'<circle cx="{cx:.1f}" cy="{cy:.1f}" r="{w * 0.045:.1f}" fill="{INK}"/>')
        for fx in (0.45, 0.55):
            out.append(f'<line x1="{px(fx):.1f}" y1="{py(0.06):.1f}" x2="{px(fx):.1f}" '
                       f'y2="{py(0.94):.1f}" stroke="{INK}" stroke-opacity="0.75" '
                       f'stroke-width="{line:.1f}"/>')

    elif kind == "fiveDots":
        r = w * 0.125
        for fx, fy in ((0.27, 0.27), (0.73, 0.27), (0.5, 0.5), (0.27, 0.73), (0.73, 0.73)):
            out.append(ring(px(fx), py(fy), r))

    elif kind == "dottedField":
        amp = w * 0.05
        corners = [(x, y), (x + w, y), (x + w, y + h), (x, y + h)]
        for i in range(4):
            a, b = corners[i], corners[(i + 1) % 4]
            out.append(f'<path d="{zigzag(a[0], a[1], b[0], b[1], 5, amp)}" fill="none" '
                       f'stroke="{INK}" stroke-opacity="0.85" stroke-width="{max(1, w * 0.022):.1f}"/>')
        ix, iy, iw, ih = inset(rect, w * 0.16, h * 0.16)
        r = w * 0.032
        for row in range(4):
            for col in range(4):
                out.append(f'<circle cx="{ix + iw * (col + 0.5) / 4:.1f}" '
                           f'cy="{iy + ih * (row + 0.5) / 4:.1f}" r="{r:.1f}" fill="{INK}"/>')

    elif kind == "squaresGrid":
        cell = w / 3
        for row in range(3):
            for col in range(3):
                bx, by, bw, bh = inset(
                    (x + col * cell, y + row * cell, cell, cell), cell * 0.16, cell * 0.16)
                out.append(f'<rect x="{bx:.1f}" y="{by:.1f}" width="{bw:.1f}" height="{bh:.1f}" '
                           f'fill="none" stroke="{INK}" stroke-opacity="0.8" '
                           f'stroke-width="{max(1, w * 0.018):.1f}"/>')
                out.append(f'<circle cx="{bx + bw / 2:.1f}" cy="{by + bh / 2:.1f}" '
                           f'r="{cell * 0.13:.1f}" fill="{INK}"/>')

    elif kind == "zigzagFive":
        amp, line = w * 0.06, max(1, w * 0.022)
        for a, b in (((x, y), (x + w, y + h)), ((x + w, y), (x, y + h))):
            out.append(f'<path d="{zigzag(a[0], a[1], b[0], b[1], 4, amp)}" fill="none" '
                       f'stroke="{INK}" stroke-opacity="0.85" stroke-width="{line:.1f}"/>')
        r = w * 0.075
        for fx, fy in ((0.5, 0.16), (0.16, 0.5), (0.5, 0.5), (0.84, 0.5), (0.5, 0.84)):
            out.append(f'<circle cx="{px(fx):.1f}" cy="{py(fy):.1f}" r="{r:.1f}" fill="{INK}"/>')

    return "".join(out)


def piece(cx, cy, r, seat):
    return (
        f'<circle cx="{cx:.1f}" cy="{cy:.1f}" r="{r * 1.12:.1f}" fill="#000000" fill-opacity="0.25"/>'
        f'<circle cx="{cx:.1f}" cy="{cy:.1f}" r="{r:.1f}" fill="{SEAT_COLOR[seat]}" '
        f'stroke="#FFFFFF" stroke-opacity="0.9" stroke-width="{max(1, r * 0.16):.1f}"/>'
        f'<circle cx="{cx:.1f}" cy="{cy:.1f}" r="{r * 0.66:.1f}" fill="none" '
        f'stroke="#FFFFFF" stroke-opacity="0.65" stroke-width="{max(1, r * 0.12):.1f}"/>'
    )


def render(width=1100, pieces=((0, 8), (0, 16), (1, 11), (1, 4))):
    layout = Layout(width)
    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{layout.width:.0f}" '
        f'height="{layout.height:.0f}" viewBox="0 0 {layout.width:.1f} {layout.height:.1f}">',
        f'<rect x="0" y="0" width="{layout.width:.1f}" height="{layout.height:.1f}" '
        f'rx="{layout.tile * 0.14:.1f}" fill="{FRAME}" stroke="#000000" '
        f'stroke-opacity="0.45" stroke-width="2"/>',
    ]
    for square in SQUARES:
        x, y, w, h = layout.rect(square)
        parts.append(f'<rect x="{x:.1f}" y="{y:.1f}" width="{w:.1f}" height="{h:.1f}" '
                     f'rx="{layout.tile * 0.08:.1f}" fill="{TILE}" stroke="{INK}" '
                     f'stroke-opacity="0.75" stroke-width="1.5"/>')
        parts.append(marking(decor(square), inset((x, y, w, h), w * 0.09, h * 0.09)))
    for seat, index in pieces:
        path = BOTTOM_PATH if seat == 0 else [(ROWS + 1 - r, c) for r, c in BOTTOM_PATH]
        x, y, w, h = layout.rect(path[index - 1])
        parts.append(piece(x + w / 2, y + h / 2, layout.tile * 0.30, seat))
    parts.append("</svg>")
    return "".join(parts)


if __name__ == "__main__":
    sys.stdout.write(render())
