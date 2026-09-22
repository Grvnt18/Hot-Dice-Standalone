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
  * a phone gets two columns and an iPad more than two, which is what
    "scales to the screen" has to mean in both directions
  * no tile is so large that a phone shows fewer than four games at once

Same spirit as tools_spawn_verify.py: prove the numbers, rather than
eyeball the screen and hope.
"""
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
    usable = width - c["gutter"] * 2 + c["columnGap"]
    fits = int(usable / (c["targetTile"] + c["columnGap"]))
    count = min(max(fits, 2), 5)
    available = width - c["gutter"] * 2 - c["columnGap"] * (count - 1)
    tile = max(120, available / count)
    icon = max(40, tile - c["inset"] * 2 - c["labelHeight"] - c["gap"])
    return count, tile, icon


def main():
    text = source(HUB)
    c = {name: constant(text, name) for name in
         ("gutter", "columnGap", "targetTile", "inset", "gap", "labelHeight")}
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
        if width < 500 and count != 2:
            notes.append("PHONE SHOULD BE 2 COLUMNS, GOT %d" % count)
        if width >= 744 and count < 3:
            notes.append("TABLET SHOULD EXCEED 2 COLUMNS, GOT %d" % count)
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

    if failed:
        print("hub layout: FAILED")
        sys.exit(1)
    print("hub layout: PASS (%d widths, icon never below %d%% of its tile)"
          % (len(WIDTHS), round(MIN_ICON_SHARE * 100)))


if __name__ == "__main__":
    main()
