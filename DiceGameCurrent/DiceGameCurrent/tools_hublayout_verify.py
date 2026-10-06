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
import os
import re
import sys

from tools_swiftconst import source, constant, SWIFT

HERE = os.path.dirname(os.path.abspath(__file__))

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
    """Mirror of GameHubView's geometry, from its own constants.

    The label band is a FUNCTION of the tile now, not a constant: the name
    is sized to span the artwork, and a band fixed for one phone width
    starves the icon on a narrower one. That is the whole reason the icon
    share is asserted at eight widths rather than one.
    """
    count = c["columnCount"]
    available = width - c["gutter"] * 2 - c["columnGap"] * (count - 1)
    tile = min(c["maxTile"], max(120, available / count))
    font = min(tile * c["labelFontScale"], c["labelFontCap"])
    label = font * c["labelLines"]
    icon = max(40, tile - c["inset"] * 2 - label - c["gap"])
    return count, tile, icon, font


def label_formula(text):
    """The three numbers in HubLayout's label sizing."""
    scale = re.search(r'min\(tile \* (\d+\.\d+), (\d+)\)', text)
    assert scale, "labelFont is no longer min(tile * scale, cap)"
    lines = re.search(r'labelFont\(tile: tile\) \* (\d+\.\d+)', text)
    assert lines, "labelHeight is no longer labelFont * lines"
    return {"labelFontScale": float(scale.group(1)),
            "labelFontCap": float(scale.group(2)),
            "labelLines": float(lines.group(1))}


def main():
    text = source(HUB)
    c = {name: constant(text, name) for name in
         ("gutter", "columnGap", "columnCount", "maxTile", "inset", "gap")}
    # The label formula's three numbers, read out of the Swift so this
    # cannot drift from it: min(tile * scale, cap), times lines.
    c.update(label_formula(text))
    print("hub constants: " + ", ".join("%s %g" % (k, c[k]) for k in sorted(c)))

    failed = False
    for label, width in WIDTHS:
        count, tile, icon, font = layout(c, width)
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
        print("  %-20s %4dpt -> %d cols, tile %5.1f, icon %5.1f (%d%%), "
              "name %4.1fpt  %s"
              % (label, width, count, tile, icon, round(share * 100), font,
                 "  ".join(notes) or "ok"))

    # A phone must show more than one row without scrolling, or the grid is
    # a list with extra steps. Four tiles is two rows of two.
    _, tile, _, _ = layout(c, 393)
    if tile * 2 > 700:
        print("  iPhone 15 shows fewer than two rows of tiles")
        failed = True

    failed |= check_tile_painting(text)
    failed |= check_label_widths(c)

    if failed:
        print("hub layout: FAILED")
        sys.exit(1)
    print("hub layout: PASS (%d widths, icon never below %d%% of its tile)"
          % (len(WIDTHS), round(MIN_ICON_SHARE * 100)))


def check_label_widths(c):
    """Every tile name fits its tile, measured off the real font file.

    The hub label is two lines at `labelFont`, and nothing used to check
    that a name actually fits them. Freighter.Yacht.Dinghy did not: no
    spaces to wrap on, so SwiftUI ran it as one line and truncated, which
    is why that tile read "F.Y.D." instead of the game's name.

    So the names are measured rather than eyeballed — each line of each
    name, at each width, against the label band the layout leaves it.
    Pillow renders the same TTF the app bundles, so this is the real
    advance width and not an estimate.

    A name wraps only where it says it does: a line here is a line in the
    app, because `tileName` carries its own newline where it needs one.
    """
    try:
        from PIL import ImageFont
    except ImportError:
        print("  %-20s skipped (Pillow unavailable)" % "label widths")
        return False

    names = tile_names()
    if not names:
        print("  %-20s no tile names found" % "label widths")
        return True

    face = os.path.join(HERE, "Resources", "Poppins-SemiBold.ttf")
    if not os.path.exists(face):
        print("  %-20s skipped (%s missing)" % ("label widths", face))
        return False

    # What the label may use: the tile less its inset on both sides. The
    # scale floor on the label is the last resort, not the budget — a name
    # that only fits because it shrank is a name that reads smaller than
    # every other tile's.
    problems = []
    widest = ("", 0.0)
    max_lines = int(c["labelLines"])          # 2.4 of room is two lines
    for width in (w for _, w in WIDTHS):
        _, tile, _, font_pt = layout(c, width)
        available = tile - c["inset"] * 2
        font = ImageFont.truetype(face, 200)

        def drawn(text):
            return font.getlength(text) * font_pt / 200

        for name in names:
            lines = []
            overflow = None
            # A name breaks where it says it does, and SwiftUI breaks the
            # rest on spaces. Greedy wrapping is what SwiftUI does for a
            # label this short, so it is what gets modelled.
            for explicit in name.split("\\n"):
                current = ""
                for word in explicit.split(" "):
                    if drawn(word) > available:
                        overflow = word          # cannot be broken at all
                    candidate = word if not current else current + " " + word
                    if current and drawn(candidate) > available:
                        lines.append(current)
                        current = word
                    else:
                        current = candidate
                lines.append(current)

            if overflow is not None:
                problems.append(
                    "%r has no break and is %.0fpt at %gpt against %.0fpt "
                    "of tile (%dpt wide)"
                    % (overflow, drawn(overflow), font_pt, available, width))
            elif len(lines) > max_lines:
                problems.append(
                    "%r needs %d lines at %gpt, and the band holds %d "
                    "(%dpt wide)"
                    % (name, len(lines), font_pt, max_lines, width))

            for line in lines:
                ratio = drawn(line) / available
                if ratio > widest[1]:
                    widest = (line, ratio)

    for line in problems:
        print("  %-20s %s" % ("label widths", line))
    if problems:
        return True
    print("  %-20s ok (%d names, tightest is %r at %d%% of its tile)"
          % ("label widths", len(names), widest[0], round(widest[1] * 100)))
    return False


def tile_names():
    """Every name a tile shows, from the games that set one.

    A game without a `tileName` shows its `displayName` — see
    SuiteGame's default — so both are collected.
    """
    names = []
    for filename in sorted(os.listdir(SWIFT)):
        if not filename.endswith(".swift"):
            continue
        body = source(filename)
        overrides = set(re.findall(r'static let tileName = "([^"]*)"', body))
        names.extend(overrides)
        for match in re.finditer(r'static let displayName = "([^"]*)"', body):
            # A game that overrides tileName never shows its displayName on
            # a tile, so measuring it would fail the check for a string no
            # tile renders.
            if not overrides:
                names.append(match.group(1))
    return names


def check_tile_painting(text):
    """The tile is an outline you can still tap anywhere inside."""
    tile = text.split("private struct GameTile")[-1]
    problems = []

    if re.search(r'\.background\(\s*\n?\s*RoundedRectangle', tile):
        problems.append("the filled plate is back behind the icons")
    if re.search(r'\.stroke\(\.black\.opacity\([\d.]+\), lineWidth:', tile):
        problems.append("the tile's outline is back — nothing is drawn "
                        "around a tile any more")
    if re.search(r'\.shadow\(color:', tile):
        problems.append("the tile's drop shadow is back")
    # Load-bearing now rather than belt-and-braces: with no fill and no
    # outline, a Button has nothing else to hit-test between the icon and
    # the label, so a tap in the margin falls through to the scroll view.
    if not re.search(
            r'\.contentShape\(RoundedRectangle\(cornerRadius: '
            r'ControlShape\.cornerRadius\)\)', tile):
        problems.append("no contentShape — with no box drawn, this is the "
                        "ONLY thing making a tile tappable")

    for line in problems:
        print("  %-20s %s" % ("tile painting", line))
    if problems:
        return True
    print("  %-20s ok (nothing drawn, whole square tappable)"
          % "tile painting")
    return False


if __name__ == "__main__":
    main()
