"""Checks the tray timber the Swift will draw against the timber that was seen.

Same job as tools_smoke_verify does for the floor, and the same reason: the
wood exists twice, as Swift in `LowPolyTextures.pixelWood` and as Python in
`tools_wood_preview.py`, and only the Python one can be looked at here.

It also guards the one thing about the wood that is invisible until it is
wrong, and then unmissable: the rim, the score panel and the roll-button panel
must be ONE piece of timber. That holds only while

  * `wallMaterial` and `HeaderFooterWood.image` call `pixelWood` identically,
    because the cache key is the arguments — identical arguments hand back the
    identical UIImage, anything else is a second copy tiling from a different
    origin; and
  * both tile at the same fraction of their own width, which is
    `PlayfieldRim.woodTileFraction`.

Either one drifts and a seam appears exactly where the score panel meets the
tray, which is the join the whole design rests on.

    python3 tools_wood_verify.py
"""
import os
import re
import sys

from tools_swiftconst import source

import tools_wood_preview as preview

CONSTANTS = {
    "woodPlanks": "PLANKS",
    "woodSeam": "SEAM",
    "woodGrainPerPlank": "GRAIN_PER_PLANK",
    "woodGrainThick": "GRAIN_THICK",
    "woodGrainAmplitude": "GRAIN_AMPLITUDE",
    "woodGrainCycles": "GRAIN_CYCLES",
    "woodKnotChance": "KNOT_CHANCE",
    "woodKnotRadius": "KNOT_R",
    "woodStudInset": "STUD_INSET",
    "woodStudRadius": "STUD_R",
}

TUPLES = {"woodBevels": "PLANK_BEVEL", "woodShades": "PLANK_SHADE"}


def main():
    failed = []
    lp = source("LowPolyTextures.swift")

    # --- 1. The constants agree. -------------------------------------
    swift = {m.group(1): float(m.group(2))
             for m in re.finditer(r'(?:static |private static )?let (wood\w+)'
                                  r'(?::\s*[\w<>]+)? = (-?[\d.]+)', lp)}
    for name, py_name in sorted(CONSTANTS.items()):
        if name not in swift:
            failed.append("LowPolyTextures no longer declares `%s`" % name)
            continue
        want = float(getattr(preview, py_name))
        if abs(swift[name] - want) > 1e-9:
            failed.append("pixelWood %s = %g but tools_wood_preview.%s = %g"
                          % (name, swift[name], py_name, want))

    for name, py_name in sorted(TUPLES.items()):
        m = re.search(r'let %s = \[([\d,\s]+)\]' % name, lp)
        if not m:
            failed.append("LowPolyTextures no longer declares `%s`" % name)
            continue
        got = tuple(int(v) for v in m.group(1).replace(" ", "").split(","))
        want = tuple(getattr(preview, py_name))
        if got != want:
            failed.append("pixelWood %s = %s but tools_wood_preview.%s = %s"
                          % (name, got, py_name, want))

    base = re.search(r'woodBaseHex = "(#\w+)"', lp)
    if not base:
        failed.append("LowPolyTextures no longer declares woodBaseHex")
    elif base.group(1).lstrip("#").upper() != preview.BASE_HEX.lstrip("#").upper():
        failed.append("pixelWood woodBaseHex = %s but tools_wood_preview.BASE_HEX "
                      "= %s — that value was measured off the reference art, "
                      "not chosen, so a change to it wants saying out loud"
                      % (base.group(1), preview.BASE_HEX))

    if not failed:
        print("  %-24s ok (%d values, Swift and Python agree)"
              % ("constants", len(CONSTANTS) + len(TUPLES) + 1))

    # --- 2. One piece of timber. -------------------------------------
    calls = []
    for name in ("DiceSceneEnvironment.swift", "DiceGameShell.swift"):
        body = source(name)
        for m in re.finditer(r'LowPolyTextures\.pixelWood\(([^)]*)\)', body):
            calls.append((name, m.group(1).strip()))

    if len(calls) < 2:
        failed.append("expected pixelWood to be called by both the 3D rim "
                      "(DiceSceneEnvironment) and the header/footer "
                      "(DiceGameShell); found %d call(s)" % len(calls))
    elif len({args for _, args in calls}) != 1:
        failed.append("pixelWood is called with different arguments in "
                      + " and ".join("%s(%s)" % (n, a or "defaults") for n, a in calls)
                      + " — the cache keys on the arguments, so these are now "
                      "two different images tiling from two different origins, "
                      "and there is a seam where the score panel meets the tray")
    else:
        print("  %-24s ok (%d call sites, identical arguments)"
              % ("one piece of timber", len(calls)))

    # --- 3. Both tile at the same fraction. ---------------------------
    layout = source("PlayfieldLayout.swift")
    frac = re.search(r'woodTileFraction: Float = ([\d.]+)', layout)
    if not frac:
        failed.append("PlayfieldLayout no longer declares woodTileFraction")
    else:
        if abs(float(frac.group(1)) - preview.TILE_FRACTION) > 1e-9:
            failed.append("PlayfieldRim.woodTileFraction = %s but "
                          "tools_wood_preview.TILE_FRACTION = %s — the preview "
                          "is showing a different plank scale than ships"
                          % (frac.group(1), preview.TILE_FRACTION))
        users = [n for n in ("DiceSceneEnvironment.swift", "DiceGameShell.swift")
                 if "woodTileFraction" in source(n)]
        if len(users) < 2:
            failed.append("only %s reads woodTileFraction — the 3D rim and the "
                          "SwiftUI header must both tile at it, or the plank "
                          "pitch jumps at the seam" % (", ".join(users) or "nothing"))
        elif not failed:
            print("  %-24s ok (%.2f of width, read by both)"
                  % ("tile scale", float(frac.group(1))))

    # --- 4. Four tones, still. ----------------------------------------
    pal = preview.palette()
    if len(pal) != 4 or len(set(pal)) != 4:
        failed.append("the wood palette is %d tones, %d of them distinct — it "
                      "is meant to be four, matching the floor"
                      % (len(pal), len(set(pal))))
    else:
        print("  %-24s ok (%s)" % ("four tones",
                                   " ".join("#%02X%02X%02X" % c for c in pal)))

    if failed:
        print()
        for line in failed:
            print("  FAIL  %s" % line)
        print("\nwood: FAIL (%d)" % len(failed))
        return 1
    print("wood: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
