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

    # --- a plain Button whose fill is decoration, not a tap target ----
    #
    # SwiftUI's .plain button style hit-tests the DRAWN content. A Text
    # draws only its glyphs, and a .frame around it is layout — not
    # something to tap. So a plain Button whose fill arrives from
    # .pixelPanel applied AFTER .buttonStyle is a button you can see but
    # mostly cannot press: the panel sits outside the button and takes no
    # part in hit-testing.
    #
    # This has now shipped twice. GameHubView's tiles were the first, when
    # their filled plate was removed and only the artwork stayed tappable;
    # the roll bar was the second, when .borderedProminent — which drew its
    # fill INSIDE the button — became .plain plus a panel outside. Both
    # were reported from the device, by someone tapping and getting
    # nothing.
    #
    # The fix either time is one line, .contentShape, which is why this
    # checks for it rather than trusting the next restyle to remember.
    for name in sorted(os.listdir(SWIFT)):
        if not name.endswith(".swift"):
            continue
        code = strip_comments(open(os.path.join(SWIFT, name)).read())
        for match in re.finditer(r'\.buttonStyle\(\.plain\)', code):
            chain = code[match.end(): match.end() + 400].split("\n\n")[0]
            if ".pixelPanel(" not in chain:
                continue          # fill is inside the label; nothing to do
            if ".contentShape(" in code[max(0, match.start() - 1200): match.start()]:
                continue
            line = code[:match.start()].count("\n") + 1
            failed.append("%s:%d is a .plain Button whose fill comes from a "
                          ".pixelPanel applied outside it, with no "
                          ".contentShape — the panel is visible but only the "
                          "label itself is tappable" % (name, line))

    # --- A tiled surface may not be sized by variable-height text. -----
    #
    # NetActionBar applied .background(SteelTiledBackground()) to a padded
    # VStack, and the caller centred that in a fixed .frame(height: 104). A
    # VStack sizes to its content, and that content is a subtitle with
    # lineLimit(3) and minimumScaleFactor(0.7) whose sentence changes every
    # phase — so the steel grew and shrank with the text, leaving bare arena
    # colour above and below it that moved as the turn progressed.
    #
    # The rule is narrowed to exactly that hazard rather than to every tiled
    # background, because most of them are legitimately content-sized: a score
    # bar's height follows its grid of cells, which is deterministic. What is
    # never legitimate is letting a sentence decide how far a MATERIAL
    # reaches. A surface is a surface; it does not breathe with a caption.
    TILED = ("SteelTiledBackground", "WoodTiledBackground")
    VARIABLE = ("lineLimit(", "minimumScaleFactor(")
    for name in sorted(f for f in os.listdir(SWIFT) if f.endswith(".swift")):
        code = strip_comments(source(name))
        for tiled in TILED:
            for m in re.finditer(r'\.background\(%s\(\)\)' % tiled, code):
                window = code[max(0, m.start() - 900):m.start()]
                if not any(v in window for v in VARIABLE):
                    continue          # nothing in it can change height
                if re.search(r'maxHeight:\s*\.infinity', window):
                    continue          # told to fill: correct
                if re.search(r'\.frame\(height:\s*\w', window):
                    continue          # given its own explicit height
                line = code[:m.start()].count("\n") + 1
                failed.append("%s:%d backs variable-height text with %s and "
                              "never tells it to fill — the material will "
                              "track the sentence, not the frame"
                              % (name, line, tiled))

    for line in failed:
        print("  %-26s FAILED  %s" % ("cohesion", line))
    if failed:
        sys.exit("cohesion: FAILED (%d problem(s))" % len(failed))

    print("  %-26s ok (direction shared, three heights)" % "one light")
    print("  %-26s ok (paper + ink, solid placements)" % "materials in use")
    print("  %-26s ok (no strokeBorder on a bare Shape)" % "shape constraints")
    print("  %-26s ok (every plain Button fills its own tap target)"
          % "tap targets")
    print("cohesion: PASS")


if __name__ == "__main__":
    main()
