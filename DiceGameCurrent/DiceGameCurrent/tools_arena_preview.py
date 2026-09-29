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


if __name__ == "__main__":
    want = sys.argv[1:] or ["steel", "board", "surfaces"]
    if "steel" in want:
        print("wrote", steel_sheet())
    if "board" in want:
        for p in scoreboard_sheet():
            print("wrote", p)
    if "surfaces" in want:
        print("wrote", posterised_sheet())
