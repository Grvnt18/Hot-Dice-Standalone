"""Writes every game's in-app guide from GAME_RULES.txt.

Why generated
-------------
The guides were hand-written from the document once and the wording drifted
immediately: bullet lists became paragraphs, numbered steps became prose,
and the tables were summarised away. That is not a thing a careful rewrite
avoids — it is what rewriting IS. The only way the app can be relied on to
say what the document says is for nobody to type it twice.

So this reads GAME_RULES.txt and replaces each game's `rules` array with
its sections, verbatim, including the leading `*` and `1.` markers and the
table rows. `tools_rules_verify.py` then checks every line in the Swift
appears in the document, so an edit on either side is caught.

    python3 tools_guides_export.py [--check]

`--check` writes nothing and exits non-zero if any file is out of date,
which is what the verifier uses.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DOC = os.path.join(HERE, "GAME_RULES.txt")
SWIFT = os.path.join(HERE, "SwiftFiles")

# Document heading -> the file holding that game's SuiteGame conformance.
# Baseball and Rolls share SuiteGame.swift, so the enum is named too.
GAMES = [
    ("BASEBALL DICE",          "SuiteGame.swift",             "BaseballDiceGame"),
    ("ROLLS",                  "SuiteGame.swift",             "RollsGame"),
    ("JACKPOT",                "Jackpot.swift",               None),
    ("HOG",                    "Hog.swift",                   None),
    ("GENERALS",               "Generals.swift",              None),
    ("THREE THOUSAND",         "ThreeThousand.swift",         None),
    ("FREIGHTER.YACHT.DINGHY", "FreighterYachtDinghy.swift",  None),
    ("ROYAL UR",               "RoyalUrScreen.swift",         None),
    ("ROLLBOTS",               "Rollbots.swift",              None),
    ("BONEHEADS",              "Boneheads.swift",             None),
    ("FREE ROLL",              "FreeRoll.swift",              None),
]

# Sections that carry a diagram, by game and by the document's own heading.
# Kept here rather than hand-edited back in after every export, which is a
# step that gets forgotten exactly once.
FIGURES = {
    ("ROYAL UR", "MOVEMENT & BOARD MECHANICS"): ["royalUrPath", "rosette"],
    ("BONEHEADS", "COLUMN STACKING MULTIPLIERS"): ["boneheadsScoring"],
}

_RULE = re.compile(r'^-{5,}\s*$')
_GAME = re.compile(r'^\d+\.\s+(.+?)\s*$')
# A section heading is a whole line in capitals at the left margin — with
# one exception that cost a silent drop: two headings carry a parenthetical
# in ordinary case, `SCORING MATRIX (Batter Roll Minus Pitcher Roll)` and
# `CYBERWARE ABILITIES (One-Time Use Per Match)`. A capitals-only pattern
# skipped both, and the only symptom was Baseball and Rollbots quietly
# shipping one section fewer than the document has. So the capitals rule
# applies to the heading, and anything in brackets after it is free.
_HEADING = re.compile(r"^([A-Z][A-Z0-9 &'./-]*?)(\s*\([^)]*\))?\s*$")


def parse(text):
    """{game name: [(heading, [lines])]} straight out of the document."""
    games, current, section = {}, None, None
    for raw in text.split("\n"):
        line = raw.rstrip()
        if _RULE.match(line):
            continue
        game = _GAME.match(line)
        if game and game.group(1).upper() == game.group(1):
            current = game.group(1)
            games[current] = []
            section = None
            continue
        if current is None:
            continue
        heading = _HEADING.match(line)
        if heading and not line.startswith(" ") and line.strip():
            full = line.strip()
            section = (full, [])
            games[current].append(section)
            continue
        if section is not None:
            section[1].append(line)
    # Trim the blank lines each section collects before the next heading.
    for name, sections in games.items():
        for _, lines in sections:
            while lines and not lines[-1].strip():
                lines.pop()
    return games


def unclaimed(text):
    """Left-margin lines the parser treated as neither heading nor content.

    The parser dropping a heading is silent by nature: the section simply
    is not there, and a game ships one short. This names any line that
    starts at the left margin, is not blank, not a rule, not a game title,
    and was not taken as a heading — which is the shape of every way this
    can go wrong.
    """
    missed = []
    for raw in text.split("\n"):
        line = raw.rstrip()
        if not line or line.startswith(" ") or _RULE.match(line):
            continue
        if line.startswith("="):
            continue
        if _GAME.match(line) or _HEADING.match(line):
            continue
        missed.append(line)
    return missed


def title(heading):
    """`SCORING & INSTANT WIN CONDITIONS` -> `Scoring & Instant Win Conditions`.

    Only the heading is restyled, and only in case — the words are the
    document's. Section headings are rendered uppercase by the guide anyway,
    so this is about what the Swift reads like, not what ships.
    """
    small = {"a", "an", "and", "the", "to", "of", "per", "vs", "or"}
    out = []
    for index, word in enumerate(heading.split()):
        if word in ("&",) or not word.isalpha():
            out.append(word)
        elif index and word.lower() in small:
            out.append(word.lower())
        else:
            out.append(word.capitalize())
    return " ".join(out)


def swift_literal(lines):
    """The section's lines as one Swift string, escaped and joined by \\n."""
    out = []
    for line in lines:
        escaped = line.replace("\\", "\\\\").replace('"', '\\"')
        out.append(escaped)
    return "\\n".join(out)


def block(sections, game):
    parts = []
    for heading, lines in sections:
        if not lines:
            continue
        figures = FIGURES.get((game, heading.upper()))
        extra = (',\n            figures: [%s]'
                 % ", ".join(".%s" % f for f in figures)) if figures else ""
        parts.append(
            '        GameRuleSection(\n'
            '            title: "%s",\n'
            '            body: "%s"%s\n'
            '        )' % (title(heading), swift_literal(lines), extra))
    return "static let rules: [GameRuleSection] = [\n" + ",\n".join(parts) + "\n    ]\n"


def rewrite(source, sections, enum_name, game):
    key = "static let rules: [GameRuleSection] = ["
    search_from = 0
    if enum_name:
        marker = "enum %s: SuiteGame {" % enum_name
        if marker not in source:
            raise SystemExit("cannot find %s" % marker)
        search_from = source.index(marker)
    start = source.index(key, search_from)
    end = source.index("\n    ]\n", start) + len("\n    ]\n")
    return source[:start] + block(sections, game) + source[end:]


def main():
    check = "--check" in sys.argv
    with open(DOC, encoding="utf-8") as handle:
        doc = handle.read()
    missed = unclaimed(doc)
    if missed:
        print("guides: FAILED — these left-margin lines were read as "
              "neither a heading nor content:")
        for line in missed:
            print("    %r" % line)
        sys.exit(1)
    games = parse(doc)

    headings = {(game, heading.upper())
                for game, sections in games.items()
                for heading, _ in sections}
    orphan = sorted(set(FIGURES) - headings)
    if orphan:
        print("guides: FAILED — a figure names a section the document does "
              "not have: %s" % ", ".join("%s / %s" % o for o in orphan))
        sys.exit(1)

    stale = []
    for name, filename, enum_name in GAMES:
        if name not in games:
            raise SystemExit("GAME_RULES.txt has no section for %s" % name)
        path = os.path.join(SWIFT, filename)
        with open(path, encoding="utf-8") as handle:
            source = handle.read()
        updated = rewrite(source, games[name], enum_name, name)
        if updated == source:
            continue
        if check:
            stale.append(filename + (" (%s)" % enum_name if enum_name else ""))
        else:
            with open(path, "w", encoding="utf-8") as handle:
                handle.write(updated)
            print("  wrote %-28s %d section(s)" % (name, len(games[name])))

    if check:
        if stale:
            print("guides: FAILED — out of date with GAME_RULES.txt: %s"
                  % ", ".join(stale))
            sys.exit(1)
        print("guides: PASS (all %d match GAME_RULES.txt)" % len(GAMES))
    else:
        print("guides: %d games written from GAME_RULES.txt" % len(GAMES))


if __name__ == "__main__":
    main()
