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
import random
from collections import Counter

COLUMNS, SLOTS = 3, 3


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


def main():
    check_scoring()
    check_strike()

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

    print("Boneheads: PASS")


if __name__ == "__main__":
    main()
