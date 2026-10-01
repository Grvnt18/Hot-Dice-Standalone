"""The arithmetic of the dice' cel bands, and what it costs the numerals.

A die body is FLAT COLOUR — no texture on any channel — banded into five
tone steps by a fragment shader in `DieMaterialFactory`. This file is the
Python half of that: the band factors, and the contrast they leave between a
face and the numeral printed on it.

**What it does not do, and why.** It used to render PNG sheets of an ordered
Bayer stipple at several strengths and cell sizes. That stipple is gone — it
had no counterpart in the reference art, and it was the source of a real bug
(an 8x8 tile sampled `.nearest` with no mipmaps aliased badly once a face
went oblique, so the texture popped in and out as dice tumbled). What
replaced it cannot be drawn honestly here, because the bands depend on
SceneKit's own lighting rather than on anything reproducible in Python. So
this keeps only the part that IS reproducible, and the device judges the
rest.

**The contrast check is narrowed to the top band on purpose**, and
`check_band_contrast` carries the reasoning: the tray camera is straight-down
orthographic, the key light is above, and a die snaps to a face on settle, so
the face a player reads is always the brightest one. Side faces sinking to
near-black is the look, not a regression.

The numerals cannot be reached by the banding, and that is structural rather
than lucky. `DieFaceLabels` puts each numeral on its own SCNPlane child node
with its own material; `applyBodyMaterial` sets
`node.geometry?.materials = [material]` on the die body alone, and the cel
modifier is attached to that material.

    python3 tools_dice_preview.py   # the contrast table
"""
import sys

# math, os, tools_smoke_preview, tools_type and tools_wood_preview were all
# imported for the PNG sheets this used to render. Those sheets drew the
# ordered dither, which no longer exists, so the imports went with them
# rather than being left to imply this file still draws something.

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
CEL_BANDS = 5

# The shade range the bands span, as a fraction of a die's own body colour.
# Mirrors DieMaterialFactory.celShadeFloor / celShadeCeiling.
CEL_SHADE_FLOOR = 0.08
CEL_SHADE_CEILING = 1.0


def rgb(hexcode):
    return tuple(int(hexcode.lstrip("#")[i:i + 2], 16) for i in (0, 2, 4))


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


def band_factors(bands=CEL_BANDS,
                 lo=CEL_SHADE_FLOOR, hi=CEL_SHADE_CEILING):
    """The shade factors the shader quantises to: the centre of each band.

    `lo + (hi - lo) * (b + 0.5) / bands`, exactly as the Metal does. At three
    bands over 0.62-1.00 that is 0.683, 0.810 and 0.937 — so neither end of
    the range is ever actually reached, and in particular no face is driven to
    its own full brightness, which is the case that erases a numeral.
    """
    return [lo + (hi - lo) * (b + 0.5) / bands for b in range(bands)]


def banded(body, factor):
    """A body colour as the cel shader renders it at one band's shade factor.

    The output is the body colour SCALED, never replaced, which is what keeps
    hue and saturation — and therefore keeps the fifteen colourways tellable
    apart. Clamped as the shader clamps, which matters for a pale body in the
    top band where an unclamped scale would push a channel past white and
    overstate the contrast.
    """
    return tuple(min(255, max(0, int(round(c * factor)))) for c in body)


def check_band_contrast(bands=CEL_BANDS):
    """Whether the numeral stays legible ON THE FACE THAT IS ACTUALLY READ.

    This deliberately asserts the TOP band only, and the reasoning belongs
    here rather than in a commit message, because it is a loosening.

    The tray camera is straight-down ORTHOGRAPHIC, the key light is above,
    and a die snaps to a face when it settles. So the face a player reads is
    always the one most square to the light — the top band. The darker bands
    are side faces, seen edge-on at a steep angle, and the reference art this
    look is built from deliberately sinks those to near-black with no legible
    numeral at all. Requiring 3:1 of them was protecting something nobody
    looks at, and it was holding the tonal range to 1.4x when the reference
    is nearer 10x.

    The first version of this check earned its keep by catching a worse
    error — a shader that quantised ABSOLUTE luminance, which flattened the
    palette's dark-numeral-on-light-body pairing to 1.13:1. That is why the
    check survives in a narrowed form rather than being deleted: the thing it
    guards against is real, it was just aimed at every band instead of the
    one that matters.

    Widening the range IMPROVES this figure, which is worth stating plainly
    because it is counter-intuitive: a wider range lowers the top band's own
    factor (0.937 at 0.62-1.00, 0.908 at 0.08-1.00), and a slightly darkened
    body separates better from a light numeral.
    """
    bar = 3.0
    factors = band_factors(bands)
    top = factors[-1]
    print("\nNumeral contrast on the TOP band — the face the camera reads.")
    print("Shade factors: %s\n" % ", ".join("%.3f" % f for f in factors))

    worst = None
    failures = []
    for body_hex, num_hex in COLORWAYS:
        body, num = rgb(body_hex), rgb(num_hex)
        ratio = contrast(banded(body, top), num)
        if worst is None or ratio < worst[0]:
            worst = (ratio, body_hex, num_hex)
        if ratio < bar:
            # Asserted outright, not merely "no worse than flat". Three
            # colourways sit under the bar FLAT today and the banding lifts
            # all three above it, so the strict form is achievable — and a
            # check that only forbids regressions would quietly accept
            # shipping those three unreadable forever.
            failures.append((body_hex, num_hex, contrast(body, num), ratio))

    print("  top band (x%.3f) — worst %s on %s at %.2f:1"
          % (top, worst[2], worst[1], worst[0]))
    print("  darkest band (x%.3f) is a side face and is allowed to go dark."
          % factors[0])

    under_flat = [(h, n, contrast(rgb(h), rgb(n)))
                  for h, n in COLORWAYS if contrast(rgb(h), rgb(n)) < bar]
    if under_flat:
        print("\n  Under %.1f:1 FLAT today, before any of this — the top band"
              % bar)
        print("  improves every one, since shading a light body under a light")
        print("  numeral moves them apart:")
        for h, n, r in under_flat:
            print("    %-9s on %-9s  flat %.2f:1  top band %.2f:1"
                  % (n, h, r, contrast(banded(rgb(h), top), rgb(n))))

    if failures:
        print("\n  FAIL — unreadable on the face that gets read:")
        for h, n, flat, got in failures:
            print("    %-9s on %-9s  flat %.2f:1 -> top band %.2f:1"
                  % (n, h, flat, got))
        return 1
    print("\n  PASS — every colourway clears %.1f:1 on the read face." % bar)
    return 0


if __name__ == "__main__":
    # The two PNG sheets this used to render both showed the ordered dither
    # at a range of strengths and cell sizes. The dither is gone, and a die
    # body is now flat colour banded by a shader — which is not something a
    # Python port can draw honestly, because the bands depend on SceneKit's
    # own lighting rather than on anything reproducible here. So this file
    # keeps the part that IS reproducible: the arithmetic of the bands, and
    # what they do to numeral contrast.
    sys.exit(check_band_contrast())
