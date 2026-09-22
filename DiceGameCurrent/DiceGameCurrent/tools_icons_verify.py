"""Checks every icon the code asks for is actually in Resources/, and
that nothing unreferenced is shipped.

The second half earns its keep: Icon-Master.png arrived looking like a
blank template and was kept aside as one, when it was in fact a second
export of the Jackpot icon. A file nothing references is worth a line of
output rather than a silent 30KB.

The loader builds a game's filename from its SuiteGame.id, and the
Rollbots marks are named in Swift as plain strings. Either can be wrong by
a character, and on device that failure is silent — GameIconView draws
nothing rather than a broken-image box, so a missing file looks like a
design choice. This catches it here instead."""
import os
import re
import sys

# Anchored to this script's directory, not the caller's: these used to be
# relative, so the tool only worked from the project root.
SWIFT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "SwiftFiles") + os.sep
RES = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Resources") + os.sep

# Non-game icons, named here because nothing in the code derives them from
# an id. Keep this list short: every entry is a name the unused-file check
# can no longer catch.
APP_ICON = "icon-app.png"


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

    # The app's own mark, which belongs to no game and so cannot be
    # derived from an id. GameHubView draws it as GameIconView(id: "app").
    app_ok = os.path.exists(RES + APP_ICON)
    print("  %-30s %s" % (APP_ICON, "ok" if app_ok else "MISSING"))
    failed |= not app_ok

    # The Rollbots weapon and ability marks.
    marks = sorted(set(re.findall(r'return "(bot-[a-z]+)"', source("Rollbots.swift"))))
    for mark in marks:
        name = mark + ".png"
        ok = os.path.exists(RES + name)
        print("  %-30s %s" % (name, "ok" if ok else "MISSING"))
        failed |= not ok

    # Nothing shipped that nothing asks for.
    wanted = ({"icon-%s.png" % i for i in ids}
              | {m + ".png" for m in marks}
              | {APP_ICON})
    shipped = {f for f in os.listdir(RES) if f.startswith(("icon-", "bot-"))}
    for extra in sorted(shipped - wanted):
        print("  %-30s shipped but unused" % extra)

    if failed:
        print("icons: FAILED")
        sys.exit(1)
    print("icons: PASS (%d games, %d marks, app mark)" % (len(ids), len(marks)))


if __name__ == "__main__":
    main()
