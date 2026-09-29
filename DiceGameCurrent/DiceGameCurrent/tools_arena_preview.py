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
    IVORY, TURF, DIRT = "#F4EDDF", "#36F422", "#C9B18A"

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

def rollbots_screen(w=560, h=780):
    import tools_type as type_

    steel = steel_palette()
    tile = render_steel()
    arena = tone_ramp("#05070E")
    panel = tone_ramp("#0B1220")
    CY, MG, INK, DIM = (34, 227, 255), (255, 45, 120), (201, 247, 255), (120, 150, 165)
    pal = list(steel) + arena + panel + [CY, MG, INK, DIM]
    S0, A0, P0 = 0, len(steel), len(steel) + len(arena)
    CYI, MGI, INKI, DIMI = P0 + 4, P0 + 5, P0 + 6, P0 + 7

    img = [bytearray([A0 + 1]) * w for _ in range(h)]

    def rect(x0, y0, x1, y1, t):
        for y in range(max(0, y0), min(h, y1)):
            for x in range(max(0, x0), min(w, x1)):
                img[y][x] = t

    rail = max(92, min(int(w * 0.22), 128))
    bar = 104
    body_h = h - bar

    # The arena field, behind everything, in the game's own near-black.
    cells = max(8, (w - 2 * rail) // 4)
    for cy in range(cells):
        v = (cy + .5) / cells
        row = [smoke.tone((cx + .5) / cells, v, 0.0, cx, cy) for cx in range(cells)]
        for dy in range(body_h * cy // cells, body_h * (cy + 1) // cells):
            for dx in range(w - 2 * rail):
                img[dy][rail + dx] = A0 + row[dx * cells // (w - 2 * rail)]

    # Steel rails down both edges, tiled from the same plate texture.
    th, tw = len(tile), len(tile[0])
    tile_h = max(1, int(rail * th / tw) * 3)
    for y in range(h):
        for x in list(range(rail)) + list(range(w - rail, w)):
            img[y][x] = tile[int((y % tile_h) * th / tile_h) % th][
                            int((x % rail) * tw / rail) % tw]

    # A cyan seam where each rail meets the field — the same one line the
    # border preview used, so the rails read as the same object as the rim.
    for y in range(body_h):
        img[y][rail] = CYI
        img[y][w - rail - 1] = MGI

    def panel_box(x0, y0, x1, y1, fill, edge):
        rect(x0 + 2, y0 + 2, x1 + 2, y1 + 2, S0)
        rect(x0, y0, x1, y1, S0)
        rect(x0 + 2, y0 + 2, x1 - 2, y1 - 2, fill)
        rect(x0 + 2, y0 + 2, x1 - 2, y0 + 4, edge)

    for side, (x0, seat, name, ip) in enumerate(
            ((6, CYI, "YOU", 42), (w - rail + 6, MGI, "RIVAL", 31))):
        type_.draw(img, pal, name, "Poppins-SemiBold", 13, x0 + 4, 30, INK)
        type_.draw(img, pal, str(ip), "Poppins-Bold", 34, x0 + 4, 74, INK)
        type_.draw(img, pal, "IP", "Poppins-Regular", 11, x0 + 4, 94, DIMI)
        # The IP bar: fills from the bottom, seat-coloured.
        bx0, bx1, by0, by1 = x0 + 4, x0 + rail - 16, 110, 430
        rect(bx0, by0, bx1, by1, P0 + 1)
        frac = ip / 50.0
        rect(bx0, int(by1 - (by1 - by0) * frac), bx1, by1, seat)
        rect(bx0, by0, bx1, by0 + 2, S0); rect(bx0, by1 - 2, bx1, by1, S0)
        rect(bx0, by0, bx0 + 2, by1, S0); rect(bx1 - 2, by0, bx1, by1, S0)
        type_.draw(img, pal, "RAIL GUN", "Poppins-SemiBold", 12, x0 + 4, 486, INK)
        type_.draw(img, pal, "Phase", "Poppins-Regular", 10, x0 + 4, 540, DIMI)

    # The two corner chrome buttons, on the field.
    for bx, glyph in ((rail + 12, "<"), (w - rail - 44, "=")):
        panel_box(bx, 12, bx + 32, 44, A0, P0 + 3)
        type_.draw(img, pal, glyph, "Poppins-SemiBold", 16, bx + 16, 36, INK,
                   centre=True)

    # The action bar.
    panel_box(rail + 8, body_h + 10, w - rail - 8, h - 12, P0 + 1, CYI)
    type_.draw(img, pal, "ATTACK", "Poppins-Bold", 20, w // 2, body_h + 52, INK,
               centre=True)
    type_.draw(img, pal, "3 dice · rail gun", "Poppins-Regular", 12, w // 2,
               body_h + 78, DIMI, centre=True)

    p = os.path.join(OUT, "rollbots-screen.png")
    wood.write_png(p, img, pal)
    return p


def royalur_screen(w=560, h=880):
    import tools_type as type_

    IVORY, INK, PETAL = "#F4EDDF", (27, 42, 74), (219, 54, 44)
    woodpal = wood.palette()
    tile = wood.render_tile()
    ivory = tone_ramp(IVORY)
    field = tone_ramp("#36F422")
    pal = list(woodpal) + ivory + field + [INK, PETAL, (250, 248, 244), (168, 160, 148)]
    W0, I0, F0 = 0, len(woodpal), len(woodpal) + len(ivory)
    INKI, PETI, WHT, DIM = F0 + 4, F0 + 5, F0 + 6, F0 + 7

    img = [bytearray([W0 + 2]) * w for _ in range(h)]

    def rect(x0, y0, x1, y1, t):
        for y in range(max(0, y0), min(h, y1)):
            for x in range(max(0, x0), min(w, x1)):
                img[y][x] = t

    header = int(h * 0.15)
    board_h = int(h * 0.34)
    button = 104
    tray_h = h - header - board_h - button

    th, tw = len(tile), len(tile[0])
    tile_w = max(1, int(w * wood.TILE_FRACTION))
    tile_h = max(1, int(tile_w * th / tw))
    for y in range(h):
        for x in range(w):
            img[y][x] = tile[int((y % tile_h) * th / tile_h) % th][
                            int((x % tile_w) * tw / tile_w) % tw]

    # The board. 3 rows x 8 columns, minus the four corners of the bridge
    # (columns 5 and 6 exist only on the middle row). Five rosettes.
    ROSETTES = {(1, 1), (3, 1), (2, 4), (1, 7), (3, 7)}
    tile_px = min((w - 24) // 8, (board_h - 20) // 3)
    bx0 = (w - tile_px * 8) // 2
    by0 = header + (board_h - tile_px * 3) // 2

    for row in range(1, 4):
        for col in range(1, 9):
            if col in (5, 6) and row != 2:
                continue
            x0 = bx0 + (col - 1) * tile_px
            y0 = by0 + (row - 1) * tile_px
            # Ivory, posterised to 4 tones and dithered, as approved.
            for yy in range(y0 + 2, y0 + tile_px - 2):
                for xx in range(x0 + 2, x0 + tile_px - 2):
                    lim = smoke.bayer8(xx, yy) - 0.5
                    img[yy][xx] = I0 + max(0, min(3, int(1.6 + lim * 2.2)))
            rect(x0, y0, x0 + tile_px, y0 + 2, INKI)
            rect(x0, y0 + tile_px - 2, x0 + tile_px, y0 + tile_px, INKI)
            rect(x0, y0, x0 + 2, y0 + tile_px, INKI)
            rect(x0 + tile_px - 2, y0, x0 + tile_px, y0 + tile_px, INKI)
            if (row, col) in ROSETTES:
                cx, cy, r = x0 + tile_px // 2, y0 + tile_px // 2, tile_px // 3
                for a in range(16):
                    ang = a * math.pi / 8
                    rr = r if a % 2 == 0 else r // 2
                    px_ = int(cx + rr * math.cos(ang))
                    py_ = int(cy + rr * math.sin(ang))
                    for dy in range(-2, 3):
                        for dx in range(-2, 3):
                            yy, xx = py_ + dy, px_ + dx
                            if 0 <= yy < h and 0 <= xx < w:
                                img[yy][xx] = PETI if a % 2 == 0 else INKI
                for dy in range(-3, 4):
                    for dx in range(-3, 4):
                        if dx * dx + dy * dy <= 9:
                            img[cy + dy][cx + dx] = WHT

    # Two pieces, one per seat.
    for (row, col), seat in (((2, 2), INKI), ((2, 7), PETI)):
        cx = bx0 + (col - 1) * tile_px + tile_px // 2
        cy = by0 + (row - 1) * tile_px + tile_px // 2
        r = tile_px // 3
        for dy in range(-r - 2, r + 3):
            for dx in range(-r - 2, r + 3):
                d = math.hypot(dx, dy)
                if d <= r:
                    img[cy + dy + 2][cx + dx + 1] = W0    # hard offset shadow
        for dy in range(-r, r + 1):
            for dx in range(-r, r + 1):
                d = math.hypot(dx, dy)
                if d <= r:
                    img[cy + dy][cx + dx] = seat
                elif d <= r + 1:
                    img[cy + dy][cx + dx] = W0

    # Scoreboard header and the tray below the board.
    type_.draw(img, pal, "ROYAL UR", "Poppins-SemiBold", 17, 20, 42, WHT)
    type_.draw(img, pal, "3", "Poppins-Black", 40, 40, 100, WHT, centre=True)
    type_.draw(img, pal, "2", "Poppins-Black", 40, w - 40, 100, WHT, centre=True)
    type_.draw(img, pal, "Your move", "Poppins-Regular", 13, w // 2, 106, DIM,
               centre=True)

    ty0 = header + board_h
    rim = 14
    cells = max(8, (w - 2 * rim) // 4)
    for cy in range(cells):
        v = (cy + .5) / cells
        row_t = [smoke.tone((cx + .5) / cells, v, 0.0, cx, cy) for cx in range(cells)]
        for dy in range(max(0, tray_h - 2 * rim) * cy // cells,
                        max(0, tray_h - 2 * rim) * (cy + 1) // cells):
            for dx in range(w - 2 * rim):
                img[ty0 + rim + dy][rim + dx] = F0 + row_t[dx * cells // (w - 2 * rim)]
    for i in range(rim - 2, rim):
        for x in range(rim - 2, w - rim + 2):
            img[ty0 + i][x] = W0
            img[ty0 + tray_h - 1 - i][x] = W0
        for y in range(ty0 + rim - 2, ty0 + tray_h - rim + 2):
            img[y][i] = W0
            img[y][w - 1 - i] = W0
    type_.draw(img, pal, "Royal Ur", "Lobster-Regular", 46, w // 2,
               ty0 + tray_h // 2 + 14, tuple(field[0]), centre=True)

    by = h - button + 14
    rect(16 + 2, by + 2, w - 16 + 2, by + 50, W0)
    rect(16, by, w - 16, by + 48, W0)
    rect(18, by + 2, w - 18, by + 46, F0 + 2)
    rect(18, by + 2, w - 18, by + 4, W0 + 3)
    type_.draw(img, pal, "ROLL", "Poppins-Bold", 20, w // 2, by + 32, WHT,
               centre=True)

    p = os.path.join(OUT, "royalur-screen.png")
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
        print("wrote", royalur_screen())