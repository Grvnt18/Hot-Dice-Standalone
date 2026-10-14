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


Note: the Swift fills the turf and the dirt with FACETED textures, the
same low-poly surface every other playfield uses; this preview draws them
flat. That is deliberate — what is being checked here is the COMPOSITION,
and flat fills show the layout more clearly than noise does. The constants
are what tools_baseball_field_verify.py compares, and they are unaffected.
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
# The mound, lifted 16% toward white off the clay — the Swift tints it
# the same way, through BaseballField.tinted(dirt, toward: .white).
MOUND_TONE = "#D3BF9E"

# The wooden rim around the playfield, deliberately thin.
RIM_WIDTH = 0.028

# The board's lettering.
#
# This was the app's display script, and it was the single worst legibility
# problem in the app: the whole scoreboard — inning numbers, run totals, the
# V/H rows, OUTS — set in a cursive at 2.4-3.0% of texture width. It is now
# Poppins SemiBold, matching BaseballField.attributes.
#
# The nine <text> elements below write FONT_TOKEN rather than a family, and
# it is substituted once in `svg()`. They used to inline the family as a
# literal and ignore this constant entirely, so editing it here did nothing
# — a preview that silently stopped tracking the app it previews.
#
# A token rather than a %s because these strings are positionally
# %-formatted; a placeholder would have to be threaded through nine separate
# argument tuples, and the token passes through untouched.
BOARD_FONT = "Poppins SemiBold, Poppins, sans-serif"
FONT_TOKEN = "@BOARD_FONT@"

# --- the field mark, in units of its own WIDTH ---------------------------
#
# Mirrors BaseballField.Mark. `y` is a fraction of the WIDTH as well, running
# from the top of the composition rather than the top of the canvas, so the
# shape is the shape whatever it is drawn on. MARK_HEIGHT is how tall the
# whole thing is in those same units.
#
# These replaced a set of fractions-of-their-own-axis constants belonging to
# the painted pitch, where x was a fraction of the width and y a fraction of
# the height. On any canvas but the one they were chosen on that put the
# bases 0.52 of the width apart and home and second 0.27 of it, which is a
# diamond half as tall as it is wide.
MARK_HEIGHT = 1.344

HOME = (0.500, 0.953)
FIRST = (0.846, 0.600)
SECOND = (0.500, 0.256)
THIRD = (0.154, 0.600)
MOUND = (0.500, 0.605)

SKIN_R = 0.419           # the clay disc around the mound
WEDGE_APEX_Y = 1.060     # where the edges parallel to the foul lines meet
MOUND_R = 0.116
HOME_CIRCLE_R = 0.195
ON_DECK_R = 0.126
ON_DECK_Y = 1.219
ON_DECK_X = (0.153, 0.847)

BASE_SIZE = 0.047        # a base's half-diagonal
PLATE_HALF = 0.033
RUBBER = (0.074, 0.019)  # the pitcher's rubber
BOX = (0.102, 0.153)     # a batter's box
BOX_GAP = 0.028
FOUL_W = 0.009
BOX_LINE = 0.007
LABEL_SIZE = 0.052
CLAY_ALPHA = 0.80

# One composition unit in pixels, and where its top-left corner lands. The
# Swift fits the same way: one scale for both axes, centred, so a circle is
# a circle on any canvas.
MARK_SCALE = min(WIDTH, HEIGHT / MARK_HEIGHT)
MARK_X = (WIDTH - MARK_SCALE) / 2
MARK_Y = (HEIGHT - MARK_SCALE * MARK_HEIGHT) / 2
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


def u(value):
    """A length in composition units, in pixels."""
    return value * MARK_SCALE


def mark(point):
    """A point in the mark's composition, in pixels."""
    return MARK_X + point[0] * MARK_SCALE, MARK_Y + point[1] * MARK_SCALE


def poly(points, fill, extra=""):
    pts = " ".join("%.1f,%.1f" % (px(x), py(y)) for x, y in points)
    return '<polygon points="%s" fill="%s" %s/>' % (pts, fill, extra)


def mark_diamond(centre, half, fill, extra=""):
    """A base: a square stood on its corner, in mark space.

    One scale on both axes, so it is a square turned 45 degrees rather than
    something that stretches with the canvas.
    """
    cx, cy = mark(centre)
    h = u(half)
    pts = " ".join("%.1f,%.1f" % p for p in
                   ((cx, cy - h), (cx + h, cy), (cx, cy + h), (cx - h, cy)))
    return '<polygon points="%s" fill="%s" %s/>' % (pts, fill, extra)


def build(innings=9, overlay=None):
    """The whole field. `innings` decides how many columns the grid shows."""
    out = ['<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" '
           'viewBox="0 0 %d %d">' % (WIDTH, HEIGHT, WIDTH, HEIGHT)]

    # The floor itself. In the app this is the player's own table colour
    # with the suite's moving field on it; flat green here, because what is
    # being looked at is the composition laid ON it.
    out.append('<rect width="%d" height="%d" fill="%s"/>' % (WIDTH, HEIGHT, GRASS))

    # All the clay at one opacity, as one group: the skin, the plate circle
    # and the two on-deck circles overlap, and four translucent fills
    # stacked would darken every overlap into a visible seam. The Swift
    # does this with a transparency layer.
    out.append('<g opacity="%.2f">' % CLAY_ALPHA)

    # The skin: a disc around the mound, cut off down each side by a line
    # parallel to the foul line. That silhouette is what a field diagram
    # actually has — a plain disc reads as a running track.
    apex_x, apex_y = mark((0.5, WEDGE_APEX_Y))
    reach = u(2)
    out.append('<clipPath id="wedge"><polygon points="%.1f,%.1f %.1f,%.1f '
               '%.1f,%.1f %.1f,%.1f %.1f,%.1f"/></clipPath>'
               % (apex_x, apex_y,
                  apex_x - reach, apex_y - reach,
                  apex_x - reach, MARK_Y - reach,
                  apex_x + reach, MARK_Y - reach,
                  apex_x + reach, apex_y - reach))
    mx, my = mark(MOUND)
    out.append('<circle cx="%.1f" cy="%.1f" r="%.1f" fill="%s" '
               'clip-path="url(#wedge)"/>' % (mx, my, u(SKIN_R), DIRT))

    hx, hy = mark(HOME)
    out.append('<circle cx="%.1f" cy="%.1f" r="%.1f" fill="%s"/>'
               % (hx, hy, u(HOME_CIRCLE_R), DIRT))
    for x in ON_DECK_X:
        ox, oy = mark((x, ON_DECK_Y))
        out.append('<circle cx="%.1f" cy="%.1f" r="%.1f" fill="%s"/>'
                   % (ox, oy, u(ON_DECK_R), DIRT))

    # The mound, a shade up from the skin it sits in — the one place the
    # field needs a tone of its own to read at all.
    out.append('<circle cx="%.1f" cy="%.1f" r="%.1f" fill="%s"/>'
               % (mx, my, u(MOUND_R), MOUND_TONE))
    out.append('</g>')

    # Foul lines, running off the corners of the canvas rather than
    # stopping at the skin, which is what makes the shape read as a field.
    for side in (-1, 1):
        out.append('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" '
                   'stroke="%s" stroke-width="%.1f" opacity="0.92"/>'
                   % (hx, hy, hx + side * u(1.4), hy - u(1.4), LINE, u(FOUL_W)))

    # Batter's boxes, outlined either side of the plate.
    for side in (-1, 1):
        near = -BOX_GAP - BOX[0] if side < 0 else BOX_GAP
        out.append('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" '
                   'fill="none" stroke="%s" stroke-width="%.1f" opacity="0.92"/>'
                   % (hx + u(near), hy - u(BOX[1] * 0.55),
                      u(BOX[0]), u(BOX[1]), LINE, u(BOX_LINE)))

    # The pitcher's rubber.
    out.append('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="%s"/>'
               % (mx - u(RUBBER[0] / 2), my - u(RUBBER[1] / 2),
                  u(RUBBER[0]), u(RUBBER[1]), BASE))

    # The three bases, then home plate, which has its own shape.
    for centre in (FIRST, SECOND, THIRD):
        out.append(mark_diamond(centre, BASE_SIZE, BASE))
    h = u(PLATE_HALF)
    out.append('<polygon points="%.1f,%.1f %.1f,%.1f %.1f,%.1f %.1f,%.1f '
               '%.1f,%.1f" fill="%s"/>'
               % (hx - h, hy - h, hx + h, hy - h,
                  hx + h, hy + h * 0.3, hx, hy + h * 1.3,
                  hx - h, hy + h * 0.3, BASE))

    # The on-deck circles say whose they are. The only lettering on the
    # floor.
    for x, label in zip(ON_DECK_X, ("VISITORS", "HOME")):
        ox, oy = mark((x, ON_DECK_Y))
        out.append('<text x="%.1f" y="%.1f" fill="%s" font-size="%.0f" '
                   'font-family="@BOARD_FONT@" text-anchor="middle" '
                   'dominant-baseline="middle" opacity="0.85">%s</text>'
                   % (ox, oy, LINE, u(LABEL_SIZE), label))

    out.extend(scoreboard(innings))
    if overlay:
        out.extend(cards(overlay))

    # The wooden rim last, so it frames everything. Thin on purpose.
    out.append('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" '
               'fill="none" stroke="%s" stroke-width="%.1f"/>'
               % (px(RIM_WIDTH) / 2, px(RIM_WIDTH) / 2,
                  WIDTH - px(RIM_WIDTH), HEIGHT - px(RIM_WIDTH),
                  RIM, px(RIM_WIDTH)))

    out.append("</svg>")
    return "\n".join(out).replace(FONT_TOKEN, BOARD_FONT)


# --- the selection overlay ------------------------------------------------
#
# Both choices — three pitching styles, three swings — are three cards over
# a scrim, with the board still legible behind them. That matters most for
# the swing: the batter is reading outs and runners while deciding.
SCRIM = "#0B1A10"
SCRIM_OPACITY = 0.62
CARD_H = 0.500           # fraction of HEIGHT — "roughly 50% of the board"
CARD_GAP = 0.020         # fraction of WIDTH, between cards
CARD_MARGIN = 0.035      # fraction of WIDTH, at the outer edges
CARD_FILL = "#F3EFE3"
CARD_EDGE = "#2E2A22"

STYLE_CARDS = [
    ("Power Pitcher", "Mostly fastballs", "Patient hitters sit on it"),
    ("Crafty", "Mostly changeups", "Contact hitters wait"),
    ("Breaking Ball", "Mostly sliders", "Power hitters guess it"),
]
SWING_CARDS = [
    ("Patient Swing", "d8", "Sits on the Fastball"),
    ("Contact Swing", "d10", "Sits on the Changeup"),
    ("Power Swing", "d12", "Sits on the Slider"),
]


def cards(which):
    """Three cards over a scrim, centred vertically on the board."""
    entries = STYLE_CARDS if which == "styles" else SWING_CARDS
    out = ['<rect width="%d" height="%d" fill="%s" opacity="%.2f"/>'
           % (WIDTH, HEIGHT, SCRIM, SCRIM_OPACITY)]

    usable = 1.0 - CARD_MARGIN * 2 - CARD_GAP * 2
    card_w = usable / 3
    top = (1.0 - CARD_H) / 2

    title = "Pick your pitching style" if which == "styles" else "Pick your swing"
    out.append('<text x="%.1f" y="%.1f" fill="#FFFFFF" font-size="%.0f" '
               'font-family="@BOARD_FONT@" text-anchor="middle">%s</text>'
               % (px(0.5), py(top) - px(0.045), px(0.055), title))

    for index, (name, line, note) in enumerate(entries):
        x = CARD_MARGIN + index * (card_w + CARD_GAP)
        out.append('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" rx="%.1f" '
                   'fill="%s" stroke="%s" stroke-width="2"/>'
                   % (px(x), py(top), px(card_w), py(CARD_H), px(0.022),
                      CARD_FILL, CARD_EDGE))
        centre_x = px(x + card_w / 2)
        out.append('<text x="%.1f" y="%.1f" fill="%s" font-size="%.0f" '
                   'font-family="@BOARD_FONT@" text-anchor="middle">%s</text>'
                   % (centre_x, py(top) + px(0.075), CARD_EDGE, px(0.042), name))
        out.append('<text x="%.1f" y="%.1f" fill="%s" font-size="%.0f" '
                   'font-family="@BOARD_FONT@" text-anchor="middle" '
                   'opacity="0.8">%s</text>'
                   % (centre_x, py(top) + px(0.135), CARD_EDGE, px(0.034), line))
        out.append('<text x="%.1f" y="%.1f" fill="%s" font-size="%.0f" '
                   'font-family="@BOARD_FONT@" text-anchor="middle" '
                   'opacity="0.65">%s</text>'
                   % (centre_x, py(top + CARD_H) - px(0.040), CARD_EDGE,
                      px(0.026), note))

    # The cards must fit the width, with the gutters they were given.
    assert CARD_MARGIN * 2 + card_w * 3 + CARD_GAP * 2 <= 1.0 + 1e-9
    return out


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
               'font-family="@BOARD_FONT@" text-anchor="middle">INNING</text>'
               % (px(x + w / 2), py(y + 0.023), PANEL_TEXT, px(0.028)))

    for index in range(innings):
        out.append('<text x="%.1f" y="%.1f" fill="%s" font-size="%.0f" '
                   'font-family="@BOARD_FONT@" text-anchor="middle">%d</text>'
                   % (px(grid_x + cell_w * (index + 0.5)),
                      py(grid_top) - px(0.008), PANEL_TEXT, px(0.024), index + 1))

    for row, name in enumerate(("V", "H")):
        top = grid_top + row * ROW_H
        out.append('<text x="%.1f" y="%.1f" fill="%s" font-size="%.0f" '
                   'font-family="@BOARD_FONT@">%s</text>'
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
               'font-family="@BOARD_FONT@" dominant-baseline="middle">OUTS</text>'
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
    overlay = sys.argv[2] if len(sys.argv) > 2 else None
    open(OUT, "w").write(build(innings, overlay))
    print("wrote %s (%dx%d, %d innings%s)"
          % (os.path.relpath(OUT), WIDTH, HEIGHT, innings,
             ", %s overlay" % overlay if overlay else ""))
