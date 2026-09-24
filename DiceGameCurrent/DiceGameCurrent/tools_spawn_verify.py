"""Checks the spawn pattern can actually hold the dice the games ask for.

Mirrors DiceSpawnPattern.rowCounts and the arithmetic in its positions()
against the real playfield and die constants. The pattern exists to
guarantee dice never spawn inside each other, and that guarantee is pure
arithmetic — so it can be checked here even though the scene cannot be
built in this container."""

ROW_COUNTS = [5, 5, 4, 3, 2, 1]        # DiceSpawnPattern.rowCounts
WORLD_WIDTH = 10.0                     # PlayfieldLayout.compute targetWorldWidth
VISUAL_THICKNESS = 0.30                # PlayfieldRim.visualThickness
OUTWARD_OVERHANG = 0.06                # PlayfieldRim.outwardOverhang
TARGET_DIE_SIZE = 1.0                  # DieMeshLibrary.targetSize
OVERSIZE = 1.5                         # DicePoolSceneBuilder.oversizeMultiplier
MAX_DICE = 20                          # FreeRollPool.maxDice


def main():
    slots = sum(ROW_COUNTS)
    rim = VISUAL_THICKNESS - OUTWARD_OVERHANG
    usable = WORLD_WIDTH - rim * 2          # square scene: depth matches width
    widest = max(ROW_COUNTS)

    cell_width = usable / widest
    cell_depth = usable / len(ROW_COUNTS)
    biggest_die = TARGET_DIE_SIZE * OVERSIZE

    print("slots            %d" % slots)
    print("usable span      %.2f world units" % usable)
    print("cell width       %.2f  (widest row %d)" % (cell_width, widest))
    print("cell depth       %.2f  (%d rows)" % (cell_depth, len(ROW_COUNTS)))
    print("largest die      %.2f" % biggest_die)

    assert slots >= MAX_DICE, "pattern holds %d, games ask for %d" % (slots, MAX_DICE)
    assert cell_width > biggest_die, cell_width
    assert cell_depth > biggest_die, cell_depth

    check_pool_order()
    print("spawn pattern: PASS (every slot clears the largest die)")


def check_pool_order():
    """The pool must reach the scene in the order the game handed it over.

    `DiceTraySession.finishRoll` states that results come back "in the
    pool's own order", and a game that throws two different dice at once
    reads one of them by position on the strength of that. `setupPool` was
    shuffling the dice themselves, so the contract was false: Baseball Dice
    puts the pitcher's die last and took `results.last`, which on a
    favoured at-bat was a BATTER'S die two thirds of the time — the batter
    measured against himself.

    The spawn variety the shuffle was for is kept by shuffling the
    positions instead, and that is what this asserts. It lives here because
    this file owns the spawn pattern, and the shuffle is part of it.
    """
    import os
    import re
    here = os.path.dirname(os.path.abspath(__file__))
    path = os.path.join(here, "SwiftFiles", "DicePoolLifecycleController.swift")
    code = open(path).read()
    # Comments stripped: the fix's own comment quotes the bug it replaced,
    # and a check that reads a comment is checking the wrong thing.
    code = re.sub(r'/\*.*?\*/', '', code, flags=re.S)
    code = "\n".join(re.sub(r'//.*$', '', line) for line in code.splitlines())
    body = code[code.index("func setupPool("):]

    problems = []
    if re.search(r'\bdice\.shuffled\(\)', body):
        problems.append("setupPool shuffles the DICE — that breaks the "
                        "pool order finishRoll promises; shuffle the "
                        "positions instead")
    if not re.search(r'DiceSpawnPattern\.positions\((?:[^)]*\n)*?[^)]*\)\s*\.shuffled\(\)',
                     body):
        problems.append("the spawn positions are no longer shuffled, so "
                        "every die type always starts from the same slot")
    if not re.search(r'liveDice = dice\.enumerated\(\)', body):
        problems.append("setupPool no longer walks `dice` in order")

    for line in problems:
        print("  %-18s FAILED  %s" % ("pool order", line))
    if problems:
        raise SystemExit("spawn pattern: FAILED (pool order)")
    print("  %-18s ok (dice in order, positions shuffled)" % "pool order")


if __name__ == "__main__":
    main()
