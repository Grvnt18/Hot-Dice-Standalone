import SwiftUI

struct ThreeThousandScreen: View {

    var onExit: (() -> Void)? = nil

    @State private var match = TurnMatch.localTwoPlayer()
    @State private var session: DiceTraySession?

    /// Points set aside earlier in this turn. Not yours until you bank.
    @State private var turnTotal = 0

    /// The whole hand as it currently reads, locked dice included.
    @State private var hand: [DiceTraySession.DieResult] = []

    /// Mirrors of the session's selection, because a SwiftUI view cannot
    /// observe a plain class — the same reason Generals mirrors its count.
    @State private var selected: Set<UUID> = []
    @State private var locked: Set<UUID> = []

    /// Set once someone banks the target: the number of turns still owed
    /// before the match is decided. See `endTurn`.
    @State private var turnsLeftAfterTarget: Int?

    /// Who reached the target first, which is who a tie goes to.
    @State private var firstToTarget: String?

    @State private var phase: Phase = .ready
    @State private var lastSummary: String?
    @State private var showingSettings = false
    @ObservedObject private var theme = AppTheme.shared

    private enum Phase {
        /// Waiting for the active player to throw.
        case ready
        /// Dice in the air.
        case rolling
        /// A roll that scores something: set dice aside, then roll on or bank.
        case choosing
        /// Turn over — banked or busted; waiting to hand over.
        case scored
        /// Handover gate between turns.
        case handover
        /// Match decided.
        case finished
    }

    var body: some View {
        ZStack {
            GeometryReader { geo in
                let headerHeight = geo.size.height * 0.17
                let minButtonHeight: CGFloat = 100
                let sceneHeight = min(geo.size.width, max(geo.size.height - headerHeight - minButtonHeight, 0))
                let buttonHeight = geo.size.height - headerHeight - sceneHeight

                VStack(spacing: 0) {
                    MatchScoreboard(
                        // A race has no round count, so the strip runs
                        // without one — same as HOG.
                        match: match,
                        totalRounds: nil,
                        subtitle: scoreboardSubtitle
                    )
                    .frame(height: headerHeight)

                    DiceTraySceneView(
                        session: $session,
                        makeInitialDice: { ThreeThousandRules.makeDice() },
                        floorTitle: ThreeThousandGame.floorTitle,
                        onSessionCreated: { newSession in
                            newSession.onRollSettled = { results in
                                applyRoll(results)
                            }
                            newSession.onSelectionChanged = { ids in
                                selected = ids
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
                        secondaryLabel: phase == .choosing ? bankLabel : nil,
                        subtitle: subtitle,
                        onPrimary: { primaryAction() },
                        onSecondary: { bank() }
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
            SettingsView(gameName: ThreeThousandGame.displayName, rules: ThreeThousandGame.rules)
        }
        .onAppear {
            AppFonts.registerIfNeeded()
            SoundEngine.shared.startMusic()
        }
        .onChange(of: theme.colorwayIndex) { _, _ in
            session?.applyTheme()
        }
    }

    // MARK: Reading the selection

    /// The dice tapped since the last set-aside — the take being considered.
    private var takenNow: [DiceTraySession.DieResult] {
        hand.filter { selected.contains($0.id) && !locked.contains($0.id) }
    }

    /// What that take is worth, or nil when it is not a legal set-aside.
    private var takePoints: Int? {
        ThreeThousandRules.score(faces: takenNow.map(\.value))
    }

    /// True when every die on the table is now set aside — the next roll is
    /// a fresh six with the running total carried.
    private var isHotDice: Bool {
        !takenNow.isEmpty && selected.count == ThreeThousandRules.diceCount
    }

    // MARK: Button

    private var primaryLabel: String {
        switch phase {
        case .ready:    return "Roll"
        case .rolling:  return "Rolling"
        case .choosing: return isHotDice ? "Hot Dice" : "Roll On"
        case .scored:   return "Pass"
        case .handover: return "Pass"
        case .finished: return "Done"
        }
    }

    private var bankLabel: String {
        guard let takePoints else { return "Bank" }
        return "Bank \(turnTotal + takePoints)"
    }

    private var subtitle: String {
        switch phase {
        case .choosing:
            guard !takenNow.isEmpty else {
                return turnTotal > 0
                    ? "Tap what scores — \(turnTotal) riding on it"
                    : "Tap the dice that score"
            }
            guard let takePoints else { return "That die doesn't score — untap it" }
            if isHotDice { return "All six — roll again for \(turnTotal + takePoints)" }
            return "Taking \(takePoints), \(remainingAfterTake) dice left"
        case .scored:
            return lastSummary ?? ""
        default:
            return ""
        }
    }

    private var remainingAfterTake: Int {
        ThreeThousandRules.diceCount - selected.count
    }

    private var scoreboardSubtitle: String? {
        switch phase {
        case .ready:
            if let owed = turnsLeftAfterTarget, owed == 0 {
                return "\(match.activeDisplayName) — last turn"
            }
            return "\(match.activeDisplayName) to roll"
        case .rolling:  return "Rolling…"
        case .choosing: return turnTotal > 0 ? "Turn \(turnTotal) — not yours yet" : nil
        default:        return nil
        }
    }

    /// The scene assembles only once the view has real bounds, so `session`
    /// is nil for the first moments on screen — rolling is gated on it for
    /// the same reason Jackpot gates it.
    private var isPrimaryEnabled: Bool {
        switch phase {
        case .ready:    return session != nil
        case .choosing: return takePoints != nil
        case .scored:   return true
        default:        return false
        }
    }

    private func primaryAction() {
        SoundEngine.shared.play(.buttonTap)
        switch phase {
        case .ready:
            if session?.roll() == true { phase = .rolling }
        case .choosing:
            rollOn()
        case .scored:
            endTurn()
        default:
            break
        }
    }

    // MARK: Turn flow

    private func applyRoll(_ results: [DiceTraySession.DieResult]) {
        // Locked dice report at their retained faces, so this is always the
        // whole table. The new dice are the ones that actually moved.
        hand = results
        let fresh = results.filter { !locked.contains($0.id) }

        // Turned on here rather than in beginTurn(): the first turn of a
        // match never passes through a handover, so enabling it there would
        // leave the opening roll untappable.
        if fresh.isEmpty || ThreeThousandRules.hasScoringDice(fresh.map(\.value)) {
            session?.isSelectionEnabled = true
            phase = .choosing
            return
        }

        // Busted. The running total goes, the banked score does not.
        lastSummary = ThreeThousandRules.summary(
            player: match.activeDisplayName,
            banked: 0,
            lost: turnTotal,
            busted: true
        )
        turnTotal = 0
        session?.isSelectionEnabled = false
        phase = .scored
    }

    /// Sets the take aside for good and throws what is left.
    private func rollOn() {
        guard let takePoints, let session else { return }

        turnTotal += takePoints

        if isHotDice {
            // All six are spoken for, so they all come back — the running
            // total carries, which is the whole appeal and the whole risk.
            session.clearSelection()
            locked = []
            if session.roll() { phase = .rolling }
            return
        }

        session.lockSelection()
        locked = session.lockedIDs
        if session.roll(keeping: session.selectedIDs) { phase = .rolling }
    }

    /// Banks the turn and, if that reaches the target, starts the countdown
    /// to the end of the match.
    private func bank() {
        SoundEngine.shared.play(.buttonTap)
        guard phase == .choosing, let takePoints else { return }

        let player = match.activeParticipant
        let total = turnTotal + takePoints
        match.addScore(total)
        turnTotal = 0

        if match.score(for: player) >= ThreeThousandRules.target,
           turnsLeftAfterTarget == nil {
            // Everyone else gets exactly one more turn to beat it.
            turnsLeftAfterTarget = match.participants.count - 1
            firstToTarget = player
        }

        lastSummary = ThreeThousandRules.summary(
            player: match.displayName(for: player),
            banked: total,
            lost: 0,
            busted: false
        )
        session?.isSelectionEnabled = false
        phase = .scored
    }

    private func endTurn() {
        if let owed = turnsLeftAfterTarget {
            if owed <= 0 {
                finishMatch()
                return
            }
            turnsLeftAfterTarget = owed - 1
        }
        match.advanceTurn()
        phase = .handover
    }

    /// Highest total wins, and a tie goes to whoever reached the target
    /// first — the chaser has to actually beat them, not match them.
    private func finishMatch() {
        match.finish(lowestScoreWins: ThreeThousandGame.lowestScoreWins)
        if let outcome = match.outcome,
           outcome.winners.count > 1,
           let firstToTarget,
           outcome.winners.contains(firstToTarget) {
            match.finish(
                winners: [firstToTarget],
                reason: "Tied — but \(match.displayName(for: firstToTarget)) got there first."
            )
        }
        phase = .finished
    }

    private func beginTurn() {
        turnTotal = 0
        hand = []
        locked = []
        session?.beginTurn()
        phase = .ready
    }

    private func startNewMatch() {
        match = TurnMatch.localTwoPlayer()
        turnsLeftAfterTarget = nil
        firstToTarget = nil
        lastSummary = nil
        session?.setPool(ThreeThousandRules.makeDice())
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
