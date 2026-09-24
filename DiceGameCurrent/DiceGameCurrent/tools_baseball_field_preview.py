"""Draws the Baseball Dice playfield as an SVG, so its composition can be
looked at before it is built in Swift.

Same trick as tools_royalur_preview.py: there is no renderer in this
container, and every visual bug this project has shipped was one a glance
would have caught. The geometry here is the geometry the Swift will use —
one set of normalised constants, ported rather than re-invented — so what
you see is what the floor texture will be.

    python3 tools_baseball_field_preview.py

Everything is expressed as a fraction of the square texture, origin top
left, because the playfield is square and the Swift draws into a square
CGContext.
"""
import os

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                   "baseball_field_preview.svg")

# Portrait, roughly 3:4, to suit a phone held upright — and it costs the
# layout engine nothing: PlayfieldLayout.compute derives depth from
# width / aspect, so a view taller than it is wide already produces a
# portrait playfield. Only the canvas changes.
WIDTH = 820
HEIGHT = 1100

# Every constant below is a fraction of its own axis, so the composition
# re-flows with the canvas instead of being re-placed by hand.

# --- palette, taken from the reference art -------------------------------
GRASS = "#7BA07E"
DIRT = "#C9B18A"
LINE = "#FFFFFF"
BASE = "#F4F4F0"
PANEL = "#111111"
PANEL_TEXT = "#FFFFFF"
CELL = "#E9E9E9"
RIM = "#6B4E31"          # the small wooden border

# --- geometry, all fractions of the square -------------------------------
RIM_WIDTH = 0.028        # the wooden border, deliberately thin

# x is a fraction of WIDTH, y a fraction of HEIGHT.
HOME = (0.500, 0.800)
FIRST = (0.760, 0.665)
SECOND = (0.500, 0.530)
THIRD = (0.240, 0.665)

MOUND = (0.500, 0.665)
MOUND_R = 0.078          # radii are fractions of WIDTH
SKIN_R = 0.330
HOME_CIRCLE_R = 0.125
PATH_W = 0.034
BASE_SIZE = 0.034

ON_DECK_R = 0.072
ON_DECK_Y = 0.930
ON_DECK_X = (0.150, 0.850)

# The scoreboard sits top left and the dice roll straight over it.
#
# Narrowed from 56% of the width to 42% and the total column dropped: it is
# flat surface the dice come to rest on, and the less of the board it covers
# the better the roll reads.
BOARD_X, BOARD_Y, BOARD_W = 0.050, 0.030, 0.420

# The panel's height is DERIVED from what it contains, not declared. The
# first version fixed it at 0.150 and positioned the grid rows downward from
# the top while positioning the outs row upward from the bottom — two origins
# growing toward each other, which met and overlapped by 9.5px. One origin
# makes that impossible.
BOARD_PAD = 0.014        # fractions of HEIGHT
HEAD_H = 0.030           # the word INNING plus the column numbers
GRID_GAP = 0.024         # head to first row
ROW_H = 0.034            # one of the two team rows
OUTS_GAP = 0.016         # last row to the outs row
OUTS_H = 0.040           # the outs row's own band, generous on purpose


def px(value):
    """A fraction of the WIDTH — used for x, radii and stroke widths."""
    return value * WIDTH


def py(value):
    """A fraction of the HEIGHT — used for y."""
    return value * HEIGHT


def poly(points, fill, extra=""):
    pts = " ".join("%.1f,%.1f" % (px(x), py(y)) for x, y in points)
    return '<polygon points="%s" fill="%s" %s/>' % (pts, fill, extra)


def diamond_at(centre, half, fill, extra=""):
    """A base or the infield, kept square on screen.

    `half` is a fraction of the WIDTH; the vertical half is scaled by the
    aspect so the shape stays a diamond rather than stretching with the
    canvas.
    """
    cx, cy = centre
    half_y = half * WIDTH / HEIGHT
    return poly([(cx, cy - half_y), (cx + half, cy),
                 (cx, cy + half_y), (cx - half, cy)], fill, extra)


def build(innings=9):
    """The whole field. `innings` decides how many columns the grid shows."""
    out = ['<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" '
           'viewBox="0 0 %d %d">' % (WIDTH, HEIGHT, WIDTH, HEIGHT)]

    out.append('<rect width="%d" height="%d" fill="%s"/>' % (WIDTH, HEIGHT, GRASS))

    # Infield skin: a dirt disc around the mound with the grass infield laid
    # back over it, which is how the real shape is made. Drawn as an ellipse
    # so a radius given in WIDTH fractions stays circular on a tall canvas.
    out.append('<ellipse cx="%.1f" cy="%.1f" rx="%.1f" ry="%.1f" fill="%s"/>'
               % (px(MOUND[0]), py(MOUND[1]), px(SKIN_R), px(SKIN_R), DIRT))
    out.append(diamond_at(MOUND, 0.190, GRASS))

    # Base paths, stroked along the diamond edges.
    path = " ".join("%.1f,%.1f" % (px(x), py(y))
                    for x, y in (HOME, FIRST, SECOND, THIRD))
    out.append('<polygon points="%s" fill="none" stroke="%s" stroke-width="%.1f"/>'
               % (path, DIRT, px(PATH_W)))

    # Foul lines run from home out past the corners.
    for corner in ((-0.05, 0.330), (1.05, 0.330)):
        out.append('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" '
                   'stroke="%s" stroke-width="%.1f"/>'
                   % (px(HOME[0]), py(HOME[1]), px(corner[0]), py(corner[1]),
                      LINE, px(0.008)))

    # Mound, its rubber, and the home-plate circle.
    out.append('<ellipse cx="%.1f" cy="%.1f" rx="%.1f" ry="%.1f" fill="%s"/>'
               % (px(MOUND[0]), py(MOUND[1]), px(MOUND_R), px(MOUND_R), DIRT))
    out.append('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="%s"/>'
               % (px(MOUND[0] - 0.030), py(MOUND[1]) - px(0.006),
                  px(0.060), px(0.012), LINE))
    out.append('<ellipse cx="%.1f" cy="%.1f" rx="%.1f" ry="%.1f" fill="%s"/>'
               % (px(HOME[0]), py(HOME[1]), px(HOME_CIRCLE_R), px(HOME_CIRCLE_R), DIRT))

    # Batter's boxes, either side of the plate.
    for side in (-1, 1):
        left = HOME[0] + (0.028 if side > 0 else -0.076)
        out.append('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" '
                   'fill="none" stroke="%s" stroke-width="%.1f"/>'
                   % (px(left), py(HOME[1]) - px(0.055),
                      px(0.048), px(0.100), LINE, px(0.006)))

    # Bases, then home plate's pentagon.
    for centre in (FIRST, SECOND, THIRD):
        out.append(diamond_at(centre, BASE_SIZE, BASE,
                              'stroke="#CFCFC8" stroke-width="2"'))
    plate = px(0.022)
    out.append('<polygon points="%.1f,%.1f %.1f,%.1f %.1f,%.1f %.1f,%.1f %.1f,%.1f" '
               'fill="%s"/>'
               % (px(HOME[0]) - plate, py(HOME[1]) - plate,
                  px(HOME[0]) + plate, py(HOME[1]) - plate,
                  px(HOME[0]) + plate, py(HOME[1]) + plate * 0.3,
                  px(HOME[0]),         py(HOME[1]) + plate * 1.3,
                  px(HOME[0]) - plate, py(HOME[1]) + plate * 0.3, BASE))

    # On-deck circles, which double as the two runner pools.
    for x, label in zip(ON_DECK_X, ("VISITORS", "HOME")):
        out.append('<ellipse cx="%.1f" cy="%.1f" rx="%.1f" ry="%.1f" fill="%s"/>'
                   % (px(x), py(ON_DECK_Y), px(ON_DECK_R), px(ON_DECK_R), DIRT))
        out.append('<text x="%.1f" y="%.1f" fill="%s" font-size="%.0f" '
                   'font-family="sans-serif" text-anchor="middle" '
                   'opacity="0.9">%s</text>'
                   % (px(x), py(ON_DECK_Y) + px(0.100), LINE, px(0.026), label))

    out.extend(scoreboard(innings))

    # The wooden rim last, so it frames everything. Thin on purpose.
    out.append('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" '
               'fill="none" stroke="%s" stroke-width="%.1f"/>'
               % (px(RIM_WIDTH) / 2, px(RIM_WIDTH) / 2,
                  WIDTH - px(RIM_WIDTH), HEIGHT - px(RIM_WIDTH),
                  RIM, px(RIM_WIDTH)))

    out.append("</svg>")
    return "\n".join(out)


def board_metrics():
    """Every vertical position on the panel, from one origin downward.

    Returned together so the drawing cannot invent a second origin: the
    outs row is placed relative to where the grid actually ended, and the
    panel's height is whatever contains both.
    """
    grid_top = BOARD_Y + HEAD_H + GRID_GAP
    rows_bottom = grid_top + 2 * ROW_H
    outs_top = rows_bottom + OUTS_GAP
    height = (outs_top + OUTS_H + BOARD_PAD) - BOARD_Y

    # The bug this replaces, asserted so it cannot come back: the outs row
    # must start below the last team row, and everything must sit inside
    # the panel.
    assert outs_top >= rows_bottom, (
        "outs row starts %.4f above the grid's last row" % (rows_bottom - outs_top))
    assert outs_top + OUTS_H <= BOARD_Y + height + 1e-9, "outs row overflows the panel"

    return grid_top, rows_bottom, outs_top, height


def scoreboard(innings):
    """Inning-by-inning runs and the outs row, top left, drawn into the field.

    Only as many columns as the match has. Nine empty boxes in a three-inning
    game reads as an unfinished game rather than a short one.
    """
    x, w = BOARD_X, BOARD_W
    y = BOARD_Y
    grid_top, rows_bottom, outs_top, h = board_metrics()

    out = ['<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" rx="%.1f" '
           'fill="%s" opacity="0.9"/>'
           % (px(x), py(y), px(w), py(h), px(0.014), PANEL)]

    label_w = 0.050
    grid_x = x + label_w
    cell_w = (w - label_w - 0.012) / innings

    out.append('<text x="%.1f" y="%.1f" fill="%s" font-size="%.0f" '
               'font-family="sans-serif" text-anchor="middle">INNING</text>'
               % (px(x + w / 2), py(y + 0.023), PANEL_TEXT, px(0.028)))

    for index in range(innings):
        out.append('<text x="%.1f" y="%.1f" fill="%s" font-size="%.0f" '
                   'font-family="sans-serif" text-anchor="middle">%d</text>'
                   % (px(grid_x + cell_w * (index + 0.5)),
                      py(grid_top) - px(0.008), PANEL_TEXT, px(0.024), index + 1))

    for row, name in enumerate(("V", "H")):
        top = grid_top + row * ROW_H
        out.append('<text x="%.1f" y="%.1f" fill="%s" font-size="%.0f" '
                   'font-family="sans-serif">%s</text>'
                   % (px(x + 0.014), py(top + ROW_H * 0.74), PANEL_TEXT,
                      px(0.028), name))
        for index in range(innings):
            out.append('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" '
                       'fill="%s" stroke="%s" stroke-width="1"/>'
                       % (px(grid_x + cell_w * index), py(top),
                          px(cell_w), py(ROW_H * 0.84), CELL, PANEL))

    # The outs row gets its own band. It is the one thing on this panel read
    # at a glance mid-turn, so the pips are large and well clear of the grid.
    centre = py(outs_top + OUTS_H / 2)
    out.append('<text x="%.1f" y="%.1f" fill="%s" font-size="%.0f" '
               'font-family="sans-serif" dominant-baseline="middle">OUTS</text>'
               % (px(x + 0.014), centre, PANEL_TEXT, px(0.030)))
    for index in range(3):
        out.append('<circle cx="%.1f" cy="%.1f" r="%.1f" fill="none" '
                   'stroke="%s" stroke-width="2.5"/>'
                   % (px(x + 0.175 + index * 0.072), centre, px(0.024),
                      PANEL_TEXT))
    return out


if __name__ == "__main__":
    import sys
    innings = int(sys.argv[1]) if len(sys.argv) > 1 else 9
    open(OUT, "w").write(build(innings))
    print("wrote %s (%dx%d, %d innings)"
          % (os.path.relpath(OUT), WIDTH, HEIGHT, innings))
