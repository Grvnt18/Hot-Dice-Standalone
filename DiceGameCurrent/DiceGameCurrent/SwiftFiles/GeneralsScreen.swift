import SwiftUI

struct GeneralsScreen: View {

    var onExit: (() -> Void)? = nil

    @State private var match = TurnMatch.passAndPlay(seatSequence: GeneralsRules.snakeOrder)
    @State private var card = GeneralsCard()
    @State private var session: DiceTraySession?
    @State private var hand: [Int] = []
    @State private var keptCount = 0
    @State private var rollsUsed = 0
    @State private var phase: Phase = .ready
    @State private var lastSummary: String?
    @State private var showingSettings = false
    @State private var showingCard = false

    /// The box the player has tapped but not yet taken.
    ///
    /// Taking a category is the one irreversible move in the game — the box
    /// is gone for the rest of the match, and the turn ends with it — and it
    /// used to happen on the first tap, with nothing between a misread cell
    /// and a spent category. So the card SELECTS and the bar CONFIRMS, which
    /// is the shape Rollbots' attack menu already uses: pick the thing, read
    /// what it does, then commit on the bar.
    @State private var pendingCategory: GeneralsCategory?
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
                        secondaryLabel: secondaryLabel,
                        subtitle: subtitle,
                        onPrimary: { primaryAction() },
                        onSecondary: { secondaryAction() }
                    )
                    .frame(height: buttonHeight)
                }
                // The card sits OVER the table and UNDER the bar.
                //
                // It was a full-screen layer in the outer ZStack, which
                // covered the bar along with everything else — fine while
                // a tap on a box was the whole move, and impossible once
                // the bar is what confirms it. So it is an overlay on the
                // split instead, given the screen less the band, and the
                // two scrims inside it no longer reach past that.
                //
                // Same region the Rollbots menu takes for the same reason:
                // the choice covers the table, the thing that commits it
                // stays where it always is.
                .overlay(alignment: .top) {
                    if showingCard {
                        GeneralsCardView(
                            card: card,
                            match: match,
                            hand: phase == .decide ? hand : nil,
                            selected: pendingCategory,
                            onSelect: { category in select(category) },
                            onClose: { closeCard() }
                        )
                        .frame(height: max(geo.size.height - buttonHeight, 0))
                        .transition(.opacity)
                    }
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

    /// What the bar says, and the card is what changes it.
    ///
    /// While the card is open over the table the bar is the confirm: it
    /// names the box that is about to be taken, so the commitment is
    /// readable on the thing being pressed rather than only in the cell
    /// that was tapped.
    private var primaryLabel: String {
        if showingCard {
            guard let pendingCategory else { return "Take a Category" }
            return "Take \(pendingCategory.displayName)"
        }
        switch phase {
        case .ready:    return "Roll"
        case .rolling:  return "Rolling"
        case .decide:   return "Roll Again"
        case .scored:   return card.isComplete ? "Finish" : "Pass"
        case .handover: return "Pass"
        case .finished: return "Done"
        }
    }

    /// Which secondary the bar carries: the one that OPENS the card, or
    /// the one that backs out of it.
    private var secondaryLabel: String? {
        if showingCard {
            // The read-only card keeps its own Back button, so the bar
            // stays out of it rather than putting a second closer an inch
            // under the first.
            guard phase == .decide else { return nil }
            // "View Dice" once a box is picked, because that is what
            // closing the card actually does from here: the hand is on the
            // table under it, and a player checking a count before they
            // commit wants to look at the dice rather than to be told they
            // have not decided yet. With nothing picked there is nothing to
            // go back to, so it stays "Close".
            return pendingCategory == nil ? "Close" : "View Dice"
        }
        return phase == .decide ? "Claim" : nil
    }

    private var subtitle: String {
        if showingCard {
            guard phase == .decide else { return "" }
            guard let pendingCategory else {
                return "Tap a category, then confirm below"
            }
            let points = pendingCategory.score(for: hand)
            return points > 0
                ? "\(pendingCategory.displayName) pays \(points)"
                : "\(pendingCategory.displayName) scores nothing — crossing it off"
        }
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
        // With the card open the bar has exactly one job, and nothing to do
        // until a box is picked. This is also what stops a roll being
        // thrown through the card — the bar is visible under it now, and
        // "Roll Again" behind a scorecard would be a turn spent blind.
        if showingCard { return pendingCategory != nil }
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
        // The confirm, when the card is what is on screen. `claim` plays
        // its own tap and checks the phase, so this neither sounds twice
        // nor needs to.
        if showingCard {
            if let pendingCategory { claim(pendingCategory) }
            return
        }
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

    private func secondaryAction() {
        showingCard ? closeCard() : openCard()
    }

    private func openCard() {
        SoundEngine.shared.play(.buttonTap)
        pendingCategory = nil
        showingCard = true
    }

    /// Backs out, and forgets the selection with it.
    ///
    /// A pending box left behind a closed card is a bar still offering to
    /// take something the player cannot see — and the chrome button can
    /// reopen the card between turns, when the hand it was selected
    /// against is long gone.
    private func closeCard() {
        SoundEngine.shared.play(.buttonTap)
        pendingCategory = nil
        showingCard = false
    }

    /// Picks a box, or unpicks it.
    ///
    /// Tapping the selected one again clears it, so a change of mind needs
    /// no separate control — the same thing the dice selection does.
    private func select(_ category: GeneralsCategory) {
        guard phase == .decide else { return }
        SoundEngine.shared.play(.buttonTap)
        pendingCategory = pendingCategory == category ? nil : category
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
        pendingCategory = nil
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
        pendingCategory = nil
        session?.beginTurn()
        phase = .ready
    }

    private func startNewMatch() {
        match = TurnMatch.passAndPlay(seatSequence: GeneralsRules.snakeOrder)
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
    /// The box the bar is currently offering to take, drawn as picked.
    let selected: GeneralsCategory?
    /// Picks a box. Taking it is the BAR's job — see
    /// GeneralsScreen.pendingCategory for why the two are separate.
    let onSelect: (GeneralsCategory) -> Void
    let onClose: () -> Void

    @ObservedObject private var theme = AppTheme.shared

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 2)

    var body: some View {
        ZStack {
            // NOT ignoresSafeArea, either of them. This view is given the
            // screen less the button band now — see the overlay in
            // GeneralsScreen — and a scrim that ignores the safe area
            // ignores that frame too, which would put a 62% black over the
            // bar the card is waiting on.
            WoodTiledBackground()
            Color.black.opacity(0.62)

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

                // Only when the card is a LOOK at the card.
                //
                // While a hand is on the table the bar below carries both
                // halves — "Take <category>" and "Not Yet" — and a third
                // closer sitting directly above it was two buttons doing
                // one job, an inch apart. The read-only card has no bar to
                // lean on: every other phase leaves the primary disabled
                // and the secondary absent, so this is its only way out.
                if hand == nil {
                    Button {
                        SoundEngine.shared.play(.buttonTap)
                        onClose()
                    } label: {
                        // "Close", the same word the bar uses for the
                        // same act in the same screen — this button and
                        // the bar's secondary both just put the card away.
                        Text("Close")
                            .font(.poppins(15))
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .contentShape(RoundedRectangle(
                                cornerRadius: ControlShape.cornerRadius))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .pixelPanel(fill: .solid(theme.accentColor.opacity(0.35)),
                                elevation: .resting)
                    .padding(.horizontal, 44)
                    .padding(.bottom, 10)
                }
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
    private func cellWash(isOpen: Bool, claimable: Bool,
                          picked: Bool) -> Color {
        guard isOpen else { return GeneralsPaper.ink.opacity(0.12) }
        if picked { return theme.accentColor.opacity(0.72) }
        return theme.accentColor.opacity(claimable ? 0.30 : 0.14)
    }

    private func box(_ category: GeneralsCategory, height: CGFloat) -> some View {
        let claim = card.claim(for: category)
        let isOpen = claim == nil
        let wouldScore = hand.map { category.score(for: $0) }

        let picked = selected == category

        return Button {
            guard isOpen, hand != nil else { return }
            onSelect(category)
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
                    .fill(cellWash(isOpen: isOpen, claimable: hand != nil,
                                   picked: picked))
            )
            // The picked box takes a heavier rule as well as a deeper
            // wash. Two cues rather than one, because the wash is the
            // accent colour and the player chooses that: on the paler
            // colourways a single step of opacity is not much of a
            // signal, and this is the box about to be spent.
            .overlay(
                RoundedRectangle(cornerRadius: ControlShape.cornerRadius * 0.5)
                    .strokeBorder(GeneralsPaper.ink.opacity(
                        picked ? 0.95 : (isOpen ? 0.45 : 0.25)),
                                  lineWidth: picked ? 3 : 1)
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
