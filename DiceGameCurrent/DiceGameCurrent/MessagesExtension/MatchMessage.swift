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

    /// Which bubble a message belongs to.
    ///
    /// **One match is one bubble, and this is what decides it.** An
    /// `MSMessage` built with another message's `MSSession` REPLACES that
    /// bubble in the transcript rather than adding one; built with a fresh
    /// session it starts a bubble of its own.
    ///
    /// Both halves matter, in opposite directions. Continuing is what keeps
    /// a Royal UR match — 21.9 messages at the measured average — from
    /// leaving twenty-two bubbles in the thread and burying every other
    /// conversation the two people were having. Starting fresh is what lets
    /// a player open a second game without finishing the first: pick it
    /// from the menu, send it, and it is its own chain in the same thread.
    ///
    /// Spelled as a choice rather than an optional `MSMessage?`, because
    /// the two are a sentence apart and the wrong one is silent: passing
    /// the selected message while starting a NEW match would mint the new
    /// game into the old game's session and the first match would vanish
    /// from the thread.
    enum Chain {
        /// Its own bubble. The first message of a match.
        case new
        /// Updates the bubble this message came from.
        case continuing(MSMessage)
    }

    /// Packs a turn into a message ready to insert into the conversation.
    static func message<State: Codable & Equatable>(
        game: String,
        version: Int,
        seed: UInt64,
        match: TurnMatch,
        state: State,
        caption: String,
        subcaption: String? = nil,
        chain: Chain
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

        let session: MSSession
        switch chain {
        case .new:                  session = MSSession()
        case .continuing(let from): session = from.session ?? MSSession()
        }

        let message = MSMessage(session: session)
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
