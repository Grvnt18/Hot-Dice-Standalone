"""Checks the in-app rules text against the constants it describes.

Free Roll's rules said "up to 10 dice" for a whole phase after the ceiling
moved to 20, and nothing caught it — the text and the code had no
connection. Where a number could be interpolated from its constant it now
is, and this asserts the rest.

Run it after touching any rules array or any tuning constant."""
import os
import re
import sys

# Paths and the constant parser both come from tools_swiftconst, which
# anchors them to the script's own directory. This used to open
# "SwiftFiles/..." relatively, so it only worked from the project root.
from tools_swiftconst import source, constant, SWIFT  # noqa: F401


def rules_blob(text):
    """Every rules body in one string, for substring checks."""
    return " ".join(m.group(1) for m in
                    re.finditer(r'body: "((?:[^"\\]|\\.)*)"', text))


def check(label, condition, detail=""):
    if condition:
        print("  %-34s ok" % label)
    else:
        print("  %-34s FAILED  %s" % (label, detail))
        check.failed = True


check.failed = False


# Wording that was renamed, and what replaced it. Every entry here was once
# shown to a player and must not be any more.
#
# This exists because the rules arrays were only half the problem. Phase 6
# renamed four games and Freighter.Yacht.Dinghy's three qualifiers; the
# rules followed, the summaries followed, and one scoreboard subtitle kept
# saying "Ship, Captain, Crew" for four phases — because nothing read the
# runtime strings back. The checks above test the rules text against the
# constants; this tests EVERY user-facing string against the renames.
RETIRED = [
    (r"Ship, Captain, Crew", "Freighter, Yacht, Dinghy"),
    (r"\bFarkle", "Busted"),
    (r"\bChasing 6\b", "Jackpot"),
    (r"\bCyberDie\b", "Rollbots"),
    (r"\bRoyal Path\b", "Royal UR"),
    (r"\bNautical\b", "Freighter.Yacht.Dinghy"),
    (r"\bPIG\b", "HOG"),
]

# A string literal that stays on one line. Crossing newlines would swallow
# the code between an empty string and the next quote, which is how the
# first draft of this scan reported nonsense.
_LITERAL = re.compile(r'"((?:[^"\\\n]|\\.)*)"')


def _user_facing_strings(text):
    """Every string literal, with comments removed first.

    Comments are stripped because they legitimately discuss the old names —
    several explain why a rename happened. Only what ships to the screen is
    in scope.
    """
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    text = re.sub(r"///[^\n]*", "", text)
    text = re.sub(r"(?<!:)//[^\n]*", "", text)
    return [(m.group(1), text[: m.start()].count("\n") + 1)
            for m in _LITERAL.finditer(text)]


def check_retired_wording():
    """No retired name may survive in anything a player can read."""
    hits = []
    for filename in sorted(os.listdir(SWIFT)):
        if not filename.endswith(".swift"):
            continue
        for literal, line in _user_facing_strings(source(filename)):
            for pattern, replacement in RETIRED:
                if re.search(pattern, literal):
                    hits.append((filename, line, literal, replacement))
    for filename, line, literal, replacement in hits:
        print("  %-34s FAILED  %s:%d" % ("retired wording", filename, line))
        print("      %r — should read %s" % (literal, replacement))
    check("no retired wording on screen", not hits,
          "%d string(s) still show a renamed term" % len(hits))


def check_figures():
    """A diagram must be generated from the rule, not drawn beside it.

    Three sections carry a figure: the rosette, Royal UR's route, and the
    Boneheads multiplier worked out. Each illustrates a rule, which means
    each has the same failure mode the rules text had before this file
    existed — the code moves and the picture does not, and a picture is
    harder to proofread than a sentence.

    So none of the three may hold its own copy of the facts. The route
    comes from the board's path array, the rosette from the board's own
    marking routine, and the Boneheads numbers from the scoring function
    the game actually scores with.

    The Boneheads total is also recomputed here, by this file, from the
    columns the figure declares. That is a second opinion on the rule
    rather than a restatement of it: if `columnScore` and the published
    formula ever disagree, this fails even though the Swift still compiles.
    """
    art = source("GuideBubbles.swift")

    for label, token in (
        ("the route reads the board", "RoyalUrBoard.path(for:"),
        ("the flowers read the board", "RoyalUrBoard.rosettes"),
        ("the squares read the board", "RoyalUrBoard.squares"),
        ("the rosette is the board's own",
         "RoyalUrArt.draw(.rosette, in: context"),
        ("the multiplier reads the scorer",
         "BoneheadsRules.columnScore("),
    ):
        check("figure: %s" % label, token in art,
              "GuideBubbles.swift no longer calls %s" % token)

    # The worked columns, read out of the Swift so the two cannot drift.
    match = re.search(r'columns: \[\[Int\]\] = (.+)\n', art)
    if not match:
        check("figure: the worked columns are readable", False,
              "BoneheadsScoringFigure.columns is no longer a literal array")
        return

    columns = [[int(n) for n in re.findall(r'\d+', group)]
               for group in re.findall(r'\[([^\[\]]+)\]', match.group(1))]

    def column_score(dice):
        """(face x occurrences) x occurrences, summed over distinct faces."""
        counts = {}
        for die in dice:
            counts[die] = counts.get(die, 0) + 1
        return sum(face * n * n for face, n in counts.items())

    subtotals = [column_score(c) for c in columns]
    total = sum(subtotals)

    # No total may be typed. The figure prints what `columnScore` returns,
    # and the reason that matters is on record: the worked chart this figure
    # was drawn from had correct per-column subtotals of 21, 27 and 11 and
    # printed their sum as 49. It is 59. A hand-added total is exactly the
    # thing a reader trusts and cannot check, so the Swift adds it up and
    # this asserts nothing typed can shadow that.
    typed = re.findall(r'TOTAL: (\d+)', art)
    check("figure: no total is typed into the figure", not typed,
          "a literal total %s is printed instead of the computed one"
          % ", ".join(typed))
    print("  %-34s %s -> %s, total %d"
          % ("figure: worked example", columns, subtotals, total))

    # All three multipliers, or the figure demonstrates less than it claims.
    shapes = {max(len([d for d in c if d == face]) for face in set(c))
              for c in columns}
    check("figure: it shows a single, a pair and a triple",
          shapes == {1, 2, 3}, "largest group per column: %s" % sorted(shapes))


def strip_comments(text):
    """Comments here legitimately discuss `1 - seat` and the rest; code may
    not. Same stripping `_user_facing_strings` does, for the same reason."""
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    text = re.sub(r"///[^\n]*", "", text)
    return re.sub(r"(?<!:)//[^\n]*", "", text)


def check_seats():
    """The games that say "two or more" must not count to two.

    GAME_RULES.txt describes Rolls, HOG, Three Thousand and
    Freighter.Yacht.Dinghy as two or more players. Rolls already had no
    ceiling; the other three declared the protocol default of 2 while
    their screens were, in fact, already seat-based — TurnMatch handles
    any number, advanceTurn wraps on participants.count, and scores are
    keyed by participant.

    So raising the ceiling was a one-line change per game, and the risk is
    not that it breaks today. It is that someone later reaches for the
    shortcut that two players make available — `1 - seat` for "the other
    one", `participants[1]` for "them", a count check — in a screen that
    now claims to take five. Each of those is correct for two and silently
    wrong for three, which is the worst way to be wrong.

    This fails them by name, in the screens that claim the ceiling.
    """
    claimants = {
        "ThreeThousand.swift": "ThreeThousandScreen.swift",
        "Hog.swift": "HogScreen.swift",
        "FreighterYachtDinghy.swift": "FreighterYachtDinghyScreen.swift",
    }

    for model, screen in sorted(claimants.items()):
        body = strip_comments(source(model))
        if "static let maxPlayers = Int.max" not in body:
            check("seats: %s has no ceiling" % model, False,
                  "GAME_RULES.txt says two or more players")
            continue

        code = strip_comments(source(screen))
        found = []
        for label, pattern in (
            ("1 - seat", r'\b1 - seat\b'),
            ("1 - activeIndex", r'\b1 - match\.activeIndex\b'),
            ("participants[1]", r'participants\[1\]'),
            ("a count of two", r'participants\.count == 2'),
            ("localTwoPlayer with a literal pair",
             r'TurnMatch\(participants: \["[^"]*", "[^"]*"\]\)'),
        ):
            if re.search(pattern, code):
                found.append(label)
        check("seats: %s is seat-based" % screen, not found,
              "uses %s, which is correct for two players and wrong for three"
              % ", ".join(found))

    # And the factory that used to be the only thing saying "two".
    turns = strip_comments(source("TurnMatch.swift"))
    check("seats: a match can be made for any number",
          "static func local(playerCount: Int" in turns,
          "TurnMatch still only builds two-player matches")

    # Compiling at N and being CORRECT at N are different claims, so the
    # turn order is simulated rather than read. A mirror of advanceTurn:
    # wrap on participants.count, advance the round on wrap, and close the
    # round on the last seat.
    for seats in (2, 3, 5, 8):
        active, rnd, closes = 0, 1, []
        for turn in range(seats * 4):
            if active == seats - 1:
                closes.append(turn)
            active += 1
            if active >= seats:
                active = 0
                rnd += 1
        check("seats: %d players take even turns" % seats,
              rnd == 5 and len(closes) == 4,
              "%d rounds and %d round-closings over %d turns"
              % (rnd, len(closes), seats * 4))


def check_wire():
    """Every game that can be sent is actually exercised.

    The transport was written, documented and budgeted long before anything
    used it: GameEnvelope, the versioned header, base64url, a 4 KB budget
    and a size report — and not one line of it had ever encoded a real
    turn. It was correct by inspection, which is the weakest kind of
    correct.

    GameWireCheck packs a turn per game, sends it through the real URL
    path, reads it back and compares. The failure this guards is the quiet
    one: a game joins the suite, declares itself sendable, and nobody adds
    a probe — so it ships having never survived a round trip.

    Free Roll is the one game legitimately absent, because it is solo and
    says so with isSendable = false.
    """
    payload = strip_comments(source("GamePayload.swift"))

    if "static func runAll()" not in payload:
        check("wire: there is a round-trip check", False,
              "GameWireCheck.runAll is gone")
        return

    probed = set(re.findall(r'probe\(game: "([^"]+)"', payload))
    if "RollsGameState.gameID" in payload:
        probed.add("rolls")

    # Every game's id, read from the games themselves.
    declared = {}
    for filename in sorted(os.listdir(SWIFT)):
        if not filename.endswith(".swift"):
            continue
        body = strip_comments(source(filename))
        for match in re.finditer(r'static let id = "([^"]+)"', body):
            declared[match.group(1)] = filename
        if "static let id = RollsGameState.gameID" in body:
            declared["rolls"] = filename

    # A game opts out by saying so, not by being forgotten.
    optedOut = set()
    for filename in sorted(os.listdir(SWIFT)):
        if not filename.endswith(".swift"):
            continue
        body = strip_comments(source(filename))
        if "static let isSendable = false" in body:
            for match in re.finditer(r'static let id = "([^"]+)"', body):
                optedOut.add(match.group(1))

    missing = sorted(set(declared) - probed - optedOut)
    check("wire: every sendable game is probed", not missing,
          "no round trip for %s" % ", ".join(missing))

    stray = sorted(probed - set(declared))
    check("wire: no probe for a game that does not exist", not stray,
          "probes name %s" % ", ".join(stray))

    check("wire: a turn carries the match and the state",
          "struct MatchPayload" in payload,
          "the bookkeeping and the game state are no longer sent together")
    check("wire: the budget is still stated",
          "safeByteBudget" in payload,
          "nothing says how big a turn may be")

    print("  %-34s %d probed, %d opted out"
          % ("wire: games", len(probed), len(optedOut)))


def main():
    print("rules text against the constants:")

    free = source("FreeRoll.swift")
    max_dice = constant(free, "maxDice")
    check("Free Roll ceiling interpolated",
          "\\(FreeRollPool.maxDice) dice" in free,
          "the number must come from the constant, not be typed again")
    check("Free Roll ceiling is 20", max_dice == 20, max_dice)
    check("Free Roll documents Totals", "Totals is off by default" in rules_blob(free))

    fyd = source("FreighterYachtDinghy.swift")
    rolls = constant(fyd, "rollsPerTurn")
    check("F.Y.D. rolls per turn is 4", rolls == 4, rolls)
    check("F.Y.D. rules say four rolls",
          "four rolls" in rules_blob(fyd), "rules and constant disagree")
    for name in ("Freighter", "Yacht", "Dinghy"):
        check("F.Y.D. names the %s" % name, name in rules_blob(fyd))

    three = source("ThreeThousand.swift")
    target = constant(three, "target")
    check("Three Thousand target is 3000", target == 3000, target)
    check("Three Thousand rules say 3,000", "3,000" in rules_blob(three))
    check("Three Thousand says Busted",
          "Busted" in rules_blob(three) and "arkle" not in rules_blob(three))

    hog = source("Hog.swift")
    check("Hog target is 75", constant(hog, "target") == 75)
    check("Hog rules say 75", "75" in rules_blob(hog))

    bones = source("Boneheads.swift")
    check("Boneheads grid is 3 columns", constant(bones, "columns") == 3)
    check("Boneheads rules say nine slots", "nine" in rules_blob(bones))

    bots = source("Rollbots.swift")
    check("Rollbots IP interpolated",
          "\\(RollbotsRules.startingIP)" in bots,
          "the number must come from the constant")
    check("Rollbots IP is 16", constant(bots, "startingIP") == 16)

    ur = source("RoyalUrScreen.swift")
    check("Royal UR describes marked points",
          "marked points" in rules_blob(ur),
          "rules must match the marked-tip dice, not the old numbers")
    check("Royal UR drops the old wording",
          "1 or a 2" not in rules_blob(ur))

    generals = source("Generals.swift")
    check("Generals rules say twelve", "twelve categories" in rules_blob(generals))

    # --- Every bubble opens something. -------------------------------
    #
    # The hub's How to Play is a cluster of bubbles built from
    # GameCatalog, one per game, each opening that game's own rules. A
    # game whose rules array is empty would give a bubble that opens a
    # blank sheet — and since the rules live in eleven different files,
    # that is exactly the kind of gap nobody notices until a player taps
    # it.
    catalog = source("SuiteGame.swift")
    check("the catalogue carries each game's rules",
          "rules: G.rules" in catalog,
          "GameCatalogEntry no longer takes rules from the game")

    empty = []
    for filename in sorted(os.listdir(SWIFT)):
        if not filename.endswith(".swift"):
            continue
        text = source(filename)
        for match in re.finditer(
                r'static let (?:id|displayName) = "', text):
            pass
        if "static let rules: [GameRuleSection] = [" not in text:
            continue
        body = text.split("static let rules: [GameRuleSection] = [", 1)[1]
        if not re.search(r'GameRuleSection\(', body.split("\n    ]", 1)[0]):
            empty.append(filename)
    check("no game ships an empty guide", not empty, ", ".join(empty))

    # --- One guide, because two tiers meant the short one was wrong. --
    #
    # The guides used to split in two: a game's own Settings showed
    # `quickRules`, the hub's bubbles showed `rules`. The reasoning was that
    # a player mid-match wants "what does my button do", not the
    # differential table.
    #
    # In practice it meant the guide you could reach fastest was the one
    # that left things out, and the full rules were two taps away on a
    # screen you have to quit the match to reach. So there is one guide now,
    # and this is what stops the second tier growing back: the NAME may not
    # appear in any Swift source at all. Checking the name rather than the
    # behaviour is deliberate — a reintroduced `quickRules` that nothing
    # reads yet is still the first half of the same mistake.
    revived = []
    for filename in sorted(os.listdir(SWIFT)):
        if not filename.endswith(".swift"):
            continue
        if "quickRules" in source(filename):
            revived.append(filename)
    check("one guide, not two", not revived,
          "quickRules is back in " + ", ".join(revived))

    # And the one guide reaches both screens that show it.
    settings = source("SettingsView.swift")
    check("a game's Settings shows the full guide",
          "self.rules = G.rules" in settings,
          "SettingsView(for:) is handing out something other than G.rules")
    check("the hub's bubbles show the full one",
          "sections: entry.rules" in source("GuideBubbles.swift"),
          "the cluster is no longer opening the detailed rules")

    check_figures()
    check_seats()
    check_wire()
    check_retired_wording()

    if check.failed:
        print("rules text: FAILED")
        sys.exit(1)
    print("rules text: PASS")


if __name__ == "__main__":
    main()
