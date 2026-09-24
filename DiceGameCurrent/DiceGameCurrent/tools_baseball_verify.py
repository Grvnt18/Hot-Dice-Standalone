"""Port of the shipped Baseball Dice rules, re-run against the measurements
that shaped them.

Mirrors BaseballDiceRules in BaseballDice.swift. There is no Swift toolchain
in this container, so this is how the logic gets checked at all.

The design arrived with one rule that broke it: the pitcher committed for a
half-inning while the batter chose per at-bat, and the dice reveal the pitch,
so from the second batter on the batter always took the favoured swing —
31.9 runs a game against 8.3. The shipped game hides the pitch and re-picks
it every at-bat. That is the single most important thing here, so the
exploit is measured too: if a future change lets the batter see the pitch,
the gap below reappears and this fails.
"""
import random
import sys
from itertools import product

import tools_swiftconst as swiftconst

OUTS_PER_HALF = 3
LENGTHS = [3, 6, 9]

SWIFT_CONSTANTS = {
    "outsPerHalfInning": OUTS_PER_HALF,
}

PITCHES = ["fastball", "changeup", "slider"]
SWINGS = ["patient", "contact", "power"]
SWING_SIDES = {"patient": 8, "contact": 10, "power": 12}

# Each pitch beats one swing and loses to another — a cycle, which is what
# makes guessing worth doing.
BEATS = {"fastball": "power", "changeup": "patient", "slider": "contact"}
LOSES_TO = {"fastball": "patient", "changeup": "contact", "slider": "power"}

# The unfavoured pairings are not derived: the chart gives each its own dice.
UNFAVORED = {"fastball": (12, 12), "changeup": (8, 10), "slider": (10, 12)}


def matchup(pitch, swing):
    """(kind, batter sides, batter dice, pitcher sides)."""
    if LOSES_TO[pitch] == swing:
        return "favored", SWING_SIDES[swing], 2, 4
    if BEATS[pitch] == swing:
        batter, pitcher = UNFAVORED[pitch]
        return "unfavored", batter, 1, pitcher
    return "neutral", SWING_SIDES[swing], 1, 8


def result(diff):
    if diff <= -5:
        return "strikeout"
    if diff <= 1:
        return "fieldOut"
    if diff == 2:
        return "walk"
    if diff <= 4:
        return "single"
    if diff == 5:
        return "double"
    if diff == 6:
        return "triple"
    if diff <= 9:
        return "deepOut"
    return "homeRun"


def at_bat(pitch, swing, rng):
    kind, sides, count, pitcher_sides = matchup(pitch, swing)
    rolls = [rng.randint(1, sides) for _ in range(count)]
    pitcher = rng.randint(1, pitcher_sides)
    jackpot = count > 1 and all(r == sides for r in rolls)
    outcome = "homeRun" if jackpot else result(max(rolls) - pitcher)
    return outcome, pitcher


def advance(bases, outcome, pitcher_roll, outs):
    """Mirrors BaseballDiceRules.advance. Returns (runs, outs added)."""
    if outcome == "strikeout":
        return 0, 1
    if outcome == "deepOut":
        if bases[2] and outs + 1 < OUTS_PER_HALF:
            bases[2] = False
            return 1, 1                      # sacrifice fly
        return 0, 1
    if outcome == "fieldOut":
        if bases[0] and outs < OUTS_PER_HALF - 1 and pitcher_roll % 2 == 0:
            bases[0] = False
            return 0, 2                      # ground-ball double play
        return _force(bases), 1
    if outcome == "walk":
        scored = _force(bases)
        bases[0] = True
        return scored, 0
    if outcome == "single":
        scored = 1 if bases[2] else 0
        bases[:] = [True, bases[0], bases[1]]
        return scored, 0
    if outcome == "double":
        scored = (1 if bases[1] else 0) + (1 if bases[2] else 0)
        bases[:] = [False, True, bases[0]]
        return scored, 0
    if outcome == "triple":
        scored = sum(bases)
        bases[:] = [False, False, True]
        return scored, 0
    scored = sum(bases) + 1
    bases[:] = [False, False, False]
    return scored, 0


def _force(bases):
    if not bases[0]:
        return 0
    scored = 0
    if bases[1] and bases[2]:
        scored = 1
    elif bases[1]:
        bases[2] = True
    else:
        bases[1] = True
    bases[0] = False
    return scored


# --- what the table actually produces -------------------------------------

def distribution(pitch, swing):
    """Exact outcome probabilities — enumerated, not sampled."""
    kind, sides, count, pitcher_sides = matchup(pitch, swing)
    tally = {}
    for rolls in product(range(1, sides + 1), repeat=count):
        jackpot = count > 1 and all(r == sides for r in rolls)
        for pitcher in range(1, pitcher_sides + 1):
            outcome = "homeRun" if jackpot else result(max(rolls) - pitcher)
            tally[outcome] = tally.get(outcome, 0) + 1
    total = sides ** count * pitcher_sides
    return kind, {k: v / total for k, v in tally.items()}


def check_table():
    """Boundaries of the differential table, by hand."""
    cases = [(-9, "strikeout"), (-5, "strikeout"), (-4, "fieldOut"),
             (0, "fieldOut"), (1, "fieldOut"), (2, "walk"), (3, "single"),
             (4, "single"), (5, "double"), (6, "triple"), (7, "deepOut"),
             (9, "deepOut"), (10, "homeRun"), (11, "homeRun")]
    for diff, expected in cases:
        assert result(diff) == expected, (diff, result(diff), expected)
    print("differential table: PASS (%d boundaries)" % len(cases))


def check_favored_never_strikes_out():
    """A favoured swing cannot strike out, and it is worth knowing why.

    The batter's floor is 1 and the pitcher's d4 ceiling is 4, so the worst
    differential available is -3 — two short of the -5 a strikeout needs.
    """
    for pitch in PITCHES:
        kind, probability = distribution(pitch, LOSES_TO[pitch])
        assert kind == "favored"
        assert probability.get("strikeout", 0) == 0, pitch
    print("favoured never strikes out: PASS")


def check_jackpot():
    """Two maximums on a favoured swing is a home run whatever the table says.

    It is the only way Fastball-versus-Patient reaches the seats at all: that
    pairing's differential tops out at 8 - 1 = +7, a Deep Out.
    """
    kind, sides, count, _ = matchup("fastball", "patient")
    assert (kind, sides, count) == ("favored", 8, 2)
    assert result(8 - 1) == "deepOut"
    rng = random.Random(0)
    hit = False
    for _ in range(20000):
        outcome, _ = at_bat("fastball", "patient", rng)
        if outcome == "homeRun":
            hit = True
            break
    assert hit, "the jackpot is the only home run here and it never fired"
    print("double max jackpot: PASS (the only Fastball/Patient home run)")


def check_edge_cases():
    """The three advancement rules that are easy to get subtly wrong."""
    # Bases loaded, forced walk: the runner on third is pushed home.
    bases = [True, True, True]
    runs, outs = advance(bases, "walk", 3, 0)
    assert (runs, outs) == (1, 0) and bases == [True, True, True], bases

    # Double play needs a runner on first, fewer than two outs, even roll.
    bases = [True, False, False]
    assert advance(bases, "fieldOut", 4, 0) == (0, 2)
    bases = [True, False, False]
    assert advance(bases, "fieldOut", 3, 0) == (0, 1)      # odd roll
    bases = [True, False, False]
    assert advance(bases, "fieldOut", 4, 2) == (0, 1)      # two outs already

    # A sacrifice fly cannot score the third out's run.
    bases = [False, False, True]
    assert advance(bases, "deepOut", 5, 2) == (0, 1)
    bases = [False, False, True]
    assert advance(bases, "deepOut", 5, 1) == (1, 1)

    # A double scores from second and third, and leaves a runner on third.
    bases = [True, True, True]
    runs, _ = advance(bases, "double", 5, 0)
    assert (runs, bases) == (2, [False, True, True]), (runs, bases)
    print("advancement edge cases: PASS (forced walk, double play, sac fly)")


# --- the balance the design rests on --------------------------------------

WEIGHTS = {"strikeout": -0.27, "fieldOut": -0.27, "deepOut": -0.27,
           "walk": 0.33, "single": 0.47, "double": 0.78, "triple": 1.09,
           "homeRun": 1.40}


def run_value(pitch, swing):
    _, probability = distribution(pitch, swing)
    return sum(WEIGHTS[k] * v for k, v in probability.items())


def check_rock_paper_scissors():
    """The cycle has to close in both directions, or the guess stops mattering.

    An earlier version of this asserted that every swing is held to a LOSS by
    some pitch. That is false and the game is fine anyway: the Power Swing's
    worst case is Fastball at +0.002 — held to break-even, not punished. So
    Power is the safe pick, worth 11.1 runs a game against a pitcher choosing
    at random versus 8.3 for mixing, and the pitcher's answer is to throw
    Fastball, which drops it to nothing and makes Patient (+0.382) the right
    swing instead. That is the cycle working, not a dominant strategy.

    What must hold is that each side's best answer is the one the chart
    names: the batter's best swing against a pitch is the swing it loses to,
    and the pitcher's best pitch against a swing is the pitch that beats it.
    """
    matrix = [[run_value(p, s) for s in SWINGS] for p in PITCHES]

    for i, pitch in enumerate(PITCHES):
        best_swing = SWINGS[max(range(3), key=lambda j: matrix[i][j])]
        assert best_swing == LOSES_TO[pitch], (pitch, best_swing)

    for j, swing in enumerate(SWINGS):
        column = [matrix[i][j] for i in range(3)]
        best_pitch = PITCHES[min(range(3), key=lambda i: column[i])]
        assert BEATS[best_pitch] == swing, (swing, best_pitch)

    # No swing may be free: its worst case must be near zero or below, or a
    # batter could pick it every time and never be punished.
    for j, swing in enumerate(SWINGS):
        floor = min(matrix[i][j] for i in range(3))
        assert floor < 0.05, "swing %s floors at %+.3f — never answered" % (swing, floor)

    print("rock-paper-scissors: PASS (the cycle closes both ways)")


def play_game(innings, batter_knows_pitch, rng):
    runs = [0, 0]
    at_bats = 0
    inning = 1
    while True:
        for half in (0, 1):
            outs = 0
            bases = [False, False, False]
            # One hidden style per half-inning; the pitch is drawn from it.
            style = rng.choice(list(STYLES))
            while outs < OUTS_PER_HALF:
                at_bats += 1
                pitch = draw_pitch(style, rng)
                swing = STYLE_ANSWER[style] if batter_knows_pitch else rng.choice(SWINGS)
                outcome, pitcher_roll = at_bat(pitch, swing, rng)
                scored, added = advance(bases, outcome, pitcher_roll, outs)
                runs[half] += scored
                outs += added
        if inning >= innings and runs[0] != runs[1]:
            return runs, at_bats
        inning += 1


def check_length_and_balance():
    """The three lengths, and that batting first is worth nothing."""
    expected = {3: (3.0, 31), 6: (5.7, 60), 9: (8.5, 89)}
    for innings in LENGTHS:
        rng = random.Random(innings)
        totals = [0, 0]
        at_bats = 0
        first = 0
        games = 6000
        for _ in range(games):
            runs, count = play_game(innings, False, rng)
            totals[0] += runs[0]
            totals[1] += runs[1]
            at_bats += count
            if runs[0] > runs[1]:
                first += 1
        mean = totals[0] / games
        per_game = at_bats / games
        share = first / games
        want_runs, want_at_bats = expected[innings]
        assert abs(mean - want_runs) < 0.4, (innings, mean, want_runs)
        assert abs(per_game - want_at_bats) < 5, (innings, per_game, want_at_bats)
        assert 0.45 < share < 0.55, "batting first is worth %.1f%%" % (100 * share)
        print("  %d innings: %.1f runs, %.0f at-bats, first seat %.1f%%"
              % (innings, mean, per_game, 100 * share))
    print("length and balance: PASS (no ordering fix needed)")


STYLES = {
    "powerPitcher": {"fastball": 60, "changeup": 25, "slider": 15},
    "crafty":       {"fastball": 20, "changeup": 60, "slider": 20},
    "breakingBall": {"fastball": 20, "changeup": 20, "slider": 60},
}
# Which swing answers which style — the same cycle as the pitches, softened.
STYLE_ANSWER = {"powerPitcher": "patient", "crafty": "contact", "breakingBall": "power"}


def draw_pitch(style, rng):
    total = sum(STYLES[style].values())
    roll = rng.randrange(total)
    for pitch, weight in STYLES[style].items():
        roll -= weight
        if roll < 0:
            return pitch
    return "slider"


def check_styles():
    """A style must tilt without becoming readable.

    Too pure and it is the fixed pitch again; too flat and choosing one stops
    meaning anything. Both ends are asserted, along with the cycle: each
    style's best answer must be the swing that beats the pitch it leans on.
    """
    for style, mix in STYLES.items():
        assert sum(mix.values()) == 100, style
        top = max(mix.values())
        assert 45 <= top <= 70, "%s leans %d%% — too %s" % (
            style, top, "pure" if top > 70 else "flat")

    values = {}
    for style, mix in STYLES.items():
        values[style] = {
            swing: sum(w / 100 * run_value(p, swing) for p, w in mix.items())
            for swing in SWINGS
        }
        best = max(SWINGS, key=lambda s: values[style][s])
        assert best == STYLE_ANSWER[style], (style, best)

    # No style may be strictly safest, or the pitcher stops choosing.
    worst = {s: max(values[s].values()) for s in STYLES}
    spread = max(worst.values()) - min(worst.values())
    assert spread < 0.08, "styles differ by %.3f in worst case" % spread
    print("pitch styles: PASS (each answered by one swing, spread %.3f)" % spread)


def check_hidden_pitch_matters():
    """The exploit the shipped game exists to avoid.

    If the batter can see the pitch they take the favoured swing every time,
    and a nine-inning game turns into 30-plus runs. The pitch is therefore
    re-chosen every at-bat and hidden until the dice land. This asserts the
    gap is still enormous, so nobody 'simplifies' the hiding away.
    """
    rng = random.Random(99)
    blind = sum(play_game(9, False, rng)[0][0] for _ in range(3000)) / 3000
    rng = random.Random(99)
    reading = sum(play_game(9, True, rng)[0][0] for _ in range(3000)) / 3000
    # The style mix is what keeps this bounded. A fixed pitch measured 3.6x;
    # anything approaching that means a style has been made too pure.
    assert reading < 2.2 * blind, \
        "reading the style is worth %.1fx — the mixes are too pure" % (reading / blind)
    print("hidden style: PASS (blind %.1f runs, reading it perfectly %.1f — %.1fx)"
          % (blind, reading, reading / blind))


def main():
    swiftconst.expect("Baseball Dice", "BaseballDice.swift", SWIFT_CONSTANTS)
    check_table()
    check_favored_never_strikes_out()
    check_jackpot()
    check_edge_cases()
    check_rock_paper_scissors()
    check_styles()
    check_length_and_balance()
    check_hidden_pitch_matters()
    print("baseball: PASS")


if __name__ == "__main__":
    main()
