"""Draws the rolling-area floor the way the shader will, so it can be looked at.

The floor is not a texture any more. It is a domain-warped noise field, dithered
against an ordered 8x8 Bayer matrix and then crushed to exactly four tones —
which is what the reference GIFs actually are. Both of them carry a four-entry
global colour table, and their tone boundaries are stippled rather than blended:

    reggie.gif    480x270    4 colours   12 frames @ 10cs
    red-wave.gif  2752x2752  4 colours   29 frames @  3cs

That stippling is the whole look. Posterising without dithering gives flat
contour bands like a topographic map; dithering AFTER quantising gives noise
sprinkled over bands. Only dithering the value BEFORE it is quantised makes the
boundary itself break up into pixels, and that is the difference between this
reading as pixel art and reading as a blurry gradient.

There is no Swift compiler and no SceneKit in the container this was written in,
so this is the only way to see the floor before it ships. `SmokeFloor.swift` is
the port of the maths below, and `tools_smoke_verify.py` asserts the two agree.

    python3 tools_smoke_preview.py              # stills, every swatch family
    python3 tools_smoke_preview.py --gif        # the loop, as an animated GIF
    python3 tools_smoke_preview.py --hex 36F422 # one specific colour
"""
import math
import os
import struct
import sys
import zlib

# --- the maths the shader runs ------------------------------------------
#
# Every constant here is mirrored in SmokeFloor.swift's GLSL and checked by
# tools_smoke_verify.py. Change one, change both.

HASH_X = 127.1          # the usual sin-fract value-noise hash
HASH_Y = 311.7
HASH_SCALE = 43758.5453

OCTAVES = 5             # fbm depth. The top octaves matter more than they look:
                        # without fine grain the field is smooth enough that the
                        # Bayer matrix shows through as a regular halftone screen
                        # rather than the irregular stipple the references have.
LACUNARITY = 2.0
GAIN = 0.5

WARP_A = 2.4            # how far the first warp drags the field
WARP_B = 1.8            # and the second — this pair is what curls it
DRIFT_A = 0.11          # per-second motion of each warp layer. Deliberately
DRIFT_B = 0.07          # incommensurate, so the field never returns to a
DRIFT_C = 0.05          # previous state and the loop is genuinely endless.

ORIGIN_X = 17.3         # the field is sampled away from (0,0) on purpose.
ORIGIN_Y = 9.1          # sin-fract value noise degenerates at the origin —
                        # hash2(0, 0) is exactly fract(sin(0) * k) = 0, and its
                        # near neighbours are correlated — which showed up as a
                        # hard-edged dark rectangle pinned in the corner of
                        # every render, straight edges and all. Nothing about
                        # the warp hides it, because it is in the noise itself.

FIELD_SCALE = 1.5       # noise cells across the floor
FIELD_ASPECT = 0.55     # squashes the field on one axis. An isotropic warp
                        # gives round clouds; the references flow in ribbons,
                        # and stretching the domain is what elongates the
                        # structures into bands rather than blobs.
CONTRAST = 2.90         # pushes the field toward its extremes before posterising
LEVELS = 4              # four tones. Not negotiable — it is the brief.
DITHER = 0.70           # strength of the Bayer offset, in quantisation steps

# The classic ordered 8x8, lifted verbatim from the Darkbringer shader's own
# comment so there is one canonical source for it rather than two derivations.
BAYER = [
    [0, 32, 8, 40, 2, 34, 10, 42],
    [48, 16, 56, 24, 50, 18, 58, 26],
    [12, 44, 4, 36, 14, 46, 6, 38],
    [60, 28, 52, 20, 62, 30, 54, 22],
    [3, 35, 11, 43, 1, 33, 9, 41],
    [51, 19, 59, 27, 49, 17, 57, 25],
    [15, 47, 7, 39, 13, 45, 5, 37],
    [63, 31, 55, 23, 61, 29, 53, 21],
]

PIXEL = 4               # texels per dither cell — the apparent pixel size


def fract(x):
    return x - math.floor(x)


def hash2(x, y):
    return fract(math.sin(x * HASH_X + y * HASH_Y) * HASH_SCALE)


def noise(x, y):
    """Value noise with a smoothstep fade — four corners, bilinear."""
    ix, iy = math.floor(x), math.floor(y)
    fx, fy = x - ix, y - iy
    ux = fx * fx * (3.0 - 2.0 * fx)
    uy = fy * fy * (3.0 - 2.0 * fy)
    a = hash2(ix, iy)
    b = hash2(ix + 1.0, iy)
    c = hash2(ix, iy + 1.0)
    d = hash2(ix + 1.0, iy + 1.0)
    return (a + (b - a) * ux) + (c - a) * uy * (1.0 - ux) + (d - b) * ux * uy


def fbm(x, y):
    """Normalised to 0..1. Without the divide the sum tops out near 0.875 and
    sits around 0.44, so the four tones end up splitting a band far narrower
    than the posterise step and two of them barely appear."""
    total, amp, freq, norm = 0.0, 0.5, 1.0, 0.0
    for _ in range(OCTAVES):
        total += amp * noise(x * freq, y * freq)
        norm += amp
        freq *= LACUNARITY
        amp *= GAIN
    return total / norm


def field(u, v, t):
    """The domain warp: sample the field at coordinates the field itself moved.

    One fbm gives blobs that drift. Feeding fbm its own output as an offset is
    what makes them fold back through each other and read as smoke rather than
    as clouds sliding past. The second warp is what keeps it from settling into
    a visible rotation.
    """
    x = u * FIELD_SCALE + ORIGIN_X
    y = v * FIELD_SCALE * FIELD_ASPECT + ORIGIN_Y

    qx = fbm(x, y + t * DRIFT_A)
    qy = fbm(x + 5.2, y + 1.3 - t * DRIFT_B)

    rx = fbm(x + WARP_A * qx + 1.7, y + WARP_A * qy + 9.2 + t * DRIFT_C)
    ry = fbm(x + WARP_A * qx + 8.3, y + WARP_A * qy + 2.8 - t * DRIFT_A)

    n = fbm(x + WARP_B * rx, y + WARP_B * ry)

    # fbm lands around 0.5 with most of its mass in the middle; without this
    # stretch the four tones split a band so narrow that two of them barely
    # appear and the floor looks two-tone.
    return min(1.0, max(0.0, (n - 0.5) * CONTRAST + 0.5))


def tone(u, v, t, px, py):
    """Field value -> which of the four tones this pixel takes."""
    n = field(u, v, t)
    limit = (BAYER[py % 8][px % 8] + 0.5) / 64.0
    # Offset the VALUE, then quantise. See the module docstring.
    n += (limit - 0.5) * (DITHER / (LEVELS - 1.0))
    idx = int(n * LEVELS)
    return 0 if idx < 0 else (LEVELS - 1 if idx > LEVELS - 1 else idx)


# --- the four tones, derived from one swatch ----------------------------
#
# The picker stays as it is: 24 single swatches. The ramp is built AROUND the
# chosen colour rather than from it, because the swatch list runs from #14140F
# (Onyx) to #C9C2E0 (Pale Lavender) and a naive lighten/darken collapses to
# four near-blacks at one end and four near-whites at the other.

RAMP_SPREAD = 0.42      # brightness drop from the swatch to the darkest tone,
                        # at the bright end of the picker
RAMP_SPREAD_MIN = 0.20  # ...and at the dark end, where there is less room
RAMP_FLOOR = 0.045      # no tone may sit below this brightness
RAMP_CEIL = 0.94        # nor above this
RAMP_SAT_LIFT = 0.10    # brightest tone desaturates slightly, as both GIFs do
RAMP_BIAS = 0.55        # spacing of the four steps. NOT even, deliberately.
                        # Sorted by luminance, red-wave.gif runs #CD0000 then
                        # #FF0000 #FF3535 #FF4F4F, and reggie.gif runs #F0243C
                        # #F21D45 #FA6278 #FFFFFF — in both, one tone sits well
                        # clear of the other three, which cluster. That is what
                        # makes them read as a graphic two-tone with shading
                        # rather than as a four-step gradient. Below 1.0 opens a
                        # gap at the dark end and tightens the light end.


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


def ramp(hexcode):
    """Four tones, hung DOWNWARD from the chosen swatch.

    The brightest of the four is the swatch itself, and the other three shade
    away beneath it. Centring the band on the swatch instead — the obvious
    first try — quietly betrays the picker at the dark end: #14140F "Onyx"
    came back as a legible but unmistakably olive-grey floor, because the
    clamp that stops four near-blacks from merging had slid the whole band
    upward. Anchoring the top instead means the colour you picked is the
    colour you mostly see, at every swatch.

    The spread narrows as the swatch darkens, since there is less brightness
    room underneath it to spend.
    """
    hexcode = hexcode.lstrip("#")
    r, g, b = (int(hexcode[i:i + 2], 16) / 255.0 for i in (0, 2, 4))
    h, s, v = rgb_to_hsb(r, g, b)

    hi = min(RAMP_CEIL, v)
    spread = RAMP_SPREAD_MIN + (RAMP_SPREAD - RAMP_SPREAD_MIN) * hi
    lo = hi - spread
    if lo < RAMP_FLOOR:
        lo = RAMP_FLOOR
        hi = max(hi, lo + RAMP_SPREAD_MIN)

    out = []
    for i in range(LEVELS):
        f = (i / (LEVELS - 1.0)) ** RAMP_BIAS
        bright = lo + (hi - lo) * f
        sat = max(0.0, s - RAMP_SAT_LIFT * f)
        rr, gg, bb = hsb_to_rgb(h, sat, bright)
        out.append((int(rr * 255 + 0.5), int(gg * 255 + 0.5), int(bb * 255 + 0.5)))
    return out


# --- output, with nothing installed -------------------------------------

def png_chunk(tag, data):
    return (struct.pack(">I", len(data)) + tag + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))


def write_png(path, pixels, size, palette):
    """Indexed-colour PNG — four entries, same as the references."""
    body = bytearray()
    for row in pixels:
        body.append(0)
        body += bytes(row)
    plte = b"".join(bytes(c) for c in palette)
    png = b"\x89PNG\r\n\x1a\n"
    png += png_chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 3, 0, 0, 0))
    png += png_chunk(b"PLTE", plte)
    png += png_chunk(b"IDAT", zlib.compress(bytes(body), 9))
    png += png_chunk(b"IEND", b"")
    open(path, "wb").write(png)
    return path


def render(hexcode, size, t):
    """Evaluated once per dither cell, then expanded.

    The field and the Bayer threshold are both constant across a PIXEL x PIXEL
    block by construction, so evaluating per output pixel recomputed an
    identical five-octave warp sixteen times over. Cells first, expand after.
    """
    pal = ramp(hexcode)
    cells = size // PIXEL
    grid = []
    for cy in range(cells):
        v = (cy + 0.5) / cells
        grid.append(bytes(tone((cx + 0.5) / cells, v, t, cx, cy)
                          for cx in range(cells)))

    rows = []
    for cy in range(cells):
        wide = bytearray()
        for value in grid[cy]:
            wide += bytes([value]) * PIXEL
        rows.extend([wide] * PIXEL)
    return rows, pal


# --- animated GIF, hand-rolled (no PIL in this container) ----------------

def lzw(pixels, size, min_code=2):
    """Minimal GIF LZW. Four colours means a 2-bit minimum code size."""
    clear, end = 1 << min_code, (1 << min_code) + 1
    width = min_code + 1
    table = {bytes([i]): i for i in range(1 << min_code)}
    nxt = end + 1

    out, bitbuf, bitcnt = bytearray(), 0, 0

    def emit(code):
        nonlocal bitbuf, bitcnt
        bitbuf |= code << bitcnt
        bitcnt += width
        while bitcnt >= 8:
            out.append(bitbuf & 0xFF)
            bitbuf >>= 8
            bitcnt -= 8

    emit(clear)
    cur = b""
    for row in pixels:
        for p in row:
            nc = cur + bytes([p])
            if nc in table:
                cur = nc
                continue
            emit(table[cur])
            if nxt < 4096:
                table[nc] = nxt
                nxt += 1
                if nxt - 1 == (1 << width) and width < 12:
                    width += 1
            else:
                emit(clear)
                table = {bytes([i]): i for i in range(1 << min_code)}
                nxt, width = end + 1, min_code + 1
            cur = bytes([p])
    if cur:
        emit(table[cur])
    emit(end)
    if bitcnt:
        out.append(bitbuf & 0xFF)

    blocks = bytearray([min_code])
    for i in range(0, len(out), 255):
        piece = out[i:i + 255]
        blocks.append(len(piece))
        blocks += piece
    blocks.append(0)
    return bytes(blocks)


def write_gif(path, frames, size, palette, delay_cs):
    gif = bytearray(b"GIF89a")
    gif += struct.pack("<HH", size, size)
    gif += bytes([0xF1, 0, 0])                      # global table, 4 entries
    for c in palette:
        gif += bytes(c)
    gif += b"\x21\xFF\x0BNETSCAPE2.0\x03\x01\x00\x00\x00"   # loop forever
    for f in frames:
        gif += b"\x21\xF9\x04\x00" + struct.pack("<H", delay_cs) + b"\x00\x00"
        gif += b"\x2C" + struct.pack("<HHHH", 0, 0, size, size) + b"\x00"
        gif += lzw(f, size)
    gif += b"\x3B"
    open(path, "wb").write(bytes(gif))
    return path


# A spread across the picker: the default, the two that stress the ramp hardest
# (near-black and near-white), and a vivid one.
SAMPLES = [
    ("green", "36F422"), ("onyx", "14140F"), ("lavender", "C9C2E0"),
    ("wine", "7A1F3D"), ("teal", "0B4F4A"), ("hotrose", "FF2D78"),
]

if __name__ == "__main__":
    out = os.environ.get("SMOKE_OUT", ".")
    args = sys.argv[1:]

    if "--hex" in args:
        code = args[args.index("--hex") + 1].lstrip("#")
        SAMPLES = [("custom-" + code.lower(), code)]

    if "--gif" in args:
        size, count = 192, 20
        for name, code in SAMPLES[:2]:
            frames, pal = [], ramp(code)
            for i in range(count):
                rows, _ = render(code, size, i * (6.0 / count))
                frames.append(rows)
                print("  frame %2d/%d" % (i + 1, count))
            p = write_gif(os.path.join(out, "smoke-%s.gif" % name),
                          frames, size, pal, 6)
            print("wrote %s" % p)
    else:
        for name, code in SAMPLES:
            rows, pal = render(code, 320, 0.0)
            p = write_png(os.path.join(out, "smoke-%s.png" % name), rows, 320, pal)
            print("wrote %s  palette %s"
                  % (p, " ".join("#%02X%02X%02X" % c for c in pal)))
