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
RESOURCES = os.path.join(HERE, "Resources")


def source(name):
    """The text of a Swift file, by bare filename."""
    path = os.path.join(SWIFT, name)
    if not os.path.exists(path):
        sys.exit("swiftconst: no such source %s" % path)
    return open(path).read()


def constant(text, name):
    """The integer a `static let <name> = <n>` holds.

    Also resolves `static let a = b + c` one level deep, since several
    constants here are written in terms of another rather than repeating a
    number (Rollbots' second-seat total, for one).
    """
    m = re.search(r'static let %s\s*=\s*(\d+)\b' % re.escape(name), text)
    if m:
        return int(m.group(1))
    m = re.search(r'static let %s\s*=\s*([A-Za-z0-9_.]+)\s*\+\s*([A-Za-z0-9_.]+)'
                  % re.escape(name), text)
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
