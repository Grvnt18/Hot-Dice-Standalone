"""Port of ChasingSix.swift's scoring, checked against the analysis the
design was approved on. Mirrors ChasingSixRules.numbers / .score exactly."""
from collections import Counter

BOOSTER = 13              # ChasingSixRules.boosterThreshold
JACKPOT = BOOSTER - 1     # ChasingSixRules.jackpotThreshold

def d4_exposed(resting_face_index):
    """DieFaceLabels.d4ExposedFaceNumbers(restingFace:)"""
    return [n for n in range(1, 5) if n != resting_face_index + 1]

def numbers_from(results):
    """ChasingSixRules.numbers(from:) — results are (sides, value)."""
    out = []
    for sides, value in results:
        if sides == 4:
            out += d4_exposed(value - 1)
        else:
            out.append(value)
    return out

def score(numbers, d20):
    """ChasingSixRules.score(numbers:d20:)"""
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
