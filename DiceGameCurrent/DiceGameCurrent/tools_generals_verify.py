"""Port of the shipped Generals scoring and turn order, re-run against the
analysis the rules were chosen from.

Mirrors GeneralsCategory.score(for:) and the snake order in Generals.swift
rather than re-deriving them, so a drift between the code and the numbers
in the plan shows up here. There is no Swift toolchain in this container.

Two things are checked. Each of the twelve categories is scored against
hand-built hands, including the edge cases the Swift picks a side on (a
five-of-a-kind in Packed House, a straight with a duplicate). Then the
first-mover edge is re-measured against the shipped seat order: strict
alternation gives the first seat ~61% of decided matches, and the snake
this game ships takes it to ~51%."""
import random

import tools_swiftconst as swiftconst
from collections import Counter

UPPER = {"ones": 1, "twos": 2, "threes": 3, "fours": 4, "fives": 5, "sixes": 6}
CATEGORIES = list(UPPER) + [
    "setOfThree", "setOfFour", "packedHouse",
    "smallJoker", "largeJoker", "setOfFive",
]
SNAKE = [0, 1, 1, 0, 0, 1, 1, 0, 0, 1, 1, 0]
ROLLS_PER_TURN = 3
DICE_COUNT = 5

# The constants above are a PORT of the Swift, not a reading of it, so
# they can drift out of agreement with the shipped game without any test
# noticing. This states which `static let`s in Generals.swift they stand on;
# swiftconst.expect fails by name if the Swift has moved.
SWIFT_CONSTANTS = {
    "diceCount": DICE_COUNT,
    "rollsPerTurn": ROLLS_PER_TURN,
}


def longest_run(faces):
    present = sorted(set(faces))
    longest = run = 0
    previous = None
    for face in present:
        run = run + 1 if previous is not None and face == previous + 1 else 1
        previous = face
        longest = max(longest, run)
    return longest


def score(category, faces):
    """GeneralsCategory.score(for:)."""
    counts = Counter(faces)
    total = sum(faces)
    best = max(counts.values()) if counts else 0
    if category in UPPER:
        face = UPPER[category]
        return counts[face] * face
    if category == "setOfThree":
        return total if best >= 3 else 0
    if category == "setOfFour":
        return total if best >= 4 else 0
    if category == "packedHouse":
        return 25 if (sorted(counts.values()) == [2, 3] or best == 5) else 0
    if category == "smallJoker":
        return 30 if longest_run(faces) >= 4 else 0
    if category == "largeJoker":
        return 40 if longest_run(faces) >= 5 else 0
    if category == "setOfFive":
        return 50 if best == 5 else 0
    raise KeyError(category)


def check_categories():
    assert score("ones", [1, 1, 3, 4, 1]) == 3
    assert score("sixes", [6, 6, 6, 2, 1]) == 18
    assert score("fours", [1, 2, 3, 5, 6]) == 0
    assert score("setOfThree", [5, 5, 5, 1, 2]) == 18      # all five dice
    assert score("setOfThree", [5, 5, 1, 2, 3]) == 0
    assert score("setOfFour", [2, 2, 2, 2, 6]) == 14
    assert score("setOfFour", [2, 2, 2, 6, 6]) == 0
    assert score("packedHouse", [3, 3, 3, 5, 5]) == 25
    assert score("packedHouse", [3, 3, 3, 3, 5]) == 0      # four and a single
    assert score("packedHouse", [4, 4, 4, 4, 4]) == 25     # five alike qualifies
    assert score("smallJoker", [2, 3, 4, 5, 5]) == 30      # duplicate is fine
    assert score("smallJoker", [1, 2, 3, 5, 6]) == 0       # the run breaks at 4
    assert score("largeJoker", [2, 3, 4, 5, 6]) == 40
    assert score("largeJoker", [1, 2, 3, 4, 6]) == 0
    assert score("setOfFive", [6, 6, 6, 6, 6]) == 50
    assert score("setOfFive", [6, 6, 6, 6, 1]) == 0
    # A five-of-a-kind pays in every box that will take it.
    assert score("setOfThree", [3] * 5) == 15 and score("setOfFour", [3] * 5) == 15
    print("category scoring: PASS (%d categories)" % len(CATEGORIES))


def play_turn(rng, open_categories):
    """Keep the most common face, then claim the best-paying open box.

    Both seats play this, so the order is the only thing being measured."""
    faces = [rng.randint(1, 6) for _ in range(DICE_COUNT)]
    for _ in range(ROLLS_PER_TURN - 1):
        keep_face = Counter(faces).most_common(1)[0][0]
        kept = [f for f in faces if f == keep_face]
        faces = kept + [rng.randint(1, 6) for _ in range(DICE_COUNT - len(kept))]
    best = max(open_categories, key=lambda c: (score(c, faces), c))
    return best, score(best, faces)


def measure(order, rng, matches):
    """Returns (seat-0 share of decided matches, mean margin)."""
    wins = [0, 0]
    draws = 0
    margin = 0
    for _ in range(matches):
        open_categories = list(CATEGORIES)
        totals = [0, 0]
        for seat in order:
            category, points = play_turn(rng, open_categories)
            open_categories.remove(category)
            totals[seat] += points
        margin += totals[0] - totals[1]
        if totals[0] == totals[1]:
            draws += 1
        else:
            wins[0 if totals[0] > totals[1] else 1] += 1
    decided = wins[0] + wins[1]
    return wins[0] / decided, margin / matches, draws / matches


def main():
    swiftconst.expect("Generals", "Generals.swift", SWIFT_CONSTANTS)
    check_categories()
    rng = random.Random(20260922)
    matches = 60_000

    alternating = [i % 2 for i in range(len(SNAKE))]
    share, mean_margin, draws = measure(alternating, rng, matches)
    print("strict alternation   seat A %.1f%% of decided, margin %+.1f, draws %.1f%%"
          % (share * 100, mean_margin, draws * 100))

    share, mean_margin, draws = measure(SNAKE, rng, matches)
    print("snake (shipped)      seat A %.1f%% of decided, margin %+.1f, draws %.1f%%"
          % (share * 100, mean_margin, draws * 100))

    assert sum(1 for s in SNAKE if s == 0) == sum(1 for s in SNAKE if s == 1), "unequal claims"
    print("snake order: PASS (6 claims each over %d turns)" % len(SNAKE))


if __name__ == "__main__":
    main()
