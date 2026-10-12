"""Reads constants out of the shipped Swift, so a Python port cannot
silently drift from the code it claims to mirror.

Why this exists
---------------
The eight game verifiers are Python *ports* of the Swift rules — the right
call with no toolchain in this container, but it means a passing verifier
proves the Python matches the measurements, not that the Swift matches the
Python. Change `RollbotsRules.startingIP` to 14 and the verifier goes on
passing at 16, cheerfully and wrongly.

That is the same shape as two failures already found the hard way: Free
Roll's rules text drifting to "10 dice" after the ceiling moved to 20, and
tools_qualcheck.py scanning zero files while printing PASS. A check that
cannot fail is worse than no check, because it is believed.

So each verifier now states, in one block, which Swift constants it is
standing on. If the Swift moves and the port does not, the verifier says so
by name instead of quietly measuring the wrong game.

Paths are anchored to this file's own directory: running a tool from the
wrong folder must be an error, never a pass over nothing.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SWIFT = os.path.join(HERE, "SwiftFiles")
# The standalone has no second target. Kept as a path rather than deleted
# because `swift_names` still looks for it: this repository and the
# Messages one share every verifier, and a check that silently scans a
# different set of files in each would be worse than one that finds
# nothing here.
EXTENSION = os.path.join(HERE, "MessagesExtension")
RESOURCES = os.path.join(HERE, "Resources")

# The two folders holding Swift the platform floor applies to, in the order
# a listing should show them. MessagesExtension/ is a SEPARATE Xcode target
# — it is the one that cannot be built in Swift Playgrounds at all, which
# makes it the one place an iOS 17 spelling would sit unnoticed longest.
SWIFT_ROOTS = (SWIFT, EXTENSION)


def source(name):
    """The text of a Swift file.

    Takes a bare filename, resolved against SwiftFiles/, or a path relative
    to the project folder — which is how a Messages extension source is
    named, as `MessagesExtension/Foo.swift`. Tried in that order so every
    existing call site means exactly what it did before.
    """
    for path in (os.path.join(SWIFT, name), os.path.join(HERE, name)):
        if os.path.exists(path):
            return open(path).read()
    sys.exit("swiftconst: no such source %s" % os.path.join(SWIFT, name))


def swift_names():
    """Every Swift source in the project, as names `source` accepts.

    SwiftFiles/ entries come back bare and extension entries prefixed, so a
    caller testing membership against a bare filename still works and a
    failure message still names something findable.
    """
    names = sorted(f for f in os.listdir(SWIFT) if f.endswith(".swift"))
    if os.path.isdir(EXTENSION):
        names += [os.path.join("MessagesExtension", f)
                  for f in sorted(os.listdir(EXTENSION))
                  if f.endswith(".swift")]
    return names


# `static let name = 3`, `static let name: CGFloat = 16`, `let name = 3`.
# The optional type annotation matters: the layout constants are typed,
# because a bare 16 would infer Int where CGFloat is wanted.
_DECL = r'(?:static\s+)?(?:private\s+)?(?:static\s+)?let\s+%s\s*(?::\s*[A-Za-z<>, ]+?)?\s*=\s*'


def constant(text, name):
    """The number a `let <name> = <n>` holds.

    Accepts an optional type annotation and a decimal value, and resolves
    `let a = b + c` one level deep, since several constants here are written
    in terms of another rather than repeating a number (Rollbots' second-seat
    total, for one). Returns an int where the literal is one, so the game
    verifiers keep comparing ints to ints.
    """
    decl = _DECL % re.escape(name)
    m = re.search(decl + r'(\d+(?:\.\d+)?)\b', text)
    if m:
        value = float(m.group(1))
        return int(value) if value.is_integer() else value
    m = re.search(decl + r'([A-Za-z0-9_.]+)\s*\+\s*([A-Za-z0-9_.]+)', text)
    if m:
        return sum(_resolve(text, part) for part in (m.group(1), m.group(2)))
    raise AssertionError("no constant named %s" % name)


def _resolve(text, token):
    if token.isdigit():
        return int(token)
    return constant(text, token.split(".")[-1])


def expect(label, swift_file, wanted):
    """Assert a verifier's own constants against the shipped Swift.

    `wanted` maps a Swift `static let` name to the value this verifier has
    been measuring with. Prints one line per constant and exits non-zero on
    any mismatch, naming both sides — a silent disagreement here would make
    every figure below it meaningless.
    """
    text = source(swift_file)
    bad = []
    for name in sorted(wanted):
        actual = constant(text, name)
        if actual != wanted[name]:
            bad.append((name, wanted[name], actual))
    if bad:
        print("  %-34s FAILED" % (label + " constants"))
        for name, mine, actual in bad:
            print("      %s: this port uses %s, %s says %s"
                  % (name, mine, swift_file, actual))
        sys.exit("%s: the port no longer matches the shipped code" % label)
    print("  %-34s ok (%d checked against %s)"
          % (label + " constants", len(wanted), swift_file))
