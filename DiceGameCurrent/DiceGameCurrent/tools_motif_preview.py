"""Draws each floor motif the way the Swift will, so it can be looked at.

The motifs are not decals painted over the floor — they are the FACETS
themselves, shaded a step lighter or darker. That is what keeps them in the
low-poly style rather than on top of it, and it is also what makes them
impossible to check by reading the code: a "7" is either legible in the
triangles or it is not.

There is no renderer in the container this was written in, so this is it.
`FloorMotif.swift` is the port of the geometry below, and
`tools_motif_verify.py` asserts the two agree.

    python3 tools_motif_preview.py            # every motif, as PNGs
    python3 tools_motif_preview.py seven      # just one
"""
import math
import os
import struct
import sys
import zlib

GRID = 30          # cells per side; each splits into two triangles
PIXELS = 300


# --- geometry, normalised to the unit square ------------------------------
#
# Every shape is (kind, params, lift). Lift is the tonal step applied to a
# facet whose CENTRE falls inside it: positive lightens, negative darkens.
# Later shapes win, so a nostril can sit on a snout that sits on a head.

def poly(points, lift):
    return ("poly", points, lift)


def circle(cx, cy, r, lift):
    return ("circle", (cx, cy, r), lift)


def ellipse(cx, cy, rx, ry, lift):
    return ("ellipse", (cx, cy, rx, ry), lift)


def ring(cx, cy, outer, inner, lift):
    return ("ring", (cx, cy, outer, inner), lift)


def star(cx, cy, r, lift, points=5, rotation=-math.pi / 2, inner=0.40):
    pts = []
    for i in range(points * 2):
        radius = r if i % 2 == 0 else r * inner
        a = rotation + i * math.pi / points
        pts.append((cx + radius * math.cos(a), cy + radius * math.sin(a)))
    return poly(pts, lift)


def bone(cx, cy, length, thickness, angle, lift):
    """A shaft with a pair of knobs at each end."""
    ca, sa = math.cos(angle), math.sin(angle)
    def at(u, v):
        return (cx + u * ca - v * sa, cy + u * sa + v * ca)
    half = length / 2
    knob = thickness * 0.62
    shapes = [poly([at(-half, -thickness / 2), at(half, -thickness / 2),
                    at(half, thickness / 2), at(-half, thickness / 2)], lift)]
    for end in (-half, half):
        for side in (-1, 1):
            c = at(end, side * knob * 0.55)
            shapes.append(circle(c[0], c[1], knob, lift))
    return shapes


def wave(y, amplitude, cycles, thickness, lift, samples=48):
    top, bottom = [], []
    for i in range(samples + 1):
        x = i / samples
        yy = y + amplitude * math.sin(2 * math.pi * cycles * x)
        top.append((x, yy - thickness / 2))
        bottom.append((x, yy + thickness / 2))
    return poly(top + bottom[::-1], lift)


def trace(x0, y0, x1, y1, w, lift):
    """An axis-aligned circuit trace."""
    if abs(y1 - y0) < 1e-9:
        return poly([(min(x0, x1), y0 - w / 2), (max(x0, x1), y0 - w / 2),
                     (max(x0, x1), y0 + w / 2), (min(x0, x1), y0 + w / 2)], lift)
    return poly([(x0 - w / 2, min(y0, y1)), (x0 + w / 2, min(y0, y1)),
                 (x0 + w / 2, max(y0, y1)), (x0 - w / 2, max(y0, y1))], lift)


LIFT = 0.30
DEEP = -0.26


def motif(name):
    if name == "seven":
        # One closed numeral, drawn as a polygon so the facets can carry it.
        return [poly([(0.26, 0.20), (0.76, 0.20), (0.76, 0.32),
                      (0.55, 0.82), (0.40, 0.82), (0.60, 0.33),
                      (0.26, 0.33)], LIFT),
                # The European crossbar, which also stops the diagonal
                # reading as a "1" at facet resolution.
                poly([(0.38, 0.52), (0.64, 0.52), (0.62, 0.59),
                      (0.36, 0.59)], LIFT)]

    if name == "pig":
        # Built to read like icon-hog.png: big upright ears, a broad head,
        # two slit eyes, and a LIGHT snout carrying two dark nostrils. The
        # snout being lighter than the head rather than darker is what
        # stopped it reading as an open mouth.
        shapes = []
        for side in (-1, 1):
            shapes.append(poly([(0.5 + side * 0.10, 0.42),
                                (0.5 + side * 0.20, 0.09),
                                (0.5 + side * 0.36, 0.26),
                                (0.5 + side * 0.34, 0.46)], LIFT))
        shapes.append(ellipse(0.5, 0.56, 0.325, 0.295, LIFT))
        for side in (-1, 1):
            shapes.append(ellipse(0.5 + side * 0.145, 0.47, 0.034, 0.056, DEEP))
        shapes.append(ellipse(0.5, 0.68, 0.162, 0.115, LIFT + 0.26))
        for side in (-1, 1):
            shapes.append(ellipse(0.5 + side * 0.058, 0.68, 0.027, 0.046, DEEP))
        return shapes

    if name == "stars":
        return [star(0.50, 0.46, 0.235, LIFT),
                star(0.17, 0.19, 0.105, LIFT),
                star(0.83, 0.19, 0.105, LIFT),
                star(0.15, 0.78, 0.120, LIFT),
                star(0.85, 0.78, 0.120, LIFT),
                star(0.50, 0.88, 0.090, LIFT)]

    if name == "circles":
        return [ring(0.5, 0.5, 0.46, 0.38, LIFT),
                ring(0.5, 0.5, 0.31, 0.23, LIFT),
                circle(0.5, 0.5, 0.15, LIFT)]

    if name == "waves":
        return [wave(y, 0.052, 2, 0.075, LIFT)
                for y in (0.18, 0.42, 0.66, 0.90)]

    if name == "bones":
        out = []
        for cx, cy, ln, th, ang in ((0.30, 0.26, 0.34, 0.075, 0.5),
                                    (0.72, 0.34, 0.30, 0.068, -0.7),
                                    (0.26, 0.70, 0.30, 0.068, -0.45),
                                    (0.68, 0.76, 0.34, 0.075, 0.6)):
            out += bone(cx, cy, ln, th, ang, LIFT)
        return out

    if name == "circuitry":
        w = 0.040
        out = []
        for x0, y0, x1, y1 in ((0.12, 0.22, 0.62, 0.22), (0.62, 0.22, 0.62, 0.50),
                               (0.62, 0.50, 0.88, 0.50), (0.24, 0.22, 0.24, 0.74),
                               (0.24, 0.74, 0.54, 0.74), (0.54, 0.74, 0.54, 0.90),
                               (0.40, 0.38, 0.88, 0.38), (0.76, 0.62, 0.76, 0.90),
                               (0.12, 0.54, 0.40, 0.54), (0.40, 0.54, 0.40, 0.38)):
            out.append(trace(x0, y0, x1, y1, w, LIFT))
        for px, py in ((0.62, 0.22), (0.62, 0.50), (0.24, 0.74), (0.54, 0.74),
                       (0.40, 0.38), (0.40, 0.54), (0.76, 0.62), (0.88, 0.50)):
            out.append(circle(px, py, 0.048, LIFT))
        return out

    return []


NAMES = ["seven", "pig", "stars", "circles", "waves", "bones", "circuitry"]


# --- containment ----------------------------------------------------------

def inside(shape, x, y):
    kind, p, _ = shape
    if kind == "circle":
        cx, cy, r = p
        return (x - cx) ** 2 + (y - cy) ** 2 <= r * r
    if kind == "ellipse":
        cx, cy, rx, ry = p
        return ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 <= 1
    if kind == "ring":
        cx, cy, outer, inner = p
        d2 = (x - cx) ** 2 + (y - cy) ** 2
        return inner * inner <= d2 <= outer * outer
    pts = p
    hit = False
    n = len(pts)
    for i in range(n):
        x0, y0 = pts[i]
        x1, y1 = pts[(i + 1) % n]
        if (y0 > y) != (y1 > y):
            xin = (x1 - x0) * (y - y0) / (y1 - y0) + x0
            if x < xin:
                hit = not hit
    return hit


def lift_at(shapes, x, y):
    """Last shape wins, so detail sits on top of the mass it belongs to."""
    value = 0.0
    for shape in shapes:
        if inside(shape, x, y):
            value = shape[2]
    return value


# --- the facets -----------------------------------------------------------

class Rng:
    """SplitMix64, matching SeededGenerator so the Swift can reproduce it."""
    def __init__(self, seed):
        self.state = seed & 0xFFFFFFFFFFFFFFFF

    def next(self):
        self.state = (self.state + 0x9E3779B97F4A7C15) & 0xFFFFFFFFFFFFFFFF
        z = self.state
        z = ((z ^ (z >> 30)) * 0xBF58476D1CE4E5B9) & 0xFFFFFFFFFFFFFFFF
        z = ((z ^ (z >> 27)) * 0x94D049BB133111EB) & 0xFFFFFFFFFFFFFFFF
        return z ^ (z >> 31)

    def unit(self):
        return self.next() / float(1 << 64)


def facets(name, grid=GRID, seed=20260101, variation=0.10):
    """Every triangle, as (points, shade delta). Mirrors the Swift loop."""
    shapes = motif(name)
    rng = Rng(seed)
    cell = 1.0 / grid
    out = []
    for row in range(grid):
        for col in range(grid):
            x, y = col * cell, row * cell
            tl, tr = (x, y), (x + cell, y)
            bl, br = (x, y + cell), (x + cell, y + cell)
            tris = ([[tl, tr, bl], [tr, br, bl]] if (row + col) % 2 == 0
                    else [[tl, tr, br], [tl, br, bl]])
            for tri in tris:
                delta = (rng.unit() * 2 - 1) * variation
                cx = sum(p[0] for p in tri) / 3
                cy = sum(p[1] for p in tri) / 3
                out.append((tri, delta + lift_at(shapes, cx, cy)))
    return out


# --- a PNG, drawn by scanline fill so nothing else is needed --------------

BASE = (0x2C, 0x5A, 0x3A)          # a mid table green, darkened like the floor


def shade(rgb, delta):
    if delta >= 0:
        return tuple(min(255, int(c + (255 - c) * delta)) for c in rgb)
    return tuple(max(0, int(c * (1 + delta))) for c in rgb)


def render(name, path, pixels=PIXELS):
    buf = bytearray()
    rows = [[BASE] * pixels for _ in range(pixels)]
    for tri, delta in facets(name):
        colour = shade(BASE, delta)
        px = [(p[0] * pixels, p[1] * pixels) for p in tri]
        ymin = max(0, int(min(p[1] for p in px)))
        ymax = min(pixels - 1, int(max(p[1] for p in px)) + 1)
        for yy in range(ymin, ymax + 1):
            sy = yy + 0.5
            xs = []
            for i in range(3):
                x0, y0 = px[i]
                x1, y1 = px[(i + 1) % 3]
                if (y0 > sy) != (y1 > sy):
                    xs.append((x1 - x0) * (sy - y0) / (y1 - y0) + x0)
            if len(xs) < 2:
                continue
            for xx in range(max(0, int(min(xs))), min(pixels - 1, int(max(xs)) + 1) + 1):
                rows[yy][xx] = colour

    for row in rows:
        buf.append(0)
        for r, g, b in row:
            buf += bytes((r, g, b))

    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", pixels, pixels, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(buf), 6))
    png += chunk(b"IEND", b"")
    open(path, "wb").write(png)
    return path


if __name__ == "__main__":
    out = os.environ.get("MOTIF_OUT", ".")
    wanted = sys.argv[1:] or NAMES
    for name in wanted:
        p = render(name, os.path.join(out, "motif-%s.png" % name))
        print("wrote %s  (%d facets)" % (p, len(facets(name))))
