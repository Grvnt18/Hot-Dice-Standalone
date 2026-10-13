"""Checks the small text still reads at the narrowest width.

Why this exists
---------------
`tools_hublayout_verify.py` measures the hub's tile names and the guide
nameplates off the real TTFs, and nothing measured anything else. Three
things changed that, all in the same week:

  * the captions under the roll button and the action bar, the round
    line, the status line and the seat names went from regular Poppins to
    semibold — a heavier face is a WIDER face, so every one of them got
    closer to its frame in exchange for being legible on timber;
  * seat names stopped being "Player 1" and became whatever somebody
    types, up to `PlayerNames.maxLength`;
  * and there can now be four of them across one strip instead of two.

Each of those was measured once, by hand, and the numbers went into a
comment. A comment is not a check. The failure mode is also the quiet
kind: SwiftUI does not complain when a `lineLimit(1)` label runs out of
room, it shrinks to `minimumScaleFactor` and then truncates, and on an
iPad — the only screen this project can actually look at — there is room
to spare, so nothing shows.

So: the frames are derived from the app's own constants, the glyphs are
measured with `tools_type` (which parses the shipped font files, so this
needs no Pillow and no network), and the question asked is always the
same one — **is this text being asked to shrink below the floor it
declares?**

What it does NOT cover, stated so the PASS is not read as more than it
is: text that wraps rather than truncating (the setup popup's footnote,
the guide bodies), anything whose string is composed at runtime from
game state rather than from a literal or a name, and the real letterforms
— this measures advance widths, with no kerning, exactly as
`tools_type`'s own docstring says.
"""
import os
import re
import sys

from tools_swiftconst import constant, source
from tools_type import face

# Every width the app can be handed, narrowest first. The 320 is an iPad
# in Slide Over rather than a phone — see tools_bandlayout_verify.py,
# which carries the same list and the same reason.
WIDTHS = [
    ("iPad Slide Over", 320),
    ("iPhone SE", 320),
    ("iPhone 13 mini", 375),
    ("iPhone 15", 393),
    ("iPhone 15 Pro Max", 430),
    ("iPhone Duo folded", 466),
    ("iPhone Duo open", 626),
]

# The weights, as PostScript names, by the spelling AppFonts uses.
WEIGHTS = {"regular": "Poppins-Regular", "medium": "Poppins-Medium",
           "semibold": "Poppins-SemiBold", "bold": "Poppins-Bold",
           "black": "Poppins-Black"}

# A name has no corpus the way the eleven game titles do — somebody types
# it — so "does a name fit" has to be asked in characters rather than
# against a list. Two letters stand in for the range: `M` is the widest
# in the Latin set and `n` is close to the mean, so the pair brackets any
# real name without pretending to predict one.
WIDEST, TYPICAL = "M", "n"

# The shortest name that must still fit without shrinking past the floor.
# Eight characters of typical width covers the overwhelming majority of
# first names; below that a seat tile starts truncating people.
MIN_TYPICAL_CHARS = 8


def poppins(weight, size, text):
    """Advance width of `text`, in points, in one of the bundled faces."""
    return face(WEIGHTS[weight]).measure(text, size)


def chars_that_fit(weight, size, available, letter):
    """How many `letter`s fit in `available` points at `size`."""
    one = poppins(weight, size, letter)
    return int(available / one) if one > 0 else 0


def uncommented(filename):
    """The Swift with its comments gone.

    Not optional. `scale_floor` below searches forward from an anchor, and
    the seat name's `minimumScaleFactor` sits behind a fifteen-line note
    explaining the measurement — so the first version of this read past it
    and reported a floor of 1.00 for a label that declares 0.70. Stricter
    than the truth, so it still passed, and wrong in the output, which is
    the kind of check this repo has twice decided is worse than none.
    `tools_bandlayout_verify.py` says it plainest: comments out first,
    always.
    """
    text = source(filename)
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    text = re.sub(r"//[^\n]*", "", text)
    # And the now-empty lines go too. Blanking a comment in place leaves
    # its newline and its indentation behind, so a fifteen-line note
    # becomes four hundred characters of whitespace — which is exactly
    # the window `scale_floor` searches, and why its first version read a
    # floor of 1.00 off a label that declares 0.70.
    return "\n".join(line for line in text.splitlines() if line.strip())


def font_call(text, anchor, after=0):
    """The `(size, weight)` of the first `.poppins(...)` after `anchor`.

    Reads the call rather than taking a number from this file, so a size
    changed in the Swift changes what gets measured instead of making
    this quietly wrong. A call with no weight is regular, which is what
    `AppFonts` defaults to.
    """
    tail = text.split(anchor, 1)
    if len(tail) < 2:
        raise AssertionError("no %r in the source" % anchor)
    match = re.search(r'\.poppins\((\d+)(?:,\s*\.(\w+))?\)',
                      tail[1][after:])
    if not match:
        raise AssertionError("no .poppins(...) after %r" % anchor)
    return int(match.group(1)), (match.group(2) or "regular")


def scale_floor(text, anchor):
    """The `minimumScaleFactor` after `anchor`, or 1.0 if there is none."""
    tail = text.split(anchor, 1)[-1]
    # 400 characters of comment-free Swift is several modifiers' worth and
    # stops well short of the next view, so a label with no floor of its
    # own cannot borrow the next one's.
    match = re.search(r'\.minimumScaleFactor\(([\d.]+)\)', tail[:400])
    return float(match.group(1)) if match else 1.0


# ---------------------------------------------------------------- seats

def check_seat_tiles(problems):
    """A typed name in a scoreboard seat tile, at two seats and at four.

    The strip is an HStack of tiles, each `maxWidth: .infinity`, inside
    horizontal padding — so a tile is the width left over divided by the
    seat count, and the seat count is now a thing the player chooses.
    """
    host = uncommented("PassAndPlayHost.swift")
    size, weight = font_call(host, "Text(match.displayName(for: participant))")
    floor = scale_floor(host, "Text(match.displayName(for: participant))")
    names = uncommented("PlayerNames.swift")
    max_seats = constant(names, "maxSeats")
    max_length = constant(names, "maxLength")

    # Both numbers off the view rather than this file.
    pad = float(re.search(r'\.padding\(\.horizontal, (\d+)\)',
                          host.split("VStack(spacing: 4)", 1)[-1]).group(1))
    spacing = float(re.search(r'HStack\(spacing: (\d+)\) \{\s*ForEach\(match\.participants',
                              host).group(1))

    rows = []
    for label, width in WIDTHS:
        for seats in (2, max_seats):
            tile = (width - pad * 2 - spacing * (seats - 1)) / seats
            room = tile / floor          # the widest string the floor allows
            typical = chars_that_fit(weight, size, room, TYPICAL)
            widest = chars_that_fit(weight, size, room, WIDEST)
            if typical < MIN_TYPICAL_CHARS:
                problems.append(
                    "a seat name on %s at %d seats fits only %d typical "
                    "characters (%.1fpt of tile, %dpt %s, floor %.2f) — a "
                    "name of ordinary length truncates"
                    % (label, seats, typical, tile, size, weight, floor))
            rows.append((label, seats, tile, typical, widest))

    tight = min(rows, key=lambda r: r[3])
    print("  %-26s %dpt %s, floor %.2f: tightest is %s at %d seats — "
          "%.1fpt holds %d typical or %d widest characters (cap %d)"
          % ("seat names", size, weight, floor, tight[0], tight[1],
             tight[2], tight[3], tight[4], max_length))
    # The cap is a cap on TYPING, not on width, so a name of the widest
    # letters can still exceed the tile. Reported rather than failed:
    # twelve capital Ms is not a name, and the alternative is capping the
    # field far below what ordinary names need.
    if tight[4] < max_length:
        print("  %-26s a %d-character name of the widest letters still "
              "truncates at %s (%d fit) — the floor shrinks it first"
              % ("", max_length, tight[0], tight[4]))


# --------------------------------------------------------------- captions

def check_band_captions(problems):
    """The one-line caption under the roll button and the action bar.

    Both are `lineLimit(1)` with a scale floor, both sit in a band with
    14 points of horizontal padding, and both now carry the status line
    that names a player — so the longest string either shows is a typed
    name plus the longest phase wording.
    """
    shell = uncommented("DiceGameShell.swift")
    host = uncommented("PassAndPlayHost.swift")
    names = uncommented("PlayerNames.swift")
    max_length = constant(names, "maxLength")

    # Anchored on the `if` rather than on `Text(subtitle)`, which is not
    # unique: MatchScoreboard's status line and TurnActionBar's caption
    # are both a `Text(subtitle)` in the same file, and the bare anchor
    # matched the scoreboard both times — reporting the action bar as
    # 11pt when it is 12. The guards differ (`if let subtitle` for the
    # optional one) and that is what tells them apart.
    #
    # The scoreboard's line is in here too, and it is the one the request
    # was actually about: "<name> to roll", white, over the timber.
    bars = [("Rolls caption", shell, "if !subtitle.isEmpty", "DiceRollButton"),
            ("action bar caption", host, "if !subtitle.isEmpty", "TurnActionBar"),
            # The scoreboard's own line, and the one the request was about:
            # "<name> to roll", white, over the timber. Every screen that
            # shows a scoreboard can put a phase line in it, so it is
            # tested against all of them.
            ("scoreboard status", host, "if let subtitle, !subtitle.isEmpty", None)]

    # A screen's phase lines belong to the bar that screen actually uses.
    #
    # The first version pooled every literal in every *Screen.swift and
    # tested the lot against both bars, which reported Rollbots' longest
    # line truncating in Rolls' caption — a string Rolls cannot display.
    # A check that invents failures is as bad as one that misses them, so
    # the mapping is read from the Swift: whichever bar the file
    # constructs is the one its strings are measured against.
    phrases = {}
    swift = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                         "SwiftFiles")
    for filename in sorted(os.listdir(swift)):
        if not filename.endswith("Screen.swift"):
            continue
        body = uncommented(filename)
        found = {bar for bar in ("DiceRollButton", "TurnActionBar")
                 if bar + "(" in body}
        lines = {m.group(1) for m in
                 re.finditer(r'return "([^"\\]{1,60})"', body)}
        for bar in found or {None}:
            phrases.setdefault(bar, set()).update(lines)
        # A screen with a scoreboard feeds the status line too.
        if "MatchScoreboard(" in body:
            phrases.setdefault(None, set()).update(lines)

    # And the composed one, at the longest name the field accepts.
    composed = WIDEST * max_length + " to roll"

    for name, text, anchor, bar in bars:
        size, weight = font_call(text, anchor)
        floor = scale_floor(text, anchor)
        pad = float(re.search(r'\.padding\(\.horizontal, (\d+)\)',
                              text.split(anchor, 1)[-1]).group(1))
        for label, width in WIDTHS:
            room = (width - pad * 2) / floor
            samples = [composed] + sorted(phrases.get(bar, set()),
                                          key=len, reverse=True)[:6]
            for sample in samples:
                if not sample:
                    continue
                drawn = poppins(weight, size, sample)
                if drawn > room:
                    problems.append(
                        "%s on %s truncates %r: %.1fpt of text in %.1fpt "
                        "of room even at the %.2f floor"
                        % (name, label, sample[:28], drawn, room, floor))
        narrow = (WIDTHS[0][1] - pad * 2) / floor
        print("  %-26s %dpt %s, floor %.2f: %.0fpt of room at %dpt holds "
              "%d typical characters"
              % (name, size, weight, floor, narrow,
                 WIDTHS[0][1], chars_that_fit(weight, size, narrow, TYPICAL)))


# ------------------------------------------------------------- the popup

def check_name_field(problems):
    """`PlayerNameField`'s label, which has a FIXED frame and no floor.

    The one piece of text in the app whose room does not vary with the
    screen: a 66-point leading-aligned frame. So it either fits at every
    size or at none, and it has no `minimumScaleFactor` to fall back on —
    it would simply wrap to a second line and make the field taller.
    """
    names = uncommented("PlayerNames.swift")
    anchor = 'Text("Player \\(seat + 1)")'
    size, weight = font_call(names, anchor)
    frame = float(re.search(r'\.frame\(width: (\d+), alignment: \.leading\)',
                            names.split(anchor, 1)[-1]).group(1))
    floor = scale_floor(names, anchor)

    # Seat numbers only ever reach the seat cap, so the label is "Player"
    # plus one digit. Measured at the cap rather than at 1 in case the cap
    # ever reaches double figures.
    label = "Player %d" % constant(names, "maxSeats")
    drawn = poppins(weight, size, label)
    if drawn > frame * (1 / floor if floor else 1):
        problems.append(
            "PlayerNameField's %r is %.1fpt in a %.0fpt frame with no "
            "scale floor — it wraps to a second line and makes every row "
            "of the setup popup taller" % (label, drawn, frame))
    print("  %-26s %r is %.1fpt in its %.0fpt frame (%dpt %s)"
          % ("setup popup label", label, drawn, frame, size, weight))


def main():
    problems = []
    print("small text, measured off the shipped faces:")
    check_seat_tiles(problems)
    check_band_captions(problems)
    check_name_field(problems)

    if problems:
        print()
        for line in problems:
            print("  FAIL  %s" % line)
        print("\ntext fit: FAIL (%d)" % len(problems))
        return 1
    print("text fit: PASS (%d widths, narrowest %dpt)"
          % (len(WIDTHS), min(w for _, w in WIDTHS)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
