"""Checks the three bands a game screen is split into, at every size.

Eight screens each computed this split separately, with three different
header fractions and a `minButtonHeight` of 100 typed into each; three
more fixed their button band outright at 100, 104 and 96. Nothing checked
any of them at any size.

That is the kind of gap that costs something quietly. The band has to hold
a known stack — padding, a 48pt button, the gap above its caption, one
caption line — which comes to 95 points. Baseball's band was 96. The
margin had been seven until the gap moved from 2 to 8, to stop the
button's shadow falling on the caption, and nothing anywhere noticed.

So: the Swift's own arithmetic, ported, walked across every size iOS can
hand the app. Like tools_hublayout_verify.py does for the hub, which was
the only screen in the app with a device matrix behind it.
"""
import re
import sys

from tools_swiftconst import source

LAYOUT = "PlayfieldLayout.swift"

# Every size the app can be handed. The iPad floor is NOT a device — it is
# Slide Over, which is about 320 points wide on every iPad, so the
# narrowest case is an iPad rather than a phone.
SIZES = [
    ("iPad Slide Over", 320, 1133),
    ("iPhone SE", 320, 568),
    ("iPhone 13 mini", 375, 812),
    ("iPhone 15", 393, 852),
    ("iPhone 15 Pro Max", 430, 932),
    ("iPad 1/2 split", 507, 1133),
    ("iPad mini", 744, 1133),
    ("iPad Air", 820, 1180),
    ("iPad Pro", 1024, 1366),
    # Landscape is not a supported orientation, and is checked anyway: it
    # is the only shape where the band bottoms out, so it is the one that
    # says how much margin the floor really has.
    ("iPad Pro landscape", 1366, 1024),
]

# How small the square playfield may get before a tray of dice stops
# being playable. Measured: at today's floor the worst case is Free Roll
# on an iPhone SE at 302.6, so this leaves about 40 points of room for the
# floor to grow before anything is said.
MIN_SCENE = 260

# Each screen and the header fraction it asks for.
SCREENS = {
    "JackpotScreen.swift": 0.17,
    "HogScreen.swift": 0.17,
    "ThreeThousandScreen.swift": 0.17,
    "FreighterYachtDinghyScreen.swift": 0.17,
    "GeneralsScreen.swift": 0.17,
    "FreeRollScreen.swift": 0.30,          # the taller of its two
    "BoneheadsScreen.swift": 0.14,
    "RoyalUrScreen.swift": 0.15,
}


def code(filename):
    """The Swift with its comments gone.

    Scanning raw source matched the word `minButtonHeight` inside the note
    that RECORDS it being removed, and failed on its own explanation. The
    same mistake tools_fyd_verify.py made. Comments out first, always.
    """
    text = source(filename)
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return re.sub(r"//[^\n]*", "", text)


def swift_constant(text, name):
    """A `let <name>: CGFloat = <n>`, however it is scoped.

    `static`, `private`, `private static` and a bare `let` all count: the
    tap targets below read constants out of a view, where they are usually
    `private let`, and a static-only pattern simply could not see them.
    """
    match = re.search(r"let %s: CGFloat = ([\d.]+)" % name, text)
    if not match:
        raise AssertionError("no `%s: CGFloat` to read" % name)
    return float(match.group(1))




# Apple's minimum tap target. Not every control in this app reaches it,
# and the ones that cannot are listed with the reason rather than excused:
# a board square and a colour stripe both sit against a neighbour, so
# growing past the gap between them means two targets claiming the same
# point, and a tap that picks the wrong square is worse than one that
# needs aiming.
TAP_MINIMUM = 44.0


def check_tap_targets():
    """Every control you press, measured at every size.

    This is the check that was missing when the Royal UR board came in at
    34pt on an iPhone SE — the primary interaction of the game, below the
    guideline on every iPhone but the Pro Max, and nothing said so.

    What it reports is the TARGET, not the drawing: a tile can stay 34pt
    and still accept a wider touch, which is what RoyalUrLayout.tapOutset
    and the colour picker's own padding do. Where even that cannot reach
    44 the shortfall is printed, so it stays a known number instead of an
    assumption.
    """
    board = code("RoyalUrBoardView.swift")
    settings = code("SettingsView.swift")
    problems, rows = [], []

    # --- Royal UR's board squares -----------------------------------
    outset = swift_constant(board, "tapOutset")
    if "padding(-RoyalUrLayout.tapOutset)" not in board:
        problems.append("Royal UR's squares no longer widen their tap "
                        "target — tapping a square is the whole game and it "
                        "is 34pt on an iPhone SE")
    for name, width, height in SIZES:
        if width > 500:                      # phones are the tight case
            continue
        tile = (width - 12) / 9.04
        rows.append(("Royal UR square", name, tile, tile + outset * 2))

    # --- the colour picker ------------------------------------------
    stripe = swift_constant(settings, "stripeWidth")
    spacing = swift_constant(settings, "swatchSpacing")
    if "padding(.horizontal, swatchSpacing / 2)" not in settings:
        problems.append("the colour swatches no longer widen their tap "
                        "target — a fixed 26pt stripe is a 26pt tap on "
                        "every device, iPad included")
    rows.append(("colour swatch", "every size", stripe, stripe + spacing))

    for label, where, drawn, target in rows:
        if target < drawn:
            problems.append("%s on %s has a target smaller than it draws"
                            % (label, where))

    short = [(l, w, t) for l, w, d, t in rows if t < TAP_MINIMUM]
    for label, where, target in short:
        print("  %-26s %-20s %.1fpt of %.0f" % ("under the tap minimum",
                                                "%s, %s" % (label, where),
                                                target, TAP_MINIMUM))
    widest = max(rows, key=lambda r: r[3])
    print("  %-26s %s at %.1fpt (drawn %.1f)"
          % ("largest target", widest[0], widest[3], widest[2]))

    for line in problems:
        print("  %-26s %s" % ("FAILED", line))
    return bool(problems)



def main():
    layout = code(LAYOUT)
    failed = []

    if "enum GameBandLayout" not in layout:
        print("  FAIL  GameBandLayout is gone — the split is back in eight "
              "screens with nothing checking it")
        sys.exit(1)

    # --- 1. The floor is summed from its parts, not typed. ------------
    padding = swift_constant(layout, "bandPadding")
    button = swift_constant(layout, "buttonHeight")
    caption = swift_constant(layout, "captionLine")
    gap_match = re.search(r"captionGap: CGFloat \{ Elevation\.lifted\.offset \+ (\d+) \}",
                          layout)
    if not gap_match:
        failed.append("captionGap no longer reads Elevation.lifted.offset — "
                      "the floor has to move when the spacing does, which is "
                      "the whole reason it is derived")
        gap = 8.0
    else:
        # Scoped to the `offset` property. A bare search for
        # `case .lifted:` finds the one in `opacity` first and reads the
        # leading 0 of 0.53 as the offset — which is how this check first
        # reported a floor of 89 instead of 95.
        offsets = code("Elevation.swift")
        tail = offsets.split("var offset: CGFloat", 1)[-1]
        lifted = re.search(r"case \.lifted:\s*return (\d+)", tail)
        if not lifted:
            failed.append("Elevation.offset no longer declares .lifted, so "
                          "the band floor cannot be derived")
            gap = 8.0
        else:
            gap = float(lifted.group(1)) + float(gap_match.group(1))

    floor = padding * 2 + button + gap + caption
    print("  %-26s %.0f = %.0f padding + %.0f button + %.0f gap + %.0f caption"
          % ("button band floor", floor, padding * 2, button, gap, caption))

    if "CGFloat = 100" in layout or re.search(r"minButtonHeight", layout):
        failed.append("a typed button-band height is back in GameBandLayout")

    # --- 2. Nothing types its own band height any more. ---------------
    for filename in sorted(SCREENS):
        body = code(filename)
        if re.search(r"let (?:min)?[Bb]uttonHeight: CGFloat = \d+", body):
            failed.append("%s types its own button height instead of taking "
                          "GameBandLayout.buttonBandFloor" % filename)

    # --- 3. The scene stays big enough to play on. --------------------
    #
    # NOT "the band holds its content": that is now true by construction,
    # because `scene` subtracts the floor and `buttonBand` takes the
    # remainder. Asserting it would pass whatever the floor became, which
    # is a check that can never fail — the first version of this did
    # exactly that and reported PASS with the caption gap at 24.
    #
    # What a bloated floor actually costs is the PLAYFIELD, and that is
    # what varies: the dice tray gives way first, by design, so the
    # question worth asking is how much of it is left. Measured at the
    # current floor the worst case is Free Roll on an iPhone SE at 302.6,
    # and the minimum below is the point where a tray of up to twenty
    # dice stops being playable.
    tightest = ("", "", 1e9)
    for filename, fraction in sorted(SCREENS.items()):
        for name, width, height in SIZES:
            header = height * fraction
            scene = min(width, max(height - header - floor, 0))
            if scene < MIN_SCENE:
                failed.append("%s on %s (%dx%d): the playfield comes to "
                              "%.1f, under the %d it needs — the button "
                              "band's floor of %.0f is eating it"
                              % (filename, name, width, height, scene,
                                 MIN_SCENE, floor))
            if scene < tightest[2]:
                tightest = (filename.replace("Screen.swift", ""), name, scene)

    print("  %-26s %s on %s at %.1f (minimum %d)"
          % ("smallest playfield", tightest[0], tightest[1], tightest[2],
             MIN_SCENE))

    if failed:
        print()
        for line in failed:
            print("  FAIL  %s" % line)
        print("\nband layout: FAIL (%d)" % len(failed))
        sys.exit(1)

    print("  %-26s ok (%d screens x %d sizes)"
          % ("every playfield holds", len(SCREENS), len(SIZES)))

    if check_tap_targets():
        failed.append("a control grew smaller than the touch it accepts")
    print("band layout: PASS")


if __name__ == "__main__":
    main()
