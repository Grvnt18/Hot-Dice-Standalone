"""Port of the shipped Freighter.Yacht.Dinghy turn logic, re-run against the
analysis the rules were chosen from.

Mirrors FreighterYachtDinghyRules.Turn.apply / .score in Freighter.Yacht.Dinghy.swift line for line
rather than re-deriving them, so a drift between the code and the numbers
in the plan shows up here. There is no Swift toolchain in this container,
so this is the closest thing to running the shipped function.

Measured at four rolls and six dice: 82.2% of turns qualify and 17.8%
score zero. (At five dice those were 68.7% and 31.3%, and at the three
rolls this shipped with first, 54.1% and 45.9% — the fourth roll and the
sixth die are each what made the game less brutal.)

The cargo rule has changed twice and both versions are modelled here. It
began as all-or-nothing — the whole cargo goes back or none of it does —
and the cargo can now be rethrown a die at a time. Over 200,000 turns on
one seed that is worth +1.28 points on a scoring round, 10.49 to 11.77,
with the qualify rate unmoved at 82.2% (cargo exists only once every
vessel is claimed, so no cargo decision can reach it) and the ceiling
unmoved at 18 (three cargo d6). More forgiving, not higher at the top."""
import random
import re

import tools_swiftconst as swiftconst

QUALIFIERS = [6, 5, 4]
DICE_COUNT = 6
ROLLS_PER_TURN = 4
CARGO_REROLL_HINT = 6   # the OLD whole-cargo threshold, kept to model
                        # the rule this replaced
CARGO_RETHROW_FLOOR = 4 # and the per-die one that replaced it

# The constants above are a PORT of the Swift, not a reading of it, so
# they can drift out of agreement with the shipped game without any test
# noticing. This states which `static let`s in FreighterYachtDinghy.swift they stand on;
# swiftconst.expect fails by name if the Swift has moved.
SWIFT_CONSTANTS = {
    "cargoRethrowFloor": CARGO_RETHROW_FLOOR,
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


# A d6 averages 3.5, so a cargo die showing less than this is worth
# throwing again and one showing 4 or more is not. This is the policy the
# per-die choice makes available and that a player will actually use — the
# rule itself is "any, all, or none" and says nothing about which.
PER_DIE_FLOOR = CARGO_RETHROW_FLOOR


def all_or_nothing(turn):
    """The old rule: the whole cargo goes back, or none of it does."""
    if turn.score > CARGO_REROLL_HINT:
        return set()
    return {i for i, _ in turn.cargo}


def per_die(turn):
    """The new rule: pick the cargo dice you are unhappy with."""
    return {i for i, value in turn.cargo if value < PER_DIE_FLOOR}


def play_turn(rng, faces=None, policy=per_die):
    """FreighterYachtDinghyScreen's turn flow.

    `policy` is the cargo decision, and the reason it is a parameter is
    that the rule changed: the cargo could only be rethrown whole, and can
    now be rethrown a die at a time. Both are kept here so the balance
    effect is a measurement in this file rather than a claim about it.
    """
    turn = Turn()
    hand = {i: 0 for i in range(DICE_COUNT)}
    while True:
        kept = turn.kept_ids
        for i in hand:
            if i not in kept:
                hand[i] = rng.randint(1, 6) if faces is None else faces.pop(0)
        turn.apply(sorted(hand.items()))
        if turn.is_qualified and not turn.is_out_of_rolls:
            picked = policy(turn)
            if not picked:
                return turn          # set sail
            # Only the picked dice go back in the cup. Everything else —
            # the three vessels AND the cargo the player kept — reports
            # its retained face, which is what the screen passes as
            # roll(keeping: allDiceIDs.subtracting(rethrowIDs)).
            keep = kept | {i for i, _ in turn.cargo if i not in picked}
            for i in hand:
                if i not in keep:
                    hand[i] = rng.randint(1, 6) if faces is None else faces.pop(0)
            turn.apply(sorted(hand.items()))
            if turn.is_out_of_rolls:
                return turn
            continue
        if turn.is_qualified or turn.is_out_of_rolls:
            return turn


def check_screen():
    """The Swift offers the per-die choice the model above measures.

    Everything above this is a PORT. It can report a balanced game the
    shipped one does not play, and the specific way that could happen here
    is that the rule changed in the document and the model and not on the
    screen — so the screen is read for the four things the choice is made
    of.
    """
    def code(filename):
        """The Swift with its comments gone.

        Scanning the raw source matched the note in FreighterYachtDinghy
        that RECORDS the retired constant's name, so the check failed on
        its own explanation. Comments out first, every time — the same rule
        the other verifiers follow.
        """
        text = swiftconst.source(filename)
        text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
        return re.sub(r"//[^\n]*", "", text)

    screen = code("FreighterYachtDinghyScreen.swift")
    session = code("DiceSceneAssembler.swift")
    rules = code("FreighterYachtDinghy.swift")
    problems = []

    # Taps have to reach the dice at all. Selection is off by default and
    # the comment on `isSelectionEnabled` named F.Y.D. as a game that
    # selects nothing, which is what this used to be.
    if "session?.isSelectionEnabled = true" not in screen:
        problems.append("the cargo choice never turns selection on, so a "
                        "tap on a cargo die does nothing")

    # The three vessels are not cargo and a tap on one must do nothing.
    if "session?.lockOnly(turn.keptIDs)" not in screen:
        problems.append("the claimed vessels are not locked out of the "
                        "choice, so a player can pick one to rethrow")
    if "func lockOnly(" not in session:
        problems.append("DiceTraySession has no lockOnly, so there is no "
                        "way to set the vessels aside without selecting them")

    # And the throw keeps everything that was NOT picked — which is the
    # whole rule. `roll(keeping: turn.keptIDs)` is the old behaviour and
    # would rethrow the entire cargo whatever the player chose.
    if "allDiceIDs.subtracting(rethrowIDs)" not in screen:
        problems.append("the rethrow does not keep the cargo the player "
                        "left alone — it is still all-or-nothing")

    # The retired constant reasoned about a total under a rule that no
    # longer exists.
    if "cargoRerollHint" in rules or "cargoRerollHint" in screen:
        problems.append("cargoRerollHint is back — it is a threshold on the "
                        "cargo TOTAL, and the cargo is picked a die at a time")

    for line in problems:
        print("  %-34s %s" % ("FAILED", line))
    if not problems:
        print("  %-34s ok (taps on, vessels locked, only the picked dice "
              "go back)" % "F.Y.D. cargo choice")
    return bool(problems)


def main():
    swiftconst.expect("F.Y.D.", "FreighterYachtDinghy.swift", SWIFT_CONSTANTS)
    if check_screen():
        raise SystemExit("F.Y.D.: FAILED")
    rng = random.Random(20260922)

    # Forced order: a hand of 6-6-5-4-4 takes ONE 6, then the 5, then one 4.
    # The sixth die is a 2 here, so the cargo is the spare 6, the spare 4
    # and that 2 — three dice now, where it used to be two.
    t = Turn()
    t.apply([(0, 6), (1, 6), (2, 5), (3, 4), (4, 4), (5, 2)])
    assert t.claimed == [0, 2, 3], t.claimed
    assert t.score == 12, t.score        # the spare 6, the spare 4 and the 2

    # No Captain before a Ship: a hand of nothing but 5's claims nothing.
    t = Turn()
    t.apply([(i, 5) for i in range(DICE_COUNT)])
    assert t.claimed == [] and t.score == 0

    # Claims carry across rolls, and kept dice report themselves again.
    t = Turn()
    t.apply([(0, 6), (1, 1), (2, 1), (3, 1), (4, 1), (5, 1)])
    assert t.claimed == [0]
    t.apply([(0, 6), (1, 5), (2, 4), (3, 2), (4, 3), (5, 1)])
    assert t.claimed == [0, 1, 2] and t.score == 6

    # An unqualified turn scores nothing however good the leftovers are.
    t = Turn()
    for _ in range(ROLLS_PER_TURN):
        t.apply([(i, 6) for i in range(DICE_COUNT)])
    assert t.is_out_of_rolls and not t.is_qualified and t.score == 0

    # The per-die choice can only touch cargo, and cargo exists only once
    # all three vessels are claimed — so it cannot change whether a turn
    # qualifies. That is the claim, and this is what checks it: the two
    # policies are run against the same seed and the qualify rates have to
    # come out the same.
    n = 200_000
    report = {}
    for label, policy in (("all or nothing", all_or_nothing),
                          ("per die", per_die)):
        rng = random.Random(20260922)
        scores = [play_turn(rng, policy=policy).score for _ in range(n)]
        qualified = [s for s in scores if s > 0]
        report[label] = {
            "qualify": len(qualified) / n,
            "zero": scores.count(0) / n,
            "mean": sum(scores) / n,
            "when qualified": sum(qualified) / len(qualified),
            "max": max(scores),
        }
        print("%-16s qualify %.3f  zero %.3f  mean %6.3f  "
              "when qualified %6.3f  ceiling %d"
              % (label, report[label]["qualify"], report[label]["zero"],
                 report[label]["mean"], report[label]["when qualified"],
                 report[label]["max"]))

    old_rate = report["all or nothing"]["qualify"]
    new_rate = report["per die"]["qualify"]
    assert abs(old_rate - new_rate) < 0.005, (old_rate, new_rate)

    # And the ceiling does not move: three cargo d6 cap at 18 either way,
    # so this is more forgiving rather than higher-scoring at the top.
    assert report["per die"]["max"] == report["all or nothing"]["max"] == 18

    # It IS more forgiving, which is the point and should be stated as a
    # number rather than left as an impression.
    lift = (report["per die"]["when qualified"]
            - report["all or nothing"]["when qualified"])
    print("per-die lift            +%.3f when qualified (+%.1f%%)"
          % (lift, lift / report["all or nothing"]["when qualified"] * 100))
    assert 0.5 < lift < 3.0, lift

    rng = random.Random(20260922)
    scores = [play_turn(rng).score for _ in range(n)]
    qualified = [s for s in scores if s > 0]

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
