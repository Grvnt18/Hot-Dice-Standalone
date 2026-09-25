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

    # --- Two tiers, and the short one is genuinely shorter. -----------
    #
    # The guides split in two: a game's own Settings shows the short
    # version, the hub's bubbles show the full one. The failure to guard
    # against is them drifting back into the same thing — a "quick start"
    # that is the whole manual is worse than no split at all, because a
    # player mid-match now scrolls past the differential table to find
    # what their button does.
    missing, not_short = [], []
    for filename in sorted(os.listdir(SWIFT)):
        if not filename.endswith(".swift"):
            continue
        text = source(filename)
        if "static let rules: [GameRuleSection] = [" not in text:
            continue
        full = text.count("static let rules: [GameRuleSection] = [")
        quick = text.count("static let quickRules: [GameRuleSection] = [")
        if quick < full:
            missing.append(filename)
            continue
        # Compared per game rather than per file, since SuiteGame.swift
        # holds two.
        for block in text.split("static let quickRules: [GameRuleSection] = [")[1:]:
            short = block.split("\n    ]", 1)[0]
            after = block.split("static let rules: [GameRuleSection] = [", 1)
            if len(after) < 2:
                continue
            long = after[1].split("\n    ]", 1)[0]
            if short.count("GameRuleSection(") >= long.count("GameRuleSection("):
                not_short.append(filename)
    check("every game has a quick guide", not missing, ", ".join(missing))
    check("the quick guide is shorter", not not_short,
          ", ".join(sorted(set(not_short))))

    # And each tier reaches the screen it belongs to.
    settings = source("SettingsView.swift")
    check("a game's Settings shows the short one",
          "self.rules = G.quickRules" in settings,
          "SettingsView(for:) is handing out the full guide again")
    check("the hub's bubbles show the full one",
          "sections: entry.rules" in source("GuideBubbles.swift"),
          "the cluster is no longer opening the detailed rules")

    check_retired_wording()

    if check.failed:
        print("rules text: FAILED")
        sys.exit(1)
    print("rules text: PASS")


if __name__ == "__main__":
    main()
