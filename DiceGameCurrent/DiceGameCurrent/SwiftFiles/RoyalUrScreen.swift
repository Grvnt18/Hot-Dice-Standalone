import SwiftUI

struct RoyalUrScreen: View {

    var onExit: (() -> Void)? = nil

    /// Scores are pieces brought home, so the scoreboard is the race.
    @State private var match = TurnMatch.localTwoPlayer()
    @State private var state = RoyalUrState()
    @State private var session: DiceTraySession?
    @State private var steps = 0
    @State private var phase: Phase = .ready
    @State private var lastSummary: String?

    /// Set when a rosette buys the same player another roll, so the board
    /// can say why nobody handed over.
    @State private var earnedAnotherRoll = false

    @State private var showingSettings = false
    @ObservedObject private var theme = AppTheme.shared

    private enum Phase {
        /// Waiting for the active player to throw.
        case ready
        /// Dice in the air.
        case rolling
        /// A roll with somewhere to go: pick the piece.
        case choosing
        /// A roll with nowhere to go: pick the piece that goes backwards.
        case setback
        /// Move made; waiting to hand over.
        case scored
        /// Handover gate between turns.
        case handover
        /// Match decided.
        case finished
    }

    private var seat: Int { match.activeIndex }

    var body: some View {
        ZStack {
            // The same faceted surface as the playfield floor, so the board
            // sits on the table the rest of the suite is played on.
            Image(uiImage: LowPolyTextures.facetedSurface(
                baseColor: theme.floorBaseColor.darkened(by: 0.35),
                variation: 0.08,
                pixelSize: 512
            ))
            .resizable()
            .ignoresSafeArea()

            GeometryReader { geo in
                let headerHeight = geo.size.height * 0.15
                let boardHeight = geo.size.height * 0.24
                let buttonHeight: CGFloat = 104
                let trayHeight = max(geo.size.height - headerHeight - boardHeight - buttonHeight, 0)

                VStack(spacing: 0) {
                    MatchScoreboard(
                        match: match,
                        totalRounds: nil,
                        subtitle: scoreboardSubtitle
                    )
                    .frame(height: headerHeight)

                    RoyalUrBoardView(
                        positions: state.positions,
                        highlighted: highlighted,
                        onTapSquare: { handleTap($0) }
                    )
                    .frame(height: boardHeight)
                    .padding(.horizontal, 6)

                    DiceTraySceneView(
                        session: $session,
                        makeInitialDice: { RoyalUrRules.makeDice() },
                        onSessionCreated: { newSession in
                            newSession.onRollSettled = { results in
                                applyRoll(results)
                            }
                        }
                    )
                    .frame(height: trayHeight)
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
                        subtitle: subtitle,
                        onPrimary: { primaryAction() }
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
            SettingsView(gameName: RoyalUrGame.displayName, rules: RoyalUrGame.rules)
        }
        .onAppear {
            AppFonts.registerIfNeeded()
            SoundEngine.shared.startMusic()
        }
        .onChange(of: theme.colorwayIndex) { _, _ in
            session?.applyTheme()
        }
    }

    // MARK: Reading the position

    private var moves: [Int: Int] {
        state.legalMoves(seat: seat, steps: steps)
    }

    /// Squares a piece could move to, and which piece would go there.
    ///
    /// Home has no square, so it is not in here — it gets the button
    /// instead, at `homeMove`.
    private var destinations: [RoyalUrBoard.Square: Int] {
        var result: [RoyalUrBoard.Square: Int] = [:]
        for (piece, destination) in moves {
            guard let square = RoyalUrBoard.square(seat: seat, index: destination) else { continue }
            result[square] = piece
        }
        return result
    }

    private var homeMove: Int? {
        moves.first(where: { $0.value == RoyalUrRules.homeIndex })?.key
    }

    private var highlighted: Set<RoyalUrBoard.Square> {
        switch phase {
        case .choosing:
            return Set(destinations.keys)
        case .setback:
            return Set(state.setbackCandidates(seat: seat).compactMap {
                state.square(seat: seat, piece: $0)
            })
        default:
            return []
        }
    }

    // MARK: Button

    private var primaryLabel: String {
        switch phase {
        case .ready:    return "Roll"
        case .rolling:  return "Rolling"
        case .choosing: return homeMove != nil ? "Bring One Home" : "Tap a Square"
        case .setback:  return "Tap a Piece"
        case .scored:   return "Pass"
        case .handover: return "Pass"
        case .finished: return "Done"
        }
    }

    private var isPrimaryEnabled: Bool {
        switch phase {
        case .ready:    return session != nil
        case .choosing: return homeMove != nil
        case .scored:   return true
        default:        return false
        }
    }

    private var subtitle: String {
        switch phase {
        case .ready:
            return earnedAnotherRoll ? "Rosette — roll again" : ""
        case .choosing:
            let count = moves.count
            return "Rolled \(steps) — \(count) move\(count == 1 ? "" : "s")"
        case .setback:
            return "Rolled \(steps) — nowhere to go. One of yours goes back \(RoyalUrRules.setbackDistance)."
        case .scored:
            return lastSummary ?? ""
        default:
            return ""
        }
    }

    private var scoreboardSubtitle: String? {
        switch phase {
        case .rolling: return "Rolling…"
        case .finished, .handover: return nil
        default:
            let waiting = state.waitingCount(seat: seat)
            let home = state.homeCount(seat: seat)
            return "\(match.activeDisplayName) — \(waiting) waiting, \(home) home"
        }
    }

    private func primaryAction() {
        SoundEngine.shared.play(.buttonTap)
        switch phase {
        case .ready:
            // Phase follows the roll rather than leading it — roll() reports
            // false when it threw nothing.
            if session?.roll() == true {
                earnedAnotherRoll = false
                phase = .rolling
            }
        case .choosing:
            if let piece = homeMove {
                move(piece: piece, to: RoyalUrRules.homeIndex)
            }
        case .scored:
            endTurn()
        default:
            break
        }
    }

    // MARK: Turn flow

    private func applyRoll(_ results: [DiceTraySession.DieResult]) {
        guard results.count == RoyalUrRules.diceCount else {
            phase = .ready
            return
        }

        // Held locally as well as in state: everything below decides the
        // phase from this roll, and reading it back out of @State to do so
        // would be relying on write ordering for no reason.
        let rolled = RoyalUrRules.steps(from: results)
        steps = rolled

        if !state.legalMoves(seat: seat, steps: rolled).isEmpty {
            phase = .choosing
            return
        }

        // No move at all. If there is anything on the board it goes
        // backwards; only a player with every piece still waiting gets a
        // turn where nothing happens, which is about one game in seven.
        if state.setbackCandidates(seat: seat).isEmpty {
            lastSummary = rolled == 0
                ? "\(match.activeDisplayName) rolled nothing."
                : "\(match.activeDisplayName) rolled \(rolled) with nothing to move."
            phase = .scored
            return
        }
        phase = .setback
    }

    private func handleTap(_ square: RoyalUrBoard.Square) {
        switch phase {
        case .choosing:
            guard let piece = destinations[square], let destination = moves[piece] else { return }
            move(piece: piece, to: destination)
        case .setback:
            guard let piece = state.piece(of: seat, on: square),
                  state.setbackCandidates(seat: seat).contains(piece) else { return }
            applySetback(piece: piece)
        default:
            break
        }
    }

    private func move(piece: Int, to destination: Int) {
        SoundEngine.shared.play(.buttonTap)
        let outcome = state.apply(seat: seat, piece: piece, destination: destination)

        if outcome.cameHome {
            // The scoreboard's number is pieces home, so this is the score.
            match.addScore(1)
        }

        lastSummary = summary(for: outcome, destination: destination)

        if state.winner != nil {
            match.finish(
                winners: [match.activeParticipant],
                reason: "Two pieces home."
            )
            phase = .finished
            return
        }

        if outcome.grantsAnotherRoll {
            // Same seat, no handover — the rosette is the only thing in the
            // game that keeps the dice on your side of the table.
            earnedAnotherRoll = true
            steps = 0
            session?.beginTurn()
            phase = .ready
            return
        }

        phase = .scored
    }

    private func applySetback(piece: Int) {
        SoundEngine.shared.play(.buttonTap)
        let from = state.index(seat: seat, piece: piece)
        let to = state.applySetback(seat: seat, piece: piece)
        lastSummary = to == 0
            ? "\(match.activeDisplayName) sent a piece back to the start."
            : "\(match.activeDisplayName) went back \(from - to) squares."
        phase = .scored
    }

    private func summary(for outcome: RoyalUrState.MoveOutcome, destination: Int) -> String {
        let player = match.activeDisplayName
        if outcome.cameHome { return "\(player) brought a piece home." }
        if outcome.captured {
            return outcome.landedOnRosette
                ? "\(player) took a piece on a rosette — and rolls again."
                : "\(player) sent a piece back to the start."
        }
        if outcome.landedOnRosette { return "\(player) landed on a rosette and rolls again." }
        return "\(player) moved to square \(destination)."
    }

    private func endTurn() {
        match.advanceTurn()
        phase = .handover
    }

    private func beginTurn() {
        steps = 0
        earnedAnotherRoll = false
        session?.beginTurn()
        phase = .ready
    }

    private func startNewMatch() {
        match = TurnMatch.localTwoPlayer()
        state = RoyalUrState()
        lastSummary = nil
        session?.setPool(RoyalUrRules.makeDice())
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

// MARK: - Suite entry

enum RoyalUrGame: SuiteGame {
    static let id = "royal_ur"
    static let displayName = "Royal UR"
    static let tagline = "Race, capture, come home."

    static let rules: [GameRuleSection] = [
        GameRuleSection(
            title: "The Race",
            body: "Three pieces each, and the first player to bring two of them home wins. Your route runs sixteen squares: out along your own row, up the middle past the bridge, around the far block, and out."
        ),
        GameRuleSection(
            title: "The Dice",
            body: "Roll five four-sided dice. Each one showing a 1 or a 2 is worth a point, so you move anywhere from nothing to five squares — two or three most of the time."
        ),
        GameRuleSection(
            title: "Moving",
            body: "Move one piece the full count. A piece waiting to start enters that many squares along. You cannot land on your own piece, and you cannot overshoot: coming home takes the exact number."
        ),
        GameRuleSection(
            title: "Capture",
            body: "Land on your opponent's piece and it goes all the way back to the start. Every shared square can be taken, rosettes included — and since you run the final loop in opposite directions, the square one step from home is exactly where they come in."
        ),
        GameRuleSection(
            title: "Rosettes",
            body: "The five flowered squares fall on the 4th, 8th, 12th and 16th square of both routes. Land on one and you roll again."
        ),
        GameRuleSection(
            title: "The Setback",
            body: "Roll nothing, or have nowhere legal to go, and you do not simply pass: one of your own pieces goes back four squares — or to the start, if something is already sitting there. You choose which."
        )
    ]
}
