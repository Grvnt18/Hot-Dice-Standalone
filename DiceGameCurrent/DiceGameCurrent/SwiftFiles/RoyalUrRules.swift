import Foundation

/// Royal UR: three pieces each, five binary dice, and a board where
/// nearly every square can be taken from you.
///
/// Measured over 15,000 simulated games with both seats playing the same
/// way: **27 messages a match, 2.8 captures, 1.2 Setbacks**, and the first
/// seat winning 52%. The two numbers that move it most are below, at
/// `rosetteGrantsAnotherRoll` and `requiresExactExit`.
enum RoyalUrRules {

    /// Five dice, each scoring one or nothing — 0 to 5 a turn, averaging
    /// 2.5. Four dice average 2.0 and make for a longer, thinner game.
    static let diceCount = 5

    static let piecesPerPlayer = 3

    /// First to bring this many home wins. Three pieces stay on the board
    /// so the tactical density is unchanged; only the long tail of walking
    /// the last one home is cut — which was worth about 15 messages.
    static let piecesToWin = 2

    /// How far back a Setback sends a piece.
    static let setbackDistance = 4

    /// One past the last square on the path.
    static let homeIndex = RoyalUrBoard.pathLength + 1

    /// A piece comes home only on an exact count; an overshoot is not a
    /// legal move.
    ///
    /// **This is the game's length dial, and it costs captures to turn.**
    /// Allowing overshoots finishes in 21.8 messages instead of 26.9 — but
    /// captures fall from 2.8 a game to 1.7, because pieces stop queueing
    /// up in the final loop waiting for the right number. Captures are what
    /// makes this board worth playing on, and every tile being capturable
    /// was a deliberate choice, so the exact count stays.
    static let requiresExactExit = true

    /// Landing on a rosette gives you another roll.
    ///
    /// Not a flourish — it is what makes the rosettes mean anything, and it
    /// nearly halves the game: without it the same match takes 40 messages
    /// instead of 27.
    static let rosetteGrantsAnotherRoll = true

    /// Five d4, each read as a single pip.
    static func makeDice() -> [Die] {
        var colorways = DiePalette.colorways.shuffled()
        return (0..<diceCount).compactMap { _ in
            guard !colorways.isEmpty else { return nil }
            return Die(sides: 4, colorway: colorways.removeLast())
        }
    }

    /// How far this roll moves you.
    ///
    /// Each die is binary: the two low numbers score a pip and the two high
    /// ones score nothing, which is an even split and — unlike "odd or
    /// even" — reads off the die at a glance. The tray reports a d4's
    /// resting face, so the apex has to be worked out first.
    static func steps(from results: [DiceTraySession.DieResult]) -> Int {
        results.reduce(0) { total, result in
            guard result.sides == 4 else { return total }
            let apex = DieFaceLabels.d4ApexValue(restingFace: result.value - 1)
            return total + (apex <= 2 ? 1 : 0)
        }
    }

    /// Whether one die scored, for showing the roll back to the player.
    static func isPip(_ result: DiceTraySession.DieResult) -> Bool {
        guard result.sides == 4 else { return false }
        return DieFaceLabels.d4ApexValue(restingFace: result.value - 1) <= 2
    }
}

// MARK: - State

/// Where the six pieces are. Index 0 is waiting to enter, 1...16 is on the
/// board, and `homeIndex` is home.
struct RoyalUrState: Codable, Equatable {

    /// `positions[seat][piece]`.
    private(set) var positions: [[Int]]

    init() {
        positions = Array(
            repeating: Array(repeating: 0, count: RoyalUrRules.piecesPerPlayer),
            count: 2
        )
    }

    private enum CodingKeys: String, CodingKey { case positions = "p" }

    // MARK: Reading

    func index(seat: Int, piece: Int) -> Int { positions[seat][piece] }

    func homeCount(seat: Int) -> Int {
        positions[seat].filter { $0 == RoyalUrRules.homeIndex }.count
    }

    func waitingCount(seat: Int) -> Int {
        positions[seat].filter { $0 == 0 }.count
    }

    /// Pieces standing on the board, which is what a Setback can move and
    /// what an opponent can take.
    func piecesOnBoard(seat: Int) -> [Int] {
        positions[seat].indices.filter { isOnBoard(positions[seat][$0]) }
    }

    private func isOnBoard(_ index: Int) -> Bool {
        index >= 1 && index <= RoyalUrBoard.pathLength
    }

    /// The square a piece occupies, or nil when it is waiting or home.
    func square(seat: Int, piece: Int) -> RoyalUrBoard.Square? {
        RoyalUrBoard.square(seat: seat, index: positions[seat][piece])
    }

    /// Which piece of a seat's is standing on a square, if any.
    func piece(of seat: Int, on square: RoyalUrBoard.Square) -> Int? {
        positions[seat].indices.first {
            RoyalUrBoard.square(seat: seat, index: positions[seat][$0]) == square
        }
    }

    // MARK: Moves

    /// Every legal move for a roll, as piece index to destination index.
    ///
    /// A move is illegal only when it would overshoot home or land on one
    /// of your own pieces. Landing on an opponent is not blocked — it is
    /// the point.
    func legalMoves(seat: Int, steps: Int) -> [Int: Int] {
        guard steps > 0 else { return [:] }
        var moves: [Int: Int] = [:]
        for piece in positions[seat].indices {
            let from = positions[seat][piece]
            guard from != RoyalUrRules.homeIndex else { continue }

            var destination = from + steps
            if destination > RoyalUrRules.homeIndex {
                guard !RoyalUrRules.requiresExactExit else { continue }
                destination = RoyalUrRules.homeIndex
            }

            if destination < RoyalUrRules.homeIndex,
               let target = RoyalUrBoard.square(seat: seat, index: destination),
               occupiedBySelf(seat: seat, square: target, ignoring: piece) {
                continue
            }
            moves[piece] = destination
        }
        return moves
    }

    private func occupiedBySelf(seat: Int, square: RoyalUrBoard.Square, ignoring piece: Int) -> Bool {
        positions[seat].indices.contains {
            $0 != piece && RoyalUrBoard.square(seat: seat, index: positions[seat][$0]) == square
        }
    }

    /// The opponent piece a move would send home, if any.
    func capture(seat: Int, destination: Int) -> Int? {
        guard destination < RoyalUrRules.homeIndex,
              let square = RoyalUrBoard.square(seat: seat, index: destination),
              RoyalUrBoard.isShared(square) else { return nil }
        return piece(of: 1 - seat, on: square)
    }

    /// What a move did, for the turn summary and for deciding who rolls next.
    struct MoveOutcome: Equatable {
        let captured: Bool
        let cameHome: Bool
        let landedOnRosette: Bool

        /// A rosette buys another roll — nothing else does.
        var grantsAnotherRoll: Bool {
            landedOnRosette && RoyalUrRules.rosetteGrantsAnotherRoll
        }
    }

    @discardableResult
    mutating func apply(seat: Int, piece: Int, destination: Int) -> MoveOutcome {
        let captured = capture(seat: seat, destination: destination)
        if let captured {
            positions[1 - seat][captured] = 0
        }
        positions[seat][piece] = destination

        return MoveOutcome(
            captured: captured != nil,
            cameHome: destination == RoyalUrRules.homeIndex,
            landedOnRosette: RoyalUrBoard.isRosette(seat: seat, index: destination)
        )
    }

    // MARK: The Setback

    /// A turn you cannot move is not a turn you skip.
    ///
    /// With no legal move — a roll of nothing, or every piece blocked by
    /// your own — one of your pieces goes back four squares. It answers
    /// "no dead turns, but keep the consequences of a bad roll": the bad
    /// roll costs more than it used to, and it costs it visibly, as a
    /// choice your opponent watches you make. Dead turns fall to about one
    /// game in seven, and only when you have nothing on the board at all.
    func setbackCandidates(seat: Int) -> [Int] {
        piecesOnBoard(seat: seat)
    }

    /// Where a Setback would put a piece.
    ///
    /// Back four, unless that square is occupied by anyone — in which case
    /// it goes all the way back to the start. A Setback never captures:
    /// being unable to move should not be a way to take a piece.
    func setbackDestination(seat: Int, piece: Int) -> Int {
        let target = positions[seat][piece] - RoyalUrRules.setbackDistance
        guard target >= 1, let square = RoyalUrBoard.square(seat: seat, index: target) else {
            return 0
        }
        let occupied = occupiedBySelf(seat: seat, square: square, ignoring: piece)
            || self.piece(of: 1 - seat, on: square) != nil
        return occupied ? 0 : target
    }

    @discardableResult
    mutating func applySetback(seat: Int, piece: Int) -> Int {
        let destination = setbackDestination(seat: seat, piece: piece)
        positions[seat][piece] = destination
        return destination
    }

    // MARK: Winning

    var winner: Int? {
        for seat in positions.indices where homeCount(seat: seat) >= RoyalUrRules.piecesToWin {
            return seat
        }
        return nil
    }
}
