"""The dither the dice are about to wear, over the real colourways.

The floor is a four-tone posterised field. The dice deliberately are NOT —
they keep all fifteen colourways, because that palette is how you tell one
die from another and collapsing it would cost the game something real. What
they can take is the same ordered 8x8 Bayer *stipple*, applied as a gentle
darkening over the body colour rather than as a quantiser: the surface picks
up the floor's pixel grammar while the colour stays exactly where it was.

The numerals are not at risk here, and that is structural rather than lucky.
`DieFaceLabels.addPermanentFaceNumbers` puts each numeral on its own SCNPlane
child node with its own material; `applyBodyMaterial` sets
`node.geometry?.materials = [material]` on the die body alone. A texture in
the body's multiply channel cannot reach a numeral even in principle. This
tool draws one over the top anyway, at the real ratio, because "cannot in
principle" is exactly the kind of claim worth showing.

The two things that actually need judging by eye, and cannot be reasoned out:

    strength    how dark the dark cells go. Too little and it is invisible
                on a device; too much and a mid-tone die turns muddy and the
                numeral's contrast drops with it.
    cell size   how many screen pixels one dither cell covers. Too small and
                it reads as photographic noise — which is the exact thing
                `applyGrainToDice = false` turned off, and the reason it must
                not come back in through a different door.

    python3 tools_dice_preview.py            # the sheet
    python3 tools_dice_preview.py --contrast # numeral contrast, measured
"""
import math
import os
import sys

import tools_smoke_preview as smoke
import tools_type as type_
import tools_wood_preview as wood

OUT = os.path.dirname(os.path.abspath(__file__))

# DiePalette.colorways, verbatim. Fifteen bodies with their paired numeral
# colour — the pairing is chosen for contrast and is why the near-white die
# does not draw a white numeral.
COLORWAYS = [
    ("#6E6456", "#F5F5F5"), ("#CCDB48", "#1B1B1B"), ("#CB7D94", "#F5F5F5"),
    ("#9A593A", "#F5F5F5"), ("#FDE558", "#1B1B1B"), ("#A1CFDD", "#1B1B1B"),
    ("#DB362C", "#F5F5F5"), ("#FFA23F", "#1B1B1B"), ("#D33AFD", "#F5F5F5"),
    ("#7CBD7B", "#1B1B1B"), ("#A88E65", "#F5F5F5"), ("#D2735F", "#F5F5F5"),
    ("#FBD365", "#1B1B1B"), ("#FCFBF9", "#1B1B1B"), ("#00ADB4", "#F5F5F5"),
]

# Candidate strengths, as the fraction a dark cell is multiplied down by.
# 0.05 is what the old photographic grain used and is included as the "too
# subtle to see" end of the range rather than as a real candidate.
STRENGTHS = [0.05, 0.10, 0.16, 0.24]

# SWATCH // CELL is the cells-across-a-face figure the Swift ships as
# `DieMaterialFactory.ditherCellsPerFace`, and tools_dice_verify.py asserts
# the two agree — so this sheet shows the density that actually ships rather
# than a density that merely looked nice once.
CELL = 6          # texels per dither cell, at the scale a die is seen
SWATCH = 120      # preview swatch side, ~ a die at arm's length on a tablet

# 120 // 6 = 20 cells across a face, down from 126 // 9 = 14. The iPad said
# 14 was too coarse — the pixels were what you noticed rather than the die —
# so both numbers moved together and the swatch stayed the same size, since
# it stands for a real die at a real viewing distance and that did not change.


def rgb(hexcode):
    return tuple(int(hexcode.lstrip("#")[i:i + 2], 16) for i in (0, 2, 4))


def dithered(base, strength, cell=CELL, side=SWATCH, facet=0.0):
    """The body colour with an ordered-Bayer stipple multiplied over it.

    MULTIPLY, not replace — which is the whole reason the fifteen colourways
    survive this. Every texel is either the body colour or the body colour
    scaled by (1 - strength), so the hue never moves and the palette stays
    exactly as distinguishable as it was.
    """
    r, g, b = base
    out = [[(0, 0, 0)] * side for _ in range(side)]
    for y in range(side):
        for x in range(side):
            # One threshold per CELL x CELL block, so the stipple reads as
            # pixels rather than as per-texel noise.
            limit = smoke.bayer8(x // cell, y // cell)
            # A fixed 0.5 duty against the Bayer threshold gives the regular
            # checker the reference art uses. Nudging it with `facet` is how
            # a lit facet and a shadowed one differ.
            dark = limit > 0.5 + facet
            k = (1.0 - strength) if dark else 1.0
            out[y][x] = (int(r * k), int(g * k), int(b * k))
    return out


def luminance(c):
    """WCAG relative luminance."""
    def channel(v):
        v /= 255.0
        return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4
    return 0.2126 * channel(c[0]) + 0.7152 * channel(c[1]) + 0.0722 * channel(c[2])


def contrast(a, b):
    la, lb = luminance(a), luminance(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


def check_contrast():
    """What the dither costs the numerals — and what it does not.

    The first version of this reported a FAIL at 2.52:1 and was measuring the
    wrong thing: that number is `#00ADB4` FLAT, which is what ships today and
    is not something this change causes. The dither only ever moves a
    colourway's contrast in one direction per pairing, and the direction
    depends on the numeral:

        dark numeral on a light body   darkening the body moves it TOWARD the
                                       numeral, so contrast falls
        light numeral on a darker body darkening moves it AWAY, so contrast
                                       rises

    So the only group at risk is the first, and the question is whether the
    dither pushes any colourway below the 3:1 WCAG large-text bar that was
    not already below it. A numeral on a die is big, bold type read at arm's
    length, which is what makes 3:1 the relevant line rather than 4.5:1.
    """
    bar = 3.0
    print("Numeral contrast: flat (ships today) vs the dither's dark cells.")
    print("Only pairings that LOSE contrast can be made worse by this.\n")

    pre_existing = [(h, n, contrast(rgb(h), rgb(n)))
                    for h, n in COLORWAYS if contrast(rgb(h), rgb(n)) < bar]

    regressions = []
    for strength in STRENGTHS:
        losers = []
        for body_hex, num_hex in COLORWAYS:
            body, num = rgb(body_hex), rgb(num_hex)
            dark = tuple(int(c * (1 - strength)) for c in body)
            flat_r, dark_r = contrast(body, num), contrast(dark, num)
            if dark_r < flat_r:
                losers.append((body_hex, num_hex, flat_r, dark_r))
                if dark_r < bar <= flat_r:
                    regressions.append((strength, body_hex, flat_r, dark_r))
        worst = min(losers, key=lambda r: r[3]) if losers else None
        print("  strength %.2f — %d pairings lose contrast, worst %s at %.2f:1"
              % (strength, len(losers),
                 worst[0] if worst else "-", worst[3] if worst else 0))

    print("\n  Already under %.1f:1 today, before any dither:" % bar)
    for h, n, r in pre_existing:
        print("    %-9s on %-9s  %.2f:1" % (n, h, r))
    print("  These three are pre-existing and the dither IMPROVES all of them")
    print("  (a light numeral on a light-ish body: darkening moves them apart).")

    if regressions:
        print("\n  FAIL — the dither pushes these under %.1f:1:" % bar)
        for strength, h, flat_r, dark_r in regressions:
            print("    strength %.2f  %s  %.2f -> %.2f" % (strength, h, flat_r, dark_r))
        return 1
    print("\n  PASS — at no strength does the dither take any colourway")
    print("  below %.1f:1 that was not already there." % bar)
    return 0


def sheet():
    """Every colourway down the page, every strength across it.

    Plus a numeral over each, at the size-to-die ratio DieFaceLabels uses, so
    the claim that the dither cannot reach the numerals is visible rather
    than merely argued.
    """
    cols = len(STRENGTHS) + 1          # flat, then one per strength
    pad, top, left = 12, 74, 96
    w = left + cols * (SWATCH + pad) + pad
    h = top + len(COLORWAYS) * (SWATCH // 2 + pad) + 40

    pal, index = [], {}

    def tone(c):
        if c not in index:
            index[c] = len(pal)
            pal.append(c)
        return index[c]

    # RGB tuples, NOT pre-resolved indices: tools_type.draw resolves the
    # colour against the palette itself. Handing it an index instead makes it
    # search a list of tuples for an integer, miss, and append that integer
    # to the colour table — which is how the first run of this sheet drew
    # #6E6456 as near-white and #00ADB4 as pink.
    BG, INK, DIM = (18, 16, 14), (236, 232, 226), (150, 144, 136)
    tone(BG); tone(INK); tone(DIM)
    img = [bytearray([index[BG]]) * w for _ in range(h)]

    def blit(block, ox, oy, rows):
        for y in range(rows):
            for x in range(len(block[0])):
                if 0 <= oy + y < h and 0 <= ox + x < w:
                    img[oy + y][ox + x] = tone(block[y][x])

    type_.draw(img, pal, "Dice dither — the body only, never the numeral",
               "Poppins-SemiBold", 21, 22, 34, INK)
    type_.draw(img, pal, "multiply over the body colour, so all 15 colourways "
               "keep their hue", "Poppins-Regular", 13, 22, 56, DIM)

    headers = ["flat (now)"] + ["%.2f" % s for s in STRENGTHS]
    for c, label in enumerate(headers):
        x = left + c * (SWATCH + pad)
        type_.draw(img, pal, label, "Poppins-Medium", 13,
                   x + SWATCH // 2, top - 8, DIM, centre=True)

    half = SWATCH // 2
    for r, (body_hex, num_hex) in enumerate(COLORWAYS):
        y = top + r * (half + pad)
        base, num = rgb(body_hex), rgb(num_hex)
        type_.draw(img, pal, body_hex, "Poppins-Regular", 12, 14,
                   y + half // 2 + 4, DIM)
        for c in range(cols):
            x = left + c * (SWATCH + pad)
            strength = 0.0 if c == 0 else STRENGTHS[c - 1]
            block = dithered(base, strength, side=SWATCH)
            blit(block, x, y, half)
            # The numeral, over the top, exactly as the label plane sits over
            # the body in the scene.
            type_.draw(img, pal, "8", "Poppins-Bold", int(half * 0.72),
                       x + SWATCH // 2, y + half - 6, num, centre=True)

    path = os.path.join(OUT, "dice-dither.png")
    wood.write_png(path, img, pal)
    return path


def scale_sheet(strength=0.10):
    """The same strength at several cell sizes, which is the other unknown.

    Strength can be reasoned about — it is a contrast number and the check
    above measures it. Cell size cannot: it is entirely a question of how
    many screen pixels one dither cell covers on a real device, and too small
    is the specific failure that matters, because a stipple finer than the
    eye resolves stops being pixel art and becomes photographic noise. That
    is exactly what `applyGrainToDice = false` turned off, and it must not
    come back in through a different door.
    """
    cells = [2, 4, 6, 9, 13]
    picks = [("#DB362C", "#F5F5F5"), ("#FDE558", "#1B1B1B"),
             ("#00ADB4", "#F5F5F5"), ("#FCFBF9", "#1B1B1B")]
    pad, top, left = 14, 78, 84
    w = left + len(cells) * (SWATCH + pad) + pad
    h = top + len(picks) * (SWATCH + pad) + 30

    pal, index = [], {}

    def tone(c):
        if c not in index:
            index[c] = len(pal)
            pal.append(c)
        return index[c]

    BG, INK, DIM = (18, 16, 14), (236, 232, 226), (150, 144, 136)
    tone(BG); tone(INK); tone(DIM)
    img = [bytearray([index[BG]]) * w for _ in range(h)]

    type_.draw(img, pal, "Dither cell size, at strength %.2f" % strength,
               "Poppins-SemiBold", 21, 22, 34, INK)
    type_.draw(img, pal, "each swatch is roughly one die face at arm's length"
               " — smaller cells read as noise, not pixels",
               "Poppins-Regular", 13, 22, 56, DIM)

    for c, cell in enumerate(cells):
        x = left + c * (SWATCH + pad)
        type_.draw(img, pal, "%dpx" % cell, "Poppins-Medium", 13,
                   x + SWATCH // 2, top - 10, DIM, centre=True)

    for r, (body_hex, num_hex) in enumerate(picks):
        y = top + r * (SWATCH + pad)
        base, num = rgb(body_hex), rgb(num_hex)
        type_.draw(img, pal, body_hex, "Poppins-Regular", 12, 10,
                   y + SWATCH // 2, DIM)
        for c, cell in enumerate(cells):
            x = left + c * (SWATCH + pad)
            block = dithered(base, strength, cell=cell, side=SWATCH)
            for by in range(SWATCH):
                for bx in range(SWATCH):
                    img[y + by][x + bx] = tone(block[by][bx])
            type_.draw(img, pal, "8", "Poppins-Bold", int(SWATCH * 0.66),
                       x + SWATCH // 2, y + SWATCH - 18, num, centre=True)

    path = os.path.join(OUT, "dice-dither-scale.png")
    wood.write_png(path, img, pal)
    return path


if __name__ == "__main__":
    if "--contrast" in sys.argv:
        sys.exit(check_contrast())
    print("wrote", sheet())
    print("wrote", scale_sheet())
