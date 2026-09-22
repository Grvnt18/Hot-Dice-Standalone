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
    print("spawn pattern: PASS (every slot clears the largest die)")


if __name__ == "__main__":
    main()
