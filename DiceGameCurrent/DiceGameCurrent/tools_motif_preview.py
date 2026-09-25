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


def tiled(builder, columns, rows, lift, inset):
    """Stamps one shape across the floor on a grid.

    Three motifs were a single mark in the middle with bare field around
    it. A rolling area is looked at as a whole, so a mark that occupies
    only its centre reads as an object dropped on the floor rather than as
    a surface. `builder(cx, cy, size, lift)` returns the shapes for one
    cell; this places it in every cell.

    Odd rows are offset half a cell — a plain grid reads as wallpaper,
    and the stagger is what makes it read as a field.
    """
    out = []
    cw, ch = 1.0 / columns, 1.0 / rows
    size = min(cw, ch) * (1.0 - inset)
    for row in range(rows):
        for col in range(columns):
            shift = (cw / 2) if row % 2 else 0.0
            cx = (col + 0.5) * cw + shift
            cy = (row + 0.5) * ch
            if cx > 1.0 + cw / 4:
                continue
            out += builder(cx, cy, size, lift)
    return out


def seven_glyph(cx, cy, size, lift):
    """A numeral 7, sized to `size` and centred on (cx, cy)."""
    pts = [(0.26, 0.20), (0.76, 0.20), (0.76, 0.32), (0.55, 0.82),
           (0.40, 0.82), (0.60, 0.33), (0.26, 0.33)]
    bar = [(0.38, 0.52), (0.64, 0.52), (0.62, 0.59), (0.36, 0.59)]
    def place(p):
        return [(cx + (x - 0.5) * size, cy + (y - 0.5) * size) for x, y in p]
    return [poly(place(pts), lift), poly(place(bar), lift)]


def crown(cx, cy, size, lift):
    """Three points over a band, with a jewel on each point."""
    s = size
    body = [(-0.42, 0.12), (-0.30, -0.34), (-0.14, 0.00), (0.0, -0.42),
            (0.14, 0.00), (0.30, -0.34), (0.42, 0.12),
            (0.34, 0.34), (-0.34, 0.34)]
    out = [poly([(cx + x * s, cy + y * s) for x, y in body], lift)]
    for x, y in ((-0.30, -0.36), (0.0, -0.44), (0.30, -0.36)):
        out.append(circle(cx + x * s, cy + y * s, 0.075 * s, lift))
    # The band, a shade deeper so the crown does not read as one blob.
    out.append(poly([(cx - 0.36 * s, cy + 0.16 * s), (cx + 0.36 * s, cy + 0.16 * s),
                     (cx + 0.34 * s, cy + 0.30 * s), (cx - 0.34 * s, cy + 0.30 * s)],
                    DEEP * 0.55))
    return out


def die_face(cx, cy, size, lift):
    """Alternating d6 and d4 silhouettes — a square and a triangle.

    Free Roll is the sandbox that holds every die in the app, so its floor
    is dice. Two shapes rather than six: at this facet size a pentagon and
    a hexagon are the same blob and pips are a facet across, while a square
    beside a triangle is unmistakable. Which one a cell gets is fixed by
    its position, so the floor is stable rather than re-rolled each launch.
    """
    r = size * 0.42
    if (int(cx * 97) + int(cy * 61)) % 2 == 0:
        return [poly([(cx - r, cy - r), (cx + r, cy - r),
                      (cx + r, cy + r), (cx - r, cy + r)], lift)]
    h = r * 1.15
    return [poly([(cx, cy - h), (cx + h * 0.92, cy + h * 0.62),
                  (cx - h * 0.92, cy + h * 0.62)], lift)]


def bone_tile(cx, cy, size, lift):
    """A bone, or a pair of them crossed.

    Half the cells cross, chosen from the cell's own position so the floor
    is the same every launch. A field of single bones reads as scattered
    sticks; the crossed pairs are what make it read as bones."""
    length, thickness = size * 0.78, size * 0.17
    if (int(cx * 6) + int(cy * 3)) % 2:
        return (bone(cx, cy, length, thickness, 0.68, lift)
                + bone(cx, cy, length, thickness, -0.68, lift))
    angle = 0.6 if (int(cx * 47) + int(cy * 29)) % 2 else -0.6
    return bone(cx, cy, length, thickness, angle, lift)


def rect(x0, y0, x1, y1, lift):
    """An axis-aligned rectangle from two corners.

    Mirrors the Swift, which needed it: twenty rectangles written as four
    arithmetic corners each is what made `circuitBoard` un-type-checkable
    there. The shape of the two sources has to match for the verifier to
    compare them number for number, so it lives here too."""
    return poly([(x0, y0), (x1, y0), (x1, y1), (x0, y1)], lift)


def segment(x0, y0, x1, y1, w, lift):
    """A trace of any angle: a quad along the line, w wide."""
    dx, dy = x1 - x0, y1 - y0
    length = math.hypot(dx, dy) or 1.0
    nx, ny = -dy / length * w / 2, dx / length * w / 2
    return poly([(x0 + nx, y0 + ny), (x1 + nx, y1 + ny),
                 (x1 - nx, y1 - ny), (x0 - nx, y0 - ny)], lift)


def circuit_board(lift, deep):
    """One board, wired from the middle out.

    This was a 3x4 tiling of an L with a pad on it, and tiled marks do not
    connect to each other — so the floor read as scattered elbows rather
    than as a circuit. It is one layout now: a chip in the middle, eight
    bundles of three traces leaving it for the edges, and branches off
    those into pads, vias and smaller blocks, so the field between the
    trunks is wired too.

    A PCB does not route in straight radial lines, so each bundle steps
    sideways part way out and carries on — which is also what stops eight
    bundles from looking like a sunburst.

    Split into three functions to mirror the Swift, which had to be split:
    see `rect`."""
    out = chip(lift, deep)
    for k in range(8):
        out += bundle(k, lift, deep)
    return out


def chip(lift, deep):
    """The chip everything leaves from, and its pins."""
    half = 0.085
    out = [rect(0.5 - half, 0.5 - half, 0.5 + half, 0.5 + half, lift)]

    # Three pins a side, darker so the block is not one mass.
    outer = half + 0.030
    inner = half - 0.004
    for i in (-1, 0, 1):
        at = i * 0.048
        low = 0.5 + at - 0.011
        high = 0.5 + at + 0.011
        out.append(rect(low, 0.5 - outer, high, 0.5 - inner, deep))
        out.append(rect(low, 0.5 + inner, high, 0.5 + outer, deep))
        out.append(rect(0.5 - outer, low, 0.5 - inner, high, deep))
        out.append(rect(0.5 + inner, low, 0.5 + outer, high, deep))
    return out


def bundle(k, lift, deep):
    """One trunk: three traces to the edge, a via where they step across,
    two branches with pads, and a block out toward the corner."""
    w = 0.026
    jog = 0.055
    lane = jog * 0.62
    a = k * math.pi / 4
    ca, sa = math.cos(a), math.sin(a)

    def at(radius, offset):
        return (0.5 + radius * ca - offset * sa,
                0.5 + radius * sa + offset * ca)

    out = []

    for side in (-1, 0, 1):
        off = side * jog
        p0 = at(0.135, off)
        p1 = at(0.340, off)
        p2 = at(0.340, off + lane)
        p3 = at(0.880, off + lane)
        out.append(segment(p0[0], p0[1], p1[0], p1[1], w, lift))
        out.append(segment(p1[0], p1[1], p2[0], p2[1], w, lift))
        out.append(segment(p2[0], p2[1], p3[0], p3[1], w, lift))

    # A via where the middle lane turns.
    via = at(0.340, lane)
    out.append(ring(via[0], via[1], 0.044, 0.019, lift))

    # A chord to the next bundle, so the trunks are a network rather than
    # a sunburst: this is most of what makes the board read as connected
    # rather than as eight separate runs.
    nxt = a + math.pi / 4
    c0 = at(0.620, lane)
    c1x = 0.5 + 0.620 * math.cos(nxt) - lane * math.sin(nxt)
    c1y = 0.5 + 0.620 * math.sin(nxt) + lane * math.cos(nxt)
    out.append(segment(c0[0], c0[1], c1x, c1y, w, lift))

    # Two branches, at radii that alternate so eight bundles do not line
    # up into rings.
    near_radius = 0.470 if k % 2 else 0.410
    far_radius = 0.740 if k % 2 else 0.790
    for radius, side in ((near_radius, 1), (far_radius, -1)):
        base = at(radius, lane)
        tip = at(radius, lane + side * 0.130)
        out.append(segment(base[0], base[1], tip[0], tip[1], w, lift))
        out.append(circle(tip[0], tip[1], 0.030, lift))

    # A smaller block between this bundle and the next, so the space
    # between the trunks is wired rather than bare.
    b = a + math.pi / 8
    bx = 0.5 + 0.560 * math.cos(b)
    by = 0.5 + 0.560 * math.sin(b)
    out.append(rect(bx - 0.055, by - 0.032, bx + 0.055, by + 0.032, lift))
    for i in (-1, 0, 1):
        leg_x = bx + i * 0.034
        out.append(rect(leg_x - 0.010, by - 0.046, leg_x + 0.010, by - 0.028,
                        deep))

    # And a pad out toward the corner, on a stub off the same angle,
    # because the diagonals reach further than the axes do and the space
    # past the blocks was the one part of the floor left bare.
    sx = 0.5 + 0.830 * math.cos(b)
    sy = 0.5 + 0.830 * math.sin(b)
    out.append(segment(bx, by, sx, sy, w * 0.72, lift))
    out.append(ring(sx, sy, 0.040, 0.017, lift))
    return out


LIFT = 0.30
DEEP = -0.26


def motif(name):
    if name == "seven":
        return tiled(seven_glyph, 2, 3, LIFT, inset=0.14)

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
        return tiled(bone_tile, 2, 3, LIFT, inset=0.06)

    if name == "circuitry":
        return circuit_board(LIFT, DEEP)

    if name == "crowns":
        return tiled(crown, 2, 3, LIFT, inset=0.12)

    if name == "diceShapes":
        return tiled(die_face, 3, 4, LIFT, inset=0.0)

    return []


NAMES = ["seven", "pig", "stars", "circles", "waves", "bones",
         "circuitry", "crowns", "diceShapes"]

# Facets per side, per motif.
#
# A tiled mark is a fraction of the size of a centred one, and below about
# eight facets across a shape stops being that shape — the first tiled
# sevens read as arrows. The repeated motifs therefore get a finer grid;
# the four that stayed centred keep the 30 they were approved at.
GRIDS = {"seven": 52, "bones": 44, "circuitry": 60,
         "crowns": 52, "diceShapes": 44}


def motif_grid(name):
    return GRIDS.get(name, GRID)


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


def facets(name, grid=None, seed=20260101, variation=0.10):
    """Every triangle, as (points, shade delta). Mirrors the Swift loop."""
    shapes = motif(name)
    grid = grid or motif_grid(name)
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
