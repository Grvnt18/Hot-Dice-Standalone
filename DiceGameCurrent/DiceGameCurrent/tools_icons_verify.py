"""Checks every icon the code asks for is actually in Resources/.

The loader builds a game's filename from its SuiteGame.id, and the
Rollbots marks are named in Swift as plain strings. Either can be wrong by
a character, and on device that failure is silent — GameIconView draws
nothing rather than a broken-image box, so a missing file looks like a
design choice. This catches it here instead."""
import os
import re
import sys

SWIFT = "SwiftFiles/"
RES = "Resources/"


def source(name):
    return open(SWIFT + name).read()


def main():
    failed = False
    print("icons referenced by the code:")

    # Every game's tile icon, by its id.
    ids = set(re.findall(r'static let id = "([a-z_0-9]+)"', "".join(
        source(f) for f in os.listdir(SWIFT) if f.endswith(".swift"))))
    ids.add(re.search(r'static let gameID = "([a-z_]+)"',
                      source("RollsPayload.swift")).group(1))
    for game_id in sorted(ids):
        name = "icon-%s.png" % game_id
        ok = os.path.exists(RES + name)
        print("  %-30s %s" % (name, "ok" if ok else "MISSING"))
        failed |= not ok

    # The Rollbots weapon and ability marks.
    marks = sorted(set(re.findall(r'return "(bot-[a-z]+)"', source("Rollbots.swift"))))
    for mark in marks:
        name = mark + ".png"
        ok = os.path.exists(RES + name)
        print("  %-30s %s" % (name, "ok" if ok else "MISSING"))
        failed |= not ok

    # Nothing shipped that nothing asks for.
    wanted = {"icon-%s.png" % i for i in ids} | {m + ".png" for m in marks}
    shipped = {f for f in os.listdir(RES) if f.startswith(("icon-", "bot-"))}
    for extra in sorted(shipped - wanted - {"icon-master.png"}):
        print("  %-30s shipped but unused" % extra)

    if failed:
        print("icons: FAILED")
        sys.exit(1)
    print("icons: PASS (%d games, %d marks)" % (len(ids), len(marks)))


if __name__ == "__main__":
    main()
