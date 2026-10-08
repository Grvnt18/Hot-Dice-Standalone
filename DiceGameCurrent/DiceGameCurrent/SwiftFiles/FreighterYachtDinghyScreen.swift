import SwiftUI

struct FreighterYachtDinghyScreen: View {

    var onExit: (() -> Void)? = nil

    @State private var match = TurnMatch.localTwoPlayer()
    @State private var session: DiceTraySession?
    @State private var turn = FreighterYachtDinghyRules.Turn()
    @State private var phase: Phase = .ready
    @State private var lastSummary: String?
    @State private var showingSettings = false

    /// Cargo dice the player has picked to throw again.
    ///
    /// Mirrored out of the session's `selectedIDs` rather than read from it,
    /// because the session is a plain class and publishes nothing — the
    /// same reason Settings mirrors `GameScope`'s statics.
    ///
    /// Note what a selection MEANS here: these are the dice that WILL be
    /// rethrown, not the ones that will be kept. The rule is "any, all, or
    /// none", so the natural gesture is to point at the ones you are
    /// unhappy with, and the pulse marks what the button is about to do —
    /// which is the same thing it means in Rolls.
    @State private var rethrowIDs: Set<UUID> = []

    /// Normally three. A tie at the end pushes this out by one and the
    /// match plays a sudden-death round — which happens about 1 game in 20,
    /// often enough to need handling and rare enough to stay a moment.
    @State private var roundsThisMatch = FreighterYachtDinghyRules.roundsPerPlayer

    @ObservedObject private var theme = AppTheme.shared


    // MARK: Sending a turn

    /// This screen's turn, packed the way the Messages extension will send
    /// it — the bookkeeping and the game's own state together, which is
    /// what MatchPayload exists to say.
    ///
    /// Assembled from the screen's own properties rather than the screen
    /// being rebuilt around the state type. The dice mid-turn are not in
    /// here on purpose: a turn is resolved on the device that threw it and
    /// arrives as a result.
    var wireTurn: MatchPayload<FreighterYachtDinghyState> {
        MatchPayload(match: match, state: FreighterYachtDinghyState(roundsThisMatch: roundsThisMatch))
    }

    /// Adopts a turn that arrived from another device.
    ///
    /// Phase goes back to `.ready` rather than being carried: a phase is
    /// what THIS device is doing with the dice in front of it, and the
    /// sender's is meaningless here.
    func adopt(_ incoming: MatchPayload<FreighterYachtDinghyState>) {
        match = incoming.match
        roundsThisMatch = incoming.state.roundsThisMatch
        // A round is four rolls on one device; the arriving turn starts a new one.
        turn = FreighterYachtDinghyRules.Turn()
        endCargoChoice()
        phase = .ready
    }

    private enum Phase {
        /// Waiting for the active player to throw.
        case ready
        /// Dice in the air.
        case rolling
        /// Qualified with rolls left: rethrow the cargo, or sail.
        case decide
        /// Turn over; waiting to send it on or finish.
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
                            newSession.onSelectionChanged = { picked in
                                rethrowIDs = picked
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
            SeaAudio.preload()
            SeaAudio.start()
        }
        .onDisappear {
            // Easy to leave out, and leaving it out plays the sea over the
            // hub for the rest of the session.
            SeaAudio.stop()
        }
        .onValueChange(of: theme.colorwayIndex) { _ in
            session?.applyTheme()
        }
    }

    // MARK: Button

    private var primaryLabel: String {
        switch phase {
        case .ready:    return turn.rollsUsed == 0 ? "Roll" : "Roll Again"
        case .rolling:  return "Rolling"
        // Says how many, because "any, all, or none" means the count is
        // the decision. Nothing picked is not a rethrow — it is Set Sail,
        // which is the other button.
        case .decide:
            return rethrowIDs.isEmpty
                ? "Pick Cargo"
                : "Rethrow \(rethrowIDs.count)"
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
            guard !rethrowIDs.isEmpty else {
                // The quiet advice cargoRethrowFloor was always for and
                // was never wired to: how many cargo dice the arithmetic
                // is against. Silent when none are, so a good cargo is not
                // nagged at.
                guard poorCargoCount > 0 else {
                    return "Cargo \(total) — tap cargo to rethrow, "
                        + "\(left) roll\(left == 1 ? "" : "s") left"
                }
                return "Cargo \(total) — \(poorCargoCount) below average, "
                    + "\(left) roll\(left == 1 ? "" : "s") left"
            }
            return "Cargo \(total) — \(rethrowIDs.count) picked, "
                + "\(left) roll\(left == 1 ? "" : "s") left"
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
        case .ready:  return session != nil
        // Nothing picked, nothing to throw: `roll(keeping:)` would return
        // false and leave the turn in a phase the button cannot exit,
        // which is the failure primaryAction's own note records.
        case .decide: return session != nil && !rethrowIDs.isEmpty
        case .scored: return true
        default:      return false
        }
    }

    private func primaryAction() {
        SoundEngine.shared.play(.buttonTap)
        switch phase {
        case .ready:
            // Phase follows the roll rather than leading it: roll() reports
            // false when it threw nothing, and moving first meant a no-op
            // left the game stuck in a phase nothing could leave.
            if session?.roll(keeping: turn.keptIDs) == true {
                phase = .rolling
            }
        case .decide:
            // Everything but the dice the player picked. The three claimed
            // vessels are in keptIDs and are locked out of selection, so
            // this can only ever rethrow cargo.
            let kept = allDiceIDs.subtracting(rethrowIDs)
            // Selection off BEFORE the throw, so nothing is left pulsing
            // while it is in the air — and the set is already captured
            // above, because turning it off clears it.
            endCargoChoice()
            if session?.roll(keeping: kept) == true {
                phase = .rolling
            } else {
                phase = .decide
                beginCargoChoice()
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
            beginCargoChoice()
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
        endCargoChoice()
        settleTurn()
    }

    /// Cargo dice showing less than a d6's own average.
    ///
    /// Out of the ViewBuilder and named rather than inlined into
    /// `subtitle`: a filter with a comparison inside a string
    /// interpolation inside a switch is the shape Xcode 14.2's solver
    /// gives up on, which is the same reason PipFace.pipOffset exists.
    private var poorCargoCount: Int {
        // Not named `floor` — that shadows the global function, which
        // compiles and then reads as a bug to the next person.
        let threshold = FreighterYachtDinghyRules.cargoRethrowFloor
        return turn.cargo.filter { $0.value < threshold }.count
    }

    /// Every die on the table, claimed and cargo alike.
    ///
    /// Out of `turn` rather than out of the session: the turn is what knows
    /// which dice are vessels and which are cargo, and the two sets
    /// together are the hand.
    private var allDiceIDs: Set<UUID> {
        turn.keptIDs.union(turn.cargo.map(\.id))
    }

    /// Opens the cargo choice: taps select, the vessels do not.
    private func beginCargoChoice() {
        rethrowIDs = []
        session?.isSelectionEnabled = true
        // `lockOnly`, not `lockSelection`: the vessels are not a selection
        // the player made, they are the three dice that are not the choice.
        session?.lockOnly(turn.keptIDs)
    }

    /// Closes it, which also clears the pulses — `isSelectionEnabled`'s
    /// didSet calls clearSelection().
    private func endCargoChoice() {
        session?.isSelectionEnabled = false
        rethrowIDs = []
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

}
