import SwiftUI
import Messages

/// Rolls, in a conversation.
///
/// Rolls first because it is the one game whose state was designed for a
/// thread rather than adapted to one: no turn order, keyed by participant,
/// a `startedBy` who can close it, and an `isClosed` so a late arrival
/// sees a result rather than an invitation. `RollsPayload.swift`'s own
/// comments describe a group chat; this is that.
///
/// **It is also why "whose turn is it" is the wrong question here.** Every
/// other game in the suite alternates, and `MessagesSeating.isLocalTurn`
/// answers it. Rolls has one round each, taken in any order, so the gate
/// is "have I rolled yet" — `state.results[localID]`. The `TurnMatch`
/// still travels, because the scores and the outcome live on it, but its
/// `activeIndex` is not what decides anything.
struct MessagesRollsHost: View {

    @ObservedObject var store: MessagesStore

    /// Nil until the conversation has been read. Built once, in `onAppear`,
    /// rather than recomputed in `body`: a new match mints a random seed,
    /// and a seed that changes on every redraw is a different deal every
    /// frame.
    @State private var game: LoadedGame?
    @State private var problem: String?

    /// A match in progress: what travelled, plus the roster it travelled
    /// with.
    struct LoadedGame {
        var seed: UInt64
        var match: TurnMatch
        var state: RollsGameState
    }

    var body: some View {
        content
            .onAppear(perform: load)
            // A turn can arrive while this screen is open: didReceive and
            // didSelect both update the store, and onAppear does not fire
            // again when SwiftUI reuses the view. Without this, a received
            // turn leaves the board showing the state it was opened with.
            //
            // Keyed on the message's URL rather than the message itself:
            // MSMessage is a reference type and not Equatable, so it cannot
            // be watched directly — and the URL is where the turn actually
            // lives, so a different turn is a different string. See
            // MessagesStore.selectedKey.
            .onValueChange(of: store.selectedKey) { _ in reload() }
            // And the first read, if the conversation arrived after this
            // view did. Guarded on `game == nil` rather than reloading:
            // `willBecomeActive` fires again every time the extension is
            // brought forward, and a reload there would throw away a round
            // the player is part way through.
            .onValueChange(of: store.isReady) { ready in
                if ready, game == nil { load() }
            }
    }

    @ViewBuilder
    private var content: some View {
        if let problem {
            MessagesProblemView(message: problem)
        } else if let game {
            loaded(game)
        } else {
            // One frame, between appearing and reading the conversation.
            Color.clear
        }
    }

    @ViewBuilder
    private func loaded(_ game: LoadedGame) -> some View {
        // Standings, not a board, for anyone who cannot or need not roll.
        //
        // `isSeated` is the one that was missing. Somebody added to the
        // thread after the match began is not in `participants`, so
        // `hasRolled` is false for them and the old condition handed them
        // the board: they could roll, and `send` would write a result and a
        // score under an id the match does not contain. Worse than a stray
        // score — `results.count >= participants.count` could then close the
        // game while a real player still had a turn to take.
        if !MessagesSeating.isSeated(game.match, in: store.conversation)
            || hasRolled(game) || game.state.isClosed {
            MessagesRollsStandings(game: game,
                                   localID: localID,
                                   // Bug: this used to be offered to
                                   // everyone, and `close` silently returns
                                   // for anyone but the starter — so every
                                   // participant saw a button that did
                                   // nothing. Only the starter can close a
                                   // game, so only the starter is shown it.
                                   onClose: canClose(game) ? close : nil)
        } else {
            // The app's own Rolls screen, unchanged, with the seed the
            // match was dealt from. `onExit` stays nil: Messages supplies
            // its own dismissal, which DiceGameScreen's comment on that
            // property already anticipated.
            DiceGameScreen(onRoundFinished: { result in
                send(result, in: game)
            }, seed: game.seed)
        }
    }

    // MARK: - Reading the conversation

    private var localID: String {
        guard let conversation = store.conversation else { return "" }
        return MessagesSeating.localID(in: conversation)
    }

    private func hasRolled(_ game: LoadedGame) -> Bool {
        game.state.results[localID] != nil
    }

    /// Whether this device may close the game early.
    ///
    /// The starter, and only while it is still open. Stated once so the
    /// button and the action cannot disagree — which is exactly how the
    /// button came to be shown to people it did nothing for.
    private func canClose(_ game: LoadedGame) -> Bool {
        !game.state.isClosed && game.state.startedBy == localID
    }

    /// Re-reads after the selected message changes.
    ///
    /// Drops what was loaded first, so a received turn cannot be merged into
    /// a half-finished local one — and so a stale `problem` from a message
    /// that would not decode does not outlive it.
    private func reload() {
        game = nil
        load()
    }

    /// Decodes the tapped message, or starts a match.
    private func load() {
        // Cleared first, so a `problem` left by an earlier attempt cannot
        // outlive the attempt that succeeds — `content` tests `problem`
        // before `game`, so a stale one hides a perfectly good board.
        problem = nil

        guard let conversation = store.conversation else {
            problem = "This needs to run inside a conversation."
            return
        }

        if store.selected != nil {
            loadReceived()
            return
        }

        // A new match. `RollsGame.maxPlayers` is `Int.max` — true about the
        // rules, since a single round has no turn order — so the ceiling
        // that applies here is the WIRE's, not the game's. See
        // RollsGameState.maxSeatsOnTheWire: a fifteen-seat game sends
        // fourteen turns fine and fails on the one that completes it.
        guard let match = MessagesSeating.newMatch(
            in: conversation,
            maxPlayers: RollsGameState.maxSeatsOnTheWire
        ) else {
            let seats = MessagesSeating.roster(in: conversation).count
            problem = seats < 2
                ? "Rolls needs at least two people in the conversation."
                : "This conversation has \(seats) people. Rolls fits "
                  + "\(RollsGameState.maxSeatsOnTheWire) in one game — "
                  + "any more and the last turn is too big to send."
            return
        }
        let me = MessagesSeating.localID(in: conversation)
        game = LoadedGame(seed: SeededGenerator.newSeed(),
                          match: match,
                          state: RollsGameState(startedBy: me))
    }

    private func loadReceived() {
        do {
            let turn = try MatchMessage.receive(
                RollsGameState.self,
                from: store.selected,
                expecting: RollsGameState.gameID,
                supportedVersion: RollsGameState.schemaVersion
            )
            game = LoadedGame(seed: turn.seed, match: turn.match, state: turn.state)
        } catch {
            // `GamePayloadError`'s descriptions are written for a player —
            // an unknown game and a newer schema both say what to do — so
            // they are shown rather than replaced.
            problem = "\(error)"
        }
    }

    // MARK: - Sending

    /// Adds this device's round to the state and sends it on.
    private func send(_ result: RollsPlayerResult, in game: LoadedGame) {
        var next = game

        // Validated before it travels, not after it arrives. The check
        // cannot prove the dice landed this way — physics is not
        // replayable, and `RollsPayload.swift` says so — but it catches a
        // wrong die count, a bank order that repeats or omits one, a face
        // that die could not show, and a total that disagrees with its own
        // dice. Catching that here means the bug is this device's to
        // report rather than the recipient's to puzzle over.
        do {
            try result.validate(againstSeed: game.seed)
        } catch {
            problem = "That round didn't add up: \(error)"
            return
        }

        next.state.results[localID] = result
        next.match.scores[localID] = result.score

        // Everyone seated has rolled, so the match is decided. Golf-scored
        // — `RollsGame.lowestScoreWins` is true, and `finish` takes the
        // direction explicitly rather than assuming, which is the mistake
        // TurnCompleteOverlay made when it was written for Rolls alone.
        if next.state.results.count >= next.match.participants.count {
            next.state.isClosed = true
            next.match.finish(lowestScoreWins: RollsGame.lowestScoreWins)
        }

        self.game = next
        insert(next)
    }

    /// The starter closing the game early.
    ///
    /// A group game cannot rely on everyone playing — people join and
    /// leave a thread, and someone may simply never open the message — so
    /// waiting for every participant would hang it forever. Whoever has
    /// rolled is who counts.
    private func close() {
        guard var next = game, canClose(next) else { return }
        next.state.isClosed = true
        next.match.finish(lowestScoreWins: RollsGame.lowestScoreWins)
        self.game = next
        insert(next)
    }

    private func insert(_ game: LoadedGame) {
        do {
            let message = try MatchMessage.message(
                game: RollsGameState.gameID,
                version: RollsGameState.schemaVersion,
                seed: game.seed,
                match: game.match,
                state: game.state,
                caption: caption(for: game),
                subcaption: subcaption(for: game),
                continuing: store.selected
            )
            store.send(message)
        } catch {
            problem = "That turn couldn't be packed: \(error)"
        }
    }

    // MARK: - Captions

    /// Rolls' own caption, rather than `MatchMessage.caption`.
    ///
    /// That one names whose turn it is, which Rolls does not have. What a
    /// participant wants to know from the transcript is whether the game is
    /// still open and how many people are still to roll.
    private func caption(for game: LoadedGame) -> String {
        if game.match.isOver {
            return MatchMessage.caption(for: game.match, game: "Rolls")
        }
        return "Rolls — your roll"
    }

    private func subcaption(for game: LoadedGame) -> String {
        if game.state.isClosed { return "Tap to see the result" }
        let waiting = game.match.participants.count - game.state.results.count
        if waiting == 1 { return "1 player still to roll" }
        return "\(waiting) players still to roll"
    }
}

// MARK: - Standings

/// Who has rolled, and what they scored.
///
/// Positional names, because that is all Messages offers — opaque
/// per-conversation UUIDs, no names and no avatars. The real attribution
/// comes free in the thread: each turn is its own bubble under the sender's
/// name. `TurnMatch.displayName(for:)` already made this call for the app
/// and is reused rather than re-spelled.
struct MessagesRollsStandings: View {

    let game: MessagesRollsHost.LoadedGame
    let localID: String
    /// Nil unless this device is the starter and the game is still open.
    let onClose: (() -> Void)?

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                // ScriptText, not Font.lobster — that face and its
                // PostScript name are fileprivate precisely so a new
                // screen cannot start from the raw font and rediscover
                // the clipped-terminal-glyph bug. See AppFonts.
                ScriptText(heading, size: 30)
                    .foregroundStyle(.white)
                    .padding(.top, 14)

                ForEach(rolled, id: \.self) { participant in
                    row(participant)
                }

                if let onClose {
                    closeButton(onClose)
                }
            }
            .padding(14)
        }
    }

    private var heading: String {
        game.state.isClosed ? "Final" : "Standings"
    }

    /// Lowest first — Rolls is golf-scored, so the smallest total leads.
    private var rolled: [String] {
        game.state.results.keys.sorted {
            (game.state.results[$0]?.score ?? 0) < (game.state.results[$1]?.score ?? 0)
        }
    }

    private func row(_ participant: String) -> some View {
        HStack {
            Text(game.match.displayName(for: participant)
                 + (participant == localID ? " (you)" : ""))
                .font(.poppins(13))
            Spacer()
            Text("\(game.state.results[participant]?.score ?? 0)")
                .font(.poppins(20, .semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .pixelWell(radius: ControlShape.cornerRadius)
    }

    private func closeButton(_ action: @escaping () -> Void) -> some View {
        Button {
            SoundEngine.shared.play(.buttonTap)
            action()
        } label: {
            Text("CLOSE THE GAME")
                .font(.poppins(13, .semibold))
                .foregroundStyle(AppTheme.shared.accentTextColor)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .pixelPanel(fill: .solid(AppTheme.shared.accentColor),
                            elevation: .lifted)
        }
        .buttonStyle(.plain)
        .padding(.top, 8)
    }
}

// MARK: - Problems

/// Something the player needs told, in words they can act on.
struct MessagesProblemView: View {

    let message: String

    var body: some View {
        Text(message)
            .font(.poppins(13))
            .multilineTextAlignment(.center)
            .foregroundStyle(.white)
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
