"""Port of the shipped Freighter.Yacht.Dinghy turn logic, re-run against the
analysis the rules were chosen from.

Mirrors FreighterYachtDinghyRules.Turn.apply / .score in Freighter.Yacht.Dinghy.swift line for line
rather than re-deriving them, so a drift between the code and the numbers
in the plan shows up here. There is no Swift toolchain in this container,
so this is the closest thing to running the shipped function.

Expected at four rolls: 68.8% of turns qualify, 31.2% score zero, a single
round ties 16.7% of the time and a best-of-three on cumulative points ties
4.4%. (At the three rolls this shipped with first, those were 54.1%,
45.9%, 24.7% and 4.8% — the fourth roll is what made the game less
brutal.)"""
import random

import tools_swiftconst as swiftconst

QUALIFIERS = [6, 5, 4]
DICE_COUNT = 5
ROLLS_PER_TURN = 4
CARGO_REROLL_HINT = 6

# The constants above are a PORT of the Swift, not a reading of it, so
# they can drift out of agreement with the shipped game without any test
# noticing. This states which `static let`s in FreighterYachtDinghy.swift they stand on;
# swiftconst.expect fails by name if the Swift has moved.
SWIFT_CONSTANTS = {
    "cargoRerollHint": CARGO_REROLL_HINT,
    "diceCount": DICE_COUNT,
    "rollsPerTurn": ROLLS_PER_TURN,
}


class Turn:
    """FreighterYachtDinghyRules.Turn."""

    def __init__(self):
        self.claimed = []          # die ids, in claim order
        self.cargo = []            # (id, value)
        self.rolls_used = 0

    @property
    def is_qualified(self):
        return len(self.claimed) == len(QUALIFIERS)

    @property
    def rolls_remaining(self):
        return max(0, ROLLS_PER_TURN - self.rolls_used)

    @property
    def score(self):
        return sum(v for _, v in self.cargo) if self.is_qualified else 0

    @property
    def kept_ids(self):
        return set(self.claimed)

    @property
    def is_out_of_rolls(self):
        return self.rolls_remaining == 0

    def apply(self, results):
        """results: the WHOLE hand, kept dice included, as [(id, value)]."""
        self.rolls_used += 1
        unclaimed = [r for r in results if r[0] not in self.claimed]
        while len(self.claimed) < len(QUALIFIERS):
            want = QUALIFIERS[len(self.claimed)]
            idx = next((i for i, r in enumerate(unclaimed) if r[1] == want), None)
            if idx is None:
                break
            self.claimed.append(unclaimed[idx][0])
            del unclaimed[idx]
        self.cargo = list(unclaimed) if self.is_qualified else []


def play_turn(rng, faces=None):
    """FreighterYachtDinghyScreen's turn flow, with the cargo reroll taken on the hint."""
    turn = Turn()
    hand = {i: 0 for i in range(DICE_COUNT)}
    while True:
        kept = turn.kept_ids
        for i in hand:
            if i not in kept:
                hand[i] = rng.randint(1, 6) if faces is None else faces.pop(0)
        turn.apply(sorted(hand.items()))
        if turn.is_qualified and not turn.is_out_of_rolls:
            if turn.score > CARGO_REROLL_HINT:
                return turn          # set sail
            continue                 # reroll the cargo
        if turn.is_qualified or turn.is_out_of_rolls:
            return turn


def main():
    swiftconst.expect("F.Y.D.", "FreighterYachtDinghy.swift", SWIFT_CONSTANTS)
    rng = random.Random(20260922)

    # Forced order: a hand of 6-6-5-4-4 takes ONE 6, then the 5, then one 4.
    t = Turn()
    t.apply([(0, 6), (1, 6), (2, 5), (3, 4), (4, 4)])
    assert t.claimed == [0, 2, 3], t.claimed
    assert t.score == 10, t.score        # the spare 6 and the spare 4

    # No Captain before a Ship: five 5's claims nothing at all.
    t = Turn()
    t.apply([(i, 5) for i in range(5)])
    assert t.claimed == [] and t.score == 0

    # Claims carry across rolls, and kept dice report themselves again.
    t = Turn()
    t.apply([(0, 6), (1, 1), (2, 1), (3, 1), (4, 1)])
    assert t.claimed == [0]
    t.apply([(0, 6), (1, 5), (2, 4), (3, 2), (4, 3)])
    assert t.claimed == [0, 1, 2] and t.score == 5

    # An unqualified turn scores nothing however good the leftovers are.
    t = Turn()
    for _ in range(ROLLS_PER_TURN):
        t.apply([(0, 6), (1, 6), (2, 6), (3, 6), (4, 6)])
    assert t.is_out_of_rolls and not t.is_qualified and t.score == 0

    n = 200_000
    scores = [play_turn(rng).score for _ in range(n)]
    qualified = [s for s in scores if s > 0]
    print("qualify rate            %.3f" % (len(qualified) / n))
    print("rounds scoring zero     %.3f" % (scores.count(0) / n))
    print("mean score              %.3f" % (sum(scores) / n))
    print("mean when qualified     %.3f" % (sum(qualified) / len(qualified)))

    m = 100_000
    single = best_of_three = 0
    for _ in range(m):
        if play_turn(rng).score == play_turn(rng).score:
            single += 1
        a = sum(play_turn(rng).score for _ in range(3))
        b = sum(play_turn(rng).score for _ in range(3))
        if a == b:
            best_of_three += 1
    print("single-round ties       %.3f" % (single / m))
    print("best-of-3 ties          %.3f" % (best_of_three / m))


if __name__ == "__main__":
    main()
