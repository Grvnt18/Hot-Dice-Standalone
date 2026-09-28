import SwiftUI

struct FreighterYachtDinghyScreen: View {

    var onExit: (() -> Void)? = nil

    @State private var match = TurnMatch.localTwoPlayer()
    @State private var session: DiceTraySession?
    @State private var turn = FreighterYachtDinghyRules.Turn()
    @State private var phase: Phase = .ready
    @State private var lastSummary: String?
    @State private var showingSettings = false

    /// Normally three. A tie at the end pushes this out by one and the
    /// match plays a sudden-death round — which happens about 1 game in 20,
    /// often enough to need handling and rare enough to stay a moment.
    @State private var roundsThisMatch = FreighterYachtDinghyRules.roundsPerPlayer

    @ObservedObject private var theme = AppTheme.shared

    private enum Phase {
        /// Waiting for the active player to throw.
        case ready
        /// Dice in the air.
        case rolling
        /// Qualified with rolls left: rethrow the cargo, or sail.
        case decide
        /// Turn over; waiting to hand over or finish.
        case scored
        /// Handover gate between turns.
        case handover
        /// Match decided.
        case finished
    }

    var body: some View {
        ZStack {
            GeometryReader { geo in
                // The same three-band split every game in the suite uses:
                // the scene is square because its world bounds come from
                // this view's measured aspect ratio.
                let headerHeight = geo.size.height * 0.17
                let minButtonHeight: CGFloat = 100
                let sceneHeight = min(geo.size.width, max(geo.size.height - headerHeight - minButtonHeight, 0))
                let buttonHeight = geo.size.height - headerHeight - sceneHeight

                VStack(spacing: 0) {
                    MatchScoreboard(
                        match: match,
                        totalRounds: roundsThisMatch,
                        subtitle: scoreboardSubtitle
                    )
                    .frame(height: headerHeight)

                    DiceTraySceneView(
                        session: $session,
                        makeInitialDice: { FreighterYachtDinghyRules.makeDice() },
                        floorTitle: FreighterYachtDinghyGame.floorTitle,
                        arenaStyle: .house,
                        onSessionCreated: { newSession in
                            newSession.onRollSettled = { results in
                                applyRoll(results)
                            }
                        }
                    )
                    .frame(height: sceneHeight)
                    .background(Color.black)
                    .overlay(alignment: .topLeading) {
                        if let onExit {
                            overlayButton(systemName: "chevron.left") { onExit() }
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        overlayButton(systemName: "gearshape.fill") {
                            showingSettings = true
                        }
                    }

                    TurnActionBar(
                        primaryLabel: primaryLabel,
                        primaryEnabled: isPrimaryEnabled,
                        secondaryLabel: phase == .decide ? "Set Sail" : nil,
                        subtitle: subtitle,
                        onPrimary: { primaryAction() },
                        onSecondary: { setSail() }
                    )
                    .frame(height: buttonHeight)
                }
            }

            if phase == .handover {
                HandoverGate(match: match, lastTurnSummary: lastSummary) {
                    beginTurn()
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
            SettingsView(for: FreighterYachtDinghyGame.self)
        }
        .onAppear {
            AppFonts.registerIfNeeded()
            SoundEngine.shared.startMusic()
        }
        .onChange(of: theme.colorwayIndex) { _, _ in
            session?.applyTheme()
        }
    }

    // MARK: Button

    private var primaryLabel: String {
        switch phase {
        case .ready:    return turn.rollsUsed == 0 ? "Roll" : "Roll Again"
        case .rolling:  return "Rolling"
        case .decide:   return "Reroll Cargo"
        case .scored:   return isFinalTurn ? "Finish" : "Pass"
        case .handover: return "Pass"
        case .finished: return "Done"
        }
    }

    private var subtitle: String {
        switch phase {
        case .ready:
            guard turn.rollsUsed > 0 else { return "" }
            let left = turn.rollsRemaining
            let needs = FreighterYachtDinghyRules.needed(after: turn) ?? ""
            return "Looking for a \(needs) — \(left) roll\(left == 1 ? "" : "s") left"
        case .decide:
            let total = turn.score
            let left = turn.rollsRemaining
            return "Cargo \(total) — \(left) roll\(left == 1 ? "" : "s") left"
        case .scored:
            return lastSummary ?? ""
        default:
            return ""
        }
    }

    /// True when the turn just scored was the last one of the last round.
    /// `match.isOver` cannot answer this — the match only finishes inside
    /// endTurn(), which this button is what triggers.
    private var isFinalTurn: Bool {
        match.round >= roundsThisMatch && match.activeIsLastInRound
    }

    private var scoreboardSubtitle: String? {
        switch phase {
        case .ready:   return "\(match.activeDisplayName) to roll"
        case .rolling: return "Rolling…"
        // Built from qualifierNames rather than spelling them out. This
        // line said "Ship, Captain, Crew" for four phases after the rename,
        // because a hardcoded list has nothing tying it to the game.
        case .decide:
            return "\(match.activeDisplayName) — "
                + FreighterYachtDinghyRules.qualifierNames.joined(separator: ", ")
        default:       return nil
        }
    }

    /// The scene assembles only once the view has real bounds, so `session`
    /// is nil for the first moments on screen — rolling is gated on it for
    /// the same reason Jackpot gates it.
    private var isPrimaryEnabled: Bool {
        switch phase {
        case .ready, .decide: return session != nil
        case .scored:         return true
        default:              return false
        }
    }

    private func primaryAction() {
        SoundEngine.shared.play(.buttonTap)
        switch phase {
        case .ready, .decide:
            // Phase follows the roll rather than leading it: roll() reports
            // false when it threw nothing, and moving first meant a no-op
            // left the game stuck in a phase nothing could leave.
            if session?.roll(keeping: turn.keptIDs) == true {
                phase = .rolling
            }
        case .scored:
            endTurn()
        default:
            break
        }
    }

    // MARK: Turn flow

    /// Folds a settled roll in and decides what the turn does next.
    private func applyRoll(_ results: [DiceTraySession.DieResult]) {
        // Score only a full hand. Kept dice report at their retained faces,
        // so this is five every time; anything less would silently cost the
        // player a qualifier they actually rolled.
        guard results.count == FreighterYachtDinghyRules.diceCount else {
            // No known path drops a die, so this should never fire. If it
            // does, hand the throw back rather than claiming off a hand we
            // cannot trust — the roll is not counted, because apply() is
            // what advances rollsUsed and it has not run.
            phase = .ready
            return
        }

        turn.apply(results)

        if turn.isQualified && !turn.isOutOfRolls {
            phase = .decide
        } else if turn.isQualified || turn.isOutOfRolls {
            settleTurn()
        } else {
            phase = .ready
        }
    }

    /// Takes the cargo as it stands and ends the turn.
    private func setSail() {
        SoundEngine.shared.play(.buttonTap)
        guard phase == .decide else { return }
        settleTurn()
    }

    /// Banks the turn's points. The one place the score is added, so no
    /// path through .decide can add it twice.
    private func settleTurn() {
        match.addScore(turn.score)
        lastSummary = FreighterYachtDinghyRules.summary(for: turn, player: match.activeDisplayName)
        phase = .scored
    }

    /// Hands over, and resolves the match if this completed the last round.
    private func endTurn() {
        let wasLastInRound = match.activeIsLastInRound
        let finishedRound = match.round

        match.advanceTurn()

        if wasLastInRound && finishedRound >= roundsThisMatch {
            if isTied {
                // Sudden death: one more round each, decided the same way.
                roundsThisMatch += 1
            } else {
                match.finish(lowestScoreWins: FreighterYachtDinghyGame.lowestScoreWins)
                phase = .finished
                return
            }
        }

        phase = .handover
    }

    /// True when more than one participant is on the leading total.
    private var isTied: Bool {
        let totals = match.participants.map { match.score(for: $0) }
        guard let best = totals.max() else { return false }
        return totals.filter { $0 == best }.count > 1
    }

    /// Clears the dice the previous player kept and starts a fresh turn.
    private func beginTurn() {
        turn = FreighterYachtDinghyRules.Turn()
        session?.beginTurn()
        phase = .ready
    }

    private func startNewMatch() {
        match = TurnMatch.localTwoPlayer()
        roundsThisMatch = FreighterYachtDinghyRules.roundsPerPlayer
        lastSummary = nil
        session?.setPool(FreighterYachtDinghyRules.makeDice())
        beginTurn()
    }

    // MARK: Chrome

    private func overlayButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button {
            SoundEngine.shared.play(.buttonTap)
            action()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: systemName == "chevron.left" ? .semibold : .regular))
                .foregroundStyle(.white.opacity(0.75))
                .padding(9)
                .background(
                    Color.black.opacity(0.45),
                    in: RoundedRectangle(cornerRadius: ControlShape.cornerRadius)
                )
        }
        .padding(10)
    }
}
