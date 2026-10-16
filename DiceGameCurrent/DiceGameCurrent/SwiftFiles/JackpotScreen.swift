import SwiftUI

struct JackpotScreen: View {

    var onExit: (() -> Void)? = nil

    /// True while a settled die sits under the tray's top corners.
    ///
    /// Fades the back and settings buttons and lets taps through to the
    /// die — see OverlayChromeButton, which reads it from the
    /// environment so its twenty-odd call sites do not each have to know
    /// about the dice.
    @State private var chromeCornersOccupied = false

    @State private var match = TurnMatch.passAndPlay()
    @State private var session: DiceTraySession?
    @State private var phase: Phase = .ready
    @State private var lastSummary: String?

    /// What the five dice showed on the turn just scored.
    ///
    /// Held as the finished line rather than the results, because that is
    /// all the screen does with it — and because a `DieResult` kept across
    /// a phase change is a snapshot of a table that has since been
    /// re-dealt. Cleared when the next turn begins, so the gate between
    /// turns cannot show the last player's dice to the next one.
    @State private var lastDice: String?

    /// The score as it stands before any escalation, held while the player
    /// decides. Nil outside that moment.
    @State private var pendingScore: JackpotRules.TurnScore?

    /// The seven numbers the roll produced, and which dice are held if the
    /// player escalates.
    ///
    /// Both are needed after the re-roll, not just during the choice: the
    /// locked numbers are what the locked points are scored from, and the
    /// held IDs are what tells the new roll's results apart from the old
    /// ones — `onRollSettled` reports the whole hand after a partial
    /// re-roll, kept dice included, which is what makes the readout honest
    /// and this bookkeeping necessary.
    @State private var lockedNumbers: [Int] = []
    @State private var lockedDice: Set<UUID> = []
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
        lastDice = nil
        clearEscalation()
        phase = .ready
    }

    private enum Phase {
        /// Waiting for the active player to roll.
        case ready
        /// Dice in the air.
        case rolling
        /// Rolled, scored, and the roll formed a set — so the turn offers
        /// the choice: bank what is on the table, or lock the best set and
        /// re-roll the rest for double.
        case deciding
        /// The escalation's re-roll is in the air.
        case escalating
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
                // The split every game makes, made once — see
                // GameBandLayout. The scene is square because its world
                // bounds come from this view's measured aspect ratio, and
                // the button band's floor is summed from what it holds
                // rather than typed as 100.
                let bands = GameBandLayout.bands(in: geo.size)
                let headerHeight = bands.header
                // The REGION, not the square: the well fills 60% of the
                // screen and the playfield stays square inside it.
                let sceneHeight = bands.sceneRegion
                let buttonHeight = bands.buttonBand

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
                            newSession.onChromeCornersChanged = { occupied in
                                chromeCornersOccupied = occupied
                            }
                            newSession.onRollSettled = { results in
                                scoreRoll(results)
                            }
                        }
                    )
                    .rollingWell(height: sceneHeight)
                    .environment(\.trayCornersOccupied, chromeCornersOccupied)
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

                    // TurnActionBar rather than DiceRollButton, because
                    // the turn now has a phase with two answers. With no
                    // secondary label it renders exactly as the single
                    // roll button did — see TurnActionBar's own note.
                    TurnActionBar(
                        primaryLabel: buttonLabel,
                        primaryEnabled: isPrimaryEnabled,
                        secondaryLabel: phase == .deciding ? "Escalate" : nil,
                        subtitle: buttonSubtitle,
                        onPrimary: { primaryAction() },
                        onSecondary: { escalate() }
                    )
                    .frame(height: buttonHeight)
                }
            }

            if phase == .handover {
                HandoverGate(match: match, lastTurnSummary: lastSummary) {
                    lastDice = nil
                    clearEscalation()
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
        case .ready:      return "Roll"
        case .rolling:    return "Rolling"
        case .deciding:   return "Bank \(pendingScore?.total ?? 0)"
        case .escalating: return "Rolling"
        case .scored:     return isFinalTurn ? "Finish" : "Pass"
        case .handover:   return "Pass"
        case .finished:   return "Done"
        }
    }

    private var buttonSubtitle: String {
        // The choice, priced. What escalating risks is the number already
        // on the bar, so the line says what it would cost rather than
        // leaving "double or nothing" as a figure of speech.
        if phase == .deciding, let pendingScore, let locked = lockedSetLine {
            return "Escalate locks \(locked) — a bust loses \(pendingScore.total)"
        }
        guard phase == .scored, let lastSummary else { return "" }
        return lastSummary
    }

    /// "three 4's", for the line above.
    private var lockedSetLine: String? {
        guard let locked = JackpotRules.lockedSet(in: lockedNumbers) else { return nil }
        return "\(locked.count) \(locked.value)'s"
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
        case .ready:      return "\(match.activeDisplayName) to roll"
        case .rolling:    return "Rolling…"
        // The dice themselves, where the strip already has a line for
        // saying what is going on. The button's own subtitle carries the
        // SCORE at this phase — see buttonSubtitle — so the two read as a
        // pair: what was rolled up here, what it paid down there.
        // The dice stay on show through the choice as well as after it:
        // deciding whether to escalate means reading what is on the table.
        case .deciding:   return lastDice
        case .escalating: return "Rolling…"
        case .scored:     return lastDice
        default:          return nil
        }
    }

    /// The scene assembles only once the view has real bounds, so `session`
    /// is nil for the first moments on screen. Requiring it here is what
    /// stops a tap in that window flipping the game into a rolling phase
    /// that nothing will ever move it out of.
    private var isPrimaryEnabled: Bool {
        switch phase {
        case .ready:    return session != nil
        case .deciding: return true
        case .scored:   return true
        default:        return false
        }
    }

    private func primaryAction() {
        switch phase {
        case .ready:
            // Phase follows the roll rather than leading it. roll() reports
            // false when it did not throw anything, and moving first meant
            // a no-op left the game stuck.
            if session?.roll() == true {
                lastDice = nil
                clearEscalation()
                phase = .rolling
            }
        case .deciding:
            bankPending()
        case .scored:
            endTurn()
        default:
            break
        }
    }

    // MARK: Turn flow

    private func scoreRoll(_ results: [DiceTraySession.DieResult]) {
        // The re-roll lands here too — same callback, same complete hand —
        // so which half of the turn this is comes from the phase rather
        // than from the shape of the results.
        if phase == .escalating {
            scoreEscalation(results)
            return
        }

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

        lastDice = JackpotRules.readout(from: results)

        // A roll with a set to lock stops here and asks. Nothing is banked
        // and nothing is recorded yet — the turn is not over until the
        // player says which way it ends, and a Jackpot is never offered
        // the gamble (see JackpotRules.canEscalate).
        if JackpotRules.canEscalate(score) {
            pendingScore = score
            lockedNumbers = []
            lockedDice = []
            if let locked = JackpotRules.lockedSet(in: numbers) {
                lockedDice = JackpotRules.lockedDice(results, setValue: locked.value)
                lockedNumbers = results
                    .filter { lockedDice.contains($0.id) }
                    .flatMap { JackpotRules.numbers(from: [$0]) }
            }
            phase = .deciding
            return
        }

        bank(score)
    }

    /// Scores the re-roll an escalation threw.
    private func scoreEscalation(_ results: [DiceTraySession.DieResult]) {
        guard results.map(\.sides).sorted() == JackpotRules.dieSides.sorted() else {
            phase = .ready
            return
        }

        // The numbers that MOVED. `onRollSettled` reports every die after
        // a partial re-roll, held ones included, so without this the
        // locked set would be counted twice — once as locked points and
        // again as a fresh set at double.
        let rerolled = results
            .filter { !lockedDice.contains($0.id) }
            .flatMap { JackpotRules.numbers(from: [$0]) }

        let score = JackpotRules.escalatedScore(
            lockedNumbers: lockedNumbers,
            rerolled: rerolled,
            d20: JackpotRules.d20Face(from: results)
        )

        lastDice = JackpotRules.readout(from: results)
        bank(score)
    }

    /// Ends the turn with this score, whichever road it took.
    private func bank(_ score: JackpotRules.TurnScore) {
        let player = match.activeDisplayName
        if score.isJackpot {
            jackpotsThisRound.append(match.activeParticipant)
        } else {
            match.addScore(score.total)
        }
        lastSummary = JackpotRules.summary(for: score, player: player)
        clearEscalation()
        phase = .scored
    }

    /// Takes the turn as rolled.
    private func bankPending() {
        guard let pendingScore else { return }
        SoundEngine.shared.play(.buttonTap)
        bank(pendingScore)
    }

    private func clearEscalation() {
        pendingScore = nil
        lockedNumbers = []
        lockedDice = []
    }

    /// Locks the best set and throws everything else.
    ///
    /// The phase moves only if the throw actually happened — the same
    /// guard the first roll uses, and for the same reason: a phase that
    /// leads the dice is a turn that can hang when the roll is refused.
    private func escalate() {
        SoundEngine.shared.play(.buttonTap)
        if session?.roll(keeping: lockedDice) == true {
            phase = .escalating
        }
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
        match = TurnMatch.passAndPlay()
        jackpotsThisRound.removeAll()
        lastSummary = nil
        lastDice = nil
        clearEscalation()
        session?.setPool(JackpotRules.makeDice())
        phase = .ready
    }

    // MARK: Chrome

}
