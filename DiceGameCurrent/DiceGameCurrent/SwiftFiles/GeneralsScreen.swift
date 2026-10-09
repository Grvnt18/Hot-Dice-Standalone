import SwiftUI

struct GeneralsScreen: View {

    var onExit: (() -> Void)? = nil

    @State private var match = TurnMatch.localTwoPlayer(seatSequence: GeneralsRules.snakeOrder)
    @State private var card = GeneralsCard()
    @State private var session: DiceTraySession?
    @State private var hand: [Int] = []
    @State private var keptCount = 0
    @State private var rollsUsed = 0
    @State private var phase: Phase = .ready
    @State private var lastSummary: String?
    @State private var showingSettings = false
    @State private var showingCard = false
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
    var wireTurn: MatchPayload<GeneralsState> {
        MatchPayload(match: match, state: GeneralsState(card: card))
    }

    /// Adopts a turn that arrived from another device.
    ///
    /// Phase goes back to `.ready` rather than being carried: a phase is
    /// what THIS device is doing with the dice in front of it, and the
    /// sender's is meaningless here.
    func adopt(_ incoming: MatchPayload<GeneralsState>) {
        match = incoming.match
        card = incoming.state.card
        // Five dice and three rolls belong to the turn that played them.
        hand = []
        keptCount = 0
        rollsUsed = 0
        phase = .ready
    }

    private enum Phase {
        /// Waiting for the active player to throw.
        case ready
        /// Dice in the air.
        case rolling
        /// A hand on the table: keep dice and roll again, or go and claim.
        case decide
        /// Category claimed; waiting to send the turn on or finish.
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
                // GameBandLayout. The button band's floor is summed from
                // what it holds rather than typed as 100.
                let bands = GameBandLayout.self
                let headerHeight = bands.header(in: geo.size, fraction: 0.17)
                let sceneHeight = bands.scene(in: geo.size, fraction: 0.17)
                let buttonHeight = bands.buttonBand(in: geo.size, fraction: 0.17)

                VStack(spacing: 0) {
                    MatchScoreboard(
                        match: match,
                        totalRounds: GeneralsRules.roundsPerPlayer,
                        subtitle: scoreboardSubtitle
                    )
                    .frame(height: headerHeight)

                    DiceTraySceneView(
                        session: $session,
                        makeInitialDice: { GeneralsRules.makeDice() },
                        floorTitle: GeneralsGame.floorTitle,
                        arenaStyle: .house,
                        onSessionCreated: { newSession in
                            newSession.onRollSettled = { results in
                                applyRoll(results)
                            }
                            // Reads the count off the session rather than a
                            // captured value: this closure outlives the body
                            // that made it, so anything captured here would
                            // be frozen at assembly time.
                            newSession.onSelectionChanged = { selected in
                                keptCount = selected.count
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
                        HStack(spacing: 0) {
                            OverlayChromeButton(systemName: "list.bullet.rectangle") {
                                showingCard = true
                            }
                            OverlayChromeButton(systemName: "gearshape.fill") {
                                showingSettings = true
                            }
                        }
                    }

                    TurnActionBar(
                        primaryLabel: primaryLabel,
                        primaryEnabled: isPrimaryEnabled,
                        secondaryLabel: phase == .decide ? "Claim" : nil,
                        subtitle: subtitle,
                        onPrimary: { primaryAction() },
                        onSecondary: { openCard() }
                    )
                    .frame(height: buttonHeight)
                }
            }

            if showingCard {
                GeneralsCardView(
                    card: card,
                    match: match,
                    hand: phase == .decide ? hand : nil,
                    onClaim: { category in claim(category) },
                    onClose: { showingCard = false }
                )
                .transition(.opacity)
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
            SettingsView(for: GeneralsGame.self)
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

    private var primaryLabel: String {
        switch phase {
        case .ready:    return "Roll"
        case .rolling:  return "Rolling"
        case .decide:   return "Roll Again"
        case .scored:   return card.isComplete ? "Finish" : "Pass"
        case .handover: return "Pass"
        case .finished: return "Done"
        }
    }

    private var subtitle: String {
        switch phase {
        case .decide:
            let left = GeneralsRules.rollsPerTurn - rollsUsed
            if left == 0 { return "No rolls left — claim a category" }
            if keptCount == GeneralsRules.diceCount { return "Every die kept — claim a category" }
            return keptCount == 0
                ? "Tap dice to keep them — \(left) roll\(left == 1 ? "" : "s") left"
                : "Keeping \(keptCount) — \(left) roll\(left == 1 ? "" : "s") left"
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
        case .decide:  return "\(card.openCategories.count) categories left"
        default:       return nil
        }
    }

    /// The scene assembles only once the view has real bounds, so `session`
    /// is nil for the first moments on screen — rolling is gated on it for
    /// the same reason Jackpot gates it.
    private var isPrimaryEnabled: Bool {
        switch phase {
        case .ready:
            return session != nil
        case .decide:
            // Out of rolls, or nothing left to throw: the turn's only
            // remaining move is to claim.
            return rollsUsed < GeneralsRules.rollsPerTurn
                && keptCount < GeneralsRules.diceCount
        case .scored:
            return true
        default:
            return false
        }
    }

    private func primaryAction() {
        SoundEngine.shared.play(.buttonTap)
        switch phase {
        case .ready, .decide:
            // Phase follows the roll rather than leading it — roll() reports
            // false when it threw nothing.
            if session?.roll(keeping: session?.selectedIDs ?? []) == true {
                phase = .rolling
            }
        case .scored:
            endTurn()
        default:
            break
        }
    }

    private func openCard() {
        SoundEngine.shared.play(.buttonTap)
        showingCard = true
    }

    // MARK: Turn flow

    private func applyRoll(_ results: [DiceTraySession.DieResult]) {
        // Kept dice report at their retained faces, so this is five every
        // time. Anything less would be scored as a smaller hand, which
        // quietly changes what every category pays.
        guard results.count == GeneralsRules.diceCount else {
            phase = .ready
            return
        }
        hand = results.map(\.value)
        rollsUsed += 1
        session?.isSelectionEnabled = true
        phase = .decide
    }

    /// Takes a box on the shared card and ends the turn.
    private func claim(_ category: GeneralsCategory) {
        guard phase == .decide else { return }
        let points = category.score(for: hand)
        guard card.claim(category, by: match.activeParticipant, points: points) else { return }

        SoundEngine.shared.play(.buttonTap)
        match.addScore(points)
        lastSummary = GeneralsRules.summary(
            player: match.activeDisplayName,
            category: category,
            points: points
        )
        // Also drops every highlight, so the next player does not inherit a
        // table of pulsing dice.
        session?.isSelectionEnabled = false
        showingCard = false
        phase = .scored
    }

    private func endTurn() {
        if card.isComplete {
            match.finish(lowestScoreWins: GeneralsGame.lowestScoreWins)
            phase = .finished
            return
        }
        match.advanceTurn()
        phase = .handover
    }

    private func beginTurn() {
        hand = []
        keptCount = 0
        rollsUsed = 0
        session?.beginTurn()
        phase = .ready
    }

    private func startNewMatch() {
        match = TurnMatch.localTwoPlayer(seatSequence: GeneralsRules.snakeOrder)
        card = GeneralsCard()
        lastSummary = nil
        session?.setPool(GeneralsRules.makeDice())
        beginTurn()
    }

    // MARK: Chrome

}

// MARK: - The card

/// The shared scorecard, as a claim sheet and as a read-only reference.
///
/// The same view does both: during a turn it shows what the hand on the
/// table would pay in each open box and lets one be taken, and at any other
/// time it shows who holds what. Hiding the claimed half would hide the
/// thing that makes the game a race.
struct GeneralsCardView: View {
    let card: GeneralsCard
    let match: TurnMatch
    /// The hand being claimed with, or nil when this is just a look at the
    /// card — which is what makes the boxes tappable or not.
    let hand: [Int]?
    let onClaim: (GeneralsCategory) -> Void
    let onClose: () -> Void

    @ObservedObject private var theme = AppTheme.shared

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 2)

    var body: some View {
        ZStack {
            WoodTiledBackground()
                .ignoresSafeArea()
            Color.black.opacity(0.62)
                .ignoresSafeArea()

            VStack(spacing: 10) {
                // Which of these two words appears is the only signal that
                // the cells below are tappable, so the text is state-bearing
                // even though both strings are fixed.
                Text(hand == nil ? "Scorecard" : "Claim a Category")
                    .font(.poppins(40, .semibold))
                    .foregroundStyle(.white)

                // One sheet, with twelve cells printed on it — which is
                // what a scorecard is. It used to be twelve coloured
                // rectangles floating on a scrim, which read as a row of
                // buttons rather than as a card being filled in.
                //
                // The sheet now FILLS whatever it is given: the cells were
                // a fixed 62pt in a ScrollView, so on a phone the card
                // needed scrolling to see all twelve and on an iPad it was
                // a small sheet adrift in the middle of the screen. Six
                // rows of two, sized from the height available, with a
                // floor so a short screen falls back to scrolling rather
                // than to cells too small to read.
                GeometryReader { geo in
                    let cell = GeneralsCardLayout.cellHeight(forHeight: geo.size.height)
                    let sheet = LazyVGrid(columns: columns,
                                          spacing: GeneralsCardLayout.spacing) {
                        ForEach(GeneralsCategory.allCases) { category in
                            box(category, height: cell)
                        }
                    }
                        .padding(GeneralsCardLayout.sheetPadding)
                        .frame(maxWidth: .infinity)
                        .background(
                            Image(uiImage: LowPolyTextures.paperSurface())
                                .resizable()
                                .clipShape(RoundedRectangle(
                                    cornerRadius: ControlShape.cornerRadius))
                        )
                        // No elevation. The card is the surface the game
                        // is played on, not an object resting on one, and
                        // with the doubled offsets its shadow read as a
                        // second card behind it.
                        .padding(.horizontal, 12)

                    if GeneralsCardLayout.fits(in: geo.size.height) {
                        // Centred, because a GeometryReader pins its child
                        // to the top left — and on an iPad, where the cell
                        // height is capped, the sheet is shorter than the
                        // space and would otherwise sit against the top.
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            sheet
                            Spacer(minLength: 0)
                        }
                    } else {
                        // Too short for twelve legible cells — a phone in
                        // landscape, mostly. The sheet keeps its minimum
                        // and the card scrolls, which is what it did
                        // everywhere before this.
                        ScrollView { sheet }
                    }
                }

                Button {
                    SoundEngine.shared.play(.buttonTap)
                    onClose()
                } label: {
                    Text(hand == nil ? "Back" : "Not Yet")
                        .font(.poppins(15))
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .contentShape(RoundedRectangle(cornerRadius: ControlShape.cornerRadius))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .pixelPanel(fill: .solid(theme.accentColor.opacity(0.35)),
                            elevation: .resting)
                .padding(.horizontal, 44)
                .padding(.bottom, 10)
            }
            .padding(.top, 14)
        }
        .textCase(.uppercase)
    }

    /// What tints a cell.
    ///
    /// The accent keeps its job — "this one is yours to take" — but as a
    /// wash on the paper rather than a fill under white text. A claimed
    /// cell goes a shade darker, the way a filled-in box does.
    private func cellWash(isOpen: Bool, claimable: Bool) -> Color {
        guard isOpen else { return GeneralsPaper.ink.opacity(0.12) }
        return theme.accentColor.opacity(claimable ? 0.30 : 0.14)
    }

    private func box(_ category: GeneralsCategory, height: CGFloat) -> some View {
        let claim = card.claim(for: category)
        let isOpen = claim == nil
        let wouldScore = hand.map { category.score(for: $0) }

        return Button {
            guard isOpen, hand != nil else { return }
            onClaim(category)
        } label: {
            VStack(spacing: 2) {
                Text(category.displayName)
                    .font(.poppins(GeneralsCardLayout.nameSize(forCell: height), .medium))
                    .foregroundStyle(GeneralsPaper.ink.opacity(isOpen ? 0.95 : 0.5))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                if let claim {
                    Text("\(match.displayName(for: claim.participant)) · \(claim.points)")
                        .font(.poppins(GeneralsCardLayout.detailSize(forCell: height)))
                        .foregroundStyle(GeneralsPaper.ink.opacity(0.62))
                } else if let wouldScore {
                    // A zero is shown as a zero rather than hidden: taking
                    // one is a legal, and sometimes correct, move.
                    Text("\(wouldScore)")
                        .font(.poppins(GeneralsCardLayout.scoreSize(forCell: height), .semibold))
                        .foregroundStyle(GeneralsPaper.ink.opacity(wouldScore > 0 ? 1 : 0.45))
                } else {
                    Text(category.detail)
                        .font(.poppins(GeneralsCardLayout.detailSize(forCell: height)))
                        .foregroundStyle(GeneralsPaper.ink.opacity(0.58))
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .padding(.horizontal, 6)
            // A cell is PRINTED on the sheet: a wash and a rule, no
            // shadow of its own. Giving each cell depth is what made
            // twelve of them look like buttons — print has no depth, and
            // the sheet underneath already carries it.
            .background(
                RoundedRectangle(cornerRadius: ControlShape.cornerRadius * 0.5)
                    .fill(cellWash(isOpen: isOpen, claimable: hand != nil))
            )
            .overlay(
                RoundedRectangle(cornerRadius: ControlShape.cornerRadius * 0.5)
                    .stroke(GeneralsPaper.ink.opacity(isOpen ? 0.45 : 0.25), lineWidth: 1)
            )
        }
        .disabled(!isOpen || hand == nil)
    }
}

// MARK: - The scorecard's material

/// The ink the scorecard is printed in.
///
/// File scope rather than a static on the view, following `HubLayout` and
/// `PlayfieldLayout`, which is the shape the hub was rebuilt into after its
/// statics-on-a-View version would not build.
///
/// Reused from Baseball Dice's cards rather than a second dark — the suite
/// has been careful not to acquire colours it does not need.
enum GeneralsPaper {
    static let ink = Color(hex: "#2E2A22")
}

/// How big the scorecard is, given the screen it is on.
///
/// The card is twelve categories in six rows of two, and that shape does
/// not change with the device — so rather than scrolling a fixed sheet, the
/// cells take whatever height is going and the lettering follows them. A
/// scorecard is a sheet of paper on a table; it should be as big as the
/// table.
enum GeneralsCardLayout {

    static let rows = 6
    static let spacing: CGFloat = 8
    static let sheetPadding: CGFloat = 14

    /// Below this a cell cannot hold a name and a figure legibly, so the
    /// card scrolls instead of shrinking further.
    static let minCellHeight: CGFloat = 62

    /// And above this it stops being a scorecard and becomes a menu.
    static let maxCellHeight: CGFloat = 132

    /// What the sheet costs around the cells: its own padding, the gaps
    /// between the rows, and the shadow's breathing room.
    static let chrome: CGFloat = sheetPadding * 2 + spacing * CGFloat(rows - 1)

    static func cellHeight(forHeight available: CGFloat) -> CGFloat {
        let raw = (available - chrome) / CGFloat(rows)
        return min(maxCellHeight, max(minCellHeight, raw))
    }

    /// Whether twelve cells at their floor fit without scrolling.
    static func fits(in available: CGFloat) -> Bool {
        available >= minCellHeight * CGFloat(rows) + chrome
    }

    // The lettering scales with the cell rather than being fixed, so a
    // bigger card is actually easier to read rather than the same text
    // marooned in more paper.
    static func nameSize(forCell height: CGFloat) -> CGFloat {
        min(20, max(12, height * 0.19))
    }

    static func scoreSize(forCell height: CGFloat) -> CGFloat {
        min(34, max(20, height * 0.32))
    }

    static func detailSize(forCell height: CGFloat) -> CGFloat {
        min(16, max(10, height * 0.16))
    }
}
