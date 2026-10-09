import Foundation

/// A two-or-more player match: who is playing, whose turn it is, what each
/// has scored, and whether it is over.
///
/// Deliberately knows nothing about dice. Every alternating game in the
/// suite — Jackpot, Freighter.Yacht.Dinghy, HOG, Three Thousand, Generals, Royal UR —
/// needs exactly this bookkeeping and nothing about it is game-specific,
/// so the games carry their own state separately and let this handle turns.
///
/// `Codable`, and shaped to ride the existing `GameEnvelope` in
/// `GamePayload.swift` when the Messages extension arrives. Pass-and-play
/// drives the same transitions today, which is the point: the extension
/// will not need a second code path.
struct TurnMatch: Codable, Equatable {

    /// Participants in seating order. Pass-and-play generates local ids;
    /// the Messages extension will use `MSConversation` participant UUIDs.
    var participants: [String]

    /// Index into `participants` of whoever is up.
    var activeIndex: Int

    /// 1-based. A round is one turn for every participant, so it advances
    /// when play wraps back to the first seat.
    var round: Int

    /// Running total per participant.
    var scores: [String: Int]

    /// Set when the match is decided. Nil while play continues.
    var outcome: Outcome?

    /// An explicit order of seats, when the game does not simply alternate.
    ///
    /// Nil for every game but Generals, which claims from a single shared
    /// scorecard and so has a measured first-mover edge: over 60,000
    /// simulated matches, strict alternation gave the first seat 61.4% of
    /// decided matches and a +9.0 mean margin. A snake order
    /// (A, B, B, A, A, B, …) takes that to 51.0% and +0.7 — still six
    /// claims each, with the advantage removed at its source rather than
    /// handed out by a coin flip.
    var seatSequence: [Int]?

    /// Turns taken, 0-based. Only read when `seatSequence` is set, which is
    /// what the sequence is indexed by.
    var turnNumber: Int

    enum Outcome: Codable, Equatable {
        /// Ended normally; `winners` has more than one entry on a draw.
        case decided(winners: [String])
        /// Ended early by a game-specific condition — Jackpot's Jackpot
        /// is the first of these. Carried separately so the result screen
        /// can say *why* rather than only who.
        case special(winners: [String], reason: String)

        var winners: [String] {
            switch self {
            case .decided(let w):      return w
            case .special(let w, _):   return w
            }
        }
    }

    init(participants: [String], startingIndex: Int = 0, seatSequence: [Int]? = nil) {
        self.participants = participants
        self.activeIndex = seatSequence?.first ?? startingIndex
        self.round = 1
        self.scores = Dictionary(uniqueKeysWithValues: participants.map { ($0, 0) })
        self.outcome = nil
        self.seatSequence = seatSequence
        self.turnNumber = 0
    }

    private enum CodingKeys: String, CodingKey {
        case participants = "p"
        case activeIndex = "a"
        case round = "r"
        case scores = "s"
        case outcome = "o"
        case seatSequence = "q"
        case turnNumber = "n"
    }
}

// MARK: - Reading

extension TurnMatch {

    var activeParticipant: String {
        participants.isEmpty ? "" : participants[activeIndex % participants.count]
    }

    var isOver: Bool { outcome != nil }

    func score(for participant: String) -> Int {
        scores[participant] ?? 0
    }

    /// True when the active seat is the last one in the round — the player
    /// who, on finishing, completes it.
    ///
    /// With an explicit seat order the seat itself cannot answer this: a
    /// snake plays the same seat twice in a row, so position in the order
    /// is what closes a round, not which seat is up.
    var activeIsLastInRound: Bool {
        guard !participants.isEmpty else { return false }
        if seatSequence != nil {
            return turnNumber % participants.count == participants.count - 1
        }
        return activeIndex == participants.count - 1
    }
}

// MARK: - Advancing

extension TurnMatch {

    /// Adds to the active participant's total.
    mutating func addScore(_ points: Int) {
        guard !participants.isEmpty else { return }
        scores[activeParticipant, default: 0] += points
    }

    /// Hands play to the next seat, advancing the round on wrap.
    mutating func advanceTurn() {
        guard !participants.isEmpty else { return }
        turnNumber += 1
        if let sequence = seatSequence, !sequence.isEmpty {
            // Wraps rather than clamping, so a sequence shorter than the
            // match simply repeats. Generals' is exactly as long as its
            // match, so it never reaches this.
            activeIndex = sequence[turnNumber % sequence.count] % participants.count
            round = turnNumber / participants.count + 1
            return
        }
        activeIndex += 1
        if activeIndex >= participants.count {
            activeIndex = 0
            round += 1
        }
    }

    /// Ends the match on points.
    ///
    /// Takes the direction explicitly rather than assuming: Rolls is
    /// golf-scored and the rest are not, which is exactly the assumption
    /// `TurnCompleteOverlay` baked in and got wrong for every game but
    /// Rolls.
    mutating func finish(lowestScoreWins: Bool) {
        guard !participants.isEmpty else { return }
        let totals = participants.map { score(for: $0) }
        guard let best = lowestScoreWins ? totals.min() : totals.max() else { return }
        outcome = .decided(winners: participants.filter { score(for: $0) == best })
    }

    /// Ends the match by a game-specific condition.
    mutating func finish(winners: [String], reason: String) {
        outcome = .special(winners: winners, reason: reason)
    }
}

// MARK: - Display names

extension TurnMatch {

    /// What to call a participant on screen.
    ///
    /// Positional, because that is all the Messages extension will be able
    /// to offer: it gets opaque per-conversation UUIDs and no names or
    /// avatars. Using the same labelling in pass-and-play keeps the two
    /// consistent, and in a thread the real attribution comes free — each
    /// turn is its own message bubble under that person's name.
    func displayName(for participant: String) -> String {
        guard let index = participants.firstIndex(of: participant) else { return "Player" }
        return "Player \(index + 1)"
    }

    var activeDisplayName: String {
        displayName(for: activeParticipant)
    }
}

// MARK: - Pass and play

extension TurnMatch {

    /// A local two-player match. Ids are arbitrary but stable within the
    /// match, which is all anything here needs.
    static func localTwoPlayer(seatSequence: [Int]? = nil) -> TurnMatch {
        local(playerCount: 2, seatSequence: seatSequence)
    }

    /// A local match for any number of seats.
    ///
    /// Everything above this line already handles N: `advanceTurn` wraps on
    /// `participants.count`, `activeIsLastInRound` compares against it, and
    /// scores are keyed by participant rather than by a player-one and a
    /// player-two. The only thing that ever said "two" was the factory.
    ///
    /// Which is what this is for. Three Thousand, HOG and
    /// Freighter.Yacht.Dinghy are all described as two or more players in
    /// GAME_RULES.txt, and none of their screens contains a two-player
    /// assumption — no `1 - seat`, no `participants[1]`, no count check.
    /// They are seat-based already. When the Messages extension supplies
    /// real participant ids, it calls `TurnMatch(participants:)` directly
    /// and these games need no further change.
    ///
    /// Clamped at one, because a match with no seats has no active
    /// participant and every read here would be answering about nobody.
    static func local(playerCount: Int, seatSequence: [Int]? = nil) -> TurnMatch {
        let seats = max(1, playerCount)
        return TurnMatch(participants: (1...seats).map { "local.\($0)" },
                         seatSequence: seatSequence)
    }

    /// A match whose ids are the SIZE Messages actually hands out.
    ///
    /// Only `GameWireCheck` uses this, and it exists because the budget
    /// figure on the device was measuring the wrong thing. Pass-and-play
    /// ids are `local.1` — seven characters — while an `MSConversation`
    /// participant is a 36-character UUID, and every participant is spelled
    /// TWICE in an encoded match: once in `participants` and once as a key
    /// in `scores`. At two seats that is 154 bytes of a 365-byte Royal UR
    /// turn, which makes the roster, not the game, the dominant cost of
    /// almost every message the suite sends.
    ///
    /// So the probe has to use ids of the real length or it reports a number
    /// no real message will ever have. The characters are arbitrary — only
    /// the count is load-bearing — but they are shaped like a UUID so that
    /// a log of a probe payload is not mistaken for a live one.
    static func messagesShaped(playerCount: Int,
                               seatSequence: [Int]? = nil) -> TurnMatch {
        let seats = max(1, playerCount)
        var ids: [String] = []
        for seat in 1...seats {
            // 8-4-4-4-12, the canonical UUID string: 36 characters.
            let tail = String(format: "%012d", seat)
            ids.append("00000000-0000-4000-8000-" + tail)
        }
        return TurnMatch(participants: ids, seatSequence: seatSequence)
    }

    /// How long a participant id is when Messages supplies it.
    ///
    /// Named so the guard on the probes can assert they are using one,
    /// rather than counting characters in a literal.
    static let messagesIDLength = 36
}
