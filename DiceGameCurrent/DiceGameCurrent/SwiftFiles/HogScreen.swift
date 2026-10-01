import SwiftUI

struct HogScreen: View {

    var onExit: (() -> Void)? = nil

    @State private var match = TurnMatch.localTwoPlayer()
    @State private var session: DiceTraySession?
    @State private var turnTotal = 0
    @State private var phase: Phase = .ready
    @State private var lastSummary: String?
    @State private var showingSettings = false
    @ObservedObject private var theme = AppTheme.shared

    private enum Phase {
        /// Waiting for the active player to throw.
        case ready
        /// The die is in the air.
        case rolling
        /// A face is up and it was not a 1: roll on, or hold.
        case decide
        /// Turn over; waiting to hand over.
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
                        // HOG is a race, not a fixed number of rounds, so
                        // there is no "round 3 of 5" to show. The strip
                        // already treats that as nil.
                        match: match,
                        totalRounds: nil,
                        subtitle: scoreboardSubtitle
                    )
                    .frame(height: headerHeight)

                    DiceTraySceneView(
                        session: $session,
                        makeInitialDice: { HogRules.makeDice() },
                        floorTitle: HogGame.floorTitle,
                        arenaStyle: .house,
                        onSessionCreated: { newSession in
                            newSession.onRollSettled = { results in
                                applyRoll(results)
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

                    TurnActionBar(
                        primaryLabel: primaryLabel,
                        primaryEnabled: isPrimaryEnabled,
                        secondaryLabel: phase == .decide ? holdLabel : nil,
                        subtitle: subtitle,
                        onPrimary: { primaryAction() },
                        onSecondary: { hold() }
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
            SettingsView(for: HogGame.self)
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
        case .ready:    return "Roll"
        case .rolling:  return "Rolling"
        case .decide:   return "Roll Again"
        case .scored:   return "Pass"
        case .handover: return "Pass"
        case .finished: return "Done"
        }
    }

    /// Says what holding is worth, because that is the whole decision.
    private var holdLabel: String {
        wouldWin ? "Hold & Win" : "Hold \(turnTotal)"
    }

    /// True when banking right now reaches the target.
    private var wouldWin: Bool {
        match.score(for: match.activeParticipant) + turnTotal >= HogRules.target
    }

    private var subtitle: String {
        switch phase {
        case .decide:
            let banked = match.score(for: match.activeParticipant)
            if wouldWin { return "Hold now and it's over" }
            return "Hold and you're on \(banked + turnTotal) — \(HogRules.target - banked - turnTotal) to go"
        case .scored:
            return lastSummary ?? ""
        default:
            return ""
        }
    }

    private var scoreboardSubtitle: String? {
        switch phase {
        case .ready:   return "\(match.activeDisplayName) to roll"
        case .rolling: return "Rolling…"
        case .decide:  return "Turn \(turnTotal) — not yours yet"
        default:       return nil
        }
    }

    /// The scene assembles only once the view has real bounds, so `session`
    /// is nil for the first moments on screen — rolling is gated on it for
    /// the same reason Jackpot gates it.
    private var isPrimaryEnabled: Bool {
        switch phase {
        case .ready:          return session != nil
        case .decide, .scored: return true
        default:              return false
        }
    }

    private func primaryAction() {
        SoundEngine.shared.play(.buttonTap)
        switch phase {
        case .ready, .decide:
            // Phase follows the roll rather than leading it — roll() reports
            // false when it threw nothing, and moving first meant a no-op
            // left the game stuck in a phase nothing could leave.
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

    private func applyRoll(_ results: [DiceTraySession.DieResult]) {
        // One die, one face. Anything else means the tray reported something
        // this game cannot read, so hand the throw back rather than guessing.
        guard results.count == 1, let face = results.first?.value else {
            phase = .ready
            return
        }

        if face == HogRules.hogFace {
            // The turn total is lost, not the banked score — and nothing is
            // added to the match, which is the whole of the penalty.
            turnTotal = 0
            lastSummary = HogRules.summary(
                player: match.activeDisplayName,
                banked: 0,
                hogged: true
            )
            phase = .scored
            return
        }

        turnTotal += face
        phase = .decide
    }

    /// Banks the turn total, and ends the match if it reaches the target.
    private func hold() {
        SoundEngine.shared.play(.buttonTap)
        guard phase == .decide else { return }

        let player = match.activeDisplayName
        let banked = turnTotal
        match.addScore(banked)
        turnTotal = 0

        if match.score(for: match.activeParticipant) >= HogRules.target {
            // Nobody gets an answering turn, so the holder is necessarily
            // the highest total: everyone else is still short of the target.
            match.finish(lowestScoreWins: HogGame.lowestScoreWins)
            phase = .finished
            return
        }

        lastSummary = HogRules.summary(player: player, banked: banked, hogged: false)
        phase = .scored
    }

    private func endTurn() {
        match.advanceTurn()
        phase = .handover
    }

    private func beginTurn() {
        turnTotal = 0
        session?.beginTurn()
        phase = .ready
    }

    private func startNewMatch() {
        match = TurnMatch.localTwoPlayer()
        lastSummary = nil
        session?.setPool(HogRules.makeDice())
        beginTurn()
    }

    // MARK: Chrome

}
