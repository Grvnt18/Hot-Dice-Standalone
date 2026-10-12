import Foundation
import Messages

/// Starting a game: pick it from the menu and it is in the message field.
///
/// **No screen in between.** Picking a game used to mint a match, expand
/// the extension and show an invitation with a Send button — which is one
/// more tap and one more screen than the thing it was imitating. In
/// GamePigeon, tapping a tile stages the message and the player hits send,
/// and that is also the plainest reading of "starting a new game needs to
/// be as easy as selecting it on the menu and sending it".
///
/// So this builds the opening message from the conversation alone, with no
/// view involved. It lives apart from `MessagesRollsHost` because the
/// picker calls it from the compact strip, where no game screen exists yet.
///
/// Every game that becomes playable in a thread adds a case here. The
/// nine that are not yet wired are deliberately absent rather than
/// defaulted: sending a message nobody can open is worse than saying the
/// game is not ready, and `MessagesGameRouter` already says so.
///
/// **Nothing is chosen before sending, and nothing should be.** No
/// difficulty, no match length, no loadout: the opening message carries an
/// empty game and the settings each game needs are taken inside it, before
/// its first roll. Rollbots' weapon and cyberware are per player, so each
/// picks their own on their own first turn.
///
/// Baseball Dice is the one with a shared setting — 3, 6 or 9 innings,
/// `BaseballDiceScreen.Phase.setup`, "before anything else". Note who
/// picks it: the recipient is player 1 and takes the first turn, so THEY
/// choose the length, not whoever started the game. That is fine, and it
/// carries one requirement for whoever wires Baseball up — the length is
/// already in `BaseballDiceState` and travels with the match, so the
/// second player must be dropped past the setup phase rather than shown
/// the picker again. A game that asks both players how long it is would
/// have two answers and no way to choose between them.
enum MessagesInvite {

    /// Whether picking this game sends an invitation straight away.
    ///
    /// False for the nine that cannot be played in a conversation yet, so
    /// the picker expands to the "not playable here" screen instead of
    /// putting an unopenable message in somebody's thread.
    static func canStart(_ gameID: String) -> Bool {
        gameID == RollsGameState.gameID
    }

    /// Builds and inserts the opening message.
    ///
    /// Returns nil on success, or a sentence to show the player: a thread
    /// too small or too large to seat the game, or an encoding failure.
    /// Returned rather than thrown because every caller does the same
    /// thing with it — puts it on screen — and `GamePayloadError`'s own
    /// descriptions are already written for a player to read.
    @discardableResult
    static func start(_ gameID: String, in store: MessagesStore) -> String? {
        guard let conversation = store.conversation else {
            return "This needs to run inside a conversation."
        }
        guard gameID == RollsGameState.gameID else {
            // Unreachable while `canStart` gates the call, and a sentence
            // rather than a crash if that ever stops being true.
            return "That game isn't playable in Messages yet."
        }
        return startRolls(in: conversation, store: store)
    }

    // MARK: - Rolls

    private static func startRolls(in conversation: MSConversation,
                                   store: MessagesStore) -> String? {
        // `RollsGame.maxPlayers` is `Int.max` — true about the rules, since
        // a single round has no turn order — so the ceiling that applies is
        // the WIRE's. See RollsGameState.maxSeatsOnTheWire: a fifteen-seat
        // game sends fourteen turns fine and fails on the one that
        // completes it.
        guard let match = MessagesSeating.newMatch(
            in: conversation,
            maxPlayers: RollsGameState.maxSeatsOnTheWire
        ) else {
            let seats = MessagesSeating.roster(in: conversation).count
            return seats < 2
                ? "Rolls needs at least two people in the conversation."
                : "This conversation has \(seats) people. Rolls fits "
                  + "\(RollsGameState.maxSeatsOnTheWire) in one game — any "
                  + "more and the last turn is too big to send."
        }

        // The starter does not roll. They are player 2 and move second —
        // see MessagesSeating.roster — so the opening message carries an
        // empty game and player 1 takes the first turn.
        let state = RollsGameState(
            startedBy: MessagesSeating.localID(in: conversation)
        )

        do {
            let message = try MatchMessage.message(
                game: RollsGameState.gameID,
                version: RollsGameState.schemaVersion,
                seed: SeededGenerator.newSeed(),
                match: match,
                state: state,
                caption: "Let's play Rolls!",
                subcaption: RollsGame.tagline,
                // Its own bubble. An opening message that continued the
                // selected one would replace whatever match was already in
                // the thread.
                chain: .new
            )
            store.send(message)
            return nil
        } catch {
            return "That game couldn't be packed: \(error)"
        }
    }
}
