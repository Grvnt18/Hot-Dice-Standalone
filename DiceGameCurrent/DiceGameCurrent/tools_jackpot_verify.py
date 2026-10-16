"""Port of Jackpot.swift's scoring, checked against the analysis the
design was approved on. Mirrors JackpotRules.numbers / .score exactly."""
import tools_swiftconst as swiftconst

from collections import Counter

BOOSTER = 13              # JackpotRules.boosterThreshold
JACKPOT = BOOSTER - 1     # JackpotRules.jackpotThreshold
BIG_SEVEN_VALUE = 7       # JackpotRules.bigSevenValue
BIG_SEVEN_COUNT = 3       # JackpotRules.bigSevenCount
BIG_SEVEN_BONUS = 77      # JackpotRules.bigSevenBonus
ESCALATION = 2            # JackpotRules.escalationMultiplier

# The constants above are a PORT of the Swift, not a reading of it, so
# they can drift out of agreement with the shipped game without any test
# noticing. This states which `static let`s in Jackpot.swift they stand on;
# swiftconst.expect fails by name if the Swift has moved.
SWIFT_CONSTANTS = {
    "boosterThreshold": BOOSTER,
    "bigSevenValue": BIG_SEVEN_VALUE,
    "bigSevenCount": BIG_SEVEN_COUNT,
    "bigSevenBonus": BIG_SEVEN_BONUS,
    "escalationMultiplier": ESCALATION,
}


def d4_exposed(resting_face_index):
    """DieFaceLabels.d4ExposedFaceNumbers(restingFace:)"""
    return [n for n in range(1, 5) if n != resting_face_index + 1]

def numbers_from(results):
    """JackpotRules.numbers(from:) — results are (sides, value)."""
    out = []
    for sides, value in results:
        if sides == 4:
            out += d4_exposed(value - 1)
        else:
            out.append(value)
    return out

def sets_in(numbers):
    """JackpotRules.sets(in:) — biggest first, ties to the bigger number."""
    counts = Counter(numbers)
    return sorted(((v, c) for v, c in counts.items() if c >= 2),
                  key=lambda t: (t[1], t[0]), reverse=True)


def has_big_seven(numbers):
    """JackpotRules.hasBigSeven(_:)"""
    return numbers.count(BIG_SEVEN_VALUE) >= BIG_SEVEN_COUNT


def score(numbers, d20):
    """JackpotRules.score(numbers:d20:)"""
    sets = sets_in(numbers)
    big = has_big_seven(numbers)
    # The Big 7 replaces its own set rather than adding to it.
    scoring = [(v, c) for v, c in sets if not (big and v == BIG_SEVEN_VALUE)]
    set_points = sum(v * c for v, c in scoring)
    has_sets = bool(sets)
    booster = d20 if (d20 is not None and d20 >= BOOSTER) else None
    is_jackpot = (not has_sets) and (d20 or 0) <= JACKPOT
    total = set_points + (booster or 0) + (BIG_SEVEN_BONUS if big else 0)
    return total, is_jackpot, has_sets


def escalated(locked_numbers, rerolled, d20):
    """JackpotRules.escalatedScore(lockedNumbers:rerolled:d20:)"""
    locked = sets_in(locked_numbers)
    fresh = sets_in(rerolled)
    if not fresh:
        return 0, True                      # wipeout: the turn, not the re-roll
    big = has_big_seven(locked_numbers + rerolled)
    keep = lambda pairs: [(v, c) for v, c in pairs
                          if not (big and v == BIG_SEVEN_VALUE)]
    points = (sum(v * c for v, c in keep(locked))
              + sum(v * c for v, c in keep(fresh)) * ESCALATION)
    booster = d20 if (d20 is not None and d20 >= BOOSTER) else None
    return points + (booster or 0) + (BIG_SEVEN_BONUS if big else 0), False

print("thresholds from the shipped constants: booster %d+, jackpot %d-" % (BOOSTER, JACKPOT))
assert BOOSTER == 13 and JACKPOT == 12, "thresholds drifted from the approved ruleset"

tot = jack = nomatch = dead = 0
total_points = 0
for rest in range(4):                      # d4 resting face index
    for d6 in range(1, 7):
        for d8 in range(1, 9):
            for d12 in range(1, 13):
                for d20 in range(1, 21):
                    tot += 1
                    nums = numbers_from([(4, rest + 1), (6, d6), (8, d8), (12, d12), (20, d20)])
                    assert len(nums) == 7, "expected seven numbers, got %d" % len(nums)
                    pts, is_jack, has_sets = score(nums, d20)
                    total_points += 100 if is_jack else pts
                    if not has_sets: nomatch += 1
                    if is_jack: jack += 1
                    if not has_sets and not is_jack and pts == 0: dead += 1

print()
print("outcomes enumerated : %d   (expected 46,080)" % tot)
print("no-match rolls      : %.2f%%  (analysis said 10.21%%)" % (100*nomatch/tot))
print("jackpot rate        : %.4f%% (analysis said 4.3750%%)" % (100*jack/tot))
print("dead zone (0 pts, no set, no jackpot): %d  (the d20=12 gap the threshold change closed)" % dead)
print()
ok = (tot == 46080
      and abs(100*nomatch/tot - 10.21) < 0.01
      and abs(100*jack/tot - 4.375) < 0.001
      and dead == 0)
print("SHIPPED SCORING MATCHES THE APPROVED ANALYSIS:", ok)

# --- the Big 7, counted exactly -------------------------------------
#
# Only the d8, d12 and d20 can show a 7 at all, so the Big 7 is all three
# of them landing on it: 4 x 6 d4/d6 combinations x 1 way each = 24 of the
# 46,080 outcomes, which is 1 in 1,920. Counted rather than asserted from
# the arithmetic, because the thing worth catching is a rule that reads
# the wrong dice.
big = 0
for rest in range(4):
    for d6 in range(1, 7):
        for d8 in range(1, 9):
            for d12 in range(1, 13):
                for d20 in range(1, 21):
                    nums = numbers_from([(4, rest + 1), (6, d6), (8, d8),
                                         (12, d12), (20, d20)])
                    if has_big_seven(nums):
                        big += 1
                        assert (d8, d12, d20) == (7, 7, 7), \
                            "a Big 7 formed without all three sevens: %s" % (nums,)
print()
print("big 7 rolls         : %d of %d  (1 in %d)" % (big, tot, tot // big))
assert big == 24, "expected 24 Big 7 outcomes, found %d" % big

# --- is escalating ever worth it? -----------------------------------
#
# The mechanic is a choice, so the question a verifier can actually
# answer is whether it is a REAL one: a gamble nobody should ever take is
# a dead button, and one nobody should ever refuse is a forced click with
# extra steps. Sampled rather than enumerated — the re-roll's outcome
# space is its own 46,080 per starting roll, and twenty thousand throws
# settles a question whose answer is "roughly".
import random
random.seed(20260118)

TRIALS = 20000
offered = busts = better = 0
bank_total = escalate_total = 0
for _ in range(TRIALS):
    rest = random.randrange(4)
    faces = {4: rest + 1, 6: random.randint(1, 6), 8: random.randint(1, 8),
             12: random.randint(1, 12), 20: random.randint(1, 20)}
    results = [(s, faces[s]) for s in (4, 6, 8, 12, 20)]
    nums = numbers_from(results)
    banked, is_jack, has_sets = score(nums, faces[20])
    if is_jack or not has_sets:
        continue                              # no choice offered
    offered += 1

    # Lock the biggest set: every die showing one of its numbers, the d4
    # on any of its three exposed faces.
    value = sets_in(nums)[0][0]
    held = [(s, v) for s, v in results if value in numbers_from([(s, v)])]
    locked_numbers = numbers_from(held)
    held_sides = {s for s, _ in held}

    rerolled_results = []
    for sides in (4, 6, 8, 12, 20):
        if sides in held_sides:
            continue
        rerolled_results.append((sides, random.randint(1, sides)))
    final_d20 = faces[20] if 20 in held_sides else next(
        (v for s, v in rerolled_results if s == 20), None)
    rerolled = numbers_from(rerolled_results)
    points, wiped = escalated(locked_numbers, rerolled, final_d20)

    busts += 1 if wiped else 0
    better += 1 if points > banked else 0
    bank_total += banked
    escalate_total += points

print()
print("escalation offered  : %.1f%% of rolls" % (100 * offered / TRIALS))
print("  busts             : %.1f%% of escalations" % (100 * busts / offered))
print("  beat banking      : %.1f%%" % (100 * better / offered))
print("  mean banked       : %.1f" % (bank_total / offered))
print("  mean escalated    : %.1f" % (escalate_total / offered))
# A choice worth having: both roads win sometimes, and neither is free.
assert 0.15 < busts / offered < 0.85, \
    "escalation busts %.0f%% of the time — that is not a choice, it is a " \
    "trap or a formality" % (100 * busts / offered)
assert 0.15 < better / offered < 0.85, \
    "escalating beats banking %.0f%% of the time — nobody would ever " \
    "face a decision" % (100 * better / offered)

# the d4 contract the game depends on
print()
for rest in range(4):
    ex = d4_exposed(rest)
    assert len(ex) == 3 and len(set(ex)) == 3
    assert rest + 1 not in ex
    print("  resting face %d -> exposed %s (complement, all distinct)" % (rest + 1, ex))

# The readout reads the dice the way the SCORING does.
#
# A line that shows what each die rolled has one way to be quietly wrong,
# and it is the d4: `value` is the face it came to rest ON, not a number
# anyone can see, so printing it would show a number that scores nothing
# while the three that scored stay hidden. The player would then be
# reading a line that contradicts the score beside it, which is worse than
# no line at all.
#
# Checked as code shape rather than by re-implementing it here: the point
# is that `readout` goes through `numbers(from:)` — the one reading — and
# never reaches for a raw value of its own.
_readout = swiftconst.source("Jackpot.swift")
_readout = _readout[_readout.index("static func readout("):]
_readout = _readout[: _readout.index("\n    }")]
assert "numbers(from:" in _readout, \
    "JackpotRules.readout no longer reads the dice through numbers(from:)"
assert "result.value" not in _readout, \
    "JackpotRules.readout reads a raw die value — on a d4 that is the " \
    "resting face, which is the one number not on show"
print("\n  readout: reads through numbers(from:), no raw values")

swiftconst.expect("Jackpot", "Jackpot.swift", SWIFT_CONSTANTS)
