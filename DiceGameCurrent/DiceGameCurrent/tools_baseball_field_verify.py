"""Checks the Swift playfield against the preview that was approved.

The composition in `tools_baseball_field_preview.py` was looked at and
signed off; `BaseballField.swift` draws it for real. Those are two copies of
the same numbers, and two copies drift — that is not a guess, it is what
happened to the rules text, to the icon loader and to `GameHubView` earlier
in this project.

So this reads both and asserts they agree. Change a constant in one and this
fails until the other matches, which means the picture that was approved
stays the picture that draws.

It also re-checks the scoreboard's one-origin rule on the Swift side: the
panel's height must follow its contents, and the outs row must sit below the
grid's last row rather than being measured up from the panel's bottom edge.
That bug overlapped the two by 9.5px once already.
"""
import os
import re
import sys

from tools_swiftconst import source

HERE = os.path.dirname(os.path.abspath(__file__))
PREVIEW = os.path.join(HERE, "tools_baseball_field_preview.py")
SWIFT = "BaseballField.swift"

# preview name -> Swift name. Points are compared component-wise.
#
# Two groups, because there are two compositions. The MARK's constants are
# in units of its own width and live in `BaseballField.Mark`; the BOARD's
# are fractions of the 820x1100 canvas and live beside it. A third group —
# the painted pitch's own geometry — is gone from both files with the pitch
# itself.
MARK_SCALARS = {
    "MARK_HEIGHT": "height",
    "SKIN_R": "skinRadius",
    "WEDGE_APEX_Y": "wedgeApexY",
    "MOUND_R": "moundRadius",
    "HOME_CIRCLE_R": "homeRadius",
    "ON_DECK_R": "onDeckRadius",
    "ON_DECK_Y": "onDeckY",
    "BASE_SIZE": "baseHalf",
    "PLATE_HALF": "plateHalf",
    "BOX_GAP": "boxGap",
    "FOUL_W": "foulWidth",
    "BOX_LINE": "boxLine",
    "LABEL_SIZE": "labelSize",
    "CLAY_ALPHA": "clayAlpha",
}

BOARD_SCALARS = {
    "BOARD_X": "boardX",
    "BOARD_Y": "boardY",
    "BOARD_W": "boardW",
    "BOARD_PAD": "boardPad",
    "HEAD_H": "headHeight",
    "GRID_GAP": "gridGap",
    "ROW_H": "rowHeight",
    "OUTS_GAP": "outsGap",
    "OUTS_H": "outsHeight",
}

SCALARS = dict(MARK_SCALARS, **BOARD_SCALARS)

POINTS = {
    "HOME": "home",
    "FIRST": "first",
    "SECOND": "second",
    "THIRD": "third",
    "MOUND": "mound",
}


def preview_values():
    """Load the preview as a module and read its constants."""
    import importlib.util
    spec = importlib.util.spec_from_file_location("field_preview", PREVIEW)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def swift_scalar(text, name):
    """`static let name: CGFloat = 0.123`."""
    match = re.search(
        r'static let %s\s*:\s*CGFloat\s*=\s*(-?\d+(?:\.\d+)?)' % re.escape(name),
        text)
    assert match, "no CGFloat named %s in %s" % (name, SWIFT)
    return float(match.group(1))


def swift_point(text, name):
    """`static let name = CGPoint(x: 0.5, y: 0.8)`."""
    match = re.search(
        r'static let %s\s*=\s*CGPoint\(x:\s*(-?\d+(?:\.\d+)?),\s*'
        r'y:\s*(-?\d+(?:\.\d+)?)\)' % re.escape(name), text)
    assert match, "no CGPoint named %s in %s" % (name, SWIFT)
    return float(match.group(1)), float(match.group(2))


def swift_on_deck_x(text):
    match = re.search(r'static let onDeckX:\s*\[CGFloat\]\s*=\s*\[([^\]]*)\]', text)
    assert match, "no onDeckX in %s" % SWIFT
    return [float(part) for part in match.group(1).split(",")]


def main():
    preview = preview_values()
    text = source(SWIFT)
    failed = []

    for py_name, swift_name in sorted(SCALARS.items()):
        want = float(getattr(preview, py_name))
        got = swift_scalar(text, swift_name)
        if abs(want - got) > 1e-9:
            failed.append("%s: preview %.4f, Swift %s %.4f"
                          % (py_name, want, swift_name, got))

    for py_name, swift_name in sorted(POINTS.items()):
        want = tuple(float(v) for v in getattr(preview, py_name))
        got = swift_point(text, swift_name)
        if abs(want[0] - got[0]) > 1e-9 or abs(want[1] - got[1]) > 1e-9:
            failed.append("%s: preview %s, Swift %s %s" % (py_name, want, swift_name, got))

    want_x = [float(v) for v in preview.ON_DECK_X]
    got_x = swift_on_deck_x(text)
    if len(want_x) != len(got_x) or any(abs(a - b) > 1e-9 for a, b in zip(want_x, got_x)):
        failed.append("ON_DECK_X: preview %s, Swift %s" % (want_x, got_x))

    for line in failed:
        print("  %-30s FAILED  %s" % ("field constants", line))
    if failed:
        print("baseball field: FAILED (%d constant(s) disagree)" % len(failed))
        sys.exit(1)

    checked = len(SCALARS) + len(POINTS) + 1
    print("  %-30s ok (%d checked against the preview)" % ("field constants", checked))

    # The scoreboard's one-origin rule, on the Swift side. The panel's height
    # must contain what it draws, and the outs row must be below the grid.
    grid_top = swift_scalar(text, "boardY") + swift_scalar(text, "headHeight") \
        + swift_scalar(text, "gridGap")
    rows_bottom = grid_top + 2 * swift_scalar(text, "rowHeight")
    outs_top = rows_bottom + swift_scalar(text, "outsGap")
    height = (outs_top + swift_scalar(text, "outsHeight")
              + swift_scalar(text, "boardPad")) - swift_scalar(text, "boardY")

    assert outs_top >= rows_bottom, "the outs row is above the grid again"
    assert outs_top + swift_scalar(text, "outsHeight") \
        <= swift_scalar(text, "boardY") + height + 1e-9, "the outs row overflows"

    gap = outs_top - rows_bottom
    print("  %-30s ok (grid to outs %.4f, panel %.4f)"
          % ("scoreboard spacing", gap, height))
    print("baseball field: PASS")


if __name__ == "__main__":
    main()
