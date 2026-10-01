"""Checks the dice dither the Swift will draw against the one that was seen.

Same job as tools_smoke_verify does for the floor and tools_wood_verify for
the timber, and the same reason: the dither exists twice, as Swift in
`DieMaterialFactory` and as Python in `tools_dice_preview.py`, and only the
Python one can be looked at in this container.

It also guards the three things about this that are invisible until they are
wrong, and then unmissable:

    the numerals are unreachable   the body material must be set on the die
                                   body ALONE, with the numerals on their own
                                   nodes. This is the entire reason the
                                   dither is safe, and it is one edit away
                                   from not being true.
    nearest-neighbour filtering    the tile is 8x8 texels magnified across a
                                   whole face. With the default linear filter
                                   SceneKit interpolates between them and the
                                   dither arrives as a soft grey wash — which
                                   looks worse than no dither, and looks like
                                   a rendering bug rather than a setting.
    multiply, not diffuse          in the multiply channel the body colour
                                   survives and all fifteen colourways stay
                                   distinguishable. Moved to diffuse it would
                                   REPLACE the body colour, which is the one
                                   thing that was explicitly not wanted.

    python3 tools_dice_verify.py
"""
import re
import sys

from tools_swiftconst import source

import tools_dice_preview as preview

SWIFT = "DieMaterialFactory.swift"
LABELS = "DieFaceLabels.swift"


def main():
    text = source(SWIFT)
    failed = []

    # --- 1. The strength agrees with what was previewed. ---------------
    match = re.search(r'static let ditherStrength: CGFloat = ([\d.]+)', text)
    if not match:
        failed.append("%s no longer declares `ditherStrength`" % SWIFT)
    else:
        strength = float(match.group(1))
        if strength not in preview.STRENGTHS:
            failed.append("ditherStrength = %g is not one of the strengths "
                          "tools_dice_preview renders (%s) — the value that "
                          "ships is one nobody has looked at"
                          % (strength, preview.STRENGTHS))
        else:
            print("  %-26s ok (%.2f, previewed)" % ("strength", strength))

    cells = re.search(r'static let ditherCellsPerFace: CGFloat = ([\d.]+)', text)
    if not cells:
        failed.append("%s no longer declares `ditherCellsPerFace`" % SWIFT)
    else:
        shipped = float(cells.group(1))
        previewed = preview.SWATCH // preview.CELL
        if abs(shipped - previewed) > 1e-9:
            failed.append("ditherCellsPerFace = %g but tools_dice_preview "
                          "renders %d cells across a face (SWATCH %d / CELL "
                          "%d) — the density on the sheet is not the density "
                          "that ships, and cell size is the one thing here "
                          "that can only be judged by looking"
                          % (shipped, previewed, preview.SWATCH, preview.CELL))
        else:
            print("  %-26s ok (%g across a face, previewed)"
                  % ("cell density", shipped))

    # --- 2. The dither cannot reach the numerals. ----------------------
    #
    # Two halves, and both have to hold. The body material must be assigned
    # as the die's WHOLE material list (so it is the body and nothing else),
    # and the numerals must be their own nodes carrying their own geometry.
    if "node.geometry?.materials = [material]" not in text:
        failed.append("%s no longer assigns the body material as the node's "
                      "entire material list — if a numeral ever shares this "
                      "material, the dither is drawn straight through it, "
                      "which is the one thing this treatment must never do"
                      % SWIFT)
    elif "material.multiply.contents = dither" not in text:
        failed.append("%s no longer puts the dither in the multiply channel"
                      % SWIFT)
    else:
        print("  %-26s ok (body material only)" % "numerals unreachable")

    labels = source(LABELS)
    if "SCNPlane(" not in labels:
        failed.append("%s no longer builds numerals as their own SCNPlane "
                      "nodes — they may now share the body's material, and "
                      "the dither would be drawn through them" % LABELS)

    # --- 3. Nearest-neighbour, or the whole thing is a grey wash. ------
    for setting in ("material.multiply.magnificationFilter = .nearest",
                    "material.multiply.minificationFilter = .nearest"):
        if setting not in text:
            failed.append("%s does not set `%s` — an 8x8 tile magnified "
                          "across a face under the default linear filter "
                          "arrives as a soft grey wash, not a dither"
                          % (SWIFT, setting.split(" = ")[0].split(".")[-1]))
    if not any("filter" in f for f in failed):
        print("  %-26s ok (hard texels, no interpolation)" % "filtering")

    # --- 4. Multiply, never diffuse. -----------------------------------
    if re.search(r'material\.diffuse\.contents = dither', text):
        failed.append("%s puts the dither in the DIFFUSE channel — that "
                      "replaces the body colour instead of shading it, and "
                      "collapses the fifteen colourways the dice are told "
                      "apart by. It belongs in multiply." % SWIFT)
    else:
        print("  %-26s ok (body colour survives)" % "multiply channel")

    # --- 5. The Bayer matrix is the real one. --------------------------
    #
    # A transposed or mis-typed matrix still dithers and still looks broadly
    # plausible, while producing visible diagonal banding rather than an even
    # stipple. Checked against the arithmetic definition the floor's shader
    # uses, so the two cannot drift into different patterns.
    rows = re.search(r'private static let bayer8: \[\[Int\]\] = \[(.+?)\n    \]',
                     text, re.S)
    if not rows:
        failed.append("%s no longer declares the bayer8 matrix" % SWIFT)
    else:
        values = [int(v) for v in re.findall(r'-?\d+', rows.group(1))]
        if len(values) != 64 or sorted(values) != list(range(64)):
            failed.append("the bayer8 matrix is not a permutation of 0..63 — "
                          "it dithers unevenly, which reads as banding")
        else:
            worst = 0.0
            for y in range(8):
                for x in range(8):
                    want = preview.smoke.bayer8(x, y) * 64
                    worst = max(worst, abs(values[y * 8 + x] - want))
            if worst > 1e-6:
                failed.append("the bayer8 literal disagrees with the "
                              "arithmetic Bayer the floor's shader uses "
                              "(worst cell off by %g) — the dice and the "
                              "floor would stipple on different patterns"
                              % worst)
            else:
                print("  %-26s ok (matches the floor's, exactly)" % "bayer matrix")

    # --- 6. The numerals still clear the bar. --------------------------
    if preview.check_contrast() != 0:
        failed.append("some colourway's numeral drops below 3:1 under the "
                      "dither that was not already there")

    if failed:
        print()
        for line in failed:
            print("  FAIL  %s" % line)
        print("\ndice: FAIL (%d)" % len(failed))
        return 1
    print("\ndice: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
