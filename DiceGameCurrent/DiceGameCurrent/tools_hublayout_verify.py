"""Checks the hub grid arithmetic at real device widths.

Why this exists
---------------
The tiles were `.aspectRatio(1, contentMode: .fit)` wrapped around a
resizable image with `maxHeight: .infinity`. That image has no ideal height
to offer, so the square had nothing to size itself from but the name label,
and every tile collapsed to a postage stamp with an unreadable icon in it.
Nothing in the tree could see that: it is a layout outcome, not a shape or
a name, and there is no compiler here, let alone a renderer.

So the geometry is arithmetic now, stated in constants this script reads
back out of the Swift, and the assertions below are the part a screenshot
would otherwise have to tell us:

  * the icon is at least half the tile, or the artwork is decoration
  * the grid is two columns at every width — ten games, five rows, the
    same arrangement on a phone and an iPad
  * no tile exceeds the cap, so a wide screen does not turn the grid into
    a row and a half of enormous squares
  * no tile is so large that a phone shows fewer than four games at once

It also guards one thing that is not arithmetic at all: the tile has no
filled background any more, and a `Button` hit-tests the content it
actually draws. Without an explicit `contentShape` the tap target would
shrink to the artwork and the label, and a tap in a tile's blank margin
would fall through to the scroll view — a grid whose whole job is being
tapped, quietly getting harder to tap. That cannot be seen in a
screenshot, so it is asserted here instead.

Same spirit as tools_spawn_verify.py: prove the numbers, rather than
eyeball the screen and hope.
"""
import re
import sys

from tools_swiftconst import source, constant

HUB = "GameHubView.swift"

# (label, points) — the widths this app actually meets.
WIDTHS = [
    ("iPhone SE", 320),
    ("iPhone 13 mini", 375),
    ("iPhone 15", 393),
    ("iPhone 15 Pro Max", 430),
    ("iPad mini portrait", 744),
    ("iPad Air portrait", 820),
    ("iPad Air landscape", 1180),
    ("iPad Pro landscape", 1366),
]

# The smallest share of a tile the artwork may take. Below this the icon
# reads as a bullet point beside the name rather than as the tile's subject.
MIN_ICON_SHARE = 0.50


def layout(c, width):
    """Mirror of GameHubView's geometry, from its own constants."""
    count = c["columnCount"]
    available = width - c["gutter"] * 2 - c["columnGap"] * (count - 1)
    tile = min(c["maxTile"], max(120, available / count))
    icon = max(40, tile - c["inset"] * 2 - c["labelHeight"] - c["gap"])
    return count, tile, icon


def main():
    text = source(HUB)
    c = {name: constant(text, name) for name in
         ("gutter", "columnGap", "columnCount", "maxTile",
          "inset", "gap", "labelHeight")}
    print("hub constants: " + ", ".join("%s %g" % (k, c[k]) for k in sorted(c)))

    failed = False
    for label, width in WIDTHS:
        count, tile, icon = layout(c, width)
        share = icon / tile
        spans = count * tile + c["columnGap"] * (count - 1) + c["gutter"] * 2
        notes = []
        if share < MIN_ICON_SHARE:
            notes.append("ICON ONLY %d%% OF TILE" % round(share * 100))
        if spans > width + 0.5:
            notes.append("GRID OVERFLOWS BY %.0fpt" % (spans - width))
        if count != 2:
            notes.append("SHOULD BE 2 COLUMNS, GOT %d" % count)
        if tile > c["maxTile"] + 0.5:
            notes.append("TILE %.0f EXCEEDS THE %.0f CAP" % (tile, c["maxTile"]))
        # The grid is given this exact width so the stack around it centres
        # the columns; it must still fit between the gutters.
        grid = count * tile + c["columnGap"] * (count - 1)
        if grid > width - c["gutter"] * 2 + 0.5:
            notes.append("GRID %.0f WIDER THAN ITS GUTTERS" % grid)
        failed |= bool(notes)
        print("  %-20s %4dpt -> %d cols, tile %5.1f, icon %5.1f (%d%%)  %s"
              % (label, width, count, tile, icon, round(share * 100),
                 "  ".join(notes) or "ok"))

    # A phone must show more than one row without scrolling, or the grid is
    # a list with extra steps. Four tiles is two rows of two.
    _, tile, _ = layout(c, 393)
    if tile * 2 > 700:
        print("  iPhone 15 shows fewer than two rows of tiles")
        failed = True

    failed |= check_tile_painting(text)

    if failed:
        print("hub layout: FAILED")
        sys.exit(1)
    print("hub layout: PASS (%d widths, icon never below %d%% of its tile)"
          % (len(WIDTHS), round(MIN_ICON_SHARE * 100)))


def check_tile_painting(text):
    """The tile is an outline you can still tap anywhere inside."""
    tile = text.split("private struct GameTile")[-1]
    problems = []

    if re.search(r'\.background\(\s*\n?\s*RoundedRectangle', tile):
        problems.append("the filled plate is back behind the icons")
    if not re.search(
            r'\.contentShape\(RoundedRectangle\(cornerRadius: '
            r'ControlShape\.cornerRadius\)\)', tile):
        problems.append("no contentShape — taps in a tile's margin will miss")
    if not re.search(r'\.stroke\(\.black\.opacity\([\d.]+\), lineWidth:', tile):
        problems.append("the tile lost its outline, so nothing marks its edge")

    for line in problems:
        print("  %-20s %s" % ("tile painting", line))
    if problems:
        return True
    print("  %-20s ok (no fill, outline kept, whole square tappable)"
          % "tile painting")
    return False


if __name__ == "__main__":
    main()
