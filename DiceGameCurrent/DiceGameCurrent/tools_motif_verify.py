"""Checks the Swift floor motifs against the ones that were looked at.

`tools_motif_preview.py` renders each motif to a PNG, and those PNGs are
what got approved. `FloorMotif.swift` is the port. Two copies of the same
geometry drift — that is not a guess, it is what happened to the rules text,
to the icon loader, to GameHubView and to the baseball field earlier in this
project — so this reads both and asserts they agree.

It also checks the wiring, which is the part that silently rots as games are
added: every motif the preview knows must exist in the Swift enum, every
game that should carry one must declare it, and every screen must actually
pass it to its scene. A motif declared and never passed is invisible, and
looks exactly like a motif that does not work.
"""
import os
import re
import sys

from tools_swiftconst import source

import tools_motif_preview as preview

SWIFT = "FloorMotif.swift"
HERE = os.path.dirname(os.path.abspath(__file__))

# preview name -> Swift case. The names differ on purpose: `pig` is short
# enough for a filename, `pigFace` reads better as a case.
CASES = {
    "seven": "seven",
    "pig": "pigFace",
    "stars": "stars",
    "circles": "circles",
    "waves": "waves",
    "bones": "bones",
    "circuitry": "circuitry",
    "crowns": "crowns",
    "diceShapes": "diceShapes",
}

# game -> (motif case, the file its conformance lives in)
GAMES = {
    "JackpotGame": ("seven", "Jackpot.swift"),
    "HogGame": ("pigFace", "Hog.swift"),
    "GeneralsGame": ("stars", "Generals.swift"),
    "ThreeThousandGame": ("circles", "ThreeThousand.swift"),
    "FreighterYachtDinghyGame": ("waves", "FreighterYachtDinghy.swift"),
    "BoneheadsGame": ("bones", "Boneheads.swift"),
    "RollbotsGame": ("circuitry", "Rollbots.swift"),
    "RoyalUrGame": ("crowns", "RoyalUrScreen.swift"),
    "FreeRollGame": ("diceShapes", "FreeRoll.swift"),
}


def numbers(text):
    """Every decimal literal, in order — the geometry, stripped of syntax.

    Two Swift spellings are removed first because they are not geometry:
    tuple accessors like `$0.1` inside a map, and the `[-1.0, 1.0]` the
    mirrored halves loop over (the preview writes that as ints, which this
    does not pick up either way).
    """
    text = re.sub(r'\$\d+\.\d+', '', text)
    text = text.replace("[-1.0, 1.0] as [CGFloat]", "")
    # Swift tuple members — `p0.0`, `via.1`, `base.0` — read as decimals
    # to a regex and are not geometry. A real literal never begins with a
    # letter, so anchoring on one cannot swallow a coordinate.
    text = re.sub(r'\b[A-Za-z_]\w*\.\d+\b', '', text)
    return [float(n) for n in re.findall(r'-?\d+\.\d+', text)]


def swift_case_body(text, case):
    """The `case .x:` arm of `var shapes`, up to the next arm."""
    start = text.index("        case .%s:" % case)
    rest = text[start + 10:]
    ends = [m.start() for m in re.finditer(r'\n        case \.|\n        \}', rest)]
    return rest[:min(ends)] if ends else rest


def python_function(src, name):
    """One `def name(...)` body, to the next line at column zero.

    Not `\ndef `: module-level constants sit between the functions, and
    swallowing them made a builder look like it carried geometry it does
    not.
    """
    start = src.index("def %s(" % name)
    out = []
    for i, line in enumerate(src[start:].splitlines()):
        if i and line and not line[0].isspace():
            break
        out.append(line)
    return "\n".join(out)


def swift_function(text, name):
    """One `func name(` body, to the next func at the same indent."""
    start = text.index("func %s(" % name)
    rest = text[start + 5:]
    end = rest.find("\n    private func ")
    if end < 0:
        end = rest.find("\n    func ")
    return rest[:end] if end >= 0 else rest


def main():
    text = source(SWIFT)
    failed = []

    # --- 1. Every previewed motif exists, and no extras. --------------
    swift_cases = set(re.findall(r'^    case (\w+)', text, re.M))
    for name, case in sorted(CASES.items()):
        if case not in swift_cases:
            failed.append("the preview draws %s but %s has no case .%s"
                          % (name, SWIFT, case))
    extra = swift_cases - set(CASES.values()) - {"none"}
    for case in sorted(extra):
        failed.append("%s has a case .%s the preview never draws, so nobody "
                      "has seen it" % (SWIFT, case))
    if not failed:
        print("  %-26s ok (%d motifs, both sides)" % ("cases", len(CASES)))

    # --- 2. The geometry agrees, number for number. -------------------
    #
    # Compared as an ordered multiset of literals rather than line by line:
    # the two languages spell a polygon differently, but a shape moved or
    # resized in one and not the other changes a number, and that is the
    # drift worth catching.
    src = open(os.path.join(HERE, "tools_motif_preview.py")).read()
    for name, case in sorted(CASES.items()):
        py_start = src.index('if name == "%s":' % name)
        py_end = src.index("    if name ==", py_start + 20) if src.count(
            "    if name ==", py_start + 20) else src.index("    return []", py_start)
        # Sorted: the two languages spell the same shape in a different
        # order (a Swift map over centre lines against a Python list
        # comprehension), and that ordering carries no geometry. What it
        # gives up is catching two shapes swapped with identical numbers,
        # which would only matter to the pig's layering and would have to be
        # a pure reorder to slip through.
        want = sorted(numbers(src[py_start:py_end]))
        got = sorted(numbers(swift_case_body(text, case)))
        if want != got:
            only_py = [n for n in want if want.count(n) > got.count(n)]
            only_sw = [n for n in got if got.count(n) > want.count(n)]
            failed.append("%s: geometry differs — preview only %s, Swift only %s"
                          % (name, sorted(set(only_py))[:6],
                             sorted(set(only_sw))[:6]))
    # --- 2b. The tiled builders, which the case arms no longer hold ----
    #
    # A tiled motif's arm is one line — `tiled(columns:rows:inset:cell:)` —
    # and all its geometry lives in the cell builder. Comparing only the
    # arms would have checked almost nothing once the repeated motifs
    # landed, which is exactly the kind of hole that makes a green check
    # worthless.
    BUILDERS = {
        "seven_glyph": "sevenGlyph",
        "crown": "crown",
        "die_face": "dieShape",
        "bone_tile": "boneTile",
        "circuit_board": "circuitBoard",
        "segment": "segment",
        "tiled": "tiled",
    }
    for py_name, swift_name in sorted(BUILDERS.items()):
        want = sorted(numbers(python_function(src, py_name)))
        got = sorted(numbers(swift_function(text, swift_name)))
        if want != got:
            failed.append("%s/%s: geometry differs — preview %s, Swift %s"
                          % (py_name, swift_name, want, got))

    if not failed:
        total = (sum(len(numbers(swift_case_body(text, c))) for c in CASES.values())
                 + sum(len(numbers(swift_function(text, b)))
                       for b in BUILDERS.values()))
        print("  %-26s ok (%d literals matched, arms and builders)"
              % ("geometry", total))

    # --- 3. The wiring, which is what rots as games are added. --------
    for game, (case, filename) in sorted(GAMES.items()):
        game_src = source(filename)
        if not re.search(r'static let floorMotif = FloorMotif\.%s\b' % case,
                         game_src):
            failed.append("%s does not declare .%s" % (game, case))

    screens = [f for f in os.listdir(os.path.join(HERE, "SwiftFiles"))
               if f.endswith("Screen.swift")]
    for game, _ in sorted(GAMES.items()):
        if game == "RollbotsGame":
            continue                  # passes .steel, which carries it
        passed = any("arenaStyle: .house(motif: %s.floorMotif)" % game
                     in source(f) for f in screens)
        if not passed:
            failed.append("%s declares a motif no screen passes to its scene "
                          "— it would never be drawn" % game)

    if "motif: .circuitry" not in source("DiceSceneEnvironment.swift"):
        failed.append("ArenaStyle.steel lost its circuitry, so Rollbots has "
                      "no motif at all")

    for line in failed:
        print("  %-26s FAILED  %s" % ("motifs", line))
    if failed:
        sys.exit("motifs: FAILED (%d problem(s))" % len(failed))
    print("  %-26s ok (%d games declare and pass one)" % ("wiring", len(GAMES)))
    print("motifs: PASS")


if __name__ == "__main__":
    main()
