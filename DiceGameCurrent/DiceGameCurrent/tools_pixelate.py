"""Re-cuts the icon art onto a coarse pixel grid.

The icons were the last thing in the app drawn as smooth line work, which is
conspicuous now the floor, timber, steel, boards and dice are all hard-edged.
This does not redraw them: it quantises what is already there onto a block
lattice and throws away every partial alpha, so each silhouette survives and
only its edges change.

The settings are MEASURED off the supplied reference, not chosen:

    run lengths   every horizontal run in the reference is a multiple of 8px
                  at 1300px wide, so the art sits on ~162 blocks across
    colours       exactly two — transparent, and opaque black. No partial
                  alpha anywhere, which is what makes the edges hard

Worth recording, because it decided the scope: the 19 other icons in the
supplied zip are hard-edged ALREADY (2 alpha values, unlike the repo's
antialiased originals) but sit on no lattice at all — Power-Hit has 1px runs,
Free 4-9px, Rolls 6-9px. They are crisp artwork, not pixel art, so they still
need this pass.

Output keeps the SOURCE DIMENSIONS. The blocks are baked in at full
resolution, so nothing in Swift has to know this happened — no
`.interpolation(.none)`, no asset wiring. The art is displayed scaled DOWN (a
1300px icon in a ~100pt tile) where smoothing is harmless; it is upscaling
that would turn blocks to mush.

    python3 tools_pixelate.py              # preview sheet, changes nothing
    python3 tools_pixelate.py --apply      # rewrite Resources/ in place
"""
import os
import struct
import sys
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
RES = os.path.join(HERE, "Resources")

# Blocks across the image. 1300 / 8 = 162.5, and the reference's runs are all
# multiples of 8, so 162 is that grid expressed in a form that transfers to
# the 800px marks too.
#
# Deliberately a GRID, not a fixed pixel size: a fixed 8px block would give
# the 800px Rollbots marks and the 1300px tiles visibly different pixel sizes,
# and they have to read as one set.
GRID = 162

# How much of a block must be ink before the whole block becomes ink.
#
# Biased toward keeping ink rather than the obvious 0.5, so a hairline
# thickens into one block instead of vanishing. Checked at 0.20 / 0.30 / 0.45
# against the three finest-stroked icons; all three held their detail, so this
# matters less than expected and 0.30 is simply the middle.
THRESHOLD = 0.30

# Tiling noise for the dice, not an icon. Blocking it would destroy the only
# thing it is for.
SKIP = {"pix_texture.png"}

# Where the new art came from, and what it is called in the app. The zip's
# names match nothing the loader asks for: GameIcons builds
# "icon-<SuiteGame.id>.png" and the marks are plain strings in Swift, so a
# name wrong by one character is a blank tile on device — silent, and the
# thing tools_icons_verify.py exists to catch.
ZIP = ("/tmp/claude-0/-home-user-Rolls/00f63c33-a200-5537-8c48-d7af637c530d"
       "/scratchpad/icons/Game Icons")

MAPPING = [
    ("icon-rolls", "Rolls.png"),
    ("icon-freeroll", "Free.png"),
    ("icon-hog", "HOG.png"),
    ("icon-generals", "Generals.png"),
    ("icon-fyd", "FYD.png"),
    ("icon-three_thousand", "3000.png"),
    ("icon-jackpot", "Jackpot.png"),
    ("icon-boneheads", "Boneheads.png"),
    ("icon-royal_ur", "Royal-UR.png"),
    ("icon-rollbots", "Rollbots.png"),
    ("icon-baseball_dice", "Baseballl.png"),
    ("bb-patient", "Patient-Hit.png"),
    ("bb-contact", "Contact-Hit.png"),
    ("bb-power", "Power-Hit.png"),
    ("bb-fastball", "Fastball.png"),
    ("bb-changeup", "Change-Up.png"),
    ("bb-slider", "Slider.png"),
    ("bot-blade", "Rollbots/Weapons/sworg-icon.png"),
    ("bot-pistol", "Rollbots/Weapons/Pistol-Icon.png"),
    ("bot-rail", "Rollbots/Weapons/rail-gun.png"),
    ("bot-overclock", "Rollbots/Specials/overclock-icon.png"),
    ("bot-phase", "Rollbots/Specials/phase-out.png"),
    ("bot-repair", "Rollbots/Specials/hp-boost.png"),
]

# In the app but not in the zip — Weapons has 3 of the 4 weapons and Specials
# 3 of the 4 abilities. They keep their current art and take the same pass, so
# the set stays complete and Rollbots' abilities stay distinguishable.
FROM_REPO = ["bot-sidearm", "bot-virus"]

LOGOS = ["Master-logo-1.png", "Master-logo-2.png"]


def read_png(path):
    """Any 8-bit colour type, to rows with their filtering undone."""
    data = open(path, "rb").read()
    i, chunks, idat = 8, {}, b""
    while i < len(data):
        length = struct.unpack(">I", data[i:i + 4])[0]
        kind = data[i + 4:i + 8]
        body = data[i + 8:i + 8 + length]
        if kind == b"IDAT":
            idat += body
        else:
            chunks[kind] = body
        i += 12 + length
    w, h, depth, colour = struct.unpack(">IIBB", chunks[b"IHDR"][:10])
    if depth != 8:
        raise ValueError("%s is %d-bit; only 8-bit is handled" % (path, depth))
    bpp = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[colour]
    raw = zlib.decompress(idat)
    stride = w * bpp
    rows, prev, pos = [], bytearray(stride), 0
    for _ in range(h):
        filt = raw[pos]
        pos += 1
        line = bytearray(raw[pos:pos + stride])
        pos += stride
        if filt == 1:
            for x in range(bpp, stride):
                line[x] = (line[x] + line[x - bpp]) & 255
        elif filt == 2:
            for x in range(stride):
                line[x] = (line[x] + prev[x]) & 255
        elif filt == 3:
            for x in range(stride):
                left = line[x - bpp] if x >= bpp else 0
                line[x] = (line[x] + ((left + prev[x]) >> 1)) & 255
        elif filt == 4:
            for x in range(stride):
                a = line[x - bpp] if x >= bpp else 0
                b = prev[x]
                c = prev[x - bpp] if x >= bpp else 0
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pred = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[x] = (line[x] + pred) & 255
        prev = line[:]
        rows.append(bytes(line))
    return w, h, colour, bpp, rows, chunks.get(b"PLTE"), chunks.get(b"tRNS", b"")


def sample(colour, bpp, row, x, palette, trns):
    if colour == 3:
        i = row[x]
        return (palette[i * 3], palette[i * 3 + 1], palette[i * 3 + 2],
                trns[i] if i < len(trns) else 255)
    if colour == 6:
        o = x * 4
        return row[o], row[o + 1], row[o + 2], row[o + 3]
    if colour == 2:
        o = x * 3
        return row[o], row[o + 1], row[o + 2], 255
    if colour == 0:
        return row[x], row[x], row[x], 255
    o = x * 2
    return row[o], row[o], row[o], row[o + 1]


def _lattice(path):
    w, h, colour, bpp, rows, palette, trns = read_png(path)
    return w, h, colour, bpp, rows, palette, trns, GRID, max(1, round(GRID * h / w))


def coverage(path):
    """Ink coverage per block, 0..1.

    "Ink" is ALPHA, not darkness. The art is a black silhouette on
    transparency, so the shape lives entirely in the alpha channel; reading
    luminance instead would call the transparent background black and fill
    every icon solid.
    """
    w, h, colour, bpp, rows, palette, trns, cols, lines = _lattice(path)
    grid = []
    for gy in range(lines):
        y0 = h * gy // lines
        y1 = max(h * (gy + 1) // lines, y0 + 1)
        out = []
        for gx in range(cols):
            x0 = w * gx // cols
            x1 = max(w * (gx + 1) // cols, x0 + 1)
            total = count = 0
            for y in range(y0, y1):
                row = rows[y]
                for x in range(x0, x1):
                    total += sample(colour, bpp, row, x, palette, trns)[3]
                    count += 1
            out.append(total / (255.0 * count))
        grid.append(out)
    return w, h, grid


def coverage_colour(path):
    """Like `coverage`, but each block also carries its dominant ink colour.

    Only one source needs this — Master-logo-1, which has a third colour
    (#009900) in its flames and pips. Everything else is black on
    transparency, where this would be a no-op.

    Worth having rather than special-casing by filename: a black-only
    transform applied to colour art destroys the one thing distinguishing it,
    silently, with no check failing.
    """
    w, h, colour, bpp, rows, palette, trns, cols, lines = _lattice(path)
    grid = []
    for gy in range(lines):
        y0 = h * gy // lines
        y1 = max(h * (gy + 1) // lines, y0 + 1)
        out = []
        for gx in range(cols):
            x0 = w * gx // cols
            x1 = max(w * (gx + 1) // cols, x0 + 1)
            total = count = 0
            tally = {}
            for y in range(y0, y1):
                row = rows[y]
                for x in range(x0, x1):
                    r, g, b, a = sample(colour, bpp, row, x, palette, trns)
                    total += a
                    count += 1
                    if a >= 128:
                        tally[(r, g, b)] = tally.get((r, g, b), 0) + 1
            ink = max(tally, key=tally.get) if tally else (0, 0, 0)
            out.append((total / (255.0 * count), ink))
        grid.append(out)
    return w, h, grid


def blocks(grid, threshold=THRESHOLD):
    return [[1 if v >= threshold else 0 for v in row] for row in grid]


def write_indexed(path, w, h, grid, colour=False, threshold=THRESHOLD):
    """Blow the lattice back up to the source size, hard-edged, as INDEXED.

    Nearest-neighbour by construction — each output pixel takes its block's
    value with no blending — which is the point: any interpolation here puts
    the soft edges straight back.

    Indexed, not RGBA, and that is not a detail. The source art is 8-bit
    palette PNG at one byte per pixel; the first version of this wrote RGBA
    and made every file BIGGER (336KB -> 491KB across the set) despite the
    content getting simpler, purely from spending four bytes per pixel to say
    "black" or "nothing". Two or three colours is what a palette is for, and
    `tRNS` carries the transparency in a couple of bytes instead of a whole
    channel.

    `colour=True` expects `grid` from `coverage_colour` and keeps each
    block's own ink; otherwise `grid` is 0/1 from `blocks`.
    """
    lines, cols = len(grid), len(grid[0])

    if colour:
        seen = []
        for row in grid:
            for _value, ink in row:
                if ink not in seen:
                    seen.append(ink)
        palette = [(0, 0, 0)] + seen
        trns = bytes([0] + [255] * len(seen))

        def index_at(row, gx):
            value, ink = row[gx]
            return (seen.index(ink) + 1) if value >= threshold else 0
    else:
        palette = [(0, 0, 0), (0, 0, 0)]   # 0 transparent, 1 opaque black
        trns = bytes([0, 255])

        def index_at(row, gx):
            return 1 if row[gx] else 0

    raw = bytearray()
    for y in range(h):
        raw.append(0)
        row = grid[min(y * lines // h, lines - 1)]
        raw += bytes(index_at(row, min(x * cols // w, cols - 1))
                     for x in range(w))

    def chunk(kind, body):
        payload = kind + body
        return (struct.pack(">I", len(body)) + payload
                + struct.pack(">I", zlib.crc32(payload)))

    open(path, "wb").write(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 3, 0, 0, 0))
        + chunk(b"PLTE", b"".join(bytes(c) for c in palette))
        + chunk(b"tRNS", trns)
        + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
        + chunk(b"IEND", b""))


def targets():
    return sorted(f for f in os.listdir(RES)
                  if f.endswith(".png") and f not in SKIP)


def apply_all():
    before = after = 0
    names = targets()
    for name in names:
        path = os.path.join(RES, name)
        was = os.path.getsize(path)
        w, h, grid = coverage(path)
        write_indexed(path, w, h, blocks(grid))
        now = os.path.getsize(path)
        before += was
        after += now
        print("  %-26s %7d -> %7d B" % (name, was, now))
    print("\n%d files, %d -> %d bytes (%.0f%% smaller)"
          % (len(names), before, after, 100 * (1 - after / before)))
    return 0


# --- the review gate -------------------------------------------------

def _tile(path, n, grid=None):
    """One icon at n x n, ink light on a dark ground.

    Light-on-dark because that is how these actually sit in the app: the
    marks are tinted over near-black panels and the tiles sit on dark timber,
    so previewing black-on-white would flatter them.
    """
    if grid is not None:
        lines, cols = len(grid), len(grid[0])
        return [[(238, 235, 230)
                 if grid[min(y * lines // n, lines - 1)][min(x * cols // n, cols - 1)]
                 else (62, 60, 58) for x in range(n)] for y in range(n)]
    w, h, colour, bpp, rows, palette, trns = read_png(path)
    out = []
    for ty in range(n):
        row = rows[ty * h // n]
        out.append([(238, 235, 230)
                    if sample(colour, bpp, row, tx * w // n, palette, trns)[3] >= 128
                    else (62, 60, 58) for tx in range(n)])
    return out


def _sheet(path, tiles, cols, side, pad=8):
    lines = (len(tiles) + cols - 1) // cols
    w = cols * (side + pad) + pad
    h = lines * (side + pad) + pad
    img = [[(24, 22, 20)] * w for _ in range(h)]
    for i, tile in enumerate(tiles):
        ox = pad + (i % cols) * (side + pad)
        oy = pad + (i // cols) * (side + pad)
        for y in range(side):
            for x in range(side):
                img[oy + y][ox + x] = tile[y][x]
    raw = bytearray()
    for row in img:
        raw.append(0)
        for px in row:
            raw += bytes(px)

    def chunk(kind, body):
        payload = kind + body
        return (struct.pack(">I", len(body)) + payload
                + struct.pack(">I", zlib.crc32(payload)))

    open(path, "wb").write(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(bytes(raw), 6))
        + chunk(b"IEND", b""))
    return path


def preview():
    """The whole set, before beside after. Touches nothing in Resources/."""
    side = 110
    tiles = []
    for _name, src in MAPPING:
        path = os.path.join(ZIP, src)
        _w, _h, grid = coverage(path)
        tiles.append(_tile(path, side))
        tiles.append(_tile(None, side, blocks(grid)))
    for name in FROM_REPO:
        path = os.path.join(RES, name + ".png")
        _w, _h, grid = coverage(path)
        tiles.append(_tile(path, side))
        tiles.append(_tile(None, side, blocks(grid)))
    return _sheet(os.path.join(HERE, "icons-pixelated.png"), tiles, 10, side)


if __name__ == "__main__":
    if "--apply" in sys.argv:
        sys.exit(apply_all())
    print("wrote", preview())
