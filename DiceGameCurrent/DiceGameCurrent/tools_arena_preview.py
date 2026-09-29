"""Previews for the three games that were left out of the restyle.

Royal UR, Rollbots and Baseball Dice each carry their own art, and each was
deferred while the tray, the wood and the chrome were rebuilt. The result is
that `LowPolyTextures.facetedSurface` — the old continuous-noise generator — is
now used by nothing in the app except those three files.

Nothing here is Swift yet, deliberately. Each piece is drawn the way the Swift
would draw it so it can be looked at and argued with first, which is how every
other part of this restyle was settled.

    python3 tools_arena_preview.py steel       # the Rollbots metal border
    python3 tools_arena_preview.py board       # the scoreboard, two variants
    python3 tools_arena_preview.py surfaces    # posterised tiles and turf
    python3 tools_arena_preview.py             # all three
"""
import math
import os
import sys

import tools_wood_preview as wood
import tools_smoke_preview as smoke

OUT = os.environ.get("ARENA_OUT", ".")


# --- shared -------------------------------------------------------------

def quantise(rgb, ramp):
    """Nearest of the four tones, by squared distance in RGB."""
    best, bi = None, 0
    for i, t in enumerate(ramp):
        d = sum((a - b) ** 2 for a, b in zip(rgb, t))
        if best is None or d < best:
            best, bi = d, i
    return bi


def tone_ramp(hexcode):
    """The same four-tone derivation the floor uses, for any base colour."""
    return [tuple(c) for c in smoke.ramp(hexcode)]


# --- 1. the Rollbots steel border ---------------------------------------
#
# Rollbots deliberately has no timber. The code says so in three places — "a
# dice tray on a table is the wrong object for a duel in the net" — so the ask
# is not to give it wood but to give it a rim of its own, in the same grammar:
# four tones, hard seams, chamfered edges, a repeating structural motif.
#
# Plates and rivets rather than planks and knots. The structural rhythm is the
# same; only the material changes.

STEEL_BASE = "#48525F"          # cool grey-blue, mid
STEEL_ACCENT = (34, 227, 255)   # NetArt seat-0 cyan, for the edge light

PLATES = 5                      # more than the wood's 3: plates are structural
PLATE_SEAM = 2                  # bays, and at rim scale 3 read as empty panels
BEVEL = 3
SHADE_EDGE = 2
RIVET_R = 5                     # up from 3 — at the tiling scale the rim is
RIVET_INSET = 34                # actually seen at, 3px rivets simply vanished


def steel_palette():
    """outline, shadow, base, highlight — darkest first, like the wood."""
    rgb = wood.hex_rgb(STEEL_BASE)
    base = tuple(int(c * 255 + .5) for c in rgb)
    return [wood.shift(rgb, -0.42, 0.04),
            wood.shift(rgb, -0.20, 0.02),
            base,
            wood.shift(rgb, 0.26, -0.06)]


def render_steel(w=wood.TILE_W, h=wood.TILE_H, seed=44021):
    """Vertical plates with riveted seams — read across a horizontal rim as
    repeating structural bays rather than as grain."""
    OUTL, SHD, BSE, HIL = 0, 1, 2, 3
    px = [[BSE] * w for _ in range(h)]
    rng = wood.Rng(seed)
    plate_w = w // PLATES

    # Top and bottom chamfer, so the rim reads as having thickness under the
    # orthographic camera exactly as the timber does.
    for y in range(0, BEVEL):
        for x in range(w):
            px[y][x] = HIL
    for y in range(h - SHADE_EDGE, h):
        for x in range(w):
            px[y][x] = SHD

    for p in range(PLATES):
        left = p * plate_w
        # Vertical seam between plates: hard, dark, full height.
        for x in range(left, min(left + PLATE_SEAM, w)):
            for y in range(h):
                px[y][x] = OUTL
        # A lit edge just right of each seam — light coming from the left.
        for x in range(left + PLATE_SEAM, min(left + PLATE_SEAM + 2, w)):
            for y in range(BEVEL, h - SHADE_EDGE):
                px[y][x] = HIL
        # ...and a shadow just left of the next one.
        for x in range(max(0, left + plate_w - 2), left + plate_w):
            for y in range(BEVEL, h - SHADE_EDGE):
                px[y][x] = SHD

        # An inset panel line inside each bay — structure, not texture.
        #
        # The first pass scattered short random scuffs here as "brushed metal".
        # At rim scale they did not read as brushing at all, they read as
        # debris lying on the plate: a handful of disconnected dashes at
        # arbitrary angles to everything else. Metal panelling gets its
        # character from edges, so this is an edge.
        inset_x0 = left + PLATE_SEAM + 6
        inset_x1 = left + plate_w - 6
        for x in range(inset_x0, min(inset_x1, w)):
            if BEVEL + 8 < h - SHADE_EDGE - 8:
                px[BEVEL + 8][x] = SHD
                px[BEVEL + 9][x] = HIL
                px[h - SHADE_EDGE - 9][x] = SHD
                px[h - SHADE_EDGE - 8][x] = HIL

        # Rivets, top and bottom of each plate.
        for ry in (RIVET_INSET, h - RIVET_INSET):
            rx = left + plate_w // 2
            for dy in range(-RIVET_R - 1, RIVET_R + 2):
                for dx in range(-RIVET_R - 1, RIVET_R + 2):
                    d = math.hypot(dx, dy)
                    y, x = ry + dy, rx + dx
                    if not (0 <= y < h and 0 <= x < w):
                        continue
                    if d <= RIVET_R - 1:
                        px[y][x] = HIL
                    elif d <= RIVET_R:
                        px[y][x] = OUTL

    return px


def steel_sheet():
    """The tile, and the tile in place as a rim around the neon arena."""
    pal = steel_palette()
    tile = render_steel()
    wood.write_png(os.path.join(OUT, "steel-tile.png"), tile, pal)

    zoom = [[tile[y // 2][x // 2] for x in range(wood.TILE_W)]
            for y in range(wood.TILE_H)]
    wood.write_png(os.path.join(OUT, "steel-tile-2x.png"), zoom, pal)

    # In place: the Rollbots arena is a dark neon field, so the rim has to hold
    # its own against near-black rather than against a bright tray floor.
    size, rim = 520, 26
    header, footer = 96, 84
    total = header + size + footer
    arena = tone_ramp("#05070E")            # NetArt.background
    full = list(pal) + arena + [STEEL_ACCENT]
    A0, ACC = len(pal), len(pal) + len(arena)

    img = [bytearray([2]) * size for _ in range(total)]
    th, tw = len(tile), len(tile[0])
    tile_w = max(1, int(size * wood.TILE_FRACTION))
    tile_h = max(1, int(tile_w * th / tw))
    for y in range(total):
        for x in range(size):
            img[y][x] = tile[int((y % tile_h) * th / tile_h) % th][
                            int((x % tile_w) * tw / tile_w) % tw]

    inner = size - 2 * rim
    cells = max(8, inner // 4)
    for cy in range(cells):
        v = (cy + 0.5) / cells
        row = [smoke.tone((cx + .5) / cells, v, 0.0, cx, cy) for cx in range(cells)]
        for dy in range(inner * cy // cells, inner * (cy + 1) // cells):
            for dx in range(inner):
                img[header + rim + dy][rim + dx] = A0 + row[dx * cells // inner]

    # A single cyan line where the steel meets the field — the one place the
    # arena's neon is allowed to touch the rim, so the border belongs to this
    # game rather than being grey wood.
    for x in range(rim - 2, size - rim + 2):
        img[header + rim - 2][x] = ACC
        img[header + size - rim + 1][x] = ACC
    for y in range(header + rim - 2, header + size - rim + 2):
        img[y][rim - 2] = ACC
        img[y][size - rim + 1] = ACC

    p = os.path.join(OUT, "steel-arena.png")
    wood.write_png(p, img, full)
    return p


# --- 2. the baseball scoreboard, two variants ---------------------------
#
# The panel is Core Graphics drawn onto a texture, not a SwiftUI view, so
# PixelPanel cannot be applied to it — only its recipe hand-ported. These are
# the two candidates, at true panel proportions with the real content.

PANEL = (17, 17, 17)            # BaseballField.panel  #111111
PANEL_TEXT = (255, 255, 255)
CELL = (233, 233, 233)          # BaseballField.cell   #E9E9E9
LIVE = (243, 217, 164)          # BaseballField.live   #F3D9A4
OUTC = (217, 70, 62)            # BaseballField.out    #D9463E
OUTLINE = (26, 18, 13)          # PixelPanel.outlineColor
BEVEL_HI = (255, 255, 255)
BEVEL_LO = (0, 0, 0)


def scoreboard(variant, w=760, h=250, innings=9, current=4):
    """variant 1 = hard outline + one-step bevel; variant 3 = flatten only."""
    import tools_type as type_

    pal = [PANEL, PANEL_TEXT, CELL, LIVE, OUTC, OUTLINE, (70, 70, 70), (90, 84, 78)]
    P, T, C, L, O, OL, BH, BL = range(8)
    img = [bytearray([P]) * w for _ in range(h)]

    def rect(x0, y0, x1, y1, tone):
        for y in range(max(0, y0), min(h, y1)):
            for x in range(max(0, x0), min(w, x1)):
                img[y][x] = tone

    if variant == 1:
        rect(0, 0, w, 2, OL); rect(0, h - 2, w, h, OL)
        rect(0, 0, 2, h, OL); rect(w - 2, 0, w, h, OL)
        rect(2, 2, w - 2, 4, BH)          # one-step bevel, lit above
        rect(2, h - 4, w - 2, h - 2, BL)  # shadowed below
        rect(2, 2, 4, h - 2, BH)
        rect(w - 4, 2, w - 2, h - 2, BL)
    else:
        rect(0, 0, w, 2, OL); rect(0, h - 2, w, h, OL)
        rect(0, 0, 2, h, OL); rect(w - 2, 0, w, h, OL)

    type_.draw(img, pal, "INNING", "Poppins-SemiBold", 22, 26, 46, PANEL_TEXT)

    cw = (w - 150) // innings
    top, ch = 70, 44
    for i in range(innings):
        x = 130 + i * cw
        type_.draw(img, pal, str(i + 1), "Poppins-SemiBold", 20,
                   x + cw // 2, top - 8, PANEL_TEXT, centre=True)
        for row in range(2):
            y = top + row * (ch + 6)
            rect(x, y, x + cw - 4, y + ch, L if i + 1 == current else C)
            rect(x, y, x + cw - 4, y + 2, OL)
            rect(x, y + ch - 2, x + cw - 4, y + ch, OL)
            rect(x, y, x + 2, y + ch, OL)
            rect(x + cw - 6, y, x + cw - 4, y + ch, OL)
            if i < current:
                type_.draw(img, pal, str((i * 3 + row) % 4), "Poppins-SemiBold",
                           20, x + (cw - 4) // 2, y + ch - 13, PANEL, centre=True)

    for row, lab in enumerate(("V", "H")):
        type_.draw(img, pal, lab, "Poppins-SemiBold", 20, 96,
                   top + row * (ch + 6) + ch - 13, PANEL_TEXT)

    type_.draw(img, pal, "OUTS", "Poppins-SemiBold", 22, 26, h - 30, PANEL_TEXT)
    for i in range(3):
        cx, cy, r = 120 + i * 34, h - 37, 11
        for dy in range(-r, r + 1):
            for dx in range(-r, r + 1):
                d = math.hypot(dx, dy)
                y, x = cy + dy, cx + dx
                if not (0 <= y < h and 0 <= x < w):
                    continue
                if d <= r - 2:
                    img[y][x] = O if i < 2 else P
                elif d <= r:
                    img[y][x] = T
    return img, pal


def scoreboard_sheet():
    out = []
    for v, name in ((1, "bevelled"), (3, "flat")):
        img, pal = scoreboard(v)
        p = os.path.join(OUT, "scoreboard-%d-%s.png" % (v, name))
        wood.write_png(p, img, pal)
        out.append(p)
    return out


# --- 3. posterised surfaces ---------------------------------------------

def posterised_sheet():
    """Royal UR's board ivory and the baseball turf, faceted vs 4-tone.

    The baseball half is the one that matters: the turf is posterised and the
    DIRT IS NOT. Ramping both from one swatch collapses the green/tan contrast
    that is the only reason the thing reads as a ballpark.
    """
    import tools_type as type_

    W, H, sw = 900, 520, 190
    # All three read straight off BaseballField/RoyalUrArt. TURF was
    # "#36F422" here — a bright green the app never renders; its grass is the
    # muted sage below. That made the posterise look far more dramatic than
    # it is, because a saturated base gives the four-tone ramp much more to
    # span. Fourth time a preview in this project has shown something the app
    # does not; worth saying out loud rather than quietly correcting.
    IVORY, TURF, DIRT = "#F4EDDF", "#7BA07E", "#C9B18A"

    def faceted_block(base, seed, cols=14):
        """The old generator: continuous per-facet brightness jitter."""
        rgb = wood.hex_rgb(base)
        px = [[0] * sw for _ in range(sw)]
        rng = wood.Rng(seed)
        cell = sw // cols
        tones, out = [], []
        for cy in range(cols + 1):
            for cx in range(cols + 1):
                d = (rng.unit() * 2 - 1) * 0.085
                tones.append(wood.shift(rgb, d, 0))
        for y in range(sw):
            for x in range(sw):
                px[y][x] = tones[min(len(tones) - 1,
                                     (y // cell) * (cols + 1) + (x // cell))]
        return px

    def posterised_block(base, seed, cols=14):
        ramp = tone_ramp(base)
        rgb = wood.hex_rgb(base)
        px = [[(0, 0, 0)] * sw for _ in range(sw)]
        rng = wood.Rng(seed)
        cell = sw // cols
        tones = []
        for _ in range((cols + 1) * (cols + 1)):
            tones.append(wood.shift(rgb, (rng.unit() * 2 - 1) * 0.085, 0))
        for y in range(sw):
            for x in range(sw):
                raw = tones[min(len(tones) - 1,
                                (y // cell) * (cols + 1) + (x // cell))]
                # Bayer-dithered before quantising, exactly as the floor does,
                # so the boundaries stipple instead of forming flat contours.
                lim = smoke.bayer8(x, y) - 0.5
                nudged = tuple(max(0, min(255, int(c + lim * 26))) for c in raw)
                px[y][x] = ramp[quantise(nudged, ramp)]
        return px

    pal = [(22, 19, 17), (238, 233, 226), (150, 144, 136)]
    img = [bytearray([0]) * W for _ in range(H)]

    def place(block, ox, oy, direct):
        for y in range(sw):
            for x in range(sw):
                v = block[y][x]
                if v not in pal:
                    pal.append(v)
                img[oy + y][ox + x] = pal.index(v)

    cols = [("Royal UR tile", IVORY, 8821), ("Baseball turf", TURF, 771001),
            ("Baseball dirt", DIRT, 771002)]
    for i, (label, base, seed) in enumerate(cols):
        ox = 40 + i * (sw + 45)
        type_.draw(img, pal, label, "Poppins-SemiBold", 17, ox, 40, (238, 233, 226))
        place(faceted_block(base, seed), ox, 60, True)
        if label == "Baseball dirt":
            type_.draw(img, pal, "unchanged", "Poppins-Regular", 13,
                       ox, 282, (150, 144, 136))
            place(faceted_block(base, seed), ox, 295, True)
        else:
            type_.draw(img, pal, "4-tone", "Poppins-Regular", 13,
                       ox, 282, (150, 144, 136))
            place(posterised_block(base, seed), ox, 295, True)

    type_.draw(img, pal, "now", "Poppins-Regular", 13, 40, 57 - 3, (150, 144, 136))
    p = os.path.join(OUT, "surfaces.png")
    wood.write_png(p, img, pal)
    return p


# --- 4. whole play areas ------------------------------------------------
#
# The border and the surfaces were approved in isolation, which is not the
# same as approving the screen. These lay the real layouts out at their real
# proportions, taken from the Swift rather than invented:
#
#   Rollbots — NetGrid behind everything; HStack of rail | tray+bar | rail,
#              railWidth = clamp(width * 0.22, 92, 128), bar 104pt
#              (RollbotsScreen.body)
#   Royal UR — VStack of scoreboard 15% | board 34% | tray | button 104pt,
#              board is 3 rows x 8 columns minus the four corners of the
#              bridge, five rosettes (RoyalUrScreen.body, RoyalUrBoard)

def load_icon(name, out_size):
    """The app's own bundled icon art, as an alpha mask.

    These are drawn with .renderingMode(.template) in the app — the PNG is a
    silhouette and the colour comes from the tint. So only the alpha matters,
    which is what this returns: a `out_size` x `out_size` grid of 0..1 coverage,
    box-downsampled from the 800x800 source.

    Using the real files rather than drawing stand-in glyphs, because the whole
    question being previewed is whether an icon and its label read as one unit
    at rail width, and a placeholder triangle cannot answer that.
    """
    import struct
    import zlib

    path = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                        "Resources", name + ".png")
    d = open(path, "rb").read()
    i, idat, trns, plte = 8, b"", b"", b""
    w = h = 0
    while i < len(d):
        ln = struct.unpack(">I", d[i:i + 4])[0]
        tag = d[i + 4:i + 8]
        body = d[i + 8:i + 8 + ln]
        if tag == b"IHDR":
            w, h = struct.unpack(">II", body[:8])
        elif tag == b"PLTE":
            plte = body
        elif tag == b"tRNS":
            trns = body
        elif tag == b"IDAT":
            idat += body
        elif tag == b"IEND":
            break
        i += 12 + ln

    raw = zlib.decompress(idat)
    rows, pos, prev = [], 0, bytearray(w)
    for _y in range(h):
        filt = raw[pos]; pos += 1
        line = bytearray(raw[pos:pos + w]); pos += w
        if filt == 1:
            for x in range(1, w):
                line[x] = (line[x] + line[x - 1]) & 255
        elif filt == 2:
            for x in range(w):
                line[x] = (line[x] + prev[x]) & 255
        elif filt == 3:
            for x in range(w):
                line[x] = (line[x] + ((line[x - 1] if x else 0) + prev[x]) // 2) & 255
        elif filt == 4:
            for x in range(w):
                a = line[x - 1] if x else 0
                b = prev[x]
                c = prev[x - 1] if x else 0
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[x] = (line[x] + pr) & 255
        rows.append(line)
        prev = line

    def alpha_of(idx):
        if idx < len(trns):
            return trns[idx] / 255.0
        # No tRNS entry means opaque; a very dark palette entry in these files
        # is the silhouette itself.
        if plte:
            r, g, b = plte[idx * 3:idx * 3 + 3]
            return 1.0 if (r + g + b) < 690 else 0.0
        return 1.0

    out = []
    step = h / float(out_size)
    for oy in range(out_size):
        line = []
        for ox in range(out_size):
            acc = n = 0.0
            for sy in range(int(oy * step), max(int(oy * step) + 1, int((oy + 1) * step))):
                for sx in range(int(ox * step), max(int(ox * step) + 1, int((ox + 1) * step))):
                    if sy < h and sx < w:
                        acc += alpha_of(rows[sy][sx]); n += 1
            line.append(acc / n if n else 0.0)
        out.append(line)
    return out


def rollbots_screen(w=560, h=780):
    """The arena with the rails rebuilt: icon and label as one unit, white
    reading text scaled to the column, and both sides equally bright."""
    import tools_type as type_

    steel = steel_palette()
    tile = render_steel()
    arena = tone_ramp("#05070E")
    panel = tone_ramp("#0B1220")
    CY, MG, WHITE, DIM = (34, 227, 255), (255, 45, 120), (255, 255, 255), (150, 172, 184)
    pal = list(steel) + arena + panel + [CY, MG, WHITE, DIM]
    S0, A0, P0 = 0, len(steel), len(steel) + len(arena)
    CYI, MGI, WHI, DIMI = P0 + 4, P0 + 5, P0 + 6, P0 + 7

    img = [bytearray([A0 + 1]) * w for _ in range(h)]

    def rect(x0, y0, x1, y1, t):
        for y in range(max(0, int(y0)), min(h, int(y1))):
            for x in range(max(0, int(x0)), min(w, int(x1))):
                img[y][x] = t

    rail = max(78, min(int(w * 0.22), 128))   # floor lowered with RollbotsScreen
    bar = 104
    body_h = h - bar

    cells = max(8, (w - 2 * rail) // 4)
    for cy in range(cells):
        v = (cy + .5) / cells
        row = [smoke.tone((cx + .5) / cells, v, 0.0, cx, cy) for cx in range(cells)]
        for dy in range(body_h * cy // cells, body_h * (cy + 1) // cells):
            for dx in range(w - 2 * rail):
                img[dy][rail + dx] = A0 + row[dx * cells // (w - 2 * rail)]

    th, tw = len(tile), len(tile[0])
    tile_h = max(1, int(rail * th / tw) * 3)
    for y in range(h):
        for x in list(range(rail)) + list(range(w - rail, w)):
            img[y][x] = tile[int((y % tile_h) * th / tile_h) % th][
                            int((x % rail) * tw / rail) % tw]

    for y in range(body_h):
        img[y][rail] = CYI
        img[y][w - rail - 1] = MGI

    # Label size derived from the rail, not fixed. The rail is
    # clamp(width * 0.22, 92, 128); the old 10-13pt labels left the widest
    # rail a third empty, which is what the 128 clamp was raised for.
    label = max(11, int(rail * 0.125))
    icon_px = int(rail * 0.44)

    def icon(mask, x0, y0, size, tone):
        for iy in range(size):
            for ix in range(size):
                if mask[iy][ix] > 0.45:
                    y, x = y0 + iy, x0 + ix
                    if 0 <= y < h and 0 <= x < w:
                        img[y][x] = tone

    gun = load_icon("bot-rail", icon_px)
    phase = load_icon("bot-phase", icon_px)

    for x0, seat, name, ip, wpn, abl in (
            (0, CYI, "YOU", 42, "RAIL GUN", "PHASE"),
            (w - rail, MGI, "RIVAL", 31, "RAIL GUN", "PHASE")):
        cx = x0 + rail // 2
        type_.draw(img, pal, name, "Poppins-SemiBold", label, cx, 28, WHI,
                   centre=True)
        type_.draw(img, pal, str(ip), "Poppins-Black", int(rail * 0.30), cx, 76,
                   WHI, centre=True)
        type_.draw(img, pal, "IP", "Poppins-Medium", label - 2, cx, 96, DIMI,
                   centre=True)

        bx0, bx1, by0, by1 = x0 + 12, x0 + rail - 12, 112, 388
        rect(bx0, by0, bx1, by1, P0 + 1)
        frac = ip / 50.0
        rect(bx0, by1 - (by1 - by0) * frac, bx1, by1, seat)
        rect(bx0, by0, bx1, by0 + 2, S0); rect(bx0, by1 - 2, bx1, by1, S0)
        rect(bx0, by0, bx0 + 2, by1, S0); rect(bx1 - 2, by0, bx1, by1, S0)

        # Icon and label as ONE unit, boxed together, so the weapon reads as a
        # thing with a name rather than a picture near some words.
        for (mask, text, top) in ((gun, wpn, 406), (phase, abl, 552)):
            bh = icon_px + label + 34
            rect(x0 + 8, top, x0 + rail - 8, top + bh, P0)
            rect(x0 + 8, top, x0 + rail - 8, top + 2, S0)
            rect(x0 + 8, top + bh - 2, x0 + rail - 8, top + bh, S0)
            rect(x0 + 8, top, x0 + 10, top + bh, S0)
            rect(x0 + rail - 10, top, x0 + rail - 8, top + bh, S0)
            icon(mask, cx - icon_px // 2, top + 8, icon_px, seat)
            type_.draw(img, pal, text, "Poppins-SemiBold", label, cx,
                       top + icon_px + label + 16, WHI, centre=True)

    for bx, glyph in ((rail + 12, "<"), (w - rail - 44, "=")):
        rect(bx + 2, 14, bx + 34, 46, S0)
        rect(bx, 12, bx + 32, 44, S0)
        rect(bx + 2, 14, bx + 30, 42, A0)
        type_.draw(img, pal, glyph, "Poppins-SemiBold", 16, bx + 16, 36, WHI,
                   centre=True)

    rect(rail + 10, body_h + 12, w - rail - 6, h - 10, S0)
    rect(rail + 8, body_h + 10, w - rail - 8, h - 12, P0 + 1)
    rect(rail + 8, body_h + 10, w - rail - 8, body_h + 13, CYI)
    type_.draw(img, pal, "ATTACK", "Poppins-Bold", 20, w // 2, body_h + 52, WHI,
               centre=True)
    type_.draw(img, pal, "3 dice · rail gun", "Poppins-Regular", 12, w // 2,
               body_h + 78, DIMI, centre=True)

    p = os.path.join(OUT, "rollbots-screen.png")
    wood.write_png(p, img, pal)
    return p


# Board furniture, sampled from the reference photograph. These are fixed,
# for the same reason the ink and the petal red are fixed: they are the board,
# not the player's theme.
GROUT = (62, 106, 114)          # the teal-grey channel between set tiles
FRAME_RED = (192, 80, 60)
FRAME_CREAM = (232, 211, 169)
ROSE_GOLD = (217, 164, 65)
TILE_IVORY = (238, 228, 205)

# Exactly what RoyalUrBoard.decor(at:) assigns. Reproduced rather than
# invented: the app's markings already match the standard board square for
# square, and the earlier preview showing plain tiles was the preview's fault.
ROSETTES = {(1, 1), (3, 1), (2, 4), (1, 7), (3, 7)}


def ur_decor(row, col):
    if (row, col) in ROSETTES:
        return "rosette"
    if (row, col) == (2, 1):
        return "squaresGrid"
    if (row, col) in ((2, 3), (2, 6)):
        return "dottedField"
    if (row, col) in ((1, 8), (3, 8)):
        return "zigzagFive"
    if (row, col) in ((1, 2), (3, 2), (1, 4), (3, 4), (2, 7)):
        return "eyes"
    return "fiveDots"


def royalur_board(w=1040, h=420):
    """The board alone, at a size the markings can actually be judged at."""
    pal = [GROUT, TILE_IVORY, (27, 42, 74), (219, 54, 44), FRAME_RED,
           FRAME_CREAM, ROSE_GOLD, (255, 255, 255), (20, 16, 14)]
    GR, IV, INK, PET, FR, FC, GD, WH, SH = range(9)
    img = [bytearray([GR]) * w for _ in range(h)]

    def rect(x0, y0, x1, y1, t):
        for y in range(max(0, int(y0)), min(h, int(y1))):
            for x in range(max(0, int(x0)), min(w, int(x1))):
                img[y][x] = t

    def disc(cx, cy, r, t):
        for dy in range(int(-r) - 1, int(r) + 2):
            for dx in range(int(-r) - 1, int(r) + 2):
                if dx * dx + dy * dy <= r * r:
                    y, x = int(cy + dy), int(cx + dx)
                    if 0 <= y < h and 0 <= x < w:
                        img[y][x] = t

    def ring(cx, cy, r, t):
        for a in range(0, 360, 3):
            rad = math.radians(a)
            for k in (0, 1):
                y = int(cy + (r - k) * math.sin(rad))
                x = int(cx + (r - k) * math.cos(rad))
                if 0 <= y < h and 0 <= x < w:
                    img[y][x] = t

    # --- the patterned frame -------------------------------------------
    #
    # A cream band carrying a run of red diamonds, with a solid medallion at
    # each corner. The most recognisable thing about the reference board, and
    # the one piece of it the app does not draw at all.
    band = 26
    rect(0, 0, w, band, FC); rect(0, h - band, w, h, FC)
    rect(0, 0, band, h, FC); rect(w - band, 0, w, h, FC)
    step = band
    for i in range(w // step + 1):
        cx = i * step + step // 2
        for k in range(step // 2):
            rect(cx - k, band // 2 - (step // 2 - k), cx + k,
                 band // 2 + (step // 2 - k), FR)
            rect(cx - k, h - band // 2 - (step // 2 - k), cx + k,
                 h - band // 2 + (step // 2 - k), FR)
    for i in range(h // step + 1):
        cy = i * step + step // 2
        for k in range(step // 2):
            rect(band // 2 - (step // 2 - k), cy - k,
                 band // 2 + (step // 2 - k), cy + k, FR)
            rect(w - band // 2 - (step // 2 - k), cy - k,
                 w - band // 2 + (step // 2 - k), cy + k, FR)
    for (mx, my) in ((band // 2, band // 2), (w - band // 2, band // 2),
                     (band // 2, h - band // 2), (w - band // 2, h - band // 2)):
        rect(mx - band // 2, my - band // 2, mx + band // 2, my + band // 2, FR)
        rect(mx - band // 4, my - band // 4, mx + band // 4, my + band // 4, FC)

    # --- tiles, set into grout with a real gap -------------------------
    inner_w, inner_h = w - 2 * band, h - 2 * band
    grout = 7
    tile = min((inner_w - grout * 9) // 8, (inner_h - grout * 4) // 3)
    ox = band + (inner_w - (tile * 8 + grout * 9)) // 2 + grout
    oy = band + (inner_h - (tile * 3 + grout * 4)) // 2 + grout

    def tile_rect(row, col):
        return (ox + (col - 1) * (tile + grout), oy + (row - 1) * (tile + grout))

    for row in range(1, 4):
        for col in range(1, 9):
            if col in (5, 6) and row != 2:
                continue
            x0, y0 = tile_rect(row, col)
            rect(x0, y0, x0 + tile, y0 + tile, IV)
            rect(x0, y0, x0 + tile, y0 + 2, SH)        # a set-in edge
            rect(x0, y0, x0 + 2, y0 + tile, SH)
            c = tile / 2.0
            cx, cy = x0 + c, y0 + c
            d = ur_decor(row, col)
            q = tile / 4.0

            if d == "rosette":
                # Eight POINTED petals alternating red and blue, gold outline,
                # white centre. Drawn as tapered wedges rather than discs: the
                # first pass used circles and read as a flower rather than the
                # reference's eight-point star, which is the single most
                # recognisable marking on the board.
                for a in range(8):
                    ang = a * math.pi / 4
                    tone = PET if a % 2 == 0 else INK
                    tipx, tipy = cx + math.cos(ang) * q * 1.85, cy + math.sin(ang) * q * 1.85
                    steps = int(q * 2)
                    for stp in range(steps + 1):
                        t = stp / max(1, steps)
                        px_ = cx + (tipx - cx) * t
                        py_ = cy + (tipy - cy) * t
                        disc(px_, py_, max(1.0, q * 0.52 * (1.0 - t * 0.88)), tone)
                ring(cx, cy, q * 1.9, GD)
                disc(cx, cy, q * 0.5, WH)
                ring(cx, cy, q * 0.5, GD)
            elif d == "fiveDots":
                for (dx, dy) in ((-q, -q), (q, -q), (0, 0), (-q, q), (q, q)):
                    disc(cx + dx, cy + dy, tile * 0.075, INK)
                    ring(cx + dx, cy + dy, tile * 0.115, INK)
            elif d == "eyes":
                for dy in (-q, q):
                    for dx in (-q, q):
                        for k in range(3):
                            ring(cx + dx, cy + dy, tile * (0.10 + k * 0.022), INK)
                        disc(cx + dx, cy + dy, tile * 0.05, INK)
            elif d == "squaresGrid":
                for gy in range(3):
                    for gx in range(3):
                        sx = x0 + tile * (0.16 + gx * 0.26)
                        sy = y0 + tile * (0.16 + gy * 0.26)
                        rect(sx, sy, sx + tile * 0.19, sy + tile * 0.19, INK)
                        rect(sx + 2, sy + 2, sx + tile * 0.19 - 2,
                             sy + tile * 0.19 - 2, IV)
                        disc(sx + tile * 0.095, sy + tile * 0.095,
                             tile * 0.045, INK)
            elif d == "dottedField":
                for gy in range(5):
                    for gx in range(5):
                        disc(x0 + tile * (0.16 + gx * 0.17),
                             y0 + tile * (0.16 + gy * 0.17), tile * 0.035, INK)
            else:   # zigzagFive
                # Continuous chevron bands, not a field of dashes.
                #
                # The first pass stepped a short rectangle up and down and drew
                # disconnected ticks — at tile size that read as another dotted
                # pattern, which this board already has two of. A zigzag is a
                # LINE; it has to actually connect corner to corner.
                for zy in range(4):
                    yy = y0 + tile * (0.17 + zy * 0.215)
                    amp = tile * 0.075
                    period = tile * 0.22
                    span = tile * 0.72
                    px_prev = None
                    for stp in range(int(span)):
                        xx = x0 + tile * 0.14 + stp
                        phase = (stp % period) / period
                        yv = yy + (amp * (2 * phase - 1) if (stp // period) % 2 == 0
                                   else amp * (1 - 2 * phase))
                        if px_prev is not None:
                            steps2 = max(1, int(abs(yv - px_prev)))
                            for k in range(steps2 + 1):
                                iy = px_prev + (yv - px_prev) * k / steps2
                                rect(xx, iy, xx + 2, iy + 2, INK)
                        px_prev = yv
                for (dx, dy) in ((-q, -q), (q, -q), (0, 0), (-q, q), (q, q)):
                    disc(cx + dx * 0.9, cy + dy * 0.9, tile * 0.045, INK)

    # Two pieces, with the hard offset shadow Elevation now specifies — dx as
    # well as dy, which drawPiece currently omits.
    for (row, col), seat in (((2, 2), INK), ((2, 7), PET)):
        x0, y0 = tile_rect(row, col)
        cx, cy, r = x0 + tile / 2, y0 + tile / 2, tile * 0.30
        disc(cx + 2, cy + 2, r, SH)
        disc(cx, cy, r, seat)
        ring(cx, cy, r, WH)
        ring(cx, cy, r * 0.62, WH)

    p = os.path.join(OUT, "royalur-board.png")
    wood.write_png(p, img, pal)
    return p


if __name__ == "__main__":
    want = sys.argv[1:] or ["steel", "board", "surfaces", "screens"]
    if "steel" in want:
        print("wrote", steel_sheet())
    if "board" in want:
        for p in scoreboard_sheet():
            print("wrote", p)
    if "surfaces" in want:
        print("wrote", posterised_sheet())
    if "screens" in want:
        print("wrote", rollbots_screen())
    if "board" in want or "screens" in want:
        print("wrote", royalur_board())