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
                        .background(Color.black)

                        if phase == .pickingStyle || phase == .swinging {
                            cardOverlay
                        }
                        if phase == .reading, let line = lastLine {
                            resultBanner(line)
                        }
                    }
                    .frame(height: fieldHeight)
                    .overlay(alignment: .topLeading) {
                        if let onExit { overlayButton("chevron.left") { onExit() } }
                    }
                    .overlay(alignment: .topTrailing) {
                        overlayButton("gearshape.fill") { showingSettings = true }
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
                ScriptText("How long a game?", size: 46)
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
                                .font(.stackSans(20))
                                .foregroundStyle(.white)
                            Text(Self.lengthBlurb(innings))
                                .font(.stackSans(13))
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

    /// Three cards over a scrim, half the board's height, with the field
    /// still legible behind them — which matters most for the swing, since
    /// the batter is reading outs and runners while deciding.
    private var cardOverlay: some View {
        GeometryReader { geo in
            let cardHeight = geo.size.height * 0.5
            let choosingStyle = phase == .pickingStyle

            ZStack {
                Color(hex: "#0B1A10").opacity(0.62).ignoresSafeArea()

                VStack(spacing: 12) {
                    ScriptText(choosingStyle
                               ? "\(names[pitcher]) — pick your pitching style"
                               : "\(names[batter]) — pick your swing",
                               size: 34, lineLimit: 2, minimumScaleFactor: 0.6)
                        .textCase(nil)
                        .foregroundStyle(.white)

                    HStack(spacing: 10) {
                        if choosingStyle {
                            ForEach(PitchStyle.allCases) { option in
                                card(option.displayName, option.tagline,
                                     isSelected: styles[pitcher] == option,
                                     height: cardHeight) { styles[pitcher] = option }
                            }
                        } else {
                            ForEach(Swing.allCases) { option in
                                card(option.displayName, option.tagline,
                                     isSelected: swing == option,
                                     height: cardHeight) { swing = option }
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                }
            }
        }
    }

    private func card(_ title: String, _ detail: String,
                      isSelected: Bool, height: CGFloat,
                      action: @escaping () -> Void) -> some View {
        Button {
            SoundEngine.shared.play(.buttonTap)
            action()
        } label: {
            VStack(spacing: 8) {
                ScriptText(title, size: 28, lineLimit: 2, minimumScaleFactor: 0.6)
                    .textCase(nil)
                Text(detail)
                    .font(.stackSans(11))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .foregroundStyle(Color(hex: "#2E2A22"))
            .padding(12)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: ControlShape.cornerRadius)
                    .fill(Color(hex: "#F3EFE3"))
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
                        .font(.stackSans(13))
                        .foregroundStyle(.white.opacity(0.8))
                    Text("\(bat.batterRoll) − \(bat.pitcherRoll) = \(bat.differential >= 0 ? "+" : "")\(bat.differential)")
                        .font(.stackSans(15))
                        .foregroundStyle(.white.opacity(0.9))
                }
                ScriptText(line, size: 38, lineLimit: 2, minimumScaleFactor: 0.6)
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
        case .deepOut:   return "Caught at the wall."
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
            if throwDice() { phase = .rolling }
        case .reading:
            endAtBat()
        default:
            break
        }
    }

    private func overlayButton(_ systemName: String,
                               action: @escaping () -> Void) -> some View {
        Button {
            SoundEngine.shared.play(.buttonTap)
            action()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .semibold))
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
