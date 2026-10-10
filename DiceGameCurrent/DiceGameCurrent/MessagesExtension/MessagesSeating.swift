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

    /// Every participant, in an order every device agrees on.
    ///
    /// **Why sorted.** The tempting spelling is local first, then
    /// `remoteParticipantIdentifiers` — and it is wrong twice over. The
    /// local participant is a different person on each device, so seat 0
    /// would be "me" on both phones and the two devices would disagree
    /// about whose score is whose. And Messages does not promise the
    /// remote order is stable between devices either.
    ///
    /// Sorting the UUID strings gives one roster that both devices compute
    /// identically from the same set of people, without either having to
    /// be told. The order is arbitrary — a UUID carries no meaning — but
    /// arbitrary and agreed is the whole requirement.
    ///
    /// In practice only the starter builds this: after the first turn the
    /// roster travels inside `TurnMatch.participants` and is read from the
    /// message. This matters for the one case where it does not — a
    /// participant leaving a group thread mid-match — where both devices
    /// must still agree, and a locally-ordered roster would not.
    static func roster(in conversation: MSConversation) -> [String] {
        var ids = conversation.remoteParticipantIdentifiers.map { $0.uuidString }
        ids.append(localID(in: conversation))
        return ids.sorted()
    }

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
        return TurnMatch(participants: ids, seatSequence: seatSequence)
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
    /// False for somebody added to the thread after a match began. They
    /// get the result, not a seat — joining a game in progress would mean
    /// a roster change mid-match, and no game in the suite has scoring that
    /// survives one.
    static func isSeated(_ match: TurnMatch,
                         in conversation: MSConversation) -> Bool {
        match.participants.contains(localID(in: conversation))
    }
}
