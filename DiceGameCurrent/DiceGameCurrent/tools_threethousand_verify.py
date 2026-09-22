"""Port of the shipped Three Thousand scoring, re-run against the analysis
the target was chosen from.

Mirrors ThreeThousandRules.score(faces:) and .hasScoringDice in
ThreeThousand.swift rather than re-deriving them. The nil return is the
half most worth checking: a set-aside is legal only when every die in it
takes part in a scoring combination, and getting that wrong would quietly
let a player smuggle a non-scoring die out of the cup.

There is no Swift toolchain in this container, so this is the closest
thing to running the shipped function.

Expected at a 3,000 target: ~12 messages a match, Bust ending 50% of
turns, a banked turn averaging ~900, first seat ~54%."""
import random

import tools_swiftconst as swiftconst

TARGET = 3000
DICE_COUNT = 6
STRAIGHT = 1500
THREE_PAIRS = 750
FOUR, FIVE, SIX = 1000, 2000, 3000

# The constants above are a PORT of the Swift, not a reading of it, so
# they can drift out of agreement with the shipped game without any test
# noticing. This states which `static let`s in ThreeThousand.swift they stand on;
# swiftconst.expect fails by name if the Swift has moved.
SWIFT_CONSTANTS = {
    "diceCount": DICE_COUNT,
    "fiveOfAKindPoints": FIVE,
    "fourOfAKindPoints": FOUR,
    "sixOfAKindPoints": SIX,
    "straightPoints": STRAIGHT,
    "target": TARGET,
    "threePairPoints": THREE_PAIRS,
}


def score(faces):
    """ThreeThousandRules.score(faces:) — None means an illegal set-aside."""
    if not faces:
        return None
    counts = {}
    for face in faces:
        counts[face] = counts.get(face, 0) + 1

    if len(faces) == 6:
        if len(counts) == 6:
            return STRAIGHT
        if all(v == 2 for v in counts.values()):
            return THREE_PAIRS

    points = 0
    for face, count in list(counts.items()):
        if count >= 3:
            if count == 3:
                points += 1000 if face == 1 else face * 100
            elif count == 4:
                points += FOUR
            elif count == 5:
                points += FIVE
            else:
                points += SIX
            counts[face] = 0

    points += counts.get(1, 0) * 100 + counts.get(5, 0) * 50
    counts[1] = 0
    counts[5] = 0

    if any(v != 0 for v in counts.values()):
        return None
    return points


def has_scoring_dice(faces):
    counts = {}
    for face in faces:
        counts[face] = counts.get(face, 0) + 1
    if 1 in counts or 5 in counts:
        return True
    if any(v >= 3 for v in counts.values()):
        return True
    if len(faces) == 6:
        if len(counts) == 6:
            return True
        if all(v == 2 for v in counts.values()):
            return True
    return False


def check_scoring():
    # The table, one line each.
    assert score([1]) == 100
    assert score([5]) == 50
    assert score([1, 1]) == 200
    assert score([1, 5]) == 150
    assert score([3, 3, 3]) == 300
    assert score([1, 1, 1]) == 1000
    assert score([6, 6, 6]) == 600
    assert score([2, 2, 2, 2]) == FOUR
    assert score([2, 2, 2, 2, 2]) == FIVE
    assert score([2] * 6) == SIX
    assert score([1, 2, 3, 4, 5, 6]) == STRAIGHT
    assert score([2, 2, 3, 3, 4, 4]) == THREE_PAIRS
    # Combinations stack: a triplet plus loose 1's and 5's.
    assert score([3, 3, 3, 1, 5]) == 300 + 100 + 50
    assert score([1, 1, 1, 1]) == FOUR            # four of a kind beats the 1's
    assert score([1, 1, 1, 5, 5, 5]) == 1500      # two triplets, not three pairs

    # The illegal set-asides — the part most worth getting wrong.
    assert score([2]) is None                     # a lone 2 scores nothing
    assert score([1, 2]) is None                  # smuggling a 2 out with a 1
    assert score([3, 3]) is None                  # a pair is not a triplet
    assert score([1, 1, 1, 2]) is None            # a triplet does not carry a 2
    assert score([]) is None
    # Three pairs and straights need all six dice; five of them do not count.
    assert score([2, 2, 3, 3, 4]) is None
    # Five of the six faces of a straight is not a straight, and you may
    # not take the 5 along with four dice that score nothing — only the 5
    # on its own is a legal take from that roll.
    assert score([2, 3, 4, 5, 6]) is None
    assert score([5]) == 50

    # Bust detection agrees with the scorer on whole rolls.
    assert not has_scoring_dice([2, 2, 3, 3, 4, 6])
    assert not has_scoring_dice([2, 3, 4])
    assert has_scoring_dice([2, 2, 3, 3, 4, 4])   # three pairs
    assert has_scoring_dice([6, 6, 6, 2, 3, 4])
    assert has_scoring_dice([2, 2, 3, 3, 4, 1])
    print("scoring table and illegal set-asides: PASS")


def best_take(faces):
    """Take every scoring die — the simple play, and the one the length
    figures were measured with."""
    counts = {}
    for f in faces:
        counts[f] = counts.get(f, 0) + 1
    if len(faces) == 6 and (len(counts) == 6 or all(v == 2 for v in counts.values())):
        return score(faces), 6
    taken = []
    for face, count in counts.items():
        if count >= 3:
            taken += [face] * count
        elif face in (1, 5):
            taken += [face] * count
    return score(taken), len(taken)


def play_turn(rng, threshold=500, need=None, mine=0):
    total, dice = 0, DICE_COUNT
    while True:
        faces = [rng.randint(1, 6) for _ in range(dice)]
        if not has_scoring_dice(faces):
            return 0                                   # Bust
        points, used = best_take(faces)
        total += points
        left = dice - used
        dice = DICE_COUNT if left == 0 else left       # hot dice
        if need is not None:
            if mine + total > need:
                return total
        elif total >= threshold and left > 0:
            return total


def match(rng):
    totals = [0, 0]
    turns = 0
    while True:
        for seat in (0, 1):
            totals[seat] += play_turn(rng)
            turns += 1
            if totals[seat] >= TARGET:
                other = 1 - seat
                totals[other] += play_turn(rng, need=totals[seat], mine=totals[other])
                turns += 1
                return turns, (other if totals[other] > totals[seat] else seat)


def main():
    swiftconst.expect("Three Thousand", "ThreeThousand.swift", SWIFT_CONSTANTS)
    check_scoring()
    rng = random.Random(20260922)

    n = 60_000
    turns = [play_turn(rng) for _ in range(n)]
    banked = [t for t in turns if t]
    bust = 1 - len(banked) / n
    print("Bust rate          %.0f%%" % (bust * 100))
    print("mean when banked     %.0f" % (sum(banked) / len(banked)))

    m = 20_000
    results = [match(rng) for _ in range(m)]
    messages = sum(r[0] for r in results) / m
    first = sum(1 for r in results if r[1] == 0) / m
    print("messages per match   %.1f" % messages)
    print("first seat wins      %.1f%%" % (first * 100))

    assert 0.45 < bust < 0.55, bust
    assert 800 < sum(banked) / len(banked) < 1000
    assert 11.0 < messages < 13.5, messages
    print("Three Thousand: PASS")


if __name__ == "__main__":
    main()
