import SwiftUI

// MARK: - A die face

/// A d6 face drawn as pips.
///
/// The grids hold a lot of small dice, and at that size a numeral is a
/// smudge while pips stay countable — and it matches what is physically
/// tumbling in the tray above them.
struct PipFace: View {
    let value: Int
    let tint: Color

    /// Which of the nine positions are inked, for each face.
    private static let layouts: [Int: [Int]] = [
        1: [4],
        2: [0, 8],
        3: [0, 4, 8],
        4: [0, 2, 6, 8],
        5: [0, 2, 4, 6, 8],
        6: [0, 2, 3, 5, 6, 8]
    ]

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let pip = side * 0.19
            let inset = side * 0.18
            let step = (side - inset * 2 - pip) / 2
            let inked = Set(PipFace.layouts[value] ?? [])

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: side * 0.18)
                    .fill(tint)

                ForEach(0..<9, id: \.self) { index in
                    if inked.contains(index) {
                        Circle()
                            .fill(Color.black.opacity(0.75))
                            .frame(width: pip, height: pip)
                            .offset(
                                x: inset + step * CGFloat(index % 3),
                                y: inset + step * CGFloat(index / 3)
                            )
                    }
                }
            }
            .frame(width: side, height: side)
            // Lit, bevelled and casting a shadow — the three things that
            // make a die read as solid under the tray's orthographic
            // top-down camera, which shows no sides at all. This game's
            // board IS dice, so a flat one beside a rolling one is the
            // most visible mismatch in the suite.
            //
            // Over the pips rather than under them: the highlight is on
            // the die's surface and the pips are in it.
            .pieceSolid(RoundedRectangle(cornerRadius: side * 0.18),
                        lineWidth: max(1, side * 0.045))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - One side of the board

/// A player's three columns.
struct BoneheadsGrid: View {
    let columns: [[Int]]
    let tint: Color
    /// Mine fills from the bottom up, theirs from the top down, so new
    /// dice on both sides appear toward the middle of the table.
    let isMine: Bool
    var placeable: Set<Int> = []
    var onTapColumn: ((Int) -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<BoneheadsRules.columns, id: \.self) { index in
                column(index)
            }
        }
    }

    private func column(_ index: Int) -> some View {
        let dice = columns[index]
        let slots = (0..<BoneheadsRules.slotsPerColumn).map { slot -> Int? in
            slot < dice.count ? dice[slot] : nil
        }
        let ordered = isMine ? Array(slots.reversed()) : slots
        let isPlaceable = placeable.contains(index)
        let total = BoneheadsRules.columnScore(dice)

        return Button {
            onTapColumn?(index)
        } label: {
            VStack(spacing: 4) {
                if !isMine { label(index, total: total) }
                VStack(spacing: 4) {
                    ForEach(Array(ordered.enumerated()), id: \.offset) { _, die in
                        slotView(die)
                    }
                }
                if isMine { label(index, total: total) }
            }
            .padding(5)
            .background(
                RoundedRectangle(cornerRadius: ControlShape.cornerRadius)
                    .fill(Color.black.opacity(isPlaceable ? 0.38 : 0.2))
            )
            .overlay(
                RoundedRectangle(cornerRadius: ControlShape.cornerRadius)
                    .stroke(tint.opacity(isPlaceable ? 0.95 : 0.25),
                            lineWidth: isPlaceable ? 2 : 1)
            )
        }
        // Plain, so the automatic style does not grey the whole column out
        // when it is not tappable — the opponent's grid is never tappable
        // and must still read at full strength.
        .buttonStyle(.plain)
        .disabled(onTapColumn == nil || !isPlaceable)
    }

    private func label(_ index: Int, total: Int) -> some View {
        HStack(spacing: 4) {
            Text(BoneheadsRules.name(of: index))
                .font(.stackSans(10))
                .foregroundStyle(.white.opacity(0.55))
            Text("\(total)")
                .font(.stackSans(12))
                .foregroundStyle(total > 0 ? tint : .white.opacity(0.35))
        }
    }

    private func slotView(_ die: Int?) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.white.opacity(0.05))
                .aspectRatio(1, contentMode: .fit)
            if let die {
                PipFace(value: die, tint: tint)
                    .aspectRatio(1, contentMode: .fit)
                    .padding(1)
            }
        }
    }
}

// MARK: - Screen

struct BoneheadsScreen: View {

    var onExit: (() -> Void)? = nil

    @State private var match = TurnMatch.localTwoPlayer()
    @State private var state = BoneheadsState()
    @State private var session: DiceTraySession?
    @State private var rolled: Int?
    @State private var phase: Phase = .ready
    @State private var lastSummary: String?
    @State private var showingSettings = false
    @ObservedObject private var theme = AppTheme.shared

    private enum Phase {
        /// Waiting for the active player to throw.
        case ready
        /// The die is in the air.
        case rolling
        /// A face is up: choose a column.
        case placing
        /// Placed; waiting to hand over.
        case placed
        /// Handover gate between turns.
        case handover
        /// Match decided.
        case finished
    }

    private var seat: Int { match.activeIndex }

    /// Columns the rolled die may go into.
    private var placeable: Set<Int> {
        guard phase == .placing else { return [] }
        return Set((0..<BoneheadsRules.columns).filter { state.canPlace(seat: seat, column: $0) })
    }

    var body: some View {
        ZStack {
            WoodTiledBackground().ignoresSafeArea()

            GeometryReader { geo in
                let headerHeight = geo.size.height * 0.14
                let boardHeight = geo.size.height * 0.23
                let buttonHeight: CGFloat = 100
                let trayHeight = max(
                    geo.size.height - headerHeight - boardHeight * 2 - buttonHeight, 0
                )

                VStack(spacing: 0) {
                    MatchScoreboard(
                        match: match,
                        totalRounds: nil,
                        subtitle: scoreboardSubtitle
                    )
                    .frame(height: headerHeight)

                    // Theirs on top, mine below, both filling toward the
                    // middle — so a strike lands where you are looking.
                    BoneheadsGrid(
                        columns: state.grids[1 - seat],
                        tint: opponentTint,
                        isMine: false
                    )
                    .frame(height: boardHeight)
                    .padding(.horizontal, 12)

                    DiceTraySceneView(
                        session: $session,
                        makeInitialDice: { BoneheadsRules.makeDice() },
                        floorTitle: BoneheadsGame.floorTitle,
                        arenaStyle: .house(motif: BoneheadsGame.floorMotif),
                        onSessionCreated: { newSession in
                            newSession.onRollSettled = { results in
                                settled(results)
                            }
                        }
                    )
                    .frame(height: trayHeight)
                    .background(Color.black)
                    .overlay(alignment: .topLeading) {
                        if let onExit {
                            overlayButton("chevron.left") { onExit() }
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        overlayButton("gearshape.fill") { showingSettings = true }
                    }

                    BoneheadsGrid(
                        columns: state.grids[seat],
                        tint: theme.accentColor,
                        isMine: true,
                        placeable: placeable,
                        onTapColumn: { place(in: $0) }
                    )
                    .frame(height: boardHeight)
                    .padding(.horizontal, 12)

                    DiceRollButton(
                        label: primaryLabel,
                        isEnabled: isPrimaryEnabled,
                        subtitle: subtitle
                    ) {
                        primaryAction()
                    }
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
            SettingsView(for: BoneheadsGame.self)
        }
        .onAppear {
            AppFonts.registerIfNeeded()
            SoundEngine.shared.startMusic()
        }
        .onChange(of: theme.colorwayIndex) { _, _ in
            session?.applyTheme()
        }
    }

    /// The opponent's grid is drawn in a fixed contrasting tone rather than
    /// the theme accent, so "mine" and "theirs" never depend on which
    /// colour the player happens to have chosen in Settings.
    private var opponentTint: Color { Color(hex: "#D2735F") }

    // MARK: Button

    private var primaryLabel: String {
        switch phase {
        case .ready:    return "Roll"
        case .rolling:  return "Rolling"
        case .placing:  return "Pick a Column"
        case .placed:   return "Pass"
        case .handover: return "Pass"
        case .finished: return "Done"
        }
    }

    private var isPrimaryEnabled: Bool {
        switch phase {
        case .ready:  return session != nil
        case .placed: return true
        default:      return false
        }
    }

    private var subtitle: String {
        switch phase {
        case .placing:
            guard let rolled else { return "" }
            let hits = strikeCount(for: rolled)
            return hits > 0
                ? "A \(rolled) — and it would smash \(hits) of theirs"
                : "A \(rolled) — where does it go?"
        case .placed:
            return lastSummary ?? ""
        default:
            return ""
        }
    }

    /// How many opponent dice the rolled value could destroy, across every
    /// column still open to you. The reason to look before placing.
    private func strikeCount(for die: Int) -> Int {
        // Named rather than shorthand: the inner closure would otherwise
        // shadow the outer's $0, with one meaning a column index and the
        // other a face value.
        (0..<BoneheadsRules.columns)
            .filter { column in state.canPlace(seat: seat, column: column) }
            .map { column in
                state.column(seat: 1 - seat, column).filter { face in face == die }.count
            }
            .max() ?? 0
    }

    private var scoreboardSubtitle: String? {
        switch phase {
        case .ready:   return "\(match.activeDisplayName) to roll"
        case .rolling: return "Rolling…"
        case .placing: return "\(match.activeDisplayName) — \(slotsLeft) slots left"
        default:       return nil
        }
    }

    private var slotsLeft: Int {
        BoneheadsRules.slotsPerPlayer
            - (0..<BoneheadsRules.columns).reduce(0) { $0 + state.column(seat: seat, $1).count }
    }

    private func primaryAction() {
        SoundEngine.shared.play(.buttonTap)
        switch phase {
        case .ready:
            // Phase follows the roll rather than leading it — roll() reports
            // false when it threw nothing.
            if session?.roll() == true { phase = .rolling }
        case .placed:
            endTurn()
        default:
            break
        }
    }

    // MARK: Turn flow

    private func settled(_ results: [DiceTraySession.DieResult]) {
        guard let value = results.first?.value, results.count == 1 else {
            phase = .ready
            return
        }
        rolled = value
        phase = .placing
    }

    private func place(in column: Int) {
        guard phase == .placing, let die = rolled,
              state.canPlace(seat: seat, column: column) else { return }

        SoundEngine.shared.play(.buttonTap)
        let strike = state.place(seat: seat, column: column, die: die)
        rolled = nil
        syncScores()

        lastSummary = BoneheadsRules.summary(
            player: match.activeDisplayName,
            opponent: match.displayName(for: match.participants[1 - seat]),
            strike: strike
        )

        // Filling the ninth slot ends it on the spot — no answering turn.
        // That rule is what keeps the first seat from being worth 55%.
        if state.isFull(seat: seat) {
            match.finish(lowestScoreWins: BoneheadsGame.lowestScoreWins)
            phase = .finished
            return
        }

        phase = .placed
    }

    /// Writes both totals, not just the active player's: a strike changes
    /// the opponent's score too, which `addScore` cannot express.
    private func syncScores() {
        for index in match.participants.indices {
            match.scores[match.participants[index]] = state.score(seat: index)
        }
    }

    private func endTurn() {
        match.advanceTurn()
        phase = .handover
    }

    private func beginTurn() {
        rolled = nil
        session?.beginTurn()
        phase = .ready
    }

    private func startNewMatch() {
        match = TurnMatch.localTwoPlayer()
        state = BoneheadsState()
        lastSummary = nil
        session?.setPool(BoneheadsRules.makeDice())
        beginTurn()
    }

    // MARK: Chrome

    private func overlayButton(_ systemName: String, action: @escaping () -> Void) -> some View {
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
