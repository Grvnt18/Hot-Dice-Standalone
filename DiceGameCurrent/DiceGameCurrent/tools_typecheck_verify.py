"""Flags SwiftUI bodies likely to blow Swift 5.7's type-checker.

Three expressions in this project have now been refused by Xcode 14.2
with "the compiler is unable to type-check this expression in reasonable
time": `FloorMotif.circuitBoard` (phase 33), and `FireworkBurst.body`
and `PipFace.body` on the first real Mac build. All three compiled fine
on the iPad.

**This is not the API floor**, which `tools_platform_verify.py` covers.
It is the other way the two machines disagree: type-checking
PERFORMANCE. The iPad runs a much newer Swift through Playgrounds, whose
constraint solver is far faster. Same source, same SDK, different
answer — and the slower one is the machine that has to build the
Messages extension.

Swift type-checks an expression as a whole, weighing every overload of
every operator in it, so cost climbs steeply with the number of
operators in ONE expression. Two things make it worse:

  * **Mixed CGFloat and Double.** Since SE-0307 the two are implicitly
    convertible, so every arithmetic node gains an extra candidate.
    `cos(angle) * reach * progress` with a Double angle and CGFloat
    reach is the shape that killed FireworkBurst.
  * **Trigonometry**, which returns Double into otherwise-CGFloat
    geometry and is where the mixing usually starts.

**Honest about its reach.** This is a heuristic, not a type-checker, and
there is no Swift toolchain in this container to be one. It cannot prove
an expression solves. What it can do is say "this one looks like the
three that did not" — and all three real failures rank in its top three.
Treat a hit as "annotate the types and move the arithmetic out of the
ViewBuilder", which is the fix that worked every time.

The remedy is always the same and never changes what is drawn:
give every local an explicit type, keep one numeric type per chain, and
compute geometry in a named function rather than inline in `body`.
"""
import os
import re
import sys

from tools_swiftconst import source, SWIFT, swift_names

# Set just under PipFace's pre-fix score of 14. Both real failures were
# 14 and 47; the next body in the tree scores 10, and everything else 5
# or less — so there is a wide gap to sit in, and this is not a number
# balanced on a knife edge.
THRESHOLD = 12

TRIG = re.compile(r'\b(?:cos|sin|tan|atan2?|acos|asin|sqrt|pow|hypot)\s*\(')


def bodies(text):
    """Every `var body: some View { ... }` block, with its line number."""
    for m in re.finditer(r'var body: some View \{', text):
        depth, i = 0, m.end() - 1
        while i < len(text):
            if text[i] == '{':
                depth += 1
            elif text[i] == '}':
                depth -= 1
                if depth == 0:
                    break
            i += 1
        yield text[:m.start()].count("\n") + 1, text[m.end():i]


def score(body):
    """How much this body looks like the ones that failed."""
    clean = re.sub(r'//[^\n]*', '', body)
    clean = re.sub(r'"(?:\\.|[^"\\\n])*"', '""', clean)
    operators = len(re.findall(r'[*/+\-]', clean))
    trig = len(TRIG.findall(clean))
    mixes = bool(re.search(r'\bCGFloat\b', clean)) and \
        bool(re.search(r'\bDouble\b', clean))
    return operators + trig * 12 + (8 if mixes else 0), operators, trig, mixes


def main():
    print("SwiftUI bodies, against Swift 5.7's solver:")
    worst, flagged = [], []
    # Both folders. The extension is the one target Swift Playgrounds
    # cannot build at all, so an expression Xcode 14.2's solver gives up
    # on would sit there unseen until the Mac opened it.
    for filename in swift_names():
        if not filename.endswith(".swift"):
            continue
        for line, body in bodies(source(filename)):
            total, operators, trig, mixes = score(body)
            worst.append((total, filename, line, operators, trig, mixes))
            if total >= THRESHOLD:
                flagged.append(
                    "%s:%d  score %d — %d operators%s%s"
                    % (filename, line, total, operators,
                       ", %d trig call(s)" % trig if trig else "",
                       ", mixes CGFloat and Double" if mixes else ""))

    for line in flagged:
        print("  %-18s FAILED  %s" % ("type-check risk", line))
    if flagged:
        sys.exit("typecheck: FAILED (%d body/bodies over %d — annotate the "
                 "types and move the arithmetic out of the ViewBuilder)"
                 % (len(flagged), THRESHOLD))

    worst.sort(reverse=True)
    top = worst[0] if worst else (0, "-", 0, 0, 0, False)
    print("  %-18s ok (%d bodies, worst is %s:%d at %d, threshold %d)"
          % ("under the solver", len(worst), top[1], top[2], top[0], THRESHOLD))
    print("typecheck: PASS")


if __name__ == "__main__":
    main()
