"""Port of the shipped Boneheads rules, re-run against the analysis.

Mirrors BoneheadsRules.columnScore and BoneheadsState.place in
Boneheads.swift. There is no Swift toolchain in this container.

The finding this exists to protect: the rules are balanced as written —
50.4% to the first seat, 47.6% to the second, 1.9% drawn.

It also corrects one of its own author's earlier numbers. A first pass at
this measurement reported that granting the loser a final turn swung the
game to 42.4/55.5, which would have made the no-answering-turn rule the
thing holding the design together. That pass only ever granted the final
turn when seat 0 happened to be the one who filled, so it was measuring
its own bug. Done properly it is 49.5/48.4 — the same game. The rule
stays because it is the design's and it is simpler, not because the
numbers require it."""
import math
import re
import random

import tools_swiftconst as swiftconst
from collections import Counter

COLUMNS, SLOTS = 3, 3

# The constants above are a PORT of the Swift, not a reading of it, so
# they can drift out of agreement with the shipped game without any test
# noticing. This states which `static let`s in Boneheads.swift they stand on;
# swiftconst.expect fails by name if the Swift has moved.
SWIFT_CONSTANTS = {
    "columns": COLUMNS,
    "slotsPerColumn": SLOTS,
}


def column_score(dice):
    """BoneheadsRules.columnScore — every distinct value times its count squared."""
    return sum(v * c * c for v, c in Counter(dice).items())


def score(grid):
    return sum(column_score(col) for col in grid)


def place(grids, seat, column, die):
    """BoneheadsState.place. Returns how many opponent dice were destroyed."""
    grids[seat][column].append(die)
    foe = 1 - seat
    before = len(grids[foe][column])
    grids[foe][column] = [d for d in grids[foe][column] if d != die]
    return before - len(grids[foe][column])


def check_scoring():
    # The document's four worked examples, exactly as written.
    assert column_score([5]) == 5
    assert column_score([5, 5]) == 20
    assert column_score([5, 5, 5]) == 45
    assert column_score([5, 5, 2]) == 22
    # A mixed column is every value on its own terms.
    assert column_score([1, 2, 3]) == 6
    assert column_score([6, 6, 1]) == 6 * 4 + 1
    assert column_score([]) == 0
    print("scoring: PASS (all four worked examples, plus mixed columns)")


def check_strike():
    grids = [[[], [], []], [[], [], []]]
    grids[1][1] = [4, 4, 2]                      # their column B
    destroyed = place(grids, 0, 1, 4)            # a 4 into my column B
    assert destroyed == 2, destroyed
    assert grids[1][1] == [2], grids[1][1]       # survivors close the gap
    assert grids[0][1] == [4]
    # A strike only reaches the column of the same letter.
    grids = [[[], [], []], [[], [], []]]
    grids[1][2] = [3, 3, 3]
    assert place(grids, 0, 0, 3) == 0
    assert grids[1][2] == [3, 3, 3]
    # Placing a value they do not hold destroys nothing.
    assert place(grids, 0, 2, 5) == 0
    print("strikes: PASS (same column only, all matches, survivors slide)")


def greedy(grids, seat, die):
    """Take the placement that gains the most, counting their loss as gain."""
    best, best_value = None, None
    for column in range(COLUMNS):
        if len(grids[seat][column]) >= SLOTS:
            continue
        trial = [[list(c) for c in side] for side in grids]
        before = score(trial[seat]) - score(trial[1 - seat])
        place(trial, seat, column, die)
        value = (score(trial[seat]) - score(trial[1 - seat])) - before
        if best_value is None or value > best_value:
            best, best_value = column, value
    return best


def play(rng, final_turn=False):
    """One die, one placement, until somebody fills their ninth slot."""
    grids = [[[], [], []], [[], [], []]]
    seat, turns = 0, 0
    while turns < 200:
        turns += 1
        die = rng.randint(1, 6)
        column = greedy(grids, seat, die)
        place(grids, seat, column, die)
        if all(len(c) == SLOTS for c in grids[seat]):
            if final_turn:
                turns += 1
                die = rng.randint(1, 6)
                other = greedy(grids, 1 - seat, die)
                if other is not None:
                    place(grids, 1 - seat, other, die)
            break
        seat = 1 - seat
    totals = [score(g) for g in grids]
    winner = 0 if totals[0] > totals[1] else (1 if totals[1] > totals[0] else -1)
    return turns, winner, totals


def check_banked_die_faces():
    """Every face can be shown, including the one that would be NaN.

    A banked die is rendered by turning the mesh so the rolled face points
    up, which is a rotation taking that face's normal onto +Y. The 1 face
    of the d6 points straight DOWN, so its normal is exactly the opposite
    of +Y — and a from/to rotation is undefined for antiparallel vectors.
    Left alone that is a NaN orientation and an invisible die for the most
    common face on the board, which is why this is checked rather than
    assumed. The normals are read out of the Swift, not restated."""
    normals_src = swiftconst.source("DiceRollController.swift")
    block = normals_src.split("private static let d6: [SCNVector3] = [", 1)[1]
    block = block.split("]", 1)[0]
    normals = [tuple(float(n) for n in row)
               for row in re.findall(
                   r'SCNVector3\((-?[\d.]+), (-?[\d.]+), (-?[\d.]+)\)', block)]
    assert len(normals) == 6, normals

    image_src = swiftconst.source("BoneheadsDieImage.swift")
    assert "simd_dot(from, to) < -0.9999" in image_src, (
        "the antiparallel case is not handled — the 1 face renders as NaN")

    def cross(a, b):
        return (a[1] * b[2] - a[2] * b[1],
                a[2] * b[0] - a[0] * b[2],
                a[0] * b[1] - a[1] * b[0])

    def dot(a, b):
        return sum(x * y for x, y in zip(a, b))

    def rotate(q, v):
        x, y, z, w = q
        t = [2 * c for c in cross((x, y, z), v)]
        c2 = cross((x, y, z), t)
        return tuple(v[i] + w * t[i] + c2[i] for i in range(3))

    up = (0.0, 1.0, 0.0)
    for value, n in enumerate(normals, 1):
        if dot(n, up) < -0.9999:
            q = (1.0, 0.0, 0.0, 0.0)                    # half a turn about X
        else:
            axis = cross(n, up)
            q = (*axis, 1 + dot(n, up))
            length = math.sqrt(sum(c * c for c in q))
            q = tuple(c / length for c in q)
        landed = rotate(q, n)
        assert abs(landed[1] - 1) < 1e-6, (value, landed)
    print("  banked dice                   ok (all 6 faces land face-up)")


def main():
    swiftconst.expect("Boneheads", "Boneheads.swift", SWIFT_CONSTANTS)
    check_scoring()
    check_strike()
    check_banked_die_faces()

    rng = random.Random(20260922)
    n = 30_000
    for label, final_turn in (("as written, no answering turn", False),
                              ("if the loser got a final turn", True)):
        res = [play(rng, final_turn) for _ in range(n)]
        turns = sum(r[0] for r in res) / n
        first = sum(1 for r in res if r[1] == 0) / n
        second = sum(1 for r in res if r[1] == 1) / n
        drawn = sum(1 for r in res if r[1] == -1) / n
        mean = sum(r[2][0] for r in res) / n
        print("%-30s turns %.1f  first %.1f%%  second %.1f%%  drawn %.1f%%  mean score %.0f"
              % (label, turns, first * 100, second * 100, drawn * 100, mean))
        if not final_turn:
            assert abs(first - second) < 0.05, (first, second)
            assert 20 < turns < 26, turns

    check_colour()
    print("Boneheads: PASS")


def check_colour():
    """A banked die keeps the colour it was thrown in.

    Colour here has been wrong twice in opposite directions. It started
    random per throw, which made the die in the air match neither side of
    the board, and was replaced by one colour per seat. Now it is random
    again by request — which is fine, and was fine the first time, except
    for the part that actually broke: a banked die had no colour of its
    own and was drawn in whatever its SEAT was using when the view ran. Had
    throws gone back to random without that fixed, the whole board would
    have re-coloured itself under the player every turn.

    So the ink is stored with the placement, and these are the three
    properties that keep it honest:

      * a placement carries its own ink, and it is Codable, because the
        board travels between devices
      * nothing renders a banked die from the seat
      * the smash still matches on the FACE — colour is for the eye and
        must never change a result
    """
    import os
    import re
    here = os.path.dirname(os.path.abspath(__file__))
    swift = os.path.join(here, "SwiftFiles")

    def read(name):
        with open(os.path.join(swift, name), encoding="utf-8") as handle:
            text = handle.read()
        text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
        return "\n".join(re.sub(r"//.*$", "", line)
                          for line in text.splitlines())

    rules = read("Boneheads.swift")
    screen = read("BoneheadsScreen.swift")
    problems = []

    if "struct BoneheadsPlacement: Codable" not in rules:
        problems.append("a placement is not a Codable value — the board "
                        "cannot carry its colours between devices")
    if "let ink: Int" not in rules:
        problems.append("a placement no longer stores its ink, so a banked "
                        "die is being coloured from somewhere else")
    if "removeAll { $0.face == die }" not in rules:
        problems.append("the smash no longer matches on the face alone — "
                        "colour must never decide what is destroyed")
    if "static func randomInk()" not in rules:
        problems.append("there is no per-throw ink any more")

    if "colorway(ink: die.ink)" not in screen:
        problems.append("a banked die is not drawn from its own ink")
    if re.search(r'colorway\(for:', screen):
        problems.append("a die is being coloured by seat again")

    # The frames went neutral when the dice went multicoloured: a frame in
    # the player's tone would be fighting a different palette entry every
    # turn, which is the clash the first random version was reverted for.
    if re.search(r'\.stroke\(tint\.opacity', screen):
        problems.append("the column frame is tinted to the seat again, and "
                        "the dice inside it are every colour in the palette")

    for line in problems:
        print("  %-29s FAILED  %s" % ("colour", line))
    if problems:
        raise SystemExit("Boneheads: FAILED (%d problem(s))" % len(problems))
    print("  %-29s ok (ink travels with the placement, face decides the smash)"
          % "colour")


if __name__ == "__main__":
    main()
