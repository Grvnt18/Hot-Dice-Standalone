import Foundation

/// Royal UR board: which squares exist, which are rosettes, and the
/// route each player walks.
///
/// Pure geometry — no pieces, no dice, no turn state. The board is the one
/// thing in this game that never changes, and everything else (capture,
/// blocking, the Setback) reduces to comparing squares, so it is worth
/// having on its own.
///
/// Rows run 1 at the top to 3 at the bottom; columns 1 to 8, left to right.
/// The shape is the traditional one: a 4x3 block, a two-square bridge along
/// the middle row, and a 2x3 block — twenty squares, with the four corners
/// of the bridge missing.
enum RoyalUrBoard {

    static let rows = 3
    static let columns = 8

    struct Square: Hashable {
        let row: Int
        let column: Int
    }

    /// Seat 0 walks the bottom row, seat 1 the top. Everything else about
    /// the two routes is identical — see `path(for:)`.
    static let bottomSeat = 0
    static let topSeat = 1

    /// Every square on the board.
    static let squares: [Square] = {
        var result: [Square] = []
        for row in 1...rows {
            for column in 1...columns {
                // The bridge is one square wide: the middle row crosses,
                // the outer rows do not.
                if (column == 5 || column == 6) && row != 2 { continue }
                result.append(Square(row: row, column: column))
            }
        }
        return result
    }()

    /// The five rosettes, exactly as the board is traditionally marked.
    ///
    /// They are not decoration: they land on path indices 4, 8, 12 and 16
    /// for *both* players, which is what "every fourth square" means here.
    static let rosettes: Set<Square> = [
        Square(row: 1, column: 1),
        Square(row: 3, column: 1),
        Square(row: 2, column: 4),
        Square(row: 1, column: 7),
        Square(row: 3, column: 7)
    ]

    /// Squares on a player's route, in order. Index 1 is the first square
    /// entered; index `pathLength` is the last before home.
    static let pathLength = 16

    /// Seat 0's route, and the mirror of seat 1's.
    ///
    /// Out along the bottom row right to left, up into the middle row, then
    /// left to right across the bridge to column 7 — and then *around* the
    /// far block clockwise: up, right, down the outer column, and back left
    /// to the rosette it exits from.
    private static let bottomPath: [Square] = [
        Square(row: 3, column: 4),   // 1
        Square(row: 3, column: 3),   // 2
        Square(row: 3, column: 2),   // 3
        Square(row: 3, column: 1),   // 4  rosette
        Square(row: 2, column: 1),   // 5
        Square(row: 2, column: 2),   // 6
        Square(row: 2, column: 3),   // 7
        Square(row: 2, column: 4),   // 8  rosette
        Square(row: 2, column: 5),   // 9
        Square(row: 2, column: 6),   // 10
        Square(row: 2, column: 7),   // 11
        Square(row: 1, column: 7),   // 12 rosette
        Square(row: 1, column: 8),   // 13
        Square(row: 2, column: 8),   // 14
        Square(row: 3, column: 8),   // 15
        Square(row: 3, column: 7)    // 16 rosette
    ]

    // MARK: Off-board trays

    /// Where a seat's pieces wait before entering.
    ///
    /// The traditional board has a four-square gap in its middle — the
    /// cells `squares` skips — and nothing has ever used it. Waiting and
    /// finished pieces go there, which means they are drawn somewhere
    /// instead of vanishing, and they land where that player's route
    /// actually begins and ends: the waiting tray sits beside the entry
    /// square, home beside the exit.
    static func waitingTray(seat: Int) -> Square {
        Square(row: seat == topSeat ? 1 : 3, column: 5)
    }

    /// Where a seat's finished pieces rest.
    static func homeTray(seat: Int) -> Square {
        Square(row: seat == topSeat ? 1 : 3, column: 6)
    }

    /// Both trays for both seats — the four cells the board itself omits.
    static var trayCells: [Square] {
        [0, 1].flatMap { [waitingTray(seat: $0), homeTray(seat: $0)] }
    }

    /// The cell a piece is drawn in, wherever it is in its life: waiting,
    /// on the route, or home.
    ///
    /// One mapping for both drawing and tapping, so a piece can never be
    /// shown somewhere it cannot be tapped.
    static func displaySquare(seat: Int, index: Int) -> Square? {
        if index <= 0 { return waitingTray(seat: seat) }
        if index > pathLength { return homeTray(seat: seat) }
        return square(seat: seat, index: index)
    }

    /// Mirrors a square across the middle row — which is the whole of the
    /// difference between the two players' routes.
    static func mirrored(_ square: Square) -> Square {
        Square(row: rows + 1 - square.row, column: square.column)
    }

    /// The route a seat walks, index 1 first.
    static func path(for seat: Int) -> [Square] {
        seat == topSeat ? bottomPath.map(mirrored) : bottomPath
    }

    /// The square a piece stands on, or nil when it is off the board —
    /// index 0 is waiting to enter and `pathLength + 1` is home.
    static func square(seat: Int, index: Int) -> Square? {
        guard index >= 1, index <= pathLength else { return nil }
        return path(for: seat)[index - 1]
    }

    /// True when a piece at this index is standing on a rosette.
    static func isRosette(seat: Int, index: Int) -> Bool {
        guard let square = square(seat: seat, index: index) else { return false }
        return rosettes.contains(square)
    }

    /// Whether both players share a square — the twelve contested ones.
    ///
    /// Asked whether capture could apply to "any potential overlapping
    /// space along the path". It already does, and this is why: the only
    /// squares excluded below are each player's first four, and those are
    /// DIFFERENT PHYSICAL SQUARES for the two seats — row 3 columns 1-4 for
    /// one, row 1 columns 1-4 for the other. Two pieces can never meet
    /// there, so there is no overlapping square that is not capturable.
    ///
    /// Indices 5 to 16 are all shared: 5 through 11 are the same square at
    /// the same index for both, and 12 through 16 are the same five squares
    /// *in reverse*, so the two players run the final loop in opposite
    /// directions and meet head-on. Only each player's first four squares
    /// are private.
    static func isShared(_ square: Square) -> Bool {
        square.row == 2 || square.column >= 7
    }
}

// MARK: - Decoration

extension RoyalUrBoard {

    /// The six markings the traditional board carries, one per square.
    ///
    /// Taken from the reference board: the rosettes, the "eyes", the
    /// five-dot quincunx, a dotted field, a grid of squares, and the
    /// zigzag-and-five. Purely visual — nothing in the rules reads this
    /// except the rosette, which has its own set above.
    enum Decor {
        case rosette
        case eyes
        case fiveDots
        case dottedField
        case squaresGrid
        case zigzagFive
    }

    static func decor(at square: Square) -> Decor {
        if rosettes.contains(square) { return .rosette }
        switch (square.row, square.column) {
        case (2, 1):                      return .squaresGrid
        case (2, 3), (2, 6):              return .dottedField
        case (1, 8), (3, 8):              return .zigzagFive
        case (1, 2), (3, 2), (1, 4), (3, 4), (2, 7):
                                          return .eyes
        default:                          return .fiveDots
        }
    }
}
