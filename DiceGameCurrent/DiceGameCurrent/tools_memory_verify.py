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

HERE = os.path.dirname(os.path.abspath(__file__))

FACES = {4: 4, 6: 6, 8: 8, 10: 10, 12: 12, 20: 20}
BYTES_PER_PIXEL = 4

# Every game's pool, as (label, how many dice, the sides of each).
#
# Read from each game's own makeDice, and kept here because they are not
# all constants — Rolls deals twelve d6 plus one each of d8, d10 and d12,
# and Free Roll's worst case is its cap in the largest die it offers. The
# counts that ARE constants are checked against the Swift below.
POOLS = [
    ("Free Roll (worst)", "FreeRoll.swift", "maxDice", None, [20] * 20),
    ("Rolls", None, None, 15, [6] * 12 + [8, 10, 12]),
    ("Jackpot", "Jackpot.swift", None, 5, [4, 6, 8, 12, 20]),
    ("Three Thousand", "ThreeThousand.swift", "diceCount", 6, [6] * 6),
    ("Generals", "Generals.swift", "diceCount", 5, [6] * 5),
    ("F.Y.D.", "FreighterYachtDinghy.swift", "diceCount", 6, [6] * 6),
    ("Royal UR", "RoyalUrRules.swift", "diceCount", 5, [4] * 5),
    ("Baseball Dice", None, None, 3, [12, 12, 12]),
    ("Rollbots", None, None, 2, [10, 12]),
    ("HOG", None, None, 1, [6]),
    ("Boneheads", None, None, 1, [6]),
]

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

    failed = []

    # --- every game's pool -------------------------------------------
    # The per-game column is what a pool would cost if every face needed
    # its own image — which is what it DID cost before the colour left the
    # cache key. It stays as the budget the cache is measured against, not
    # as the figure the app now pays: with the colour out of the key, every
    # game shares one set of numerals and the real total is the ceiling
    # printed below.
    print("  %-22s %5s %6s %10s" % ("game", "dice", "faces", "uncached"))
    for label, swift_file, const, expected, sides in POOLS:
        if swift_file and const:
            actual = constant(source(swift_file), const)
            if expected is not None and actual != expected:
                failed.append("%s: this table says %d dice, %s says %d"
                              % (label, expected, swift_file, actual))
            count = actual
        else:
            count = expected
        faces = sum(sides)
        cost = faces * per_face
        flag = ""
        if cost > BUDGET_MIB:
            flag = "  OVER BUDGET"
            failed.append("%s costs %.0f MiB of face images, over the %.0f "
                          "MiB budget" % (label, cost, BUDGET_MIB))
        print("  %-22s %5d %6d %7.1f MiB%s" % (label, count, faces, cost, flag))

    # --- the ceilings, which are what a session actually accumulates --
    #
    # No single game is expensive. The caches were, because their keys
    # multiplied and nothing evicted: colourways times numerals, table
    # colours times surfaces.
    # The KEYS, specifically — `colorway.numberHex` still appears in this
    # file, as the tint `artworkMaterial` applies, and that is the point.
    for key in re.findall(r'cached\("([^"]*)"\)', labels):
        if "colorway" in key:
            failed.append('the colourway is back in a face-image cache key '
                          '("%s") — that multiplies the cache by 15 and is '
                          "what artworkMaterial's multiply channel exists to "
                          "avoid" % key)
    if "material.multiply.contents" not in labels:
        failed.append("face artwork is no longer tinted through multiply, so "
                      "every colourway needs its own copy of every numeral")

    for name, cap_file in (("DieFaceLabels.swift", "DieFaceLabels.swift"),
                           ("LowPolyTextures.swift", "LowPolyTextures.swift")):
        if "BoundedImageCache(" not in source(cap_file):
            failed.append("%s caches without a bound" % name)

    caps = re.findall(r'BoundedImageCache\(limit: (\d+)\)',
                      source("DieFaceLabels.swift") + source("LowPolyTextures.swift"))
    assert caps, "no BoundedImageCache limits found"
    label_ceiling = int(caps[0]) * per_face
    print("  %-22s labels <= %s entries (%.1f MiB), textures <= %s (%.0f MiB)"
          % ("ceilings", caps[0], label_ceiling, caps[-1], int(caps[-1]) * 1.0))
    print("  %-22s ~25 images for every die in every game, in every colour"
          % "in practice")

    # --- Boneheads' banked dice, which are rendered pictures now -------
    #
    # A slot asks for one every time the board draws, so they have to be
    # cached; and the key has to stay small, because an unbounded one
    # would be a picture per face per colour per size.
    bones = source("BoneheadsDieImage.swift")
    if "private static var cache" not in bones:
        failed.append("BoneheadsDieImage does not cache, so a banked die is "
                      "re-rendered on every draw of the board")
    key_pixels = re.search(r'static let pixels: CGFloat = (\d+)', bones)
    assert key_pixels, "no canvas size in BoneheadsDieImage"
    px = int(key_pixels.group(1))
    # The key space used to be six faces times two seat colours, which
    # bounded itself at twelve. Dice take a random colourway per throw now,
    # so it is six faces times the whole palette — and the cache needs a
    # stated ceiling rather than an arithmetic one.
    limit = re.search(r'static let cacheLimit = (\d+)', bones)
    if not limit:
        failed.append("BoneheadsDieImage has no cacheLimit, and its key is "
                      "now a face times the whole palette rather than a face "
                      "times two seat colours")
        bones_mib = 0.0
    else:
        entries = int(limit.group(1))
        bones_mib = entries * px * px * 4 / (1024.0 * 1024.0)
        if bones_mib > 8:
            failed.append("Boneheads' die images are %.1f MiB at %dpx x %d "
                          "entries, over the 8 MiB a picture cache is worth"
                          % (bones_mib, px, entries))
        # A board holds every slot on both sides at once, so the ceiling
        # has to clear that or it thrashes on a full board.
        if entries < 18:
            failed.append("cacheLimit %d is below the 18 dice a full board "
                          "shows, so drawing it would evict and re-render"
                          % entries)
        print("  %-22s %d entries at %dpx = %.1f MiB, cleared at the ceiling"
              % ("banked dice", entries, px, bones_mib))
    if "isUnavailable" not in bones:
        failed.append("BoneheadsDieImage retries a renderer that has already "
                      "failed, once per slot per draw")

    # Cached, because setupPool rebuilds the lot on every pool change.
    if "private static var imageCache" not in labels:
        failed.append("DieFaceLabels no longer caches its face images, so "
                      "every + and - tap in Free Roll re-renders the pool")
    for builder in ("drawLabel", "drawPip", "drawCornerMark",
                    "drawRollsWordmark"):
        if not re.search(r'cached\("[^"]*"\)\s*\{\s*%s' % builder, labels):
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

    # No game's makeDice may return fewer dice than it was asked for.
    for name in sorted(os.listdir(os.path.join(HERE, "SwiftFiles"))):
        if not name.endswith(".swift"):
            continue
        body = strip_comments(source(name))
        if "func makeDice()" not in body:
            continue
        if re.search(r'guard !colorways\.isEmpty else \{ return nil \}', body):
            failed.append("%s drops dice when the palette runs out" % name)

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
