"""Checks that the script face cannot lose its last character again.

Why this exists
---------------
The face's terminal glyphs are drawn past their own advance width. Core
Text and `size(withAttributes:)` both measure the advance, so anything that
sizes a box from them cuts the final glyph.

Still true after the swap from Aguafina to Lobster, and checked rather than
assumed: Lobster's `L` overhangs its advance by +0.284 em, against Aguafina's
worst of +0.490 on `Y`. Tamer, nowhere near tame enough to retire this — and
`L` is its worst glyph, in a face whose whole remaining job is "Rolls" and
"ROLLS".

That has been fixed three times in this project, three different ways — an
ink-measured canvas for the floor text, a guessed trailing pad for the hub,
two literal spaces appended to the turn-complete caption — and it came back
each time, because every new screen started again from the raw font. Four
schemes, and the two newest sites had none at all.

So the fix is a single path, and this is the part that keeps it single:

  * nothing outside AppFonts.swift may name the font or call .lobster(),
    which the compiler already enforces via fileprivate — this catches an
    attempt to reconstruct the name from a literal, which it would not
  * every UIKit site that draws it measures with AppFonts.inkBounds, never
    size(withAttributes:)
  * ScriptText still carries its reserve

A guard that has not been seen failing is not a guard, so each of these was
broken on purpose once before being trusted.
"""
import os
import re
import sys

from tools_swiftconst import source

HERE = os.path.dirname(os.path.abspath(__file__))
SWIFT = os.path.join(HERE, "SwiftFiles")
HOME = "AppFonts.swift"

# The PostScript name, as a literal. Anything reconstructing it has gone
# around the fileprivate.
FONT_NAME = "Lobster-Regular"


def swift_files():
    names = sorted(f for f in os.listdir(SWIFT) if f.endswith(".swift"))
    assert names, "no Swift sources found at %s" % SWIFT
    return names


def strip_comments(text):
    """Comments legitimately discuss all of this; code may not."""
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.S)
    return "\n".join(re.sub(r'//.*$', '', line) for line in text.splitlines())


def functions(code):
    """Each `func` body, as (text, offset), split at the next `func`.

    Crude on purpose — this needs to know which draw calls sit beside a
    script font, not to parse Swift.
    """
    starts = [m.start() for m in re.finditer(r'\bfunc\s+\w+', code)]
    bounds = starts + [len(code)]
    return [(code[bounds[i]:bounds[i + 1]], bounds[i])
            for i in range(len(starts))]


def main():
    failed = []

    # --- 1. One door in. --------------------------------------------
    for name in swift_files():
        if name == HOME:
            continue
        code = strip_comments(source(name))
        for label, pattern in (
            ("names the font directly", re.escape(FONT_NAME)),
            ("calls .lobster(", r'\.lobster\('),
            ("reaches for the PostScript name",
             r'lobsterPostScriptName'),
        ):
            for match in re.finditer(pattern, code):
                line = code[:match.start()].count("\n") + 1
                failed.append("%s:%d %s — use ScriptText, or "
                              "AppFonts.scriptFont for UIKit drawing"
                              % (name, line, label))
    if not failed:
        print("  %-28s ok (%d files, none bypass AppFonts)"
              % ("one door in", len(swift_files()) - 1))

    # --- 2. UIKit draws measure ink, not advance. -------------------
    #
    # Only files that actually draw script text are in scope: a plain sans
    # face has little overhang and `size(withAttributes:)` is fine there.
    # Only the renderers that SIZE A CANVAS from their text.
    #
    # That is the distinction, and getting it wrong cost a release:
    # BaseballField was switched to ink on this rule and every label on the
    # scoreboard moved. Ink measurement answers "how big must the canvas be
    # so nothing is cut off"; it does not answer "where does this go inside
    # a canvas somebody else sized", which wants the typographic box so
    # that rows line up with each other.
    #
    # Scoped to the FUNCTION, not the file: DieFaceLabels draws Stack Sans
    # numerals a few functions away from the script wordmark, and a plain
    # sans face has little enough overhang that its advance is fine.
    drawers = ["DiceSceneEnvironment.swift", "DieFaceLabels.swift"]
    checked = 0
    for name in drawers:
        code = strip_comments(source(name))
        if "AppFonts.scriptFont" not in code:
            continue                      # draws no script text any more
        checked += 1
        if ("AppFonts.inkBounds" not in code
                and "AppFonts.canvasBounds" not in code):
            failed.append("%s draws script text but never measures its ink"
                          % name)

        # --- and a canvas SIZED from the text needs canvasBounds ------
        #
        # inkBounds says where the glyphs put pixels. draw(at:) positions
        # from the LINE box. Both are valid, in the same coordinate space,
        # describing different rectangles — and sizing a canvas from one
        # while drawing with the other is a mismatch that only shows up
        # when a font's metrics change.
        #
        # That is exactly how it surfaced: the arrangement held for
        # Aguafina for months, then the swap to Lobster clipped the floor
        # wordmark along its bottom edge, because Lobster's descender hangs
        # below a box measured without it.
        #
        # canvasBounds is the union of the two, so neither can be cut off.
        # Only flagged where the canvas is DERIVED from the measurement —
        # DieFaceLabels centres script text inside a fixed labelCanvas, and
        # centring on ink is right there.
        for body, start in functions(code):
            if "AppFonts.scriptFont" not in body:
                continue
            if "UIGraphicsImageRenderer(" not in body:
                continue
            for m in re.finditer(r'let (\w+) = AppFonts\.inkBounds\(', body):
                var = m.group(1)
                # Deliberately a window rather than a balanced-paren
                # match: the real code reads `CGSize(width: ceil(ink.width)
                # + padding * 2, ...)`, and a paren-matching pattern choked
                # on `ceil(`. The first version of this check silently
                # matched nothing and passed — which is the failure mode
                # every guard here is written to avoid, so it is worth the
                # cruder, working approach.
                sized_from_it = any(
                    re.search(r'\b%s\.(?:width|height)\b' % var,
                              body[c.start(): c.start() + 240])
                    for c in re.finditer(r'CGSize\(', body))
                if sized_from_it:
                    line = code[:start + m.start()].count("\n") + 1
                    failed.append(
                        "%s:%d sizes a canvas from AppFonts.inkBounds — use "
                        "AppFonts.canvasBounds, which also covers the line "
                        "box draw(at:) lays out from, or the text clips when "
                        "a font's metrics change" % (name, line))
        for body, start in functions(code):
            if "AppFonts.scriptFont" not in body:
                continue
            for match in re.finditer(r'size\(withAttributes:', body):
                line = code[:start + match.start()].count("\n") + 1
                failed.append("%s:%d measures the advance while drawing "
                              "script text — use AppFonts.inkBounds"
                              % (name, line))
    if not failed:
        print("  %-28s ok (%d renderers measure ink)"
              % ("uikit measurement", checked))

    # --- 3. The reserve is still there. -----------------------------
    # Comments stripped: this file's own doc comment explains the reserve
    # and names the code point, which would otherwise satisfy the check
    # after the code doing the work had been deleted.
    home = strip_comments(source(HOME))
    if not re.search(r'var reserved: String \{[^}]*\\u\{00A0\}', home):
        failed.append("ScriptText lost its no-break-space reserve")
    if "fileprivate static let lobsterPostScriptName" not in home:
        failed.append("the PostScript name is no longer fileprivate, so "
                      "any file can start from the raw font again")
    if "fileprivate static func lobster(" not in home:
        failed.append("Font.lobster is no longer fileprivate")
    if not failed:
        print("  %-28s ok (reserve present, font sealed in %s)"
              % ("ScriptText", HOME))

    for line in failed:
        print("  %-28s FAILED  %s" % ("script text", line))
    if failed:
        sys.exit("script text: FAILED (%d problem(s))" % len(failed))
    print("script text: PASS")


if __name__ == "__main__":
    main()
