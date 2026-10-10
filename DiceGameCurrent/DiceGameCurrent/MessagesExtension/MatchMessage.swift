import Foundation
import Messages

/// A turn, as a message in a thread.
///
/// `GameTransport` already knows how to turn a match and a game's state
/// into a URL and read one back; this is the layer above it that knows
/// about `MSMessage` — the session a turn belongs to, the bubble it draws,
/// and the caption a participant reads before they open anything.
///
/// Nothing here is game-specific. A game hands over its own `State` and
/// gets a message; a received message hands back a header, and the caller
/// decides what to decode it as. That split is deliberate: the extension
/// must be able to read the game id out of a message for a game this build
/// does not have, which is exactly what `GameEnvelopeHeader` is for.
enum MatchMessage {

    // MARK: - Sending

    /// Packs a turn into a message ready to insert into the conversation.
    ///
    /// **The session is reused, and that is the whole point.** An
    /// `MSMessage` created with the session of the message that was
    /// selected REPLACES that bubble in the transcript rather than adding
    /// another one. Without it, a Royal UR match — 21.9 messages at the
    /// measured average — would leave twenty-two bubbles in the thread and
    /// bury every other conversation the two people were having. With it,
    /// a match is one bubble that updates.
    ///
    /// `MSSession()` is only created when there is nothing to continue,
    /// which is the first turn of a new match.
    static func message<State: Codable & Equatable>(
        game: String,
        version: Int,
        seed: UInt64,
        match: TurnMatch,
        state: State,
        caption: String,
        subcaption: String? = nil,
        continuing selected: MSMessage?
    ) throws -> MSMessage {
        let url = try GameTransport.send(game: game, version: version,
                                         seed: seed, match: match, state: state)

        let layout = MSMessageTemplateLayout()
        layout.caption = caption
        layout.subcaption = subcaption
        // No image and no trailing captions. The template draws a generic
        // placeholder when `image` is nil, which is plainer than the
        // alternative of shipping a second icon set at sizes Messages
        // decides; the game's own artwork is one tap away and the caption
        // is what gets read in a notification.

        let message = MSMessage(session: selected?.session ?? MSSession())
        message.url = url
        message.layout = layout
        // A summary is what VoiceOver reads and what appears in the
        // notification when the thread is not open, so it says who is
        // waiting rather than repeating the caption.
        message.summaryText = subcaption ?? caption
        return message
    }

    // MARK: - Receiving

    /// What game a received message carries, without committing to a type.
    ///
    /// Throws rather than returning nil so the caller can tell "not one of
    /// ours" (`notAGamePayload` — somebody shared a link) from a game this
    /// build does not have, which deserves a different thing on screen.
    static func header(from message: MSMessage?) throws -> GameEnvelopeHeader {
        guard let url = message?.url else {
            throw GamePayloadError.notAGamePayload
        }
        return try GameTransport.header(from: url)
    }

    /// Unpacks a received turn, once the game is known.
    static func receive<State: Codable & Equatable>(
        _ type: State.Type,
        from message: MSMessage?,
        expecting game: String,
        supportedVersion: Int
    ) throws -> (seed: UInt64, match: TurnMatch, state: State) {
        guard let url = message?.url else {
            throw GamePayloadError.notAGamePayload
        }
        return try GameTransport.receive(type, from: url,
                                         expecting: game,
                                         supportedVersion: supportedVersion)
    }

    // MARK: - Captions

    /// The caption for a turn that is waiting on somebody.
    ///
    /// Positional names, because that is all there is: Messages hands an
    /// extension opaque per-conversation UUIDs and no names or avatars.
    /// `TurnMatch.displayName(for:)` already decided this for the app and
    /// is reused rather than re-spelled, so the two never drift.
    static func caption(for match: TurnMatch, game: String) -> String {
        if let outcome = match.outcome {
            let names = outcome.winners.map { match.displayName(for: $0) }
            switch names.count {
            case 0:  return "\(game) — over"
            case 1:  return "\(game) — \(names[0]) wins"
            default: return "\(game) — draw"
            }
        }
        return "\(game) — \(match.activeDisplayName)'s turn"
    }

    /// The second line: where the match is, in as few words as carry.
    static func subcaption(for match: TurnMatch, totalRounds: Int?) -> String {
        if match.isOver { return "Tap to see the result" }
        if let totalRounds {
            return "Round \(min(match.round, totalRounds)) of \(totalRounds)"
        }
        return "Round \(match.round)"
    }
}
