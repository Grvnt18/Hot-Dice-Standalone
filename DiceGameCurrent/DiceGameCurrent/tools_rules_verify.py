"""Checks the in-app rules text against the constants it describes.

Free Roll's rules said "up to 10 dice" for a whole phase after the ceiling
moved to 20, and nothing caught it — the text and the code had no
connection. Where a number could be interpolated from its constant it now
is, and this asserts the rest.

Run it after touching any rules array or any tuning constant."""
import base64
import json
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

    # And the dice in it are flat. `PipFace` carries the board's own
    # treatment — sheen, bevel and `.elevated(.piece)` — and at 24 points
    # that shadow read as a second die offset behind the first. The comment
    # beside the figure claimed "no plate, no bevel, no shadow" while the
    # component added all three, so the claim is now asserted.
    screen = source("BoneheadsScreen.swift")
    check("figure: the dice can be drawn flat",
          "var flat: Bool = false" in screen,
          "PipFace has no flat option")
    check("figure: the figure's dice are flat",
          "PipFace(value: die, tint: MenuInk.text, flat: true)" in art,
          "the Boneheads figure is drawing board dice, shadow and all")
    check("figure: the board's dice are not",
          "PipFace(value: die.face," in screen,
          "the board is no longer drawing solid dice")


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

    # --- and a live game can actually produce one --------------------
    #
    # A round trip proves the TYPE survives the wire. It says nothing about
    # whether a game being played can hand one over, and for a while
    # nothing could: five games had a state type that only the probe ever
    # constructed, from values invented for the test. Shipping that would
    # have meant an extension with ten states it could encode and no game
    # that could fill one in.
    #
    # So each screen states both directions — what it would send, and what
    # it does with one that arrives.
    SCREENS = {
        "hog": "HogScreen.swift",
        "jackpot": "JackpotScreen.swift",
        "three_thousand": "ThreeThousandScreen.swift",
        "fyd": "FreighterYachtDinghyScreen.swift",
        "generals": "GeneralsScreen.swift",
        "royal_ur": "RoyalUrScreen.swift",
        "rollbots": "RollbotsScreen.swift",
        "baseball_dice": "BaseballDiceScreen.swift",
        "boneheads": "BoneheadsScreen.swift",
    }
    unbridged = []
    for game, filename in sorted(SCREENS.items()):
        code = strip_comments(source(filename))
        if "var wireTurn: MatchPayload<" not in code:
            unbridged.append("%s cannot pack a turn" % game)
        if "func adopt(_ incoming: MatchPayload<" not in code:
            unbridged.append("%s cannot take one" % game)
    check("wire: a live game can pack and take a turn", not unbridged,
          "; ".join(unbridged))

    # Rolls is the exception and needs naming rather than excusing: it has
    # no TurnMatch and no per-screen state — a single round, no turn order,
    # which is why it is the one game a whole group chat can play at once.
    # Its result is packed off the controller that owns the live round,
    # because DiceGameSession.round goes stale the moment a new game begins
    # and that type's own comment says so.
    turns = strip_comments(source("DiceTurnController.swift"))
    check("wire: Rolls can pack its round",
          "var wireResult: RollsPlayerResult" in turns,
          "DiceTurnController no longer exposes a packed result")
    check("wire: Rolls packs from the live round",
          "private var round: DiceGameRound" in turns,
          "the round is no longer private, so the packed result is not the "
          "only way out of it")

    print("  %-34s %d probed, %d opted out"
          % ("wire: games", len(probed), len(optedOut)))


# ---------------------------------------------------------------------------
# The guide tables
#
# GuideBody.parse in GuideBubbles.swift turns the document's column-aligned
# blocks back into real rows. Two things went wrong there and neither was
# visible to any check: a blank line ended the table, so only the first of
# Rollbots' four cyberware abilities rendered inside the box; and a wrapped
# cell was appended whole to the last column, gluing each ability's effect
# and drawback into one sentence.
#
# This mirrors the parser and asserts the shape of what it produces. Run
# against the old rule (a blank line closes the table) the Rollbots table
# comes back with one row of four, which is what shipped.
# ---------------------------------------------------------------------------

COLUMN_SLACK = 2


def _cells(text):
    """Columns are separated by two or more spaces."""
    out, current, spaces = [], "", 0
    for character in text:
        if character == " ":
            spaces += 1
            continue
        if spaces >= 2 and current:
            out.append(current.strip())
            current = ""
        elif spaces > 0 and current:
            current += " "
        spaces = 0
        current += character
    if current:
        out.append(current.strip())
    return out


def _word_starts(text):
    return [i for i, c in enumerate(text)
            if c != " " and (i == 0 or text[i - 1] == " ")]


def _column_offsets(header, columns):
    out, search = [], 0
    for column in columns:
        found = header.find(column, search)
        if found < 0:
            return []
        out.append(found)
        search = found + len(column)
    return out


def _cells_at(text, offsets):
    """Re-split a row at the header's own column positions."""
    if len(offsets) < 2:
        return None
    starts = _word_starts(text)
    cuts = [0]
    for want in offsets[1:]:
        near = [p for p in starts if abs(p - want) <= COLUMN_SLACK]
        if not near:
            return None
        cuts.append(min(near, key=lambda p: abs(p - want)))
    cuts.append(len(text))
    out = []
    for index in range(len(offsets)):
        cell = text[cuts[index]:cuts[index + 1]].strip()
        if not cell:
            return None
        out.append(cell)
    return out


def _step_marker(text):
    digits = ""
    for character in text:
        if character.isdigit():
            digits += character
        elif character == "." and digits:
            return digits + "."
        else:
            return None
    return None


def guide_tables(body, blank_ends_table=False):
    """Every table in one rules body, as (columns, rows)."""
    found, pending, columns, offsets = [], [], [], []
    in_table, indent0, blank, header = False, 0, False, None

    def close():
        if in_table and columns:
            found.append((columns, pending))

    for raw in body.split("\n"):
        line = raw.replace("\u00a0", " ")
        trimmed = line.strip()
        if not trimmed:
            if in_table and not blank_ends_table:
                blank = True
            else:
                close()
                pending, columns, offsets, in_table, blank = [], [], [], False, False
            continue
        if set(trimmed) == {"-"} and len(trimmed) >= 5:
            if header is not None:
                columns = _cells(header)
                offsets = _column_offsets(header, columns)
                in_table, header = True, None
            continue
        indent = len(line) - len(line.lstrip(" "))
        if in_table and blank:
            width = len(_cells(trimmed))
            row_like = indent == indent0
            if trimmed.startswith("* ") or _step_marker(trimmed):
                row_like = False
            if width < 2 or width > len(columns):
                row_like = False
            if not row_like:
                close()
                pending, columns, offsets, in_table = [], [], [], False
            blank = False
        if in_table:
            if indent >= indent0 + 4 and pending:
                last = pending[-1]
                pieces = _cells(trimmed)
                reach = min(len(pieces), len(last))
                for offset, piece in enumerate(pieces[len(pieces) - reach:]):
                    slot = len(last) - reach + offset
                    last[slot] = last[slot] + " " + piece
            else:
                if indent0 == 0:
                    indent0 = indent
                row = _cells(trimmed)
                if len(row) < len(columns):
                    rescued = _cells_at(trimmed, offsets)
                    if rescued and len(rescued) == len(columns):
                        row = rescued
                pending.append(row)
            continue
        if trimmed.startswith("* ") or _step_marker(trimmed) or indent >= 4:
            header = None
            continue
        header = trimmed
    close()
    return found


def _guide_bodies():
    """Every rules body in every game, with the file it came from."""
    for filename in sorted(os.listdir(SWIFT)):
        if not filename.endswith(".swift"):
            continue
        text = source(filename)
        for match in re.finditer(r'body: "((?:[^"\\]|\\.)*)"', text):
            raw = match.group(1)
            raw = raw.replace("\\n", "\n").replace('\\"', '"')
            yield filename, raw.replace("\\\\", "\\")


# What the document holds: six three-column tables and Three Thousand's
# two-column one. A table that loses rows, or a row that loses a column,
# is a parser fault rather than a change to the text.
TABLE_SHAPE = {
    ("Generals.swift", "Category"): (3, 7),
    ("Rollbots.swift", "Ability"): (3, 4),
    ("RoyalUrScreen.swift", "Marked Points"): (3, 2),
    ("SuiteGame.swift", "Matchup Type"): (3, 5),
    ("SuiteGame.swift", "Differential"): (3, 8),
    ("SuiteGame.swift", "Die Type"): (3, 4),
    ("ThreeThousand.swift", "Combination"): (2, 9),
}


def check_tables():
    print("guide tables")
    seen = {}
    ragged = []
    for filename, body in _guide_bodies():
        for columns, rows in guide_tables(body):
            seen[(filename, columns[0])] = (len(columns), len(rows))
            for row in rows:
                if len(row) != len(columns):
                    ragged.append("%s/%s: %r" % (filename, columns[0], row))

    check("every table is found", seen == TABLE_SHAPE,
          "got %r" % (sorted(set(seen) ^ set(TABLE_SHAPE)) or
                      [(k, seen[k], TABLE_SHAPE[k]) for k in TABLE_SHAPE
                       if seen.get(k) != TABLE_SHAPE[k]],))
    check("no row loses a column", not ragged,
          "; ".join(ragged[:3]))

    # And the two fixes are in the parser the app actually runs, not only
    # in the mirror above.
    guides = source("GuideBubbles.swift")
    check("a blank line separates rows", "blankInTable" in guides,
          "GuideBody.parse still ends a table on a blank line")
    check("a wrap keeps its column", "cells(trimmed, at: offsets)" in guides,
          "GuideBody.parse no longer rescues a row from the header offsets")


# ---------------------------------------------------------------------------
# The byte budget
#
# The device panel reported 442 bytes across ten games and every row green,
# which was false comfort twice over. The probes used pass-and-play ids —
# `local.1`, seven characters — where Messages hands out 36-character
# `MSConversation` UUIDs, and each participant is spelled TWICE in an
# encoded match. And the Rolls probe sent `RollsGameState(startedBy:)`,
# whose `results` are EMPTY: the one game in the suite that scales with the
# size of the chat was being measured with none of the thing that scales.
#
# This models Rolls' encoding here, so the ceiling is a number in the repo
# rather than something to find out on a stranger's phone.
# ---------------------------------------------------------------------------

# The URL is built by URLComponents from one query item and nothing else,
# so this is the whole of it: "?s=" before the base64url.
URL_PREFIX = len("?s=")

# 12 d6, 1 d8, 1 d10, 1 d12 — the pool DiceGameRound(seed:) deals.
ROLLS_POOL = [6] * 12 + [8, 10, 12]

# The smallest group chat Rolls must still fit in. Measured at 14 seats
# today; this is the floor under that, so a change which makes the payload
# heavier is caught here rather than by someone whose message fails to send.
ROLLS_MIN_SEATS = 12


def _rolls_url_bytes(seats, budget_seed=0xD1CED1CE):
    """What one Rolls turn costs at `seats` players, in URL bytes.

    Mirrors the encoding exactly: `GameEnvelope`'s four one-letter keys,
    `MatchPayload`'s two, `TurnMatch`'s short keys with the nil `outcome`
    and nil `seatSequence` omitted (the synthesized encoder uses
    encodeIfPresent), and `RollsPlayerResult`'s three.
    """
    ids = ["00000000-0000-4000-8000-%012d" % (i + 1) for i in range(seats)]
    results = {}
    for seat, participant in enumerate(ids):
        values, score = [], 0
        for index, sides in enumerate(ROLLS_POOL):
            value = (index + seat) % sides + 1
            values.append(value)
            score += sides if value == 1 else sides - value
        results[participant] = {"o": list(reversed(range(len(ROLLS_POOL)))),
                                "s": score, "v": values}
    match = {"a": 0, "n": 0, "p": ids, "r": 1,
             "s": {participant: 0 for participant in ids}}
    envelope = {"d": {"d": {"b": ids[0], "c": False, "r": results},
                      "m": match},
                "g": "rolls", "s": budget_seed, "v": 1}
    raw = json.dumps(envelope, separators=(",", ":"),
                     sort_keys=True).encode()
    return URL_PREFIX + len(base64.urlsafe_b64encode(raw).rstrip(b"="))


def check_budget():
    print("byte budget")
    payload = strip_comments(source("GamePayload.swift"))
    turn = strip_comments(source("TurnMatch.swift"))

    try:
        budget = int(constant(source("GamePayload.swift"), "safeByteBudget"))
    except AssertionError:
        check("the budget is readable", False,
              "GameTransport.safeByteBudget is no longer a readable literal")
        return

    # 1. The probes measure a real message, not a pass-and-play one.
    check("probes use Messages-sized ids",
          "TurnMatch.messagesShaped(" in payload
          and not re.search(r'TurnMatch\.local(?:TwoPlayer)?\(', payload),
          "GameWireCheck still builds its matches with local ids, so every "
          "number it reports is short by 29 bytes per participant mention")
    check("an id is the length Messages gives",
          "static let messagesIDLength = 36" in turn
          and turn.count('"00000000-0000-4000-8000-"') == 1,
          "TurnMatch.messagesShaped is not producing 36-character ids")
    check("no probe state names a short id",
          "local." not in payload,
          "a probe state still carries a `local.N` literal, which is 29 "
          "bytes shorter than the id it stands for")

    # 2. ...and the game that scales is measured with its state full.
    check("the Rolls probe sends a finished round",
          "filledRolls(match:" in payload
          and not re.search(r'state: RollsGameState\(startedBy: "', payload),
          "the Rolls probe is back on an empty RollsGameState, which "
          "measures the envelope and none of the game")

    # 3. The heaviest two-player game is not spelling its keys out.
    generals = source("Generals.swift")
    check("a Generals claim has short keys",
          'case participant = "w"' in generals
          and 'case points = "p"' in generals,
          "GeneralsCard.Claim has no CodingKeys, so it spells "
          "\"participant\" and \"points\" out once per claim — twelve times "
          "in a full card, and Generals is already the heaviest of the "
          "two-player games")

    # 4. The ceiling, modelled.
    ceiling = 0
    for seats in range(1, 64):
        if _rolls_url_bytes(seats) <= budget:
            ceiling = seats
        else:
            break
    for seats in (2, 6, ROLLS_MIN_SEATS, ceiling, ceiling + 1):
        used = _rolls_url_bytes(seats)
        print("  %-34s %2d seats  %5d B  %5.1f%%%s"
              % ("Rolls against %d B" % budget, seats, used,
                 used / budget * 100, "  OVER" if used > budget else ""))
    check("Rolls fits a group chat", ceiling >= ROLLS_MIN_SEATS,
          "a Rolls turn stops fitting at %d seats, and %d is the floor"
          % (ceiling + 1, ROLLS_MIN_SEATS))
    print("  %-34s %d seats" % ("largest Rolls match that fits", ceiling))


def main():
    print("rules text against the constants:")

    # The guides are GAME_RULES.txt, verbatim, generated by
    # tools_guides_export.py — so these can no longer ask for particular
    # English. They ask the thing that actually matters instead: the NUMBER
    # the document states and the constant the game runs on have to agree.
    #
    # That is a better check than the wording one it replaces. "F.Y.D. rules
    # say four rolls" passed on the word "four" and would have gone on
    # passing if rollsPerTurn became five.

    def stated(text, pattern, label):
        """One number out of the guide text, by pattern."""
        match = re.search(pattern, rules_blob(text))
        if not match:
            check(label, False, "the guide no longer states it")
            return None
        return int(match.group(1).replace(",", ""))

    free = source("FreeRoll.swift")
    max_dice = constant(free, "maxDice")
    check("Free Roll ceiling interpolated",
          "\\(FreeRollPool.maxDice) dice" in free,
          "the number must come from the constant, not be typed again")
    check("Free Roll ceiling is 20", max_dice == 20, max_dice)
    said = stated(free, r"[Uu]p to (\d+) total dice", "Free Roll states a ceiling")
    if said is not None:
        check("Free Roll guide agrees with the ceiling", said == max_dice,
              "guide says %s, FreeRollPool.maxDice is %s" % (said, max_dice))
    check("Free Roll documents its subtotals toggle",
          "subtotals" in rules_blob(free))

    fyd = source("FreighterYachtDinghy.swift")
    rolls = constant(fyd, "rollsPerTurn")
    check("F.Y.D. rolls per turn is 4", rolls == 4, rolls)
    said = stated(fyd, r"up to (\d+) rolls", "F.Y.D. states its roll allowance")
    if said is not None:
        check("F.Y.D. guide agrees with the allowance", said == rolls,
              "guide says %s, rollsPerTurn is %s" % (said, rolls))
    for name in ("Freighter", "Yacht", "Dinghy"):
        check("F.Y.D. names the %s" % name, name in rules_blob(fyd))

    three = source("ThreeThousand.swift")
    target = constant(three, "target")
    check("Three Thousand target is 3000", target == 3000, target)
    said = stated(three, r"exceed ([\d,]+) points",
                  "Three Thousand states its target")
    if said is not None:
        check("Three Thousand guide agrees with the target", said == target,
              "guide says %s, target is %s" % (said, target))
    check("Three Thousand names the bust",
          "Bust" in rules_blob(three) and "arkle" not in rules_blob(three))

    hog = source("Hog.swift")
    hog_target = constant(hog, "target")
    check("Hog target is 75", hog_target == 75)
    said = stated(hog, r"bank (\d+) points", "Hog states its target")
    if said is not None:
        check("Hog guide agrees with the target", said == hog_target,
              "guide says %s, target is %s" % (said, hog_target))

    bones = source("Boneheads.swift")
    columns_n = constant(bones, "columns")
    per_column = constant(bones, "slotsPerColumn")
    check("Boneheads grid is 3 columns", columns_n == 3)
    said = stated(bones, r"\((\d+) slots total\)", "Boneheads states its slot count")
    if said is not None:
        check("Boneheads guide agrees with the grid",
              said == columns_n * per_column,
              "guide says %s, the grid is %s x %s"
              % (said, columns_n, per_column))

    bots = source("Rollbots.swift")
    starting = constant(bots, "startingIP")
    check("Rollbots IP is 16", starting == 16)
    said = stated(bots, r"(\d+) Integrity Points", "Rollbots states starting IP")
    if said is not None:
        check("Rollbots guide agrees with starting IP", said == starting,
              "guide says %s, startingIP is %s" % (said, starting))
    second = stated(bots, r"Player 2 starts with (\d+)",
                    "Rollbots states the second seat's IP")
    if second is not None:
        check("Rollbots guide agrees with the second seat",
              second == starting + 1,
              "guide says %s, the second seat gets %s"
              % (second, starting + 1))

    ur = source("RoyalUrScreen.swift")
    check("Royal UR describes marked points",
          "marked points" in rules_blob(ur),
          "rules must match the marked-tip dice, not the old numbers")
    check("Royal UR drops the old wording",
          "1 or a 2" not in rules_blob(ur))

    generals = source("Generals.swift")
    said = stated(generals, r"(\d+) total turns", "Generals states its turn count")
    if said is not None:
        check("Generals guide agrees with the categories", said == 12,
              "guide says %s turns, there are 12 categories" % said)

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
    check_tables()
    check_budget()
    check_seats()
    check_wire()
    check_retired_wording()

    if check.failed:
        print("rules text: FAILED")
        sys.exit(1)
    print("rules text: PASS")


if __name__ == "__main__":
    main()
