import Foundation

/// Rolls as it travels in a message.
///
/// Rolls is the suite's one N-player game: a single round each, lowest
/// score wins, and because there is no turn order to maintain it works in a
/// group chat as well as one-to-one. The state is therefore keyed by
/// participant rather than being a player-one/player-two pair.
///
/// **What makes the payload small.** The pool — which of the 15 colorways
/// gets which die type, and in what order — is built entirely from the
/// seed, so both devices can reconstruct it from that one number. The only
/// things that genuinely have to travel are the 15 landed face values and
/// the order the dice were banked in.
///
/// **What cannot be seeded.** A die's value in Rolls is read from whichever
/// face physically lands up in SceneKit, not drawn from a generator, and
/// floating-point physics does not reproduce across devices. So unlike the
/// rest of the suite, a Rolls result cannot be replayed and re-derived from
/// the seed — the values are asserted by the sender. `score` is therefore
/// carried redundantly and recomputed on arrival: it cannot prove the dice
/// really landed that way, but it does catch a client whose arithmetic
/// disagrees, and it makes a hand-edited score obvious.

// MARK: - One player's round

struct RollsPlayerResult: Codable, Equatable {

    /// Landed face value for each die, indexed to match the pool order that
    /// `DiceGameRound(seed:)` produces. 15 entries in a finished round.
    var values: [Int]

    /// Pool indices in the order the dice were banked, for the history grid.
    var order: [Int]

    /// Banked total as the sender calculated it. Recomputed on arrival —
    /// see `validate(againstSeed:)`.
    var score: Int

    private enum CodingKeys: String, CodingKey {
        case values = "v"
        case order = "o"
        case score = "s"
    }
}

extension RollsPlayerResult {

    /// A finished round, packed for sending.
    ///
    /// `originalPool` rather than `pool`: dice travel as indices into the
    /// dealt order, and by the time a round is finished `pool` is empty.
    /// That property exists for exactly this, and its own comment says so.
    ///
    /// The index map is built with a plain loop rather than
    /// `Dictionary(uniqueKeysWithValues: pool.enumerated().map { ... })`,
    /// which is the closure-inside-an-inference-chain shape that took the
    /// Playgrounds build down once and that tools_qualcheck.py flags.
    init(round: DiceGameRound) {
        let dealt = round.originalPool

        var positions: [UUID: Int] = [:]
        for (index, die) in dealt.enumerated() {
            positions[die.id] = index
        }

        var faces: [Int] = []
        for die in dealt {
            // A die with no settled value cannot have been banked, so zero
            // is unreachable in a finished round. It is here rather than a
            // force-unwrap because an unfinished round is a programming
            // error, not a crash the player should take.
            faces.append(die.currentValue ?? 0)
        }

        var banked: [Int] = []
        for die in round.bankedOrder {
            if let index = positions[die.id] { banked.append(index) }
        }

        self.values = faces
        self.order = banked
        self.score = round.bankedScore
    }
}

// MARK: - The game

struct RollsGameState: Codable, Equatable {

    /// Participant identifier -> their finished round.
    ///
    /// Keys are `MSConversation` participant UUIDs, which are opaque and
    /// scoped to the conversation. Messages does not hand an extension the
    /// participants' names or avatars, so these cannot be turned into
    /// display names — the in-app leaderboard labels people positionally,
    /// and real attribution comes from the message bubbles themselves.
    var results: [String: RollsPlayerResult]

    /// Who opened the game. They are the one who can close it early.
    var startedBy: String

    /// Set once the game is resolved, so a late arrival sees a result rather
    /// than an invitation to play.
    ///
    /// A group game needs this because it cannot rely on everyone playing:
    /// people join and leave a thread, and someone may simply never open the
    /// message. Waiting for every participant would hang the game forever,
    /// so the starter can close it at any point and whoever has rolled is
    /// who counts.
    var isClosed: Bool

    private enum CodingKeys: String, CodingKey {
        case results = "r"
        case startedBy = "b"
        case isClosed = "c"
    }

    init(startedBy: String, results: [String: RollsPlayerResult] = [:], isClosed: Bool = false) {
        self.startedBy = startedBy
        self.results = results
        self.isClosed = isClosed
    }
}

// MARK: - Identity and versioning

extension RollsGameState {
    static let gameID = "rolls"

    /// Bumped whenever the encoded shape changes in a way an older build
    /// could not read correctly. The receiver checks this before decoding.
    static let schemaVersion = 1
}

// MARK: - Scoring and validation

extension RollsPlayerResult {

    /// Points for one die, matching `Die.pointValue`: rolling the maximum
    /// face scores 0, and a 1 is special-cased to the die's own maximum so
    /// it is the worst possible result on any die. Lower totals win.
    static func points(sides: Int, value: Int) -> Int {
        value == 1 ? sides : sides - value
    }

    enum ValidationFailure: Error, CustomStringConvertible {
        case wrongDieCount(expected: Int, got: Int)
        case orderIsNotAPermutation
        case valueOutOfRange(poolIndex: Int, value: Int, sides: Int)
        case scoreMismatch(claimed: Int, actual: Int)

        var description: String {
            switch self {
            case .wrongDieCount(let expected, let got):
                return "Expected \(expected) dice, got \(got)."
            case .orderIsNotAPermutation:
                return "Bank order doesn't list each die exactly once."
            case .valueOutOfRange(let i, let value, let sides):
                return "Die \(i) shows \(value), impossible on a d\(sides)."
            case .scoreMismatch(let claimed, let actual):
                return "Score claimed \(claimed) but the dice add up to \(actual)."
            }
        }
    }

    /// Rebuilds the pool from the seed and checks the sender's claims
    /// against it.
    ///
    /// This cannot verify that the dice really landed on these faces —
    /// physics is not replayable, so the values are taken on trust. What it
    /// does catch is everything structural: a wrong number of dice, a bank
    /// order that repeats or omits one, a face value that die could not
    /// physically show, and a total that does not match its own dice. That
    /// covers honest bugs and casual tampering alike.
    func validate(againstSeed seed: UInt64) throws {
        let pool = DiceGameRound(seed: seed).pool

        guard values.count == pool.count else {
            throw ValidationFailure.wrongDieCount(expected: pool.count, got: values.count)
        }
        guard order.count == pool.count, Set(order) == Set(0..<pool.count) else {
            throw ValidationFailure.orderIsNotAPermutation
        }

        var total = 0
        for (index, die) in pool.enumerated() {
            let value = values[index]
            guard value >= 1, value <= die.sides else {
                throw ValidationFailure.valueOutOfRange(
                    poolIndex: index, value: value, sides: die.sides
                )
            }
            total += Self.points(sides: die.sides, value: value)
        }

        guard total == score else {
            throw ValidationFailure.scoreMismatch(claimed: score, actual: total)
        }
    }
}

// MARK: - Building a result from a finished round

extension RollsPlayerResult {

    /// Snapshots a completed `DiceGameRound` into sendable form.
    ///
    /// Returns nil if the round is not actually finished — every die has to
    /// have been banked, since the payload's pool indices are derived from
    /// the full 15-die pool the seed produces.
    init?(finished round: DiceGameRound) {
        let dealt = round.originalPool
        let banked = round.bankedOrder
        guard round.isGameOver, banked.count == dealt.count else { return nil }

        // Map each banked die back to where it sat in the dealt pool, by id.
        // This uses the round's own `originalPool` rather than rebuilding
        // from the seed, because a rebuild produces fresh UUIDs that would
        // match nothing.
        var indexByID: [UUID: Int] = [:]
        for (index, die) in dealt.enumerated() {
            indexByID[die.id] = index
        }

        var values = [Int](repeating: 0, count: dealt.count)
        var order: [Int] = []
        order.reserveCapacity(banked.count)

        for die in banked {
            guard let index = indexByID[die.id], let value = die.currentValue else { return nil }
            values[index] = value
            order.append(index)
        }

        self.values = values
        self.order = order
        self.score = round.bankedScore
    }
}

// MARK: - Leaderboard

extension RollsGameState {

    struct Standing: Equatable {
        let participant: String
        let score: Int
    }

    /// Everyone who has rolled, best (lowest) first. Rolls scores are
    /// penalty points, so the smallest total wins.
    var standings: [Standing] {
        results
            .map { Standing(participant: $0.key, score: $0.value.score) }
            // Sorted by participant id as a secondary key purely so the
            // ordering is stable and identical on every device — otherwise
            // two players tied on score could see the list in different
            // orders, which looks like a bug.
            .sorted { ($0.score, $0.participant) < ($1.score, $1.participant) }
    }

    /// The winning participants. More than one means a tie.
    var leaders: [String] {
        guard let best = standings.first?.score else { return [] }
        return standings.filter { $0.score == best }.map(\.participant)
    }

    /// A finished game with more than one leader is a draw, which by the
    /// game's rules restarts rather than resolving.
    var isTie: Bool {
        leaders.count > 1
    }
}
