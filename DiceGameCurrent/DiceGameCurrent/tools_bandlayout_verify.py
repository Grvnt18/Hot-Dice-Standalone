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

from tools_swiftconst import constant, source, swift_names

LAYOUT = "PlayfieldLayout.swift"

# Every size the app can be handed. The iPad floor is NOT a device — it is
# Slide Over, which is about 320 points wide on every iPad, so the
# narrowest case is an iPad rather than a phone.
SIZES = [
    ("iPad Slide Over", 320, 1133),
    # The SMALLEST IPHONE IS 375x667, and this row used to say 320x568.
    #
    # That is the 4-inch SE, which stops at iOS 15.8 — the deployment
    # floor here is iOS 16, so no device the app can install on is that
    # shape. It is not a harmless extra either: it is 60 points shorter
    # than anything real, and the scoreboard check below reported three
    # screens overflowing a header on a phone that cannot run the app.
    #
    # The narrow case is not lost with it. 320 points wide is still here,
    # as Slide Over above — which is where it always came from, per the
    # note at the top of this list.
    ("iPhone SE 2/3", 375, 667),
    ("iPhone 13 mini", 375, 812),
    ("iPhone 15", 393, 852),
    ("iPhone 15 Pro Max", 430, 932),
    ("iPad 1/2 split", 507, 1133),
    ("iPad mini", 744, 1133),
    ("iPad Air", 820, 1180),
    ("iPad Pro", 1024, 1366),
    # Landscape IS a supported orientation on iPad now, and these are no
    # longer hypothetical. Apple will not accept an iPad app that claims
    # one orientation while also allowing Slide Over and Split View, and
    # multitasking is the half this suite keeps — so an iPad can be
    # turned, and every one of these shapes is a screen somebody sees.
    #
    # The note here used to say landscape was unsupported and checked
    # anyway, "the only shape where the band bottoms out". That part is
    # still true and is now load-bearing rather than curiosity.
    ("iPad mini landscape", 1133, 744),
    ("iPad Air landscape", 1180, 820),
    ("iPad Pro landscape", 1366, 1024),
    # The iPhone Duo, Apple's first foldable, in both states. It is the
    # squattest thing the app meets in PORTRAIT — 1.46 and 1.42, where
    # every other iPhone is about 2.16 — and the only device whose window
    # changes size while the app is open, which is why check 4 below
    # exists.
    #
    # Points derived, not published: Apple gives 1398x2034 at 460ppi
    # folded and 1878x2670 at 430ppi open, and both ppi figures are the
    # @3x family, so these are those divided by three. Correct them from
    # the SDK once a build has actually run on one — the aspect ratios,
    # which are what check 4 reads, barely move if the scale factor turns
    # out to differ.
    ("iPhone Duo folded", 466, 678),
    ("iPhone Duo open", 626, 890),
]

# Sizes one device can move BETWEEN without the app being relaunched, as
# (label, [size names]). Everything else in SIZES is a different device.
#
# This is the list that did not need to exist before a foldable did. The
# app is portrait-only, so a window used to change size only when an iPad
# Split View divider was dragged; a Duo changes it by being opened.
RESIZE_GROUPS = [
    ("folding a Duo", ["iPhone Duo folded", "iPhone Duo open"]),
    ("dragging an iPad Split View divider",
     ["iPad Slide Over", "iPad 1/2 split", "iPad mini"]),
]

# How small the square playfield may get before a tray of dice stops
# being playable. Measured: at today's floor the worst case is Free Roll
# on an iPhone SE at 302.6, so this leaves about 40 points of room for the
# floor to grow before anything is said.
MIN_SCENE = 260

# The cap on the button band (`bandCeiling`) and the shape gate that
# decides whether it applies at all (`tallAspect`) are READ out of
# PlayfieldLayout.swift where they are used, not restated here — a typed
# copy of 0.20 outlived the Swift's move to 0.10 and the model went on
# passing while modelling a layout the app no longer draws.

# Each screen and the header fraction it asks for.
SCREENS = {
    # Rolls joined the shared split — it used to compute 0.15 and a typed
    # 100 inline, which is how it ended up with a 237pt button band on an
    # iPhone 14 while its tray stopped at 393.
    "DiceGameShell.swift": 0.17,
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


# The strip's own metrics, by the names GameBandLayout gives them. Read,
# not typed: the point of moving them out of MatchScoreboard was that the
# header is sized in one file and its content described in another.
SCOREBOARD_METRICS = ("scoreboardNameFont", "scoreboardScoreFont",
                      "scoreboardLineFactor", "scoreboardTileGap",
                      "scoreboardTilePadding", "scoreboardRowGap",
                      "scoreboardPadding", "scoreboardRoundFont",
                      "scoreboardSubtitleFont")

SCOREBOARD = "PassAndPlayHost.swift"


def four_seat_screens():
    """The screens whose game can seat four, derived from the games.

    `localSeats = Int.max` is a game saying it will take as many seats as
    the setup gate offers, and the gate offers four — see
    MatchSetup.maxSeats. Each such game's screen is its own file plus
    "Screen", which holds for all four of them.

    Derived rather than listed so a FIFTH game opening up to four seats
    cannot quietly keep a one-row header: it appears here the moment its
    `localSeats` changes, and the checks below then have something to say
    about it.

    One game is deliberately outside this: Rolls seats four through
    `RollsPassAndPlayHost`, one screen per seat, and its header is its own
    banked-dice grid rather than `MatchScoreboard`. It drops out here
    because `SuiteGameScreen.swift` does not exist, which is luck rather
    than design — a game whose screen is not named after its rules file
    would drop out the same way.
    """
    screens = []
    for name in swift_names():
        if name.endswith("Screen.swift") or "/" in name:
            continue
        if not re.search(r"static let localSeats = Int\.max", code(name)):
            continue
        screen = name.replace(".swift", "Screen.swift")
        if screen in swift_names():
            screens.append(screen)
    return sorted(screens)


def check_scoreboard(failed, floor):
    """The header has to HOLD the scoreboard, at four seats as at two.

    Nothing checked this, and it is the one band whose content is not
    bounded by its own frame: `MatchScoreboard` is a ZStack inside a
    `.frame(height:)`, and a ZStack does not clip. A strip taller than its
    header does not fail or compress — it draws over the tray below it,
    on one seat count, on some devices, in three games nobody plays
    two-handed while testing.

    Which is exactly what four seats on two rows would have done: the
    content comes to about 167pt and 17% of an iPhone is 113 to 158.
    """
    layout = code(LAYOUT)
    metrics = {}
    for name in SCOREBOARD_METRICS:
        try:
            metrics[name] = swift_constant(layout, name)
        except AssertionError:
            failed.append("GameBandLayout no longer states %s, so the "
                          "header cannot be checked against what it holds"
                          % name)
            return

    line = metrics["scoreboardLineFactor"]
    tile = ((metrics["scoreboardNameFont"] + metrics["scoreboardScoreFont"])
            * line + metrics["scoreboardTileGap"]
            + metrics["scoreboardTilePadding"] * 2)
    gap = metrics["scoreboardRowGap"]

    def content(rows, rounds=True):
        """The strip's height: padding, the optional round line, the seat
        tiles, the status line.

        `rounds` because four of the seven screens pass `totalRounds:
        nil` — HOG and Three Thousand are races, Royal UR and Boneheads
        have no round count — and a model that assumes the line is always
        there prices Boneheads' 14% header against 21 points it does not
        draw. Every screen passes a subtitle, so that one is not
        optional.
        """
        tiles = rows * tile + (rows - 1) * gap
        head = (metrics["scoreboardRoundFont"] * line + gap) if rounds else 0
        return (metrics["scoreboardPadding"] * 2
                + head
                + tiles
                + gap + metrics["scoreboardSubtitleFont"] * line)

    def shows_rounds(filename):
        call = re.search(r"MatchScoreboard\((.*?)\n\s*\)", code(filename),
                         flags=re.S)
        return bool(call) and "totalRounds: nil" not in call.group(1)

    # The rule the Swift states, ported: two rows at four seats, one
    # otherwise. Read from the source so it cannot drift out of this.
    rows_rule = re.search(r"func scoreboardRows\(seats: Int\) -> Int \{\s*"
                          r"seats == (\d+) \? 2 : 1", layout)
    if not rows_rule:
        failed.append("GameBandLayout.scoreboardRows is no longer "
                      "'two rows at one seat count', so this check's model "
                      "of the strip is guesswork")
        return
    grid_at = int(rows_rule.group(1))

    # --- a. One row fits each screen's OWN share, everywhere. ---------
    #
    # Not one fraction: Boneheads asks for 0.14 and Royal UR 0.15, and
    # both are below the 0.17 the rest take. The seats-aware fraction only
    # ever raises a header, so every screen that does not ask for it — and
    # every 4-seat screen below the grid count — is relying on its own
    # share alone.
    strips = [f for f in sorted(SCREENS) if "MatchScoreboard(" in code(f)]
    if not strips:
        failed.append("no screen uses MatchScoreboard any more, so this "
                      "check is measuring a strip nothing draws")
        return
    tightest = ("", "", 1e9)
    for filename in strips:
        one = content(1, rounds=shows_rounds(filename))
        for name, _, height in SIZES:
            slack = height * SCREENS[filename] - one
            if slack < 0:
                failed.append("%s's scoreboard wants %.1fpt and its %.0f%% "
                              "of %s is %.1f — the strip would draw over "
                              "the tray"
                              % (filename, one, SCREENS[filename] * 100,
                                 name, height * SCREENS[filename]))
            if slack < tightest[2]:
                tightest = (filename.replace("Screen.swift", ""), name, slack)
    print("  %-26s %d strips, tightest margin %.1fpt (%s on %s)"
          % ("one-row scoreboard", len(strips), tightest[2],
             tightest[0], tightest[1]))

    # --- b. The grid's taller header must not starve the playfield. ---
    #
    # `scene` is capped by WIDTH in portrait, so on a phone the extra
    # header comes out of tray rather than playfield. The two shapes that
    # are height-bound instead — a folded Duo, a landscape iPad mini — pay
    # in playfield, and this is where that is priced.
    four = four_seat_screens()
    grid = max(content(2, rounds=shows_rounds(f)) for f in four) if four \
        else content(2)
    worst = ("", 1e9)
    for name, width, height in SIZES:
        header = max(height * 0.17, grid)
        scene = min(width, max(height - header - floor, 0))
        if scene < MIN_SCENE:
            failed.append("at four seats %s leaves a %.1fpt playfield, "
                          "under the %d it needs" % (name, scene, MIN_SCENE))
        if scene < worst[1]:
            worst = (name, scene)
    print("  %-26s %.1fpt of content, smallest playfield %.1f on %s"
          % ("2x2 scoreboard", grid, worst[1], worst[0]))

    # --- c. The strip and the header read the SAME numbers. -----------
    #
    # A retyped literal in MatchScoreboard is the silent half of this: the
    # model above would go on passing while the strip grew.
    strip = code(SCOREBOARD)
    for name in SCOREBOARD_METRICS:
        if name == "scoreboardLineFactor":
            continue               # the font's own metric, not a spacing
        if "GameBandLayout.%s" % name not in strip:
            failed.append("MatchScoreboard no longer reads %s from "
                          "GameBandLayout, so the header's model of its "
                          "height is only a copy" % name)
    if "GameBandLayout.scoreboardRows" not in strip:
        failed.append("MatchScoreboard splits its seats by something other "
                      "than GameBandLayout.scoreboardRows, which is what "
                      "sized the header it sits in")

    # --- d. Every screen that can seat four asks for the seat-aware
    #        header, and the ones that cannot do not. ------------------
    for filename in sorted(SCREENS):
        asks = "seats: match.participants.count" in code(filename)
        is_four = filename in four_seat_screens()
        if is_four and not asks:
            failed.append("%s can seat %d but takes the fixed header share "
                          "— at four seats its scoreboard is %.1fpt in a "
                          "header of %.1f on an iPhone 15"
                          % (filename, grid_at, grid, 852 * 0.17))
        if asks and not is_four:
            failed.append("%s passes a seat count but its game cannot seat "
                          "four, so the header moves for nothing" % filename)
    print("  %-26s %s"
          % ("seat-aware headers", ", ".join(s.replace("Screen.swift", "")
                                             for s in four_seat_screens())
             or "none"))


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

    # --- 1b. The header holds the scoreboard, at every seat count. ----
    check_scoreboard(failed, floor)

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
            # The scene is unchanged: the square it always was. What
            # changed is where the LEFTOVER goes — the band is capped at a
            # fifth now and the rest becomes tray around the scene, so
            # this still measures the playfield itself.
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

    # --- 4. A resize must REFIT, never re-deal. -----------------------
    #
    # The arena is built for a SHAPE — PlayfieldLayout.compute takes an
    # aspect ratio and a world-width constant, and nothing in it is in
    # points — so a view that changes size keeps a valid arena and a view
    # that changes SHAPE does not.
    #
    # This check used to police a threshold. Re-assembly re-dealt the
    # dice, so `aspectRebuildThreshold` had to sit above a Duo fold and
    # below an iPad divider drag, and the check held it there. The arena
    # is re-fitted in place now: DiceSceneAssembler.refit swaps the arena
    # node and leaves the dice container alone, so no shape change costs a
    # round and the threshold is only there to stop pointless work during
    # a layout pass.
    #
    # So what is worth holding is the shape of the CODE: both views must
    # ask `needsRefit` and call `refit`, and neither may still re-enter
    # assembly by clearing its own flag. The drift numbers below stay as a
    # report, because they are what says a fold and a drag are different
    # sizes of problem.
    for filename in ("DiceGameShell.swift", "DiceTraySceneView.swift"):
        view = code(filename)
        if "PlayfieldLayout.needsRefit" not in view:
            failed.append("%s does not ask PlayfieldLayout.needsRefit, so a "
                          "window that changes shape leaves it rendering an "
                          "arena built for the shape before" % filename)
        if "DiceSceneAssembler.refit" not in view:
            failed.append("%s does not call DiceSceneAssembler.refit — if it "
                          "answers a shape change by assembling again it "
                          "re-deals the dice mid-round, which is the fault "
                          "the refit exists to remove" % filename)
        # `coordinator.` on purpose: the Coordinator's own declaration is
        # `var hasStartedAssembly = false`, so the bare spelling matches
        # the property rather than a reset of it.
        if "coordinator.hasStartedAssembly = false" in view:
            failed.append("%s still clears hasStartedAssembly, which re-enters "
                          "assembly and tears down the dice pool" % filename)

    layout_src = source("PlayfieldLayout.swift")
    threshold = constant(layout_src, "aspectRefitThreshold")
    # Read, not typed. BAND_CEILING sat at 0.20 here for a while after the
    # Swift moved to 0.10: the model stayed looser than the code, so it
    # went on passing while reporting splits the app does not produce.
    # Same for the shape gate below, which did not exist in the model at
    # all — and it is the whole reason full-screen iPads do not move.
    ceiling = constant(layout_src, "bandCeiling")
    tall = constant(layout_src, "tallAspect")
    # Rolls used to be absent here, because it split its bands inline with
    # its own fraction and its own typed 100. It goes through
    # GameBandLayout now like the other five, so it is simply a row in
    # SCREENS and this no longer needs a special case for it.
    by_name = {name: (w, h) for name, w, h in SIZES}
    resettable = []
    for filename, fraction in sorted(SCREENS.items()):
        label = filename.replace("Screen.swift", "").replace("DiceGameShell", "Rolls")
        # Which screens actually hand the REGION to the well, and so have
        # an aspect that moves with the window. Free Roll passes the
        # square instead, and Boneheads and Royal UR do not use these
        # bands at all — counting them was a conservative guess where the
        # Swift gives a straight answer.
        fills = "bands.sceneRegion" in code(filename)
        for group, members in RESIZE_GROUPS:
            # The scene FILLS its region now — it was briefly squared,
            # which left tray between it and the roll button — so its
            # aspect is the region's and moves with the window.
            ratios = []
            for name in members:
                width, height = by_name[name]
                square = min(width, max(height - height * fraction - floor, 0))
                if not fills:
                    ratios.append(width / square if square > 0 else float("inf"))
                    continue
                leftover = height - height * fraction - square
                if width > 0 and height / width > tall:
                    band = min(max(leftover, floor),
                               max(height * ceiling, floor))
                else:
                    # Not a tall screen, so the cap does not apply at all
                    # and the band keeps whatever the square leaves it —
                    # this is what holds the full-screen iPads still.
                    band = max(leftover, floor)
                region = max(height - height * fraction - band, 0)
                ratios.append(width / region if region > 0 else float("inf"))
            drift = max(ratios) - min(ratios)
            if drift > threshold:
                resettable.append((label, group, drift))

    # Both moves must now REACH the threshold rather than clear it: a fold
    # that goes unnoticed is a Duo showing walls for the shape it had
    # while closed. The old threshold was set to miss a fold on purpose,
    # because noticing cost a round; the refit means noticing is free, so
    # anything that moves the shape at all should be picked up.
    folds = [r for r in resettable if "Duo" in r[1]]
    drags = sorted({r[0] for r in resettable if "divider" in r[1]})
    if not folds:
        failed.append("no screen re-fits on a Duo fold at the %.3f threshold "
                      "— the fold moves the playfield's shape by about 2%% "
                      "and that is now worth following, since a refit keeps "
                      "the dice" % threshold)
    print("  %-26s a divider drag refits %d screen(s); a fold refits "
          "%d (threshold %.3f)"
          % ("resize refits", len(drags), len(folds), threshold))

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
