import Foundation

/// A two-or-more player match: who is playing, whose turn it is, what each
/// has scored, and whether it is over.
///
/// Deliberately knows nothing about dice. Every alternating game in the
/// suite — Chasing 6, Nautical, PIG, Three Thousand, Generals, Royal Path —
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

    enum Outcome: Codable, Equatable {
        /// Ended normally; `winners` has more than one entry on a draw.
        case decided(winners: [String])
        /// Ended early by a game-specific condition — Chasing 6's Jackpot
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

    init(participants: [String], startingIndex: Int = 0) {
        self.participants = participants
        self.activeIndex = startingIndex
        self.round = 1
        self.scores = Dictionary(uniqueKeysWithValues: participants.map { ($0, 0) })
        self.outcome = nil
    }

    private enum CodingKeys: String, CodingKey {
        case participants = "p"
        case activeIndex = "a"
        case round = "r"
        case scores = "s"
        case outcome = "o"
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
    var activeIsLastInRound: Bool {
        activeIndex == participants.count - 1
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
    /// `TurnCompleteOverlay` baked in and got wrong for six of eight games.
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
    static func localTwoPlayer() -> TurnMatch {
        TurnMatch(participants: ["local.1", "local.2"])
    }
}
