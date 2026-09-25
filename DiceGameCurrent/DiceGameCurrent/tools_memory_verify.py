"""Checks what a pool of dice costs before it is built.

Free Roll crashed at around eight dice against a stated cap of twenty, and
it was not a logic error — it was arithmetic nobody had done. Every face of
every die carries its own image, so a pool costs

    faces x canvas^2 x 4 bytes

before SceneKit's own GPU copy, and at a 512px canvas one d20 is 20 MiB.
Eight of them is 160 MiB of label bitmaps, on a device that will not give
you that, and `setupPool` holds the old pool while it builds the new one.

So the budget is asserted here rather than discovered on a device. It reads
the canvas out of the Swift, so shrinking the number is not enough — raising
it again fails this instead of failing a player.

It also checks the two things that made the crash worse than it needed to
be: that the face images are cached (Free Roll rebuilds the whole pool on
every + and - tap) and that a full pool actually produces a full pool.
"""
import os
import re
import sys

from tools_swiftconst import constant, source

# The worst pool the app can be asked for: FreeRollPool.maxDice, all d20.
FACES = {4: 4, 6: 6, 8: 8, 10: 10, 12: 12, 20: 20}
BYTES_PER_PIXEL = 4

# What a pool of labels may cost. Not a device limit — a budget with room
# under one, chosen so the worst case stays well inside what an app can
# hold alongside its meshes, textures and the scene itself.
BUDGET_MIB = 120.0


def strip_comments(text):
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.S)
    return "\n".join(re.sub(r'//.*$', '', l) for l in text.splitlines())


def main():
    labels = source("DieFaceLabels.swift")
    canvas = constant(labels, "labelCanvas")
    max_dice = constant(source("FreeRoll.swift"), "maxDice")
    per_face = canvas * canvas * BYTES_PER_PIXEL / 1024 / 1024

    print("  %-26s %d px  (%.2f MiB a face)" % ("label canvas", canvas, per_face))

    worst = max_dice * FACES[20] * per_face
    print("  %-26s %d d20 -> %.0f MiB" % ("worst pool", max_dice, worst))
    for n in (4, 8, 12, max_dice):
        print("      %2d d20  %6.0f MiB" % (n, n * FACES[20] * per_face))

    failed = []
    if worst > BUDGET_MIB:
        failed.append("a full pool of d20 costs %.0f MiB of face images, over "
                      "the %.0f MiB budget — this is what killed Free Roll at "
                      "eight dice" % (worst, BUDGET_MIB))

    # Cached, because setupPool rebuilds the lot on every pool change.
    if "private static var imageCache" not in labels:
        failed.append("DieFaceLabels no longer caches its face images, so "
                      "every + and - tap in Free Roll re-renders the pool")
    for builder in ("drawLabel", "drawPip", "drawCornerMark",
                    "drawRollsWordmark"):
        if not re.search(r'cached\("[^"]*"[^)]*\)\s*\{[^}]*%s' % builder,
                         labels, re.S):
            failed.append("%s is not reached through the cache" % builder)

    # A full pool must BE full. Free Roll drew from 15 colourways and
    # stopped when they ran out, so 20 dice put 15 on the table.
    # Comments stripped: the fix's own comment quotes the guard it replaced.
    free_roll = strip_comments(source("FreeRoll.swift"))
    if "guard !colorways.isEmpty else { break }" in free_roll:
        failed.append("makeDice still breaks when the palette runs out, so a "
                      "pool past the colourway count silently loses dice")
    if "colorways = DiePalette.colorways.shuffled()" not in free_roll:
        failed.append("makeDice does not refill the palette")

    # And the spawn pattern must have a slot for every one of them.
    spawn = source("DiceSpawnPattern.swift")
    rows = re.search(r'rowCounts = \[([\d, ]+)\]', spawn)
    assert rows, "no rowCounts in DiceSpawnPattern.swift"
    slots = sum(int(n) for n in rows.group(1).split(","))
    if slots < max_dice:
        failed.append("the spawn pattern holds %d dice, the pool allows %d"
                      % (slots, max_dice))

    for line in failed:
        print("  %-26s FAILED  %s" % ("memory", line))
    if failed:
        sys.exit("memory: FAILED (%d problem(s))" % len(failed))
    print("  %-26s ok (cached, %d slots for %d dice)"
          % ("pool integrity", slots, max_dice))
    print("memory: PASS")


if __name__ == "__main__":
    main()
