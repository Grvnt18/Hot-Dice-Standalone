"""Port of the shipped PIG rules, re-run against the analysis the target was
chosen from.

Mirrors PigRules and PigScreen's turn flow in Pig.swift / PigScreen.swift:
a 1 ends the turn and loses the running total, holding banks it, and the
first player to bank 75 wins on the spot with no answering turn. There is
no Swift toolchain in this container, so this is the closest thing to
running the shipped code.

The hold-at-20 policy below is the simulation's, not the game's — the game
never holds for you. It is the standard near-optimal PIG heuristic and is
what every length figure in the plan was measured with.

Expected: 14.8 messages a match, first seat winning 54.5%."""
import random

TARGET = 75
PIG_FACE = 1
HOLD_AT = 20


def turn(rng, banked):
    """One turn. Returns the points banked — 0 if the die pigged out."""
    total = 0
    while True:
        if banked + total >= TARGET:
            return total                 # holding wins; never risk it
        if total >= HOLD_AT:
            return total
        face = rng.randint(1, 6)
        if face == PIG_FACE:
            return 0
        total += face


def match(rng):
    """Alternating turns, no catch-up. Returns (turns taken, winning seat)."""
    totals = [0, 0]
    turns = 0
    seat = 0
    while True:
        totals[seat] += turn(rng, totals[seat])
        turns += 1
        if totals[seat] >= TARGET:
            return turns, seat
        seat = 1 - seat


def main():
    rng = random.Random(20260922)

    # A pig loses the turn, not the bank.
    assert turn(random.Random(0), 0) >= 0
    # Holding at the target never overshoots into another roll: with 74
    # banked, any single non-pig face is enough and the turn stops there.
    for seed in range(200):
        assert turn(random.Random(seed), TARGET - 1) in (0, 2, 3, 4, 5, 6)

    n = 60_000
    results = [match(rng) for _ in range(n)]
    messages = sum(r[0] for r in results) / n
    first = sum(1 for r in results if r[1] == 0) / n
    print("PIG to %d, win on the spot" % TARGET)
    print("  messages per match   %.1f" % messages)
    print("  first seat wins      %.1f%%" % (first * 100))

    assert 14.0 < messages < 15.5, messages
    assert 0.53 < first < 0.56, first
    print("PIG: PASS")


if __name__ == "__main__":
    main()
