"""Port of Jackpot.swift's scoring, checked against the analysis the
design was approved on. Mirrors JackpotRules.numbers / .score exactly."""
import tools_swiftconst as swiftconst

from collections import Counter

BOOSTER = 13              # JackpotRules.boosterThreshold
JACKPOT = BOOSTER - 1     # JackpotRules.jackpotThreshold

# The constants above are a PORT of the Swift, not a reading of it, so
# they can drift out of agreement with the shipped game without any test
# noticing. This states which `static let`s in Jackpot.swift they stand on;
# swiftconst.expect fails by name if the Swift has moved.
SWIFT_CONSTANTS = {
    "boosterThreshold": BOOSTER,
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

def score(numbers, d20):
    """JackpotRules.score(numbers:d20:)"""
    counts = Counter(numbers)
    sets = sorted(((v, c) for v, c in counts.items() if c >= 2),
                  key=lambda t: (t[1], t[0]), reverse=True)
    set_points = sum(v * c for v, c in sets)
    has_sets = bool(sets)
    booster = d20 if (d20 is not None and d20 >= BOOSTER) else None
    is_jackpot = (not has_sets) and (d20 or 0) <= JACKPOT
    return set_points + (booster or 0), is_jackpot, has_sets

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
