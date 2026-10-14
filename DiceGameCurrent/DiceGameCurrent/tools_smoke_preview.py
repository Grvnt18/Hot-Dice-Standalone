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
LOOP_SECONDS = 37.5     # one full cycle, after which the field is EXACTLY
                        # where it started — not approximately.

# Time enters the field only as a point travelling a circle. That is the whole
# trick: a linear drift (`y + t * DRIFT`) never returns, so it can never loop,
# however long you wait. Offsetting each noise sample by (R·cos a, R·sin a)
# with a = 2π·t/LOOP makes every term periodic in LOOP, so the composite is
# too, exactly, with no cross-fade. Cross-dissolving two drifting fields is
# the other way to fake a loop and it ghosts visibly at the seam.
#
# The cost is real and worth stating: a circle only explores as far as its
# radius, so speed = 2π·R / LOOP. A long calm loop cannot also travel far.
# What keeps it from feeling stuck is that the warp layers RESHAPE the field
# as they orbit, and that is not bounded by the radius the way translation is.
ORBIT_Q = 0.45          # first warp layer
ORBIT_R = 0.55          # second warp layer
ORBIT_N = 0.22          # the field itself — see the note on ORBIT_N below
PHASE_R = 2.1           # each layer starts somewhere else on its circle, so
PHASE_N = 4.3           # they never line up into one obvious sweep

ORIGIN_X = 17.3         # the field is sampled away from (0,0) on purpose.
ORIGIN_Y = 9.1          # sin-fract value noise degenerates at the origin —
                        # hash2(0, 0) is exactly fract(sin(0) * k) = 0, and its
                        # near neighbours are correlated — which showed up as a
                        # hard-edged dark rectangle pinned in the corner of
                        # every render, straight edges and all. Nothing about
                        # the warp hides it, because it is in the noise itself.

FIELD_SCALE = 1.5       # noise cells across the floor
FIELD_ASPECT = 1.0      # was 0.55, to pull the structures into ribbons rather
                        # than blobs. Squashing the domain by 0.55 stretches what
                        # is drawn by 1.8, and the camera is orthographic and
                        # straight down, so that was 1.8x taller on the screen
                        # too — the whole of the vertical stretch left once the
                        # cell grid was corrected. 1 is isotropic: equal world
                        # distances, equal distances through the noise.
CONTRAST = 2.90         # pushes the field toward its extremes before posterising
LEVELS = 6              # was 4, which read as four flat shelves in motion
DITHER = 0.70           # strength of the Bayer offset, in quantisation steps

# The ordered 8x8, built arithmetically rather than stored.
#
# The Darkbringer shader carries the matrix as a literal — 0, 32, 8, 40, ... —
# and so did this, until the Swift side needed it. A file-scope constant array
# is the least portable thing you can put in a SceneKit shader modifier, which
# is translated rather than compiled as written, so the recursive form is used
# on both sides instead: no array, no bit twiddling, just arithmetic.
#
# This is not an approximation of the literal matrix. Checked cell by cell,
# `bayer8(x, y)` equals `LITERAL[y][x] / 64` exactly, to 0.0 — same ordering,
# same values, so the dither pattern is unchanged.


def bayer2(x, y):
    return fract(math.floor(x) / 2.0 + math.floor(y) * math.floor(y) * 0.75)


def bayer4(x, y):
    return bayer2(0.5 * x, 0.5 * y) * 0.25 + bayer2(x, y)


def bayer8(x, y):
    """0..63/64, the standard ordered-dither threshold for this cell."""
    return bayer4(0.5 * x, 0.5 * y) * 0.25 + bayer2(x, y)


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
    as clouds sliding past.

    ORBIT_N is the one that stops the floor being half-dead. The final sample
    used to be `fbm(x + WARP_B*rx, y + WARP_B*ry)` — no time term at all — so
    the base field was pinned in space and only the warp offsets moved it.
    Wherever the warp gradient was weak, that part of the floor just sat
    there, which is exactly how it looked: motion in one band and stillness
    everywhere else. Giving the final sample its own orbit translates the
    WHOLE field, so every pixel changes; the warp orbits, running at other
    radii and phases, keep that from reading as a rigid slide.

    The old drift was also applied to the `y` coordinate alone, so what motion
    there was ran vertically. A circle has no such preference.
    """
    x = u * FIELD_SCALE + ORIGIN_X
    y = v * FIELD_SCALE * FIELD_ASPECT + ORIGIN_Y

    a = 2.0 * math.pi * (t / LOOP_SECONDS)
    ca, sa = math.cos(a), math.sin(a)
    cr, sr = math.cos(a + PHASE_R), math.sin(a + PHASE_R)
    cn, sn = math.cos(a + PHASE_N), math.sin(a + PHASE_N)

    qx = fbm(x + ORBIT_Q * ca, y + ORBIT_Q * sa)
    qy = fbm(x + 5.2 - ORBIT_Q * sa, y + 1.3 + ORBIT_Q * ca)

    rx = fbm(x + WARP_A * qx + 1.7 + ORBIT_R * cr,
             y + WARP_A * qy + 9.2 + ORBIT_R * sr)
    ry = fbm(x + WARP_A * qx + 8.3 - ORBIT_R * sr,
             y + WARP_A * qy + 2.8 + ORBIT_R * cr)

    n = fbm(x + WARP_B * rx + ORBIT_N * cn,
            y + WARP_B * ry + ORBIT_N * sn)

    # fbm lands around 0.5 with most of its mass in the middle; without this
    # stretch the four tones split a band so narrow that two of them barely
    # appear and the floor looks two-tone.
    return min(1.0, max(0.0, (n - 0.5) * CONTRAST + 0.5))


def tone(u, v, t, px, py):
    """Field value -> which of the four tones this pixel takes."""
    n = field(u, v, t)
    limit = bayer8(px, py) + 0.5 / 64.0
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

RAMP_SPREAD = 0.24      # brightness drop from the swatch to the darkest tone,
                        # at the bright end of the picker
RAMP_SPREAD_MIN = 0.12  # ...and at the dark end, where there is less room
                        # Measured against the references rather than guessed:
                        # red-wave.gif's four tones span 0.20 in brightness,
                        # #CD0000 to #FF4F4F. A wider ramp stops reading as one
                        # material catching the light and starts reading as a
                        # gradient — which is what the first pass did.
RAMP_FLOOR = 0.045      # no tone may sit below this brightness
RAMP_CEIL = 0.94        # nor above this
RAMP_SAT_LIFT = 0.05    # brightest tone desaturates slightly, as both GIFs do
RAMP_MEAN_LEVEL = 0.689 # where the AVERAGE tone sits in the band. Measured:
                        # the field spends 13.9/8.9/11.7/18.4/25.0/22.2 per
                        # cent of its area in the six levels, and weighting
                        # pow(i/5, RAMP_BIAS) by that gives 0.689.
RAMP_LIFT = 0.8         # how much of the gap between that mean and the top of
                        # the band to close. The band used to hang straight
                        # down from the swatch, so every tone on screen was
                        # darker than the colour picked and #006B38 came back
                        # as #045D33 — a dE of 7.3. Lifting it puts the MEAN
                        # on the swatch (dE 2.4) and leaves the L* span and
                        # every step size alone, so the posterised look is
                        # untouched. Onyx is pinned by RAMP_FLOOR and does not
                        # move, which is why the olive-grey regression noted
                        # in ramp() cannot return through this.
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
    """Six tones, in a band whose AVERAGE is the chosen swatch.

    It used to hang straight downward, with the brightest tone being the
    swatch itself. That is one reading of "the colour you picked is the
    colour you see" and it is the wrong one: every tone on screen was then
    darker than the swatch, and the floor read duller than the picker
    promised — #006B38 came back as #045D33, a dE of 7.3.

    So the band is LIFTED by RAMP_LIFT until its area-weighted mean lands on
    the swatch instead of its ceiling. This slides the band; it does not
    squeeze it, so the L* span and every step size are what they were and
    the posterised look is unchanged.

    Centring it was the other obvious try, and it quietly betrays the picker
    at the dark end: #14140F "Onyx" came back as a legible but unmistakably
    olive-grey floor, because the clamp that stops six near-blacks from
    merging had slid the whole band upward. That is NOT what this does —
    Onyx is pinned by RAMP_FLOOR and the lift moves it by nothing at all.

    The spread narrows as the swatch darkens, since there is less brightness
    room underneath it to spend.
    """
    hexcode = hexcode.lstrip("#")
    r, g, b = (int(hexcode[i:i + 2], 16) / 255.0 for i in (0, 2, 4))
    h, s, v = rgb_to_hsb(r, g, b)

    # The band's width at the swatch's own brightness, which sets how far
    # the lift may travel.
    top = min(RAMP_CEIL, v)
    band = RAMP_SPREAD_MIN + (RAMP_SPREAD - RAMP_SPREAD_MIN) * top
    hi = min(RAMP_CEIL, v + band * RAMP_LIFT * (1.0 - RAMP_MEAN_LEVEL))
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


# --- the two properties an eye cannot check ------------------------------

def check_loop(cells=24, places=12):
    """t = 0 and t = LOOP_SECONDS must be the SAME field, not a close one."""
    worst = 0.0
    for cy in range(cells):
        v = (cy + 0.5) / cells
        for cx in range(cells):
            u = (cx + 0.5) / cells
            worst = max(worst, abs(field(u, v, 0.0) - field(u, v, LOOP_SECONDS)))
    ok = round(worst, places) == 0.0
    print("  loop closes            %s (worst drift over %d cells: %.3e)"
          % ("ok" if ok else "FAIL", cells * cells, worst))
    return ok


def check_everywhere(cells=16, steps=16):
    """Every part of the floor must visibly CHANGE TONE over a cycle.

    The first version of this check measured the span of the raw field value
    and passed happily on a floor with the defect still in it. The mistake was
    measuring the wrong quantity: the field is posterised to four levels, so a
    step is 0.25, and a region whose value wanders by 0.17 never crosses a
    boundary and never changes colour. It is frozen on screen while the number
    looks healthy.

    So this asks the only question that matches what an eye sees — how many
    distinct tones does this region actually take over the cycle — and fails
    any region that only ever shows one. Dither is included, since it shifts
    where the boundaries fall.
    """
    worst, where = 99, None
    for cy in range(cells):
        v = (cy + 0.5) / cells
        for cx in range(cells):
            u = (cx + 0.5) / cells
            seen = {tone(u, v, LOOP_SECONDS * i / steps, cx, cy)
                    for i in range(steps)}
            if len(seen) < worst:
                worst, where = len(seen), (round(u, 3), round(v, 3))
    ok = worst >= 2
    print("  every region moves     %s (quietest of %d regions shows %d tone%s"
          " over the cycle, at %s)"
          % ("ok" if ok else "FAIL", cells * cells, worst,
             "" if worst == 1 else "s", where))
    return ok


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

    if "--check" in args:
        print("smoke field:")
        good = check_loop() and check_everywhere()
        sys.exit(0 if good else 1)

    if "--loop" in args:
        # A full cycle, played fast. 30s of field in 2.4s of GIF, so the point
        # being checked is that the wrap is seamless — NOT the speed, which is
        # what --gif shows.
        size, count, delay_cs = 192, 60, 4
        for name, code in SAMPLES[:1]:
            frames, pal = [], ramp(code)
            for i in range(count):
                rows, _ = render(code, size, LOOP_SECONDS * i / count)
                frames.append(rows)
                print("  frame %2d/%d" % (i + 1, count))
            p = write_gif(os.path.join(out, "smoke-%s-loop.gif" % name),
                          frames, size, pal, delay_cs)
            print("wrote %s  (one %.0fs cycle at %.0fx)"
                  % (p, LOOP_SECONDS, LOOP_SECONDS / (count * delay_cs / 100.0)))
    elif "--gif" in args:
        # delay_cs x count IS the playback duration, so the sampled time has to
        # advance at exactly that rate or the preview misrepresents the speed.
        # It did: t ran 0..6 over frames that play in 1.2s, five times too fast,
        # and the motion got judged on that.
        size, count, delay_cs = 192, 44, 8
        span = count * delay_cs / 100.0
        for name, code in SAMPLES[:2]:
            frames, pal = [], ramp(code)
            for i in range(count):
                rows, _ = render(code, size, i * (span / count))
                frames.append(rows)
                print("  frame %2d/%d" % (i + 1, count))
            p = write_gif(os.path.join(out, "smoke-%s.gif" % name),
                          frames, size, pal, delay_cs)
            print("wrote %s" % p)
    else:
        for name, code in SAMPLES:
            rows, pal = render(code, 320, 0.0)
            p = write_png(os.path.join(out, "smoke-%s.png" % name), rows, 320, pal)
            print("wrote %s  palette %s"
                  % (p, " ".join("#%02X%02X%02X" % c for c in pal)))
