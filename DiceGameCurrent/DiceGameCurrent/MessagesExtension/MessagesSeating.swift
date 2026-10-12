import Foundation
import Messages

/// Who is playing, when the players come from a conversation.
///
/// `TurnMatch` is seat-based and participant-keyed already, so this is a
/// translation layer and nothing more. The care it needs is all in one
/// place: **the roster has to be identical on every device**, and the
/// obvious way to build it is not.
enum MessagesSeating {

    /// This device's seat id.
    ///
    /// A 36-character UUID string, which is what the byte budget in
    /// `tools_rules_verify.py` is modelled on — see
    /// `TurnMatch.messagesIDLength`.
    static func localID(in conversation: MSConversation) -> String {
        conversation.localParticipantIdentifier.uuidString
    }

    /// Every participant, in an order every device agrees on, with the
    /// SENDER LAST.
    ///
    /// **The seating rule: whoever sends the invitation is player 2 and
    /// moves second.** The person who receives it is player 1 and takes the
    /// first turn — which is also what decides when a match has begun. So
    /// the local participant goes on the end of the roster, and seat 0 is
    /// the opponent.
    ///
    /// That is the opposite of the obvious spelling (local first, then
    /// `remoteParticipantIdentifiers`) and it is load-bearing in two ways.
    /// The order is the seating, so it decides who rolls first. And it has
    /// to be the same on both devices: the local participant is a different
    /// person on each phone, so a locally-ordered roster would have each
    /// device calling itself seat 0, and the two would disagree about whose
    /// score is whose.
    ///
    /// It works because only the SENDER ever builds this. After the invite,
    /// the roster travels inside `TurnMatch.participants` and every device
    /// reads it from the message rather than recomputing it. The remote ids
    /// are still sorted, because Messages does not promise their order is
    /// stable between devices and a group match must not reshuffle its
    /// middle seats if anyone ever does rebuild it.
    ///
    /// Two-player games, which is nine of the ten, come out as
    /// `[them, me]`.
    static func roster(in conversation: MSConversation) -> [String] {
        let remote = conversation.remoteParticipantIdentifiers
            .map { $0.uuidString }
            .sorted()
        return remote + [localID(in: conversation)]
    }

    /// Which seat takes the first turn.
    ///
    /// Zero, always: seat 0 is the invitation's recipient. Named rather
    /// than written as a literal at the call site, because "player 1 goes
    /// first and player 1 is not the sender" is the kind of rule that gets
    /// quietly inverted by somebody tidying up.
    static let firstSeat = 0

    /// A fresh match for this conversation, or nil when the thread cannot
    /// seat this game.
    ///
    /// Refused rather than truncated. A five-person thread opening a
    /// two-player game is a real case, and silently seating the first two
    /// would produce a match three participants can see, cannot join, and
    /// whose scoreboard names two of them as the only players. Better to
    /// say so.
    static func newMatch(in conversation: MSConversation,
                         maxPlayers: Int,
                         seatSequence: [Int]? = nil) -> TurnMatch? {
        let ids = roster(in: conversation)
        guard ids.count >= 2, ids.count <= maxPlayers else { return nil }
        // `startingIndex`, explicitly: the recipient of the invitation
        // opens. TurnMatch defaults to 0 anyway, but the default and the
        // rule agreeing by coincidence is not the same as saying so.
        return TurnMatch(participants: ids,
                         startingIndex: firstSeat,
                         seatSequence: seatSequence)
    }

    /// Whether this device sent the invitation — player 2.
    ///
    /// The sender is the last seat by construction (see `roster`), so this
    /// is a question about the roster rather than about anything stored.
    static func isSender(_ match: TurnMatch,
                         in conversation: MSConversation?) -> Bool {
        guard let conversation else { return false }
        return match.participants.last == localID(in: conversation)
    }

    /// Whether the person holding this device is the one to move.
    ///
    /// The single most important question in the extension: everything the
    /// player can do is gated on it, and a received turn is read-only until
    /// it answers true.
    static func isLocalTurn(_ match: TurnMatch,
                            in conversation: MSConversation) -> Bool {
        !match.isOver && match.activeParticipant == localID(in: conversation)
    }

    /// Whether this device's participant is in the match at all.
    ///
    /// False for somebody added to the thread after a match began. They get
    /// the result, not a seat — joining a game in progress would mean a
    /// roster change mid-match, and no game in the suite has scoring that
    /// survives one.
    ///
    /// Takes an optional conversation and answers `false` without one. The
    /// store holds `MSConversation?` — it is dropped on `didResignActive`,
    /// because a retained conversation is a stale one — and "not seated" is
    /// the safe direction to fail in: it shows standings rather than a
    /// board, and a board is the thing that could write a turn.
    static func isSeated(_ match: TurnMatch,
                         in conversation: MSConversation?) -> Bool {
        guard let conversation else { return false }
        return match.participants.contains(localID(in: conversation))
    }
}
