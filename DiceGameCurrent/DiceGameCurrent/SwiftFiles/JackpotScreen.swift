import SwiftUI

struct JackpotScreen: View {

    var onExit: (() -> Void)? = nil

    @State private var match = TurnMatch.localTwoPlayer()
    @State private var session: DiceTraySession?
    @State private var phase: Phase = .ready
    @State private var lastSummary: String?
    @State private var showingSettings = false
    @ObservedObject private var theme = AppTheme.shared

    /// Jackpots within the current round, by participant.
    ///
    /// Held until the round completes rather than resolved on the spot,
    /// because of the Equalizer: a Jackpot only wins once the opponent has
    /// had their turn in that same round, and two in one round cancel.
    @State private var jackpotsThisRound: [String] = []


    // MARK: Sending a turn

    /// This screen's turn, packed the way the Messages extension will send
    /// it — the bookkeeping and the game's own state together, which is
    /// what MatchPayload exists to say.
    ///
    /// Assembled from the screen's own properties rather than the screen
    /// being rebuilt around the state type. The dice mid-turn are not in
    /// here on purpose: a turn is resolved on the device that threw it and
    /// arrives as a result.
    var wireTurn: MatchPayload<JackpotState> {
        MatchPayload(match: match, state: JackpotState(jackpotsThisRound: jackpotsThisRound))
    }

    /// Adopts a turn that arrived from another device.
    ///
    /// Phase goes back to `.ready` rather than being carried: a phase is
    /// what THIS device is doing with the dice in front of it, and the
    /// sender's is meaningless here.
    func adopt(_ incoming: MatchPayload<JackpotState>) {
        match = incoming.match
        jackpotsThisRound = incoming.state.jackpotsThisRound
        phase = .ready
    }

    private enum Phase {
        /// Waiting for the active player to roll.
        case ready
        /// Dice in the air.
        case rolling
        /// Roll scored; waiting to send the turn on or finish.
        case scored
        /// Handover gate between turns.
        case handover
        /// Match decided.
        case finished
    }

    var body: some View {
        ZStack {
            GeometryReader { geo in
                // Same three-band split as Rolls and Free Roll, so the
                // playfield stays square: the scene's world bounds are
                // derived from this view's measured aspect ratio.
                // The split every game makes, made once — see
                // GameBandLayout. The button band's floor is summed from
                // what it holds rather than typed as 100.
                let bands = GameBandLayout.self
                let headerHeight = bands.header(in: geo.size, fraction: 0.17)
                let sceneHeight = bands.scene(in: geo.size, fraction: 0.17)
                let buttonHeight = bands.buttonBand(in: geo.size, fraction: 0.17)

                VStack(spacing: 0) {
                    MatchScoreboard(
                        match: match,
                        totalRounds: JackpotRules.roundsPerPlayer,
                        subtitle: scoreboardSubtitle
                    )
                    .frame(height: headerHeight)

                    DiceTraySceneView(
                        session: $session,
                        makeInitialDice: { JackpotRules.makeDice() },
                        // The d4 carries each face's number at all three of
                        // its corners, so the three visible faces read as
                        // three different numbers — which is what this game
                        // scores. Free Roll's top-read d4 would give one.
                        d4Style: .faceNumbers,
                        floorTitle: JackpotGame.floorTitle,
                        arenaStyle: .house,
                        onSessionCreated: { newSession in
                            newSession.onRollSettled = { results in
                                scoreRoll(results)
                            }
                        }
                    )
                    .rollingWell(height: sceneHeight)
                    .overlay(alignment: .topLeading) {
                        if let onExit {
                            OverlayChromeButton(systemName: "chevron.left") { onExit() }
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        OverlayChromeButton(systemName: "gearshape.fill") {
                            showingSettings = true
                        }
                    }

                    DiceRollButton(
                        label: buttonLabel,
                        isEnabled: isPrimaryEnabled,
                        subtitle: buttonSubtitle
                    ) {
                        primaryAction()
                    }
                    .frame(height: buttonHeight)
                }
            }

            if phase == .handover {
                HandoverGate(match: match, lastTurnSummary: lastSummary) {
                    phase = .ready
                }
                .transition(.opacity)
            }

            if phase == .finished {
                MatchResultView(
                    match: match,
                    onPlayAgain: { startNewMatch() },
                    onExit: { onExit?() }
                )
                .transition(.opacity)
            }
        }
        .textCase(.uppercase)
        .dynamicTypeSize(.large)
        .ignoresSafeArea(.keyboard)
        .sheet(isPresented: $showingSettings) {
            SettingsView(for: JackpotGame.self)
        }
        .onAppear {
            AppFonts.registerIfNeeded()
            SoundEngine.shared.startMusic()
        }
        .onValueChange(of: theme.colorwayIndex) { _ in
            session?.applyTheme()
        }
    }

    // MARK: Button

    private var buttonLabel: String {
        switch phase {
        case .ready:    return "Roll"
        case .rolling:  return "Rolling"
        case .scored:   return isFinalTurn ? "Finish" : "Pass"
        case .handover: return "Pass"
        case .finished: return "Done"
        }
    }

    private var buttonSubtitle: String {
        guard phase == .scored, let lastSummary else { return "" }
        return lastSummary
    }

    /// True when the turn just scored was the last one of the last round.
    ///
    /// `match.isOver` cannot answer this: the match is only finished inside
    /// endTurn(), which this button is what triggers, so at .scored it is
    /// always still false and the label read "Pass" on the final turn.
    private var isFinalTurn: Bool {
        match.round >= JackpotRules.roundsPerPlayer && match.activeIsLastInRound
    }

    private var scoreboardSubtitle: String? {
        switch phase {
        case .ready:   return "\(match.activeDisplayName) to roll"
        case .rolling: return "Rolling…"
        default:       return nil
        }
    }

    /// The scene assembles only once the view has real bounds, so `session`
    /// is nil for the first moments on screen. Requiring it here is what
    /// stops a tap in that window flipping the game into a rolling phase
    /// that nothing will ever move it out of.
    private var isPrimaryEnabled: Bool {
        switch phase {
        case .ready:  return session != nil
        case .scored: return true
        default:      return false
        }
    }

    private func primaryAction() {
        switch phase {
        case .ready:
            // Phase follows the roll rather than leading it. roll() reports
            // false when it did not throw anything, and moving first meant
            // a no-op left the game stuck.
            if session?.roll() == true {
                phase = .rolling
            }
        case .scored:
            endTurn()
        default:
            break
        }
    }

    // MARK: Turn flow

    private func scoreRoll(_ results: [DiceTraySession.DieResult]) {
        // Score only a complete set. numbers(from:) happily turns four dice
        // into five numbers, and a quietly wrong score is a far worse
        // failure than an obvious one — fewer numbers means fewer possible
        // sets, so the total would just read low with nothing to show for
        // it. No known path drops a die (force-settled dice report through
        // the same callback), so this should never fire; if it does, the
        // player simply rolls again.
        guard results.map(\.sides).sorted() == JackpotRules.dieSides.sorted() else {
            phase = .ready
            return
        }

        let numbers = JackpotRules.numbers(from: results)
        let score = JackpotRules.score(
            numbers: numbers,
            d20: JackpotRules.d20Face(from: results)
        )

        let player = match.activeDisplayName
        if score.isJackpot {
            jackpotsThisRound.append(match.activeParticipant)
        } else {
            match.addScore(score.total)
        }
        lastSummary = JackpotRules.summary(for: score, player: player)
        phase = .scored
    }

    /// Hands over, and resolves the round if this was the last seat in it.
    private func endTurn() {
        let wasLastInRound = match.activeIsLastInRound
        let finishedRound = match.round

        match.advanceTurn()

        if wasLastInRound {
            // The Equalizer resolves here, not when the Jackpot was rolled:
            // everyone has now had their turn in that round.
            if let winners = JackpotRules.jackpotWinners(jackpotsThisRound) {
                match.finish(
                    winners: winners,
                    reason: "Jackpot in round \(finishedRound)."
                )
                phase = .finished
                return
            }
            // Two jackpots in the same round cancel each other; play goes on.
            jackpotsThisRound.removeAll()

            if finishedRound >= JackpotRules.roundsPerPlayer {
                match.finish(lowestScoreWins: JackpotGame.lowestScoreWins)
                phase = .finished
                return
            }
        }

        phase = .handover
    }

    private func startNewMatch() {
        match = TurnMatch.localTwoPlayer()
        jackpotsThisRound.removeAll()
        lastSummary = nil
        session?.setPool(JackpotRules.makeDice())
        phase = .ready
    }

    // MARK: Chrome

}
