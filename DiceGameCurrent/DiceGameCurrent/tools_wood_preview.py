"""Draws the tray timber the way the Swift will, so it can be looked at.

The wood is the frame around everything: the 3D rim of the tray and, tiled at
the same scale, the SwiftUI header behind the score and the footer behind the
roll button. It has to read as ONE piece of timber across that join, which is
the whole reason the tray and the score area look like one object rather than
two panels stacked.

What it is aiming at came from the reference images, and one number in it was
measured rather than chosen: the low-poly table set's PNG is 8-bit colormapped,
so its palette could be read directly, and its plank tone clusters tightly
around #AE7B5B. That is noticeably lighter and more orange than the #8B6039
this app has been using — the difference between furniture and a game object.

Four tones, like the floor, and for the same reason: flat regions with hard
edges between them read as drawn, where a continuous ramp reads as rendered.

    python3 tools_wood_preview.py           # the tile, and a tray using it
"""
import math
import os
import struct
import sys
import zlib

# --- the constants the Swift is built from -------------------------------

BASE_HEX = "AE7B5B"     # measured off the low-poly reference, not picked

TILE_W = 1024           # 4:1, which the rim's world-mapped UVs assume
TILE_H = 256

TILE_FRACTION = 0.75    # of the view width, and of the playfield width on the
                        # 3D rim. MUST be the same number in both or a seam
                        # appears exactly where the score panel meets the tray.

PLANKS = 3              # was 5. Five boards tiled at the old 0.4 of the view
                        # width put each one at about 2% of the screen, which
                        # reads as veneer or wicker — furniture scale. Three
                        # boards at 0.75 read as a tray you could pick up,
                        # which is what the references show.
BEVEL = 3               # px of lit edge along the top of each plank, before
SHADE_EDGE = 2          # PLANK_BEVEL/PLANK_SHADE vary it per board
SEAM = 2                # px of hard outline between boards

GRAIN_PER_PLANK = 2     # long curved swooshes, NOT evenly spaced straight
GRAIN_AMPLITUDE = 6.0   # lines — the clearest single difference between the
GRAIN_CYCLES = 1.3      # hand-painted reference wood and generic plank art
GRAIN_THICK = 2         # 1px reads as a scratch; 2 reads as painted grain

# Boards are told apart by the WIDTH of their chamfer bands, not by colour.
#
# The first attempt dithered a sparse veil of the neighbouring tone across
# each plank face to lean it darker or paler. It works on the floor, where the
# field underneath is already broken up, and it failed badly here: over a flat
# fill it reads as a regular dotted grid — fabric, or a print screen, not
# timber. Varying how much of each board is lit edge and how much is shadowed
# edge gives the same tonal spread with nothing repeating.
PLANK_BEVEL = (3, 1, 5)
PLANK_SHADE = (2, 5, 1)

KNOT_CHANCE = 45        # 1 in N shard columns carries a knot
KNOT_R = 5

# The four tones, as offsets from the base in HSB. Fixed rather than derived
# per plank: with only four tones there is no room for per-plank COLOUR, so
# boards are told apart by their grain and knots instead, which is how
# the pixel-art references do it anyway.
HILITE = (0.22, -0.16)  # (brightness up, saturation down)
SHADOW = (-0.26, 0.13)
OUTLINE = (-0.50, 0.06)


def hex_rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


def rgb_to_hsb(r, g, b):
    mx, mn = max(r, g, b), min(r, g, b)
    d = mx - mn
    s = 0.0 if mx == 0 else d / mx
    if d == 0:
        h = 0.0
    elif mx == r:
        h = ((g - b) / d) % 6.0
    elif mx == g:
        h = (b - r) / d + 2.0
    else:
        h = (r - g) / d + 4.0
    return h / 6.0, s, mx


def hsb_to_rgb(h, s, v):
    i = int(h * 6.0) % 6
    f = h * 6.0 - math.floor(h * 6.0)
    p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
    return [(v, t, p), (q, v, p), (p, v, t),
            (p, q, v), (t, p, v), (v, p, q)][i]


def shift(rgb, dv, ds):
    h, s, v = rgb_to_hsb(*rgb)
    r, g, b = hsb_to_rgb(h, min(1.0, max(0.0, s + ds)),
                         min(1.0, max(0.0, v + dv)))
    return (int(r * 255 + .5), int(g * 255 + .5), int(b * 255 + .5))


def palette(base_hex=BASE_HEX):
    """outline, shadow, base, highlight — darkest first, like the floor."""
    rgb = hex_rgb(base_hex)
    base = tuple(int(c * 255 + .5) for c in rgb)
    return [shift(rgb, *OUTLINE), shift(rgb, *SHADOW), base, shift(rgb, *HILITE)]


OUT, SHD, BSE, HIL = 0, 1, 2, 3


# --- a deterministic generator, matching SeededGenerator's shape ---------

class Rng:
    """Same splitmix64 the Swift side uses, so both draw the same plank."""

    def __init__(self, seed):
        self.state = seed & 0xFFFFFFFFFFFFFFFF

    def next(self):
        self.state = (self.state + 0x9E3779B97F4A7C15) & 0xFFFFFFFFFFFFFFFF
        z = self.state
        z = ((z ^ (z >> 30)) * 0xBF58476D1CE4E5B9) & 0xFFFFFFFFFFFFFFFF
        z = ((z ^ (z >> 27)) * 0x94D049BB133111EB) & 0xFFFFFFFFFFFFFFFF
        return z ^ (z >> 31)

    def unit(self):
        # Bit-for-bit as SeededGenerator.nextUnit: drop the low 11 bits and
        # scale by 2^-53, filling a Double's mantissa exactly once. Dividing
        # the raw 64 bits instead is also uniform and would place every knot
        # and grain line somewhere else, so the preview would stop being a
        # preview of the thing that ships.
        return (self.next() >> 11) * (1.0 / 9007199254740992.0)

    def below(self, n):
        return self.next() % n


# --- the tile ------------------------------------------------------------

def render_tile(w=TILE_W, h=TILE_H, seed=77123):
    """Indices into `palette()`, one per pixel. Everything snaps to whole
    pixels: a grain line at a fractional y would antialias into a fifth and
    sixth tone and the whole point is that there are four."""
    px = [[BSE] * w for _ in range(h)]
    rng = Rng(seed)
    plank_h = h // PLANKS

    for p in range(PLANKS):
        top = p * plank_h
        bot = top + plank_h

        # The seam goes down FIRST, and the bevel starts below it. Painted the
        # other way round — bevel, then seam over the top of it — the seam
        # simply erases the lit edge, which is what the first pass did: every
        # board came out flat and the chamfer was nowhere on screen.
        for y in range(top, min(top + SEAM, h)):
            for x in range(w):
                px[y][x] = OUT

        # Chamfer: lit along the top edge, shadowed along the bottom. This is
        # what gives a flat quad the look of a board with thickness, which
        # matters here because the rim genuinely has none — it is four flat
        # quads under an orthographic camera.
        bevel = PLANK_BEVEL[p % len(PLANK_BEVEL)]
        shade_edge = PLANK_SHADE[p % len(PLANK_SHADE)]

        inner_top = top + SEAM
        for y in range(inner_top, min(inner_top + bevel, h)):
            for x in range(w):
                px[y][x] = HIL
        for y in range(max(inner_top, bot - shade_edge), min(bot, h)):
            for x in range(w):
                px[y][x] = SHD

        face_top = inner_top + bevel
        face_bot = bot - shade_edge

        # Grain: a few long, slowly curving swooshes rather than straight
        # lines. Each one starts and ends somewhere different along the board.
        for _ in range(GRAIN_PER_PLANK):
            span = max(1, face_bot - face_top - GRAIN_THICK)
            gy = face_top + rng.below(span)
            phase = rng.unit() * math.tau
            x0 = rng.below(w)
            length = w // 2 + rng.below(w // 2)
            for i in range(length):
                x = (x0 + i) % w
                off = GRAIN_AMPLITUDE * math.sin(phase + GRAIN_CYCLES * math.tau * i / w)
                base_y = int(gy + round(off))
                for k in range(GRAIN_THICK):
                    y = base_y + k
                    if face_top <= y < face_bot:
                        px[y][x] = SHD

        # A knot now and then: dark centre, lighter halo, so it reads as a
        # feature of the board rather than a blot on it.
        if rng.below(100) < KNOT_CHANCE:
            kx = rng.below(w)
            ky = (face_top + face_bot) // 2
            for dy in range(-KNOT_R - 1, KNOT_R + 2):
                for dx in range(-KNOT_R - 1, KNOT_R + 2):
                    d = math.hypot(dx, dy)
                    y, x = ky + dy, (kx + dx) % w
                    if not (face_top <= y < face_bot):
                        continue
                    if d <= KNOT_R - 1.5:
                        px[y][x] = OUT
                    elif d <= KNOT_R:
                        px[y][x] = SHD
                    elif d <= KNOT_R + 1:
                        px[y][x] = HIL

        # The studs are gone — two per plank at a fixed inset from each end,
        # which is where a crate's fasteners sit and what they read as. The
        # knots above stay: a knot is grain, not a fastener.

    return px


# --- output --------------------------------------------------------------

def chunk(tag, data):
    return (struct.pack(">I", len(data)) + tag + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))


def write_png(path, rows, pal):
    h = len(rows)
    w = len(rows[0])
    body = bytearray()
    for row in rows:
        body.append(0)
        body += bytes(row)
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 3, 0, 0, 0))
    png += chunk(b"PLTE", b"".join(bytes(c) for c in pal))
    png += chunk(b"IDAT", zlib.compress(bytes(body), 9))
    png += chunk(b"IEND", b"")
    open(path, "wb").write(png)
    return path


def render_tray(tile, wood_pal, swatch="36F422", size=560):
    """The whole screen: score panel, tray, roll button — as one object.

    The tile on its own says nothing about the only question that matters,
    which is whether the timber and the field belong to each other. So this
    puts them together at the real proportions (header 15% of height, the tray
    square beneath it, the button taking the rest, per DiceGameScreen) and at
    the real tiling scale (TILE_FRACTION of the width), because
    grain that looks right in isolation routinely looks wrong in place.
    """
    import tools_smoke_preview as smoke

    th, tw = len(tile), len(tile[0])
    header = int(size * 0.15 / 0.72)
    footer = int(size * 0.13 / 0.72)
    total = header + size + footer
    rim = max(6, size // 26)

    smoke_pal = smoke.ramp(swatch)
    pal = list(wood_pal) + [tuple(c) for c in smoke_pal]
    SMOKE0 = len(wood_pal)

    tile_w = max(1, int(size * TILE_FRACTION))
    tile_h = max(1, int(tile_w * th / tw))

    out = [[BSE] * size for _ in range(total)]
    for y in range(total):
        for x in range(size):
            sx = int((x % tile_w) * tw / tile_w) % tw
            sy = int((y % tile_h) * th / tile_h) % th
            out[y][x] = tile[sy][sx]

    # The field, inset by the rim. Rendered at the dither cell size the shader
    # uses, so the stipple is the size it will really be against that grain.
    inner = size - 2 * rim
    cells = max(8, inner // 4)
    for cy in range(cells):
        v = (cy + 0.5) / cells
        row = [smoke.tone((cx + 0.5) / cells, v, 0.0, cx, cy) for cx in range(cells)]
        for dy in range(inner * cy // cells, inner * (cy + 1) // cells):
            y = header + rim + dy
            for dx in range(inner):
                out[y][rim + dx] = SMOKE0 + row[dx * cells // inner]

    # A hard dark line where the rim meets the field, which is what stops the
    # two reading as one flat sheet of colour.
    for i in range(rim - 2, rim):
        for x in range(rim - 2, size - rim + 2):
            out[header + i][x] = OUT
            out[header + size - 1 - i][x] = OUT
        for y in range(header + rim - 2, header + size - rim + 2):
            out[y][i] = OUT
            out[y][size - 1 - i] = OUT

    return out, pal


if __name__ == "__main__":
    out_dir = os.environ.get("WOOD_OUT", ".")
    pal = palette()
    tile = render_tile()

    p = write_png(os.path.join(out_dir, "wood-tile.png"), tile, pal)
    print("wrote %s  %dx%d" % (p, TILE_W, TILE_H))
    print("  palette  " + "  ".join("#%02X%02X%02X" % c for c in pal))

    # Twice actual tiling scale, so the grain can be judged close up.
    zoom = [[tile[y // 2][x // 2] for x in range(TILE_W)] for y in range(TILE_H)]
    write_png(os.path.join(out_dir, "wood-tile-2x.png"), zoom, pal)
    print("wrote %s  (2x, one half of the tile)"
          % os.path.join(out_dir, "wood-tile-2x.png"))

    for swatch, name in (("36F422", "green"), ("7A1F3D", "wine"),
                         ("14140F", "onyx")):
        rows, full = render_tray(tile, pal, swatch=swatch)
        p = write_png(os.path.join(out_dir, "tray-%s.png" % name), rows, full)
        print("wrote %s" % p)
