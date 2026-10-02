import SwiftUI

/// Baseball Dice: pick a pitching style for the half-inning, then bat.
///
/// The turn cycle, which is the thing to hold in mind reading this:
///
///   match length (3/6/9)          — once, before anything
///     -> the pitcher picks a hidden STYLE
///     -> hand over
///     -> the opponent bats until three outs      [a swing card per at-bat]
///     -> they pick their own style, still holding the device
///     -> hand over, roles swap, repeat
///
/// One handover per half-inning, because the style pick rides along with the
/// handover that was already happening. The batter holds the device for the
/// whole half-inning, which is right — they are the one making choices and
/// rolling.
struct BaseballDiceScreen: View {

    var onExit: (() -> Void)? = nil

    @State private var match = TurnMatch.localTwoPlayer()
    @State private var state = BaseballDiceState(innings: 6)

    /// Which dice in the pool are the pitcher's, for this at-bat.
    ///
    /// The batter can throw dice of the same kind the pitcher throws, so
    /// neither position nor sides identifies them, and the Fastball's
    /// unfavoured pair throws two. See `throwDice`.
    @State private var pitcherDieIDs: Set<UUID> = []
    @State private var session: DiceTraySession?
    @State private var showingSettings = false
    @ObservedObject private var theme = AppTheme.shared

    @State private var phase: Phase = .setup
    @State private var styles: [PitchStyle?] = [nil, nil]
    @State private var swing: Swing?
    @State private var pitch: Pitch?
    @State private var lastAtBat: BaseballDiceRules.AtBat?
    @State private var lastLine: String?

    /// Draws each at-bat's pitch from the half-inning's style. Seeded so a
    /// replayed match produces the same pitches, like every roll in the suite.
    @State private var generator = SeededGenerator(seed: SeededGenerator.newSeed())

    /// The intro sting plays twice in a match and no more: with the very
    /// first throw, and once on the result screen. Two flags rather than
    /// one, because the second is a different moment and a match can end
    /// on an inning that had no first throw of its own.
    @State private var introHasPlayed = false
    @State private var outroHasPlayed = false

    private enum Phase {
        /// Choosing 3, 6 or 9 innings. Before anything else.
        case setup
        /// The pitching seat picks a style, screen turned away.
        case pickingStyle
        /// Handing the device to the batter.
        case handover
        /// The batter picks a swing, blind to the pitch.
        case swinging
        /// Both dice in the air.
        case rolling
        /// The throw has settled and both players are reading it.
        case reading
        /// Match decided.
        case finished
    }

    private var names: [String] {
        [match.displayName(for: match.participants[0]),
         match.displayName(for: match.participants[1])]
    }

    private var batter: Int { state.battingSeat }
    private var pitcher: Int { state.pitchingSeat }

    var body: some View {
        ZStack {
            GeometryReader { geo in
                let buttonHeight: CGFloat = 96
                let fieldHeight = geo.size.height - buttonHeight

                VStack(spacing: 0) {
                    ZStack {
                        DiceTraySceneView(
                            session: $session,
                            makeInitialDice: { [BaseballArt.die(sides: 8, isBatter: true)] },
                            floorTitle: "",
                            arenaStyle: .ballpark(),
                            onSessionCreated: { newSession in
                                newSession.onRollSettled = { results in
                                    settled(results)
                                }
                                // The posts are part of the playfield, so they
                                // go in as soon as there is a scene to put
                                // them in, and are refreshed to match the
                                // diamond as it stands.
                                BaseballColumns.install(
                                    in: newSession.scene,
                                    bounds: newSession.playAreaBounds,
                                    floorY: 0
                                )
                                BaseballScoreboard.install(
                                    in: newSession.scene,
                                    bounds: newSession.playAreaBounds,
                                    floorY: 0
                                )
                                refreshField(newSession)
                            }
                        )
                        .rollingWell()

                        if phase == .pickingStyle || phase == .swinging {
                            cardOverlay
                        }
                        if phase == .reading, let line = lastLine {
                            resultBanner(line)
                        }
                    }
                    .frame(height: fieldHeight)
                    .overlay(alignment: .topLeading) {
                        if let onExit { OverlayChromeButton(systemName: "chevron.left") { onExit() } }
                    }
                    .overlay(alignment: .topTrailing) {
                        OverlayChromeButton(systemName: "gearshape.fill") { showingSettings = true }
                    }

                    DiceRollButton(
                        label: primaryLabel,
                        isEnabled: isPrimaryEnabled,
                        subtitle: subtitle,
                        action: { primaryAction() }
                    )
                    .frame(height: buttonHeight)
                }
            }

            if phase == .setup { setupOverlay.transition(.opacity) }

            if phase == .handover {
                HandoverGate(match: match, lastTurnSummary: lastLine) {
                    phase = .swinging
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
            SettingsView(for: BaseballDiceGame.self)
        }
        .onAppear {
            AppFonts.registerIfNeeded()
            SoundEngine.shared.startMusic()
            // Decoded when the game opens, so the first swing of a match
            // is not also the first file read.
            BaseballAudio.preload()
        }
        // Nine screens had this and Baseball did not, which is why its
        // floor kept the old colour until something else rebuilt the
        // scene. refreshField comes with it: the runner posts are painted
        // from the theme too, and they were only repainted after an
        // at-bat — so the posts changed colour on the next roll rather
        // than when the colour was picked.
        .onValueChange(of: theme.colorwayIndex) { _ in
            session?.applyTheme()
            refreshField()
        }
    }

    /// Repaints everything on the pitch that carries state: the posts for
    /// the diamond as it now stands, and the scoreboard.
    ///
    /// Called after every at-bat and every half-inning, because both change
    /// who is on base, which side is batting, and what the board says.
    private func refreshField(_ target: DiceTraySession? = nil) {
        guard let live = target ?? session else { return }
        BaseballScoreboard.update(in: live.scene, state: state)
        BaseballColumns.update(
            in: live.scene,
            diamond: state.diamond,
            battingSeat: batter,
            battingColour: UIColor(hex: AppTheme.swatches[AppTheme.shared.colorwayIndex].hex),
            waitingColour: UIColor(hex: "#0A0A0C")
        )
    }

    // MARK: Setup

    private var setupOverlay: some View {
        ZStack {
            Color.black.opacity(0.9).ignoresSafeArea()
            VStack(spacing: 14) {
                // A fixed string, but it is a question the player has to
                // answer before the game will start, so it is an
                // instruction rather than a title.
                Text("How long a game?")
                    .font(.poppins(46, .semibold))
                    .textCase(nil)
                    .foregroundStyle(.white)

                ForEach(BaseballDiceRules.lengths, id: \.self) { innings in
                    Button {
                        SoundEngine.shared.play(.buttonTap)
                        state = BaseballDiceState(innings: innings)
                        // The board's column count comes from the state, so
                        // it has to be repainted the moment the state says
                        // something different — otherwise it keeps the
                        // previous match's grid until the first at-bat ends.
                        refreshField()
                        phase = .pickingStyle
                    } label: {
                        VStack(spacing: 2) {
                            Text("\(innings) Innings")
                                .font(.poppins(20, .semibold))
                                .foregroundStyle(.white)
                            Text(Self.lengthBlurb(innings))
                                .font(.poppins(13))
                                .foregroundStyle(.white.opacity(0.75))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: ControlShape.cornerRadius)
                                .fill(theme.accentColor.opacity(0.9))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 30)
        }
    }

    /// Measured over 30,000 games apiece, so the labels promise what the game
    /// delivers rather than a guess at it.
    static func lengthBlurb(_ innings: Int) -> String {
        switch innings {
        case 3:  return "Short — about 30 at-bats"
        case 6:  return "Medium — about 60 at-bats"
        default: return "Extra long — about 90 at-bats"
        }
    }

    // MARK: The card overlay

    /// Three cards over a light scrim, stacked down the screen so each one
    /// gets the full width.
    ///
    /// They were three across at a third of the width each, which is why
    /// the mark and the lettering could not grow: on a 393pt phone a third
    /// is 120pt whatever the type size says, and `minimumScaleFactor`
    /// quietly shrank the name back down to fit. A column gives every card
    /// the whole width, so the mark and the name are genuinely twice what
    /// they were, and the field still reads through all three.
    private var cardOverlay: some View {
        GeometryReader { geo in
            let cardHeight = min(geo.size.height * BaseballCardLayout.heightFraction,
                                 BaseballCardLayout.maxHeight)
            let cardWidth = min(geo.size.width - BaseballCardLayout.margin * 2,
                                BaseballCardLayout.maxCardWidth)
            let choosingStyle = phase == .pickingStyle

            ZStack {
                Color(hex: "#0B1A10").opacity(BaseballCardLayout.scrimOpacity)
                    .ignoresSafeArea()

                VStack(spacing: BaseballCardLayout.gap) {
                    // Names a player and tells them what to do. Shrinks to
                    // 0.6, which a script face does not survive.
                    Text(choosingStyle
                         ? "\(names[pitcher]) — pick your pitching style"
                         : "\(names[batter]) — pick your swing")
                        .font(.poppins(BaseballCardLayout.headlineSize, .semibold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                        .multilineTextAlignment(.center)
                        .textCase(nil)
                        .foregroundStyle(.white)
                        .padding(.bottom, 4)

                    if choosingStyle {
                        ForEach(PitchStyle.allCases) { option in
                            card(option.displayName, option.tagline,
                                 icon: option.iconName,
                                 isSelected: styles[pitcher] == option,
                                 width: cardWidth,
                                 height: cardHeight) { styles[pitcher] = option }
                        }
                    } else {
                        ForEach(Swing.allCases) { option in
                            card(option.displayName, option.tagline,
                                 icon: option.iconName,
                                 isSelected: swing == option,
                                 width: cardWidth,
                                 height: cardHeight) { swing = option }
                        }
                    }
                }
            }
        }
    }

    /// One card: the mark on the left, the name and the line it needs on
    /// the right. Laid out along the long axis, which is what a full-width
    /// card has and a column of three narrow ones did not.
    private func card(_ title: String, _ detail: String,
                      icon: String, isSelected: Bool,
                      width: CGFloat, height: CGFloat,
                      action: @escaping () -> Void) -> some View {
        Button {
            SoundEngine.shared.play(.buttonTap)
            action()
        } label: {
            HStack(spacing: BaseballCardLayout.padding) {
                NetIconView(name: icon, tint: Color(hex: "#2E2A22"))
                    .frame(width: height * BaseballCardLayout.iconFraction,
                           height: height * BaseballCardLayout.iconFraction)

                VStack(alignment: .leading, spacing: 2) {
                    // The label on a button the player is choosing between —
                    // and the tagline directly below it was already sans, so
                    // this also stops one card carrying two faces.
                    Text(title)
                        .font(.poppins(BaseballCardLayout.titleSize, .semibold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                        .multilineTextAlignment(.center)
                        .textCase(nil)
                    Text(detail)
                        .font(.poppins(BaseballCardLayout.detailSize))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundStyle(Color(hex: "#2E2A22"))
            .padding(BaseballCardLayout.padding)
            .frame(width: width, height: height)
            .background(
                RoundedRectangle(cornerRadius: ControlShape.cornerRadius)
                    .fill(Color(hex: "#F3EFE3").opacity(BaseballCardLayout.cardOpacity))
            )
            .overlay(
                RoundedRectangle(cornerRadius: ControlShape.cornerRadius)
                    .stroke(isSelected ? theme.accentColor : Color(hex: "#2E2A22"),
                            lineWidth: isSelected ? 3 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func resultBanner(_ line: String) -> some View {
        VStack {
            Spacer(minLength: 0)
            VStack(spacing: 4) {
                if let bat = lastAtBat {
                    Text("\(bat.pitch.displayName) vs \(bat.swing.displayName)  \(bat.matchup.kind.symbol)")
                        .font(.poppins(13))
                        .foregroundStyle(.white.opacity(0.8))
                    Text("\(bat.batterRoll) − \(bat.pitcherRoll) = \(bat.differential >= 0 ? "+" : "")\(bat.differential)")
                        .font(.poppins(15))
                        .foregroundStyle(.white.opacity(0.9))
                }
                // The outcome of the at-bat: "Caught at the wall — third
                // out, the run does not count." The most information-dense
                // string in the game, long enough to shrink onto two lines,
                // and it sat above dice arithmetic that was already sans.
                Text(line)
                    .font(.poppins(38, .medium))
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .multilineTextAlignment(.center)
                    .textCase(nil)
                    .foregroundStyle(.white)
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(Color.black.opacity(0.72))
            Spacer(minLength: 0)
        }
    }

    // MARK: Flow

    private func throwDice() -> Bool {
        guard let session, let swing else { return false }
        guard let style = styles[pitcher] else { return false }

        // The pitch is drawn here, from the half-inning's style, and is never
        // shown before the dice land — that is the whole reason a style is a
        // mix rather than a pitch.
        let drawn = style.pitch(using: &generator)
        pitch = drawn

        let matchup = BaseballDiceRules.matchup(pitch: drawn, swing: swing)
        var pool = (0..<matchup.batterDice).map { _ in
            BaseballArt.die(sides: matchup.batterSides, isBatter: true)
        }
        let pitcherDice = (0..<matchup.pitcherDice).map { _ in
            BaseballArt.die(sides: matchup.pitcherSides, isBatter: false)
        }
        pool.append(contentsOf: pitcherDice)

        // The pitcher's dice are remembered by ID, not by where they sit.
        //
        // This used to be read as `results.last`, on the stated contract
        // that results come back in the pool's order — and the pool was
        // being shuffled on its way into the scene, so on a favoured
        // at-bat (two batter dice and the pitcher's d4) that read a
        // batter's die two thirds of the time. The shuffle is fixed at
        // source, in DicePoolLifecycleController; this is the belt to its
        // braces. An ID cannot be reordered, and a set of them does not
        // care that the Fastball now throws two.
        pitcherDieIDs = Set(pitcherDice.map(\.id))

        session.beginTurn()
        session.setPool(pool)
        return session.roll()
    }

    private func settled(_ results: [DiceTraySession.DieResult]) {
        guard phase == .rolling, let pitch, let swing else { return }
        let matchup = BaseballDiceRules.matchup(pitch: pitch, swing: swing)

        // Taken by ID, not by position and not by sides: two matchups throw
        // the same number of sides on both sides of the at-bat, so picking
        // by sides would read the wrong dice, and picking by position
        // depends on an ordering this screen does not own.
        let pitcherRolls = results.filter { pitcherDieIDs.contains($0.id) }
            .map(\.value)
        let batterRolls = results.filter { !pitcherDieIDs.contains($0.id) }
            .map(\.value)
        guard pitcherRolls.count == matchup.pitcherDice,
              batterRolls.count == matchup.batterDice else { return }

        let bat = BaseballDiceRules.atBat(pitch: pitch, swing: swing,
                                          batterRolls: batterRolls,
                                          pitcherRolls: pitcherRolls)
        lastAtBat = bat

        // The whole sequence goes here rather than at the throw: the dice
        // ARE the pitch and the swing, so until they settle there is no
        // way to know whether this was a hit, a catch or a ball four.
        BaseballAudio.play(bat.result)

        var diamond = state.diamond
        // bat.pitcherRoll, not a local: it is the KEPT die, so the double
        // play's even/odd test reads the same number the differential did.
        let effect = BaseballDiceRules.advance(&diamond, result: bat.result,
                                               pitcherRoll: bat.pitcherRoll,
                                               outs: state.outs)
        state.diamond = diamond
        // state.score, not state.runs[batter] += — the total and the line
        // score the board draws are the same runs, and one mutator is what
        // stops them disagreeing.
        state.score(effect.runs)
        state.outs += effect.outs
        mirrorScores()
        refreshField()
        lastLine = line(for: bat, effect: effect)
        phase = .reading
    }

    /// TurnMatch has no setter for a participant's score, so the runs are
    /// mirrored into its dictionary directly. State is the source of truth;
    /// the match carries it only so the shared scoreboard and result screen
    /// can read it.
    private func mirrorScores() {
        for seat in 0..<2 {
            match.scores[match.participants[seat]] = state.runs[seat]
        }
    }

    private func line(for bat: BaseballDiceRules.AtBat,
                      effect: BaseballDiceRules.Advance) -> String {
        if bat.isJackpot { return "Double max — it is gone!" }
        if effect.isDoublePlay { return "Double play. Two down." }
        if effect.isSacrificeFly { return "Sacrifice fly — a run scores." }
        switch bat.result {
        case .homeRun:
            return effect.runs > 1 ? "Home run — \(effect.runs) score!" : "Home run!"
        case .triple, .double, .single:
            return effect.runs > 0
                ? "\(bat.result.displayName) — \(effect.runs) in."
                : bat.result.displayName
        case .walk:
            return effect.runs > 0 ? "Walk, forced in." : "Walk."
        case .strikeout: return "Strikeout."
        case .deepOut:
            return effect.strandedOnThird
                ? "Caught at the wall — third out, the run does not count."
                : "Caught at the wall."
        case .fieldOut:  return "Field out."
        }
    }

    /// Closes the at-bat, then the half-inning, then the match.
    private func endAtBat() {
        swing = nil
        pitch = nil

        guard state.outs >= BaseballDiceRules.outsPerHalfInning else {
            phase = .swinging          // same batter's side, next hitter
            return
        }

        state.endHalfInning()
        refreshField()
        if isMatchOver() {
            match.finish(lowestScoreWins: BaseballDiceGame.lowestScoreWins)
            phase = .finished
            if !outroHasPlayed {
                outroHasPlayed = true
                BaseballAudio.playIntro()
            }
            return
        }

        // The seat that just batted now pitches, and picks its style while
        // still holding the device — one handover per half-inning.
        styles[state.pitchingSeat] = nil
        match.activeIndex = state.battingSeat
        phase = .pickingStyle
    }

    /// True once a scheduled game is complete and somebody leads.
    ///
    /// Checked only at the top of an inning, which is what makes extras work:
    /// a level score simply lets play continue into inning n+1.
    private func isMatchOver() -> Bool {
        state.isTopHalf
            && state.inning > state.innings
            && state.runs[0] != state.runs[1]
    }

    private func startNewMatch() {
        match = TurnMatch.localTwoPlayer()
        state = BaseballDiceState(innings: state.innings)
        styles = [nil, nil]
        swing = nil
        pitch = nil
        lastAtBat = nil
        lastLine = nil
        generator = SeededGenerator(seed: SeededGenerator.newSeed())
        // A new match gets its intro back — it is the first throw of THAT
        // match the sting belongs to.
        introHasPlayed = false
        outroHasPlayed = false
        phase = .setup
    }

    // MARK: Button

    private var primaryLabel: String {
        switch phase {
        case .setup:        return ""
        case .pickingStyle: return styles[pitcher] == nil ? "Pick a Style" : "Hide It"
        case .handover:     return "Pass"
        case .swinging:     return swing == nil ? "Pick a Swing" : "Swing"
        case .rolling:      return "Rolling"
        case .reading:      return "Next Batter"
        case .finished:     return "Done"
        }
    }

    private var isPrimaryEnabled: Bool {
        switch phase {
        case .pickingStyle: return styles[pitcher] != nil
        case .swinging:     return swing != nil && session != nil
        case .reading:      return true
        default:            return false
        }
    }

    private var subtitle: String {
        switch phase {
        case .pickingStyle:
            return "\(names[batter]) must not see this"
        case .swinging:
            return "\(state.outs) out · \(state.diamond.runnerCount) on · \(state.runs[0])-\(state.runs[1])"
        case .reading:
            return "\(state.outs) out · \(state.runs[0])-\(state.runs[1])"
        default:
            return ""
        }
    }

    private func primaryAction() {
        SoundEngine.shared.play(.buttonTap)
        switch phase {
        case .pickingStyle:
            match.activeIndex = state.battingSeat
            phase = .handover
        case .swinging:
            if throwDice() {
                // With the VERY FIRST throw of the match, and never again.
                if !introHasPlayed {
                    introHasPlayed = true
                    BaseballAudio.playIntro()
                }
                phase = .rolling
            }
        case .reading:
            endAtBat()
        default:
            break
        }
    }

}

// MARK: - Dice

enum BaseballArt {

    /// The two sides' dice are coloured apart, because two matchups throw the
    /// same die on both sides: a Fastball against a Power Swing is d12 versus
    /// d12, and a Slider against Patient is d8 versus d8. Without colour
    /// those throws would be unreadable.
    ///
    /// The batter takes the player's chosen table colour; the pitcher is
    /// black with TAN numerals, because Onyx (#14140F) is in the colour
    /// selector and a black-on-white die would otherwise be indistinguishable
    /// from a player who picked it.
    static func die(sides: Int, isBatter: Bool) -> Die {
        Die(
            sides: sides,
            colorway: DieColorway(
                bodyHex: isBatter ? AppTheme.swatches[AppTheme.shared.colorwayIndex].hex
                                 : "#0A0A0C",
                numberHex: isBatter ? "#1B1B1F" : "#C9B18A"
            )
        )
    }
}

// MARK: - The selection cards' geometry

/// One place for the size and weight of the pitching-style and swing cards.
///
/// File scope rather than statics on the view, following `PlayfieldLayout`
/// and `HubLayout`, which is the shape the hub was rebuilt into after its
/// statics-on-a-View version would not build.
///
/// The cards used to be half the board's height on opaque stock over a 0.62
/// scrim, which hid the outs, the runners and the score at exactly the
/// moment a player is deciding against them.
enum BaseballCardLayout {

    /// One card's height as a fraction of the playfield, capped so a tall
    /// phone does not turn three cards into three billboards.
    ///
    /// Three of these plus the headline is what the overlay costs — about
    /// 60% of the board at the cap, which is what the previous three-across
    /// row cost as well. The card itself is roughly twice the area, because
    /// it now spans the width rather than a third of it.
    static let heightFraction: CGFloat = 0.17
    static let maxHeight: CGFloat = 150

    /// Full width less a margin, capped so an iPad does not stretch a card
    /// to a line of text nobody can scan.
    static let maxCardWidth: CGFloat = 560
    static let margin: CGFloat = 14

    /// Between the cards, and under the headline.
    static let gap: CGFloat = 12

    /// The mark, as a fraction of the card's height — square, so it takes
    /// the same from both. At the 150pt cap that is a 105pt mark against
    /// the 88pt the three-across cards could manage.
    static let iconFraction: CGFloat = 0.7

    /// The lettering. These are real sizes now rather than sizes a
    /// `minimumScaleFactor` immediately undoes: a full-width card has room
    /// for "Power Pitcher" at 40 without scaling it back.
    static let titleSize: CGFloat = 40
    static let detailSize: CGFloat = 15
    static let headlineSize: CGFloat = 34
    static let padding: CGFloat = 14

    /// The card stock's opacity — 0.7, so the field reads through it while
    /// the ink on top stays legible. Lower it and the dark lettering starts
    /// to fight the grass behind it; this is the one constant to move.
    static let cardOpacity: Double = 0.7

    /// Enough to separate the cards from the field without covering it.
    static let scrimOpacity: Double = 0.28
}
