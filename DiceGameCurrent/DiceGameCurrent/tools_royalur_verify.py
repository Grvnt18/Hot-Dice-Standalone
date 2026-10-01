"""Port of the shipped Royal UR rules, re-run against the analysis the
rule choices were made from.

Mirrors RoyalUrBoard and RoyalUrState in RoyalUrBoard.swift and
RoyalUrRules.swift: the same route and mirror, capture only on shared
squares, the exact-exit requirement, the rosette's extra roll, and a
Setback that goes back four or to the start if that square is taken.
There is no Swift toolchain in this container.

The choose-a-move policy is the simulation's own — the game never chooses
for you — and both seats use it, so the order is the only asymmetry left.

Expected: about 27 messages a match, 2.8 captures, 1.2 Setbacks, dead
turns well under one a game, and the first seat around 52%."""
import re
import random

import tools_swiftconst as swiftconst

ROWS = 3
BOTTOM_PATH = [
    (3, 4), (3, 3), (3, 2), (3, 1), (2, 1), (2, 2), (2, 3), (2, 4),
    (2, 5), (2, 6), (2, 7), (1, 7), (1, 8), (2, 8), (3, 8), (3, 7),
]
PATHS = {0: BOTTOM_PATH, 1: [(ROWS + 1 - r, c) for r, c in BOTTOM_PATH]}
ROSETTES = {(1, 1), (3, 1), (2, 4), (1, 7), (3, 7)}
PATH_LENGTH = 16
HOME = PATH_LENGTH + 1
PIECES = 3
TO_WIN = 2
SETBACK = 4
DICE = 5
EXACT_EXIT = True
ROSETTE_ROLLS_AGAIN = True

# The constants above are a PORT of the Swift, not a reading of it, so
# they can drift out of agreement with the shipped game without any test
# noticing. This states which `static let`s in RoyalUrRules.swift they stand on;
# swiftconst.expect fails by name if the Swift has moved.
SWIFT_CONSTANTS = {
    "diceCount": DICE,
    "piecesPerPlayer": PIECES,
    "piecesToWin": TO_WIN,
    "setbackDistance": SETBACK,
}


def square(seat, index):
    return PATHS[seat][index - 1] if 1 <= index <= PATH_LENGTH else None


def is_shared(sq):
    return sq[0] == 2 or sq[1] >= 7


class State:
    def __init__(self):
        self.pos = [[0] * PIECES, [0] * PIECES]

    def on_board(self, seat):
        return [p for p, i in enumerate(self.pos[seat]) if 1 <= i <= PATH_LENGTH]

    def piece_on(self, seat, sq):
        for p, i in enumerate(self.pos[seat]):
            if square(seat, i) == sq:
                return p
        return None

    def occupied_by_self(self, seat, sq, ignoring):
        return any(square(seat, i) == sq
                   for p, i in enumerate(self.pos[seat]) if p != ignoring)

    def legal_moves(self, seat, steps):
        if steps <= 0:
            return {}
        moves = {}
        for p, frm in enumerate(self.pos[seat]):
            if frm == HOME:
                continue
            dest = frm + steps
            if dest > HOME:
                if EXACT_EXIT:
                    continue
                dest = HOME
            if dest < HOME and self.occupied_by_self(seat, square(seat, dest), p):
                continue
            moves[p] = dest
        return moves

    def capture(self, seat, dest):
        if dest >= HOME:
            return None
        sq = square(seat, dest)
        if not is_shared(sq):
            return None
        return self.piece_on(1 - seat, sq)

    def apply(self, seat, piece, dest):
        taken = self.capture(seat, dest)
        if taken is not None:
            self.pos[1 - seat][taken] = 0
        self.pos[seat][piece] = dest
        sq = square(seat, dest)
        return {
            "captured": taken is not None,
            "home": dest == HOME,
            "rosette": sq in ROSETTES if sq else False,
        }

    def setback_destination(self, seat, piece):
        target = self.pos[seat][piece] - SETBACK
        if target < 1:
            return 0
        sq = square(seat, target)
        if self.occupied_by_self(seat, sq, piece) or self.piece_on(1 - seat, sq) is not None:
            return 0
        return target

    def home_count(self, seat):
        return sum(1 for i in self.pos[seat] if i == HOME)


def choose(state, seat, moves):
    """Home first, then a capture, then a rosette, then whatever is furthest."""
    other = 1 - seat

    def key(item):
        piece, dest = item
        home = 1 if dest == HOME else 0
        sq = square(seat, dest)
        cap = 1 if sq and is_shared(sq) and state.piece_on(other, sq) is not None else 0
        ros = 1 if sq in ROSETTES else 0
        return (home, cap, ros, dest)

    return max(moves.items(), key=key)


def game(rng):
    state = State()
    messages = captures = setbacks = dead = 0
    seat = 0
    while messages < 400:
        messages += 1
        rolling = True
        while rolling:
            rolling = False
            steps = sum(1 for _ in range(DICE) if rng.random() < 0.5)
            moves = state.legal_moves(seat, steps)
            if not moves:
                candidates = state.on_board(seat)
                if candidates:
                    # The simulation gives up the least advanced piece.
                    piece = min(candidates, key=lambda p: state.pos[seat][p])
                    state.pos[seat][piece] = state.setback_destination(seat, piece)
                    setbacks += 1
                else:
                    dead += 1
                break
            piece, dest = choose(state, seat, moves)
            outcome = state.apply(seat, piece, dest)
            captures += 1 if outcome["captured"] else 0
            if state.home_count(seat) >= TO_WIN:
                return messages, captures, setbacks, dead, seat
            if outcome["rosette"] and ROSETTE_ROLLS_AGAIN:
                rolling = True
        seat = 1 - seat
    return messages, captures, setbacks, dead, -1


def check_board():
    assert len({(r, c) for r in (1, 2, 3) for c in range(1, 9)
                if not (c in (5, 6) and r != 2)}) == 20
    for seat in (0, 1):
        path = PATHS[seat]
        assert len(set(path)) == 16
        assert [i + 1 for i, s in enumerate(path) if s in ROSETTES] == [4, 8, 12, 16]
    a, b = PATHS[0], PATHS[1]
    assert a[11] == b[15] and a[15] == b[11] and a[13] == b[13]
    shared = [i + 1 for i in range(16) if a[i] in b]
    assert shared == list(range(5, 17)), shared
    # Only the first four squares of a route are a player's own.
    assert all(not is_shared(a[i]) for i in range(4))
    assert all(is_shared(a[i]) for i in range(4, 16))
    print("board: PASS (20 squares, rosettes on 4/8/12/16, 12 contested)")


def check_layout():
    """The diamond band and the squares' margin must be ONE number.

    Two bugs came out of them being two. The band was `margin * 1.35` while
    the squares were inset by `margin`, so the board overlapped its own
    border by the difference — drawFrame paints first and the squares paint
    over it. And the band was drawn against the whole VIEW while the squares
    are laid out from a centred board rect, so any frame wider than the
    board's ratio left bare timber between the band and the first square.

    Both are gone by construction rather than by tuning once margin IS the
    band, and the layout constants follow from it:

        width  = 8 tiles + 7 gaps + 2 margins
        height = 3 tiles + 2 gaps + 2 margins

    Asserted from the Swift so the four numbers cannot drift apart, which is
    exactly how they came apart in the first place.
    """
    # Comments stripped first. The comment in drawFrame that EXPLAINS the
    # clipBoundingRect bug naturally names it, so an unstripped scan fails on
    # the very documentation that prevents the bug coming back — the same trap
    # the shader-dialect check in tools_dice_verify.py already fell into.
    raw = swiftconst.source("RoyalUrBoardView.swift")
    text = "\n".join(line.split("//")[0] for line in raw.split("\n"))

    def constant(name):
        m = re.search(r'self\.%s = tile \* ([\d.]+)' % name, text)
        assert m, "RoyalUrBoardView no longer sets %s from tile" % name
        return float(m.group(1))

    gap, margin = constant("gap"), constant("margin")

    band = re.search(r'let band = ([^\n]+)', text)
    assert band, "drawFrame no longer declares a band width"
    assert band.group(1).strip() == "layout.margin", (
        "the diamond band is %s, not layout.margin — if it is wider the "
        "board overlaps its own border, and if narrower a gap opens between "
        "them" % band.group(1).strip())

    assert "context.clipBoundingRect" not in text, (
        "drawFrame measures the VIEW again instead of the board's own rect — "
        "that is what left bare timber down the horizontal edges")

    # The border is protected by a CLIP, not by arithmetic — and the
    # difference is the whole reason this assertion exists rather than another
    # measurement. Making band == margin put the squares flush, and they were;
    # what still crossed the border was drawGrout, which expands every square
    # by `gap` on all sides, plus each square's centred 2pt stroke bleeding a
    # further 1pt. The arithmetic check passed the whole time.
    #
    # So: everything after drawFrame must draw into a clipped context. That
    # holds however the grout's inset, the stroke's width or a tile's corner
    # changes, which an arithmetic rule never would.
    assert re.search(r'context\.clip\(to: Path\(CGRect\(origin: layout\.origin', text), (
        "the board content is no longer clipped inside the band — the grout "
        "expands past every square by `gap` and the tile stroke bleeds 1pt, "
        "so without the clip they cross the border even when band == margin")
    assert "drawFrame(in: outerContext" in text, (
        "drawFrame must paint into the UNCLIPPED context — it draws the "
        "border itself, so clipping it to the inside erases it")

    want_w = 8 + 7 * gap + 2 * margin
    want_h = 3 + 2 * gap + 2 * margin
    for axis, want in (("width", want_w), ("height", want_h)):
        hits = re.findall(r'tile \* ([\d.]+)', text)
        assert any(abs(float(h) - want) < 1e-9 for h in hits), (
            "no %s constant equals %g tiles (8/3 tiles + gaps + margins at "
            "gap %g, margin %g) — the board would not fit its own frame"
            % (axis, want, gap, margin))
    print("layout: PASS (band == margin == %g tile, board %g x %g tiles)"
          % (margin, want_w, want_h))


def check_trays():
    """Waiting and finished pieces live in the board's own four-cell notch.

    Mirrors RoyalUrBoard.waitingTray / .homeTray. The cells they claim must
    be exactly the ones the board omits — putting a tray on a playable
    square would let a piece be drawn where another piece can land."""
    on_board = {(r, c) for r in (1, 2, 3) for c in range(1, 9)
                if not (c in (5, 6) and r != 2)}
    all_cells = {(r, c) for r in (1, 2, 3) for c in range(1, 9)}
    notch = all_cells - on_board
    assert notch == {(1, 5), (1, 6), (3, 5), (3, 6)}, notch

    def waiting(seat): return (1 if seat == 1 else 3, 5)
    def home(seat):    return (1 if seat == 1 else 3, 6)

    trays = {waiting(0), home(0), waiting(1), home(1)}
    assert trays == notch, trays
    assert len(trays) == 4, "a tray is shared between seats"

    for seat in (0, 1):
        row = PATHS[seat][0][0]          # the row that seat's route starts on
        assert waiting(seat)[0] == row, seat
        assert home(seat)[0] == row, seat
        # Waiting sits beside the entry square, home beside the exit.
        assert waiting(seat)[1] < home(seat)[1]
    print("trays: PASS (the four cells the board omits, one pair per row)")


def check_rules():
    s = State()
    # Exact exit: a piece on 16 comes home on a 1 and cannot move on a 2.
    s.pos[0][0] = 16
    assert s.legal_moves(0, 1)[0] == HOME
    assert 0 not in s.legal_moves(0, 2)
    # You cannot land on your own piece.
    s = State()
    s.pos[0][0], s.pos[0][1] = 5, 3
    assert 1 not in s.legal_moves(0, 2)
    # Capture only happens on a shared square.
    s = State()
    s.pos[0][0] = 3                      # seat 0, square (3,2): its own
    s.pos[1][0] = 3                      # seat 1, square (1,2): its own
    assert s.capture(0, 3) is None
    s = State()
    s.pos[1][0] = 6                      # (2,2), shared
    assert s.capture(0, 6) == 0
    # A Setback goes back four, or to the start when that square is taken.
    s = State()
    s.pos[0][0] = 9
    assert s.setback_destination(0, 0) == 5
    s.pos[0][1] = 5
    assert s.setback_destination(0, 0) == 0
    s = State()
    s.pos[0][0] = 3
    assert s.setback_destination(0, 0) == 0
    print("rules: PASS (exact exit, self-blocking, shared-only capture, Setback)")


def main():
    swiftconst.expect("Royal UR", "RoyalUrRules.swift", SWIFT_CONSTANTS)
    check_board()
    check_layout()
    check_trays()
    check_rules()
    rng = random.Random(20260922)
    n = 15_000
    results = [game(rng) for _ in range(n)]
    messages = sum(r[0] for r in results) / n
    captures = sum(r[1] for r in results) / n
    setbacks = sum(r[2] for r in results) / n
    dead = sum(r[3] for r in results) / n
    first = sum(1 for r in results if r[4] == 0) / n
    print("messages per match   %.1f" % messages)
    print("captures per match   %.1f" % captures)
    print("setbacks per match   %.1f" % setbacks)
    print("dead turns per match %.2f" % dead)
    print("first seat wins      %.1f%%" % (first * 100))
    assert 24 < messages < 30, messages
    assert captures > 2.0, captures
    assert dead < 0.5, dead
    print("Royal UR: PASS")


if __name__ == "__main__":
    main()
