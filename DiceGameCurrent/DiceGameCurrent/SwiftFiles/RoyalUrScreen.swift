import SwiftUI

struct RoyalUrScreen: View {

    var onExit: (() -> Void)? = nil

    /// Scores are pieces brought home, so the scoreboard is the race.
    @State private var match = TurnMatch.localTwoPlayer()
    @State private var state = RoyalUrState()
    @State private var session: DiceTraySession?
    @State private var steps = 0

    /// The piece the player has chosen but not yet committed.
    ///
    /// Royal UR is the one game in the suite where a mis-tap can cost
    /// sixteen squares, so a move takes two taps: one to choose, one to
    /// commit. Nothing moves while this is merely set.
    @State private var selectedPiece: Int?
    @State private var phase: Phase = .ready
    @State private var lastSummary: String?

    /// Set when a rosette buys the same player another roll, so the board
    /// can say why nobody handed over.
    @State private var earnedAnotherRoll = false

    @State private var showingSettings = false
    @ObservedObject private var theme = AppTheme.shared

    /// How tall the board should be so that it fills the width it is given.
    ///
    /// It was a flat 0.34 of the screen height, which on a phone happens to
    /// leave the WIDTH binding — the board spans the screen and nothing
    /// looks wrong. Turn an iPad to landscape and the height binds instead:
    /// the board shrinks to 865pt inside 1354pt and sits in the middle of
    /// 489pt of empty timber.
    ///
    /// 9.04 x 3.64 tiles is the board's own aspect — see RoyalUrLayout — so
    /// the first term is the height at which the width is exactly used up.
    /// It is clamped so the tray below never drops under `minimumTray`,
    /// because a board that fills the screen by squeezing the dice out of it
    /// is not an improvement.
    ///
    /// Out of the ViewBuilder because it has to be: inline, this body scored
    /// 12 operators against a threshold of 12, which is the arithmetic
    /// Xcode 14.2's solver gives up on.
    static func boardHeight(in size: CGSize) -> CGFloat {
        let minimumTray: CGFloat = 220
        let buttonRow: CGFloat = 104
        let usableWidth = size.width - 12
        let fillsWidth = usableWidth / 9.04 * 3.64
        let header = size.height * 0.15
        let spare = size.height - header - buttonRow - minimumTray
        return min(fillsWidth, max(spare, size.height * 0.30))
    }

    private enum Phase {
        /// Waiting for the active player to throw.
        case ready
        /// Dice in the air.
        case rolling
        /// A roll with somewhere to go: pick the piece.
        case choosing
        /// A roll with nowhere to go: pick the piece that goes backwards.
        case setback
        /// Move made; waiting to send the turn on.
        case scored
        /// Handover gate between turns.
        case handover
        /// Match decided.
        case finished
    }

    private var seat: Int { match.activeIndex }


    // MARK: Sending a turn

    /// This screen's turn, packed the way the Messages extension will send
    /// it — the bookkeeping and the game's own state together, which is
    /// what MatchPayload exists to say.
    var wireTurn: MatchPayload<RoyalUrState> {
        MatchPayload(match: match, state: state)
    }

    /// Adopts a turn that arrived from another device.
    ///
    /// Phase goes back to `.ready` rather than being carried: a phase is
    /// what THIS device is doing with the dice in front of it, and the
    /// sender's is meaningless here.
    func adopt(_ incoming: MatchPayload<RoyalUrState>) {
        match = incoming.match
        state = incoming.state
        phase = .ready
    }

    var body: some View {
        ZStack {
            // The floor's own darkest tone, so the board sits on the table
            // the rest of the suite is played on.
            //
            // This was a faceted surface described as "the same as the
            // playfield floor", which stopped being true the day the floor
            // became a shader. SmokeFloor.backdropColor is the thing that
            // statement now means, and it is also what every other screen
            // uses behind its tray — so a sliver at any aspect reads as
            // the field rather than as a hole in it.
            SmokeFloor.backdropColor
                .ignoresSafeArea()

            GeometryReader { geo in
                let headerHeight = geo.size.height * 0.15
                // The board takes a third of the screen, up from a
                // quarter. On a tablet the layout is height-bound —
                // `tile = min(width / 8.92, height / 3.52)` — so this is
                // what actually makes the board bigger there: 81.5pt
                // tiles become 92.2pt on an 11-inch iPad. The tray still
                // keeps more height than the board at every size, which
                // it has to: five d4s are thrown in it.
                let boardHeight = RoyalUrScreen.boardHeight(in: geo.size)
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
                        focused: focusedSquare,
                        destination: previewSquare,
                        onTapSquare: { handleTap($0) }
                    )
                    .frame(height: boardHeight)
                    .padding(.horizontal, 6)

                    DiceTraySceneView(
                        session: $session,
                        makeInitialDice: { RoyalUrRules.makeDice() },
                        d4Style: .markedTips,
                        floorTitle: RoyalUrGame.floorTitle,
                        arenaStyle: .house,
                        onSessionCreated: { newSession in
                            newSession.onRollSettled = { results in
                                applyRoll(results)
                            }
                        }
                    )
                    .rollingWell(height: trayHeight)
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
            SettingsView(for: RoyalUrGame.self)
        }
        .onAppear {
            AppFonts.registerIfNeeded()
            SoundEngine.shared.startMusic()
        }
        .onValueChange(of: theme.colorwayIndex) { _ in
            session?.applyTheme()
        }
    }

    // MARK: Reading the position

    private var moves: [Int: Int] {
        state.legalMoves(seat: seat, steps: steps)
    }

    /// Where a piece is drawn right now — its square, or its tray.
    private func shown(_ piece: Int) -> RoyalUrBoard.Square? {
        RoyalUrBoard.displaySquare(seat: seat, index: state.index(seat: seat, piece: piece))
    }

    /// Where the chosen piece would land.
    private var destinationSquare: RoyalUrBoard.Square? {
        guard let selectedPiece, let target = moves[selectedPiece] else { return nil }
        return RoyalUrBoard.displaySquare(seat: seat, index: target)
    }

    /// Where a Setback would put the chosen piece.
    private var setbackSquare: RoyalUrBoard.Square? {
        guard let selectedPiece else { return nil }
        return RoyalUrBoard.displaySquare(
            seat: seat,
            index: state.setbackDestination(seat: seat, piece: selectedPiece)
        )
    }

    /// Everything tappable right now.
    ///
    /// Before a choice that is every piece the roll can move, so you can
    /// see what is actually on offer; after one it is just the square
    /// that commits it.
    private var highlighted: Set<RoyalUrBoard.Square> {
        switch phase {
        case .choosing:
            guard selectedPiece == nil else { return [] }
            return Set(moves.keys.compactMap { shown($0) })
        case .setback:
            guard selectedPiece == nil else { return [] }
            return Set(state.setbackCandidates(seat: seat).compactMap { shown($0) })
        default:
            return []
        }
    }

    private var focusedSquare: RoyalUrBoard.Square? {
        guard let selectedPiece, phase == .choosing || phase == .setback else { return nil }
        return shown(selectedPiece)
    }

    private var previewSquare: RoyalUrBoard.Square? {
        switch phase {
        case .choosing: return destinationSquare
        case .setback:  return setbackSquare
        default:        return nil
        }
    }

    // MARK: Button

    private var primaryLabel: String {
        switch phase {
        case .ready:    return "Roll"
        case .rolling:  return "Rolling"
        case .choosing: return selectedPiece == nil ? "Tap a Piece" : "Move"
        case .setback:  return selectedPiece == nil ? "Tap a Piece" : "Send It Back"
        case .scored:   return "Pass"
        case .handover: return "Pass"
        case .finished: return "Done"
        }
    }

    private var isPrimaryEnabled: Bool {
        switch phase {
        case .ready:    return session != nil
        case .choosing, .setback: return selectedPiece != nil
        case .scored:   return true
        default:        return false
        }
    }

    private var subtitle: String {
        switch phase {
        case .ready:
            return earnedAnotherRoll ? "Rosette — roll again" : ""
        case .choosing:
            guard selectedPiece == nil else {
                return "Tap the ringed square to move, or pick another piece"
            }
            // How far the roll MOVES, not how many pieces could take it.
            // The four binary dice give a distance, and that distance is
            // the same for every piece — the piece count was answering a
            // question the player had not asked, and the one they had
            // (how far does this get me?) was only on the board.
            //
            // And without "Rolled N —" in front of it: the four dice are on
            // screen above this line, so repeating their total here only
            // made room for the number that matters to be read as the
            // second one.
            return "Move \(steps) space\(steps == 1 ? "" : "s")"
        case .setback:
            guard selectedPiece == nil else {
                return "Tap the ringed square to send it back, or pick another"
            }
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
            commitMove()
        case .setback:
            commitSetback()
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
        selectedPiece = nil

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
            // Tapping one of your movable pieces chooses it, and tapping
            // another switches — nothing commits until the landing square
            // itself is tapped.
            if let piece = moves.keys.first(where: { shown($0) == square }) {
                SoundEngine.shared.play(.buttonTap)
                selectedPiece = piece
                return
            }
            if square == destinationSquare { commitMove() }

        case .setback:
            if let piece = state.setbackCandidates(seat: seat).first(where: { shown($0) == square }) {
                SoundEngine.shared.play(.buttonTap)
                selectedPiece = piece
                return
            }
            if square == setbackSquare { commitSetback() }

        default:
            break
        }
    }

    private func commitMove() {
        guard let piece = selectedPiece, let destination = moves[piece] else { return }
        selectedPiece = nil
        move(piece: piece, to: destination)
    }

    private func commitSetback() {
        guard let piece = selectedPiece else { return }
        selectedPiece = nil
        applySetback(piece: piece)
    }

    private func move(piece: Int, to destination: Int) {
        // The piece landing, sliced from one take of the real thing. Not
        // the button cue: a move is a thing happening on the board, and the
        // tap that started it already sounded.
        DiceAudioEngine.shared.play(set: AudioSet.urMove, jitter: false)
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
        selectedPiece = nil
        earnedAnotherRoll = false
        session?.beginTurn()
        phase = .ready
    }

    private func startNewMatch() {
        match = TurnMatch.localTwoPlayer()
        selectedPiece = nil
        state = RoyalUrState()
        lastSummary = nil
        session?.setPool(RoyalUrRules.makeDice())
        beginTurn()
    }

    // MARK: Chrome

}

// MARK: - Suite entry

enum RoyalUrGame: SuiteGame {
    static let id = "royal_ur"
    static let displayName = "Royal UR"
    static let tagline = "Race, capture, come home."

    static let rules: [GameRuleSection] = [
        GameRuleSection(
            title: "Game Overview",
            body: "  * Players: 2.\n  * Dice Pool: 5x d4 (marked points system).\n  * Pieces: 3 pieces per player on shared 16-square track.\n  * Objective: First player to bring 2 pieces home wins."
        ),
        GameRuleSection(
            title: "Movement Dice Calculation",
            body: "  Roll 5x d4. Count total upward-facing marked points (0 to 5) for distance.\n\n  Marked Points   Movement Distance   Special Effect\n  -----------------------------------------------------------------------------\n  0               0 Squares           Triggers Setback Rule\n  1 to 5          1 to 5 Squares      Move one piece standard distance"
        ),
        GameRuleSection(
            title: "Movement & Board Mechanics",
            body: "  * Move a single piece full exact count rolled. Exact count to enter/land home.\n  * Cannot land on your own pieces.\n  * Capture: Landing on opponent's piece sends it back to start.\n  * Rosettes (Squares 4, 8, 12, 16): Landing on a Rosette grants extra roll.\n  * Setback Rule: Rolling 0 or having no legal moves forces player to move one of\n    their own pieces backward 4 squares (or to start if occupied).",
            figures: [.royalUrPath, .rosette]
        )
    ]
}
