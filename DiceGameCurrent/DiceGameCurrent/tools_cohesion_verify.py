"""Checks that the app is lit and layered from one place.

Four hand-picked shadow values had accumulated — 0.5/radius 4/y 2 on the
hub, 0.22 under Royal UR's trays, 0.25 under its pieces, 0.22 over the
board — and nothing said what any of them meant. A suite stops reading as
one object exactly this way: not through one bad decision, but through
four reasonable ones made separately.

So: `Elevation` owns depth, `PieceSheen` owns the light, and this fails
anything that goes around them. It also pins the two materials that were
added to close the survey's gaps, because a material nobody uses is the
same as no material.
"""
import os
import re
import sys

from tools_swiftconst import source

HERE = os.path.dirname(os.path.abspath(__file__))
SWIFT = os.path.join(HERE, "SwiftFiles")


def strip_comments(text):
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.S)
    return "\n".join(re.sub(r'//.*$', '', line) for line in text.splitlines())


def main():
    failed = []
    names = sorted(f for f in os.listdir(SWIFT) if f.endswith(".swift"))
    assert names, "no Swift sources found"

    # --- 1. One place owns depth. ------------------------------------
    for name in names:
        if name in ("Elevation.swift", "PieceSheen.swift"):
            continue
        code = strip_comments(source(name))
        for match in re.finditer(r'\.shadow\(', code):
            line = code[:match.start()].count("\n") + 1
            failed.append("%s:%d writes its own shadow — use .elevated(_:), "
                          "which is where the app's three heights live"
                          % (name, line))
    if not failed:
        print("  %-26s ok (%d files, none hand-roll a shadow)"
              % ("one source of depth", len(names) - 2))

    # --- 2. The light is shared, not duplicated. ---------------------
    elevation = strip_comments(source("Elevation.swift"))
    if "PieceSheen.litFromTop" not in elevation:
        failed.append("Elevation no longer takes its direction from "
                      "PieceSheen — the shadow and the highlight can now "
                      "disagree about where the light is")
    for height in ("resting", "piece", "lifted"):
        if "case %s" % height not in elevation:
            failed.append("Elevation lost its .%s height" % height)

    # --- 3. The materials are actually used. -------------------------
    generals = strip_comments(source("GeneralsScreen.swift"))
    if "LowPolyTextures.paperSurface" not in generals:
        failed.append("the Generals scorecard is not on paper any more")
    if "Color(hex: \"#2E2A22\")" not in generals:
        failed.append("the scorecard's ink is gone — printing on paper "
                      "cannot be white")
    if re.search(r'\.fill\(\s*isOpen \? theme\.accentColor', generals):
        failed.append("the cells are filled with the accent again, which is "
                      "what made twelve of them read as buttons")

    boneheads = strip_comments(source("BoneheadsScreen.swift"))
    if "pieceSolid(" not in boneheads:
        failed.append("Boneheads' placements lost the lit/bevelled/shadowed "
                      "treatment that makes them read as the tray's dice")

    if not source("LowPolyTextures.swift").count("paperSurface"):
        failed.append("LowPolyTextures has no paper generator")

    # --- 4. strokeBorder needs an InsettableShape. -------------------
    #
    # `strokeBorder` is declared on InsettableShape, not on Shape, so a
    # helper generic over `S: Shape` that strokes its own border does not
    # compile — "value of type 'S' has no member 'strokeBorder'", which is
    # exactly what the device reported for `pieceSolid`. A plain `stroke`
    # is not the fix either: it straddles the edge, so half a bevel would
    # fall outside the die.
    for name in names:
        code = strip_comments(source(name))
        for match in re.finditer(r'func\s+\w+\s*<\s*(\w+)\s*:\s*Shape\s*>', code):
            param = match.group(1)
            body, depth, started = "", 0, False
            for ch in code[match.end():]:
                if ch == "{":
                    depth += 1
                    started = True
                elif ch == "}":
                    depth -= 1
                body += ch
                if started and depth == 0:
                    break
            if "strokeBorder" in body:
                line = code[:match.start()].count("\n") + 1
                failed.append("%s:%d is generic over %s: Shape and calls "
                              "strokeBorder, which only exists on "
                              "InsettableShape — this does not compile"
                              % (name, line, param))

    for line in failed:
        print("  %-26s FAILED  %s" % ("cohesion", line))
    if failed:
        sys.exit("cohesion: FAILED (%d problem(s))" % len(failed))

    print("  %-26s ok (direction shared, three heights)" % "one light")
    print("  %-26s ok (paper + ink, solid placements)" % "materials in use")
    print("  %-26s ok (no strokeBorder on a bare Shape)" % "shape constraints")
    print("cohesion: PASS")


if __name__ == "__main__":
    main()
