import SwiftUI

/// Shared chrome for every alternating game: the scoreboard, the handover
/// gate between turns, and the end-of-match result.
///
/// Pass-and-play exists because the Messages extension is the last step and
/// gated on a Mac — until then there is no way for two people to play at
/// all. It is not scaffolding, though: it drives exactly the state
/// transitions a received message will drive, so the extension inherits a
/// path that has already been played rather than a second one written blind.

// MARK: - Scoreboard

/// Round, both totals, and whose turn — the strip every alternating game
/// carries above its playfield.
struct MatchScoreboard: View {
    let match: TurnMatch
    let totalRounds: Int?
    let subtitle: String?

    var body: some View {
        ZStack {
            WoodTiledBackground()

            // `maxWidth: .infinity` on the stack and on both lines of
            // text, so they centre on the SCREEN rather than on whatever
            // the row of seat tiles happens to be wide. A VStack hugs its
            // widest child, which means two seats of uneven name length
            // were quietly deciding where "Round 3 of 6" sat.
            VStack(spacing: 4) {
                if let totalRounds {
                    Text("Round \(min(match.round, totalRounds)) of \(totalRounds)")
                        // Semibold throughout this strip and the bar below
                        // it. Everything here is small white type over
                        // timber at reduced opacity, and regular Poppins at
                        // 11 and 12 has strokes narrower than the grain it
                        // is printed on — which is exactly the state the
                        // header of Rolls was in, and the same fix applies
                        // to the ten games that use this instead.
                        .font(.poppins(12, .semibold))
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                }

                HStack(spacing: 10) {
                    ForEach(match.participants, id: \.self) { participant in
                        seat(participant)
                    }
                }

                if let subtitle, !subtitle.isEmpty {
                    // "<name> to roll" and the other phase lines — see
                    // each screen's `statusLine`. The white text the
                    // request named.
                    Text(subtitle)
                        .font(.poppins(11, .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        // Pinned like every game screen (see DiceGameShell's note): these
        // layouts are geometric, and at the larger accessibility sizes the
        // labels win the fight with the frames they sit in. AppFonts' faces
        // use the relativeTo: overload, so shrink-to-fit still works inside
        // the pinned size.
        .dynamicTypeSize(.large)
    }

    private func seat(_ participant: String) -> some View {
        let isActive = participant == match.activeParticipant && !match.isOver
        return VStack(spacing: 1) {
            Text(match.displayName(for: participant))
                .font(.poppins(11, .semibold))
                .foregroundStyle(.white.opacity(isActive ? 0.95 : 0.6))
                // Shrink rather than wrap, now that these are typed names
                // at up to twelve characters and there can be four of them
                // across the strip.
                //
                // Measured off Poppins-SemiBold at 11pt: four tiles on the
                // narrowest phone this app meets (375pt, iPhone SE) come to
                // 80.2pt each, and a twelve-character name sets at about
                // 75pt — "Alexandria W" is 74.7. So it fits, and this fires
                // only for a name of unusually wide glyphs: twelve capital
                // Ms is 118.7pt, which scales to 83pt at the 0.7 floor and
                // still truncates. Without the two lines the tile grows a
                // SECOND LINE instead, and the whole strip changes height
                // the moment somebody types a long name.
                //
                // Four is also why `MatchSetup.maxSeats` is four — see
                // there; this is the measurement it is standing on.
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text("\(match.score(for: participant))")
                .font(.poppins(22, .semibold))
                .foregroundStyle(.white.opacity(isActive ? 1 : 0.65))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: ControlShape.cornerRadius)
                // The active seat is the only lit one, so whose turn it is
                // is readable at a glance without a separate label.
                .fill(Color.black.opacity(isActive ? 0.42 : 0.18))
        )
    }
}

// MARK: - Action bar

/// The button band for a game where a turn can offer a choice.
///
/// `DiceRollButton` is one button and Rolls needs no more than that.
/// Freighter.Yacht.Dinghy's cargo reroll is the first real decision in the suite — take
/// the throw or sail with what you have — and Generals' keep-or-score is
/// the same shape, so the two-button case lives here rather than being
/// rebuilt per game. With no secondary label this renders exactly like
/// `DiceRollButton`.
struct TurnActionBar: View {
    let primaryLabel: String
    let primaryEnabled: Bool
    /// Nil when the turn offers no choice.
    var secondaryLabel: String? = nil
    var subtitle: String = ""
    let onPrimary: () -> Void
    var onSecondary: () -> Void = {}

    @ObservedObject private var theme = AppTheme.shared

    var body: some View {
        // Spacing read off the shadow ladder rather than typed.
        //
        // It was 2, and `.lifted` throws its shadow 6pt down — so four
        // points of hard-edged shadow landed on the line of text below the
        // button, in this bar and in Rolls' own. Two is a gap between a
        // button and a caption; six is the thing the button is casting.
        VStack(spacing: Elevation.lifted.offset + 2) {
            HStack(spacing: 10) {
                // `.plain` + `.pixelPanel`, which is what Rolls' roll
                // button wears — see DiceRollButton.
                //
                // These ten games were on `.borderedProminent` with a
                // tint: a system shape with a system fill, no pixel
                // outline, no bevel and no Elevation shadow. That is the
                // mismatch, and it was never a tuning difference — it is
                // two different button systems, one of which the restyle
                // replaced everywhere except here.
                Button {
                    onPrimary()
                } label: {
                    Text(primaryLabel)
                        .font(.poppins(15))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        // Load-bearing: `.plain` hit-tests what it draws,
                        // and a frame around a Text is layout rather than
                        // something to tap.
                        .contentShape(RoundedRectangle(cornerRadius: ControlShape.cornerRadius))
                }
                .buttonStyle(.plain)
                .foregroundStyle(primaryEnabled
                                 ? Color.white
                                 : Color.white.opacity(0.5))
                .pixelPanel(fill: .solid(primaryEnabled
                                         ? theme.accentColor
                                         : theme.accentColor.opacity(0.4)),
                            elevation: .lifted)
                .disabled(!primaryEnabled)

                if let secondaryLabel {
                    // The same panel, unfilled, so a secondary action reads
                    // as the same control at a lower weight rather than as
                    // a different kind of button.
                    Button {
                        onSecondary()
                    } label: {
                        Text(secondaryLabel)
                            .font(.poppins(15))
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .contentShape(RoundedRectangle(cornerRadius: ControlShape.cornerRadius))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.accentTextColor)
                    .pixelPanel(fill: .solid(theme.accentColor.opacity(0.35)),
                                elevation: .resting)
                }
            }

            if !subtitle.isEmpty {
                // The line beneath the buttons, matching the roll button's
                // own — see DiceRollButton.
                Text(subtitle)
                    .font(.poppins(12, .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        // Fills the band it is handed, like DiceGameShell's own bar.
        //
        // This is the gap. Converting these buttons from
        // `.borderedProminent` to `.plain` + `.pixelPanel` took away the
        // system style's intrinsic padding, so the stack got shorter — and
        // without this it sizes to its content and sits CENTRED in a band
        // the caller fixes with `.frame(height: buttonHeight)`, leaving
        // bare screen above and below it where the timber used to reach.
        //
        // The other bar got this line in the same change, for the same
        // reason, and only seven of the eleven games use this one. That is
        // why the gap appeared in some games and not others.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WoodTiledBackground())
    }
}

// MARK: - Handover

/// The screen between turns.
///
/// Its entire job is to stop the next player seeing the last player's roll
/// while the device changes hands. It deliberately shows the score and
/// nothing else about the turn that just happened — and it requires a tap,
/// rather than a timer, so nobody is rushed while passing.
struct HandoverGate: View {
    let match: TurnMatch
    let lastTurnSummary: String?
    let onReady: () -> Void

    @ObservedObject private var theme = AppTheme.shared

    var body: some View {
        ZStack {
            WoodTiledBackground()
                .ignoresSafeArea()

            // Opaque, not translucent: anything showing through would
            // defeat the point of the gate.
            Color.black.opacity(0.55)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                if let lastTurnSummary, !lastTurnSummary.isEmpty {
                    Text(lastTurnSummary)
                        .font(.poppins(15))
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                }

                // "Pass to", because that is exactly what happens: this
                // is the standalone, where one device goes round a table.
                //
                // It read "Over to" for a while, when one codebase was
                // becoming an iMessage game and a turn was going to arrive
                // in a message rather than in somebody's hand. That version
                // is its own repository now, and this one can say the true
                // thing again. Note the view is under .textCase(.uppercase).
                Text("Pass to \(match.activeDisplayName)")
                    .font(.poppins(46, .semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)

                HStack(spacing: 14) {
                    ForEach(match.participants, id: \.self) { participant in
                        VStack(spacing: 2) {
                            Text(match.displayName(for: participant))
                                .font(.poppins(11, .semibold))
                                .foregroundStyle(.white.opacity(0.7))
                            Text("\(match.score(for: participant))")
                                .font(.poppins(24, .bold))
                                .foregroundStyle(.white)
                        }
                    }
                }

                Button {
                    SoundEngine.shared.play(.buttonTap)
                    onReady()
                } label: {
                    Text("I'm Ready")
                        .font(.poppins(16))
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .contentShape(RoundedRectangle(cornerRadius: ControlShape.cornerRadius))
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.accentTextColor)
                .pixelPanel(fill: .solid(theme.accentColor), elevation: .lifted)
                .padding(.horizontal, 44)
            }
        }
        .textCase(.uppercase)
    }
}

// MARK: - Result

/// End-of-match screen.
///
/// Replaces `TurnCompleteOverlay` for suite games. That overlay's praise
/// bands are explicitly golf-scored for Rolls ("Lower is better… bands run
/// from 0 up"), which is wrong for every game but Rolls, so rather than
/// generalise a Rolls-shaped thing this reads the winner off `TurnMatch`
/// and says who won.
///
/// Rolls now uses BOTH, and they are not in competition: the overlay ends
/// a ROUND and praises the score that seat just made, and this ends the
/// MATCH and says which of the seats won it. `RollsPassAndPlayHost` shows
/// the first after every turn and the second after the last one. The
/// direction comes from `RollsGame.lowestScoreWins`, so the lowest total
/// wins here exactly as the overlay's bands assume.
struct MatchResultView: View {
    let match: TurnMatch
    let onPlayAgain: () -> Void
    let onExit: () -> Void

    @ObservedObject private var theme = AppTheme.shared

    var body: some View {
        ZStack {
            Color.black.opacity(0.78)
                .ignoresSafeArea()

            FireworksView()
                .allowsHitTesting(false)
                // The sky this view already draws, now with the bangs. One
                // opener then the bodies cycling, so it keeps going for as
                // long as the screen is up rather than firing once.
                .onAppear {
                    VictoryAudio.preload()
                    VictoryAudio.start()
                }
                .onDisappear { VictoryAudio.stop() }

            VStack(spacing: 16) {
                // "<name> Wins" — dynamic, decides the match, and also
                // uppercased by the enclosing view.
                Text(headline)
                    .font(.poppins(54, .bold))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)

                if let reason {
                    Text(reason)
                        .font(.poppins(14, .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                }

                HStack(spacing: 18) {
                    ForEach(match.participants, id: \.self) { participant in
                        VStack(spacing: 2) {
                            Text(match.displayName(for: participant))
                                .font(.poppins(11, .semibold))
                                .foregroundStyle(.white.opacity(0.7))
                            Text("\(match.score(for: participant))")
                                .font(.poppins(30, .bold))
                                .foregroundStyle(.white)
                        }
                    }
                }
                .padding(.top, 4)

                VStack(spacing: 8) {
                    Button {
                        SoundEngine.shared.play(.buttonTap)
                        onPlayAgain()
                    } label: {
                        Text("Play Again")
                            .font(.poppins(16))
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .contentShape(RoundedRectangle(cornerRadius: ControlShape.cornerRadius))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.accentTextColor)
                    .pixelPanel(fill: .solid(theme.accentColor), elevation: .lifted)

                    Button {
                        SoundEngine.shared.play(.buttonTap)
                        onExit()
                    } label: {
                        Text("Back to Games")
                            .font(.poppins(14))
                            .frame(maxWidth: .infinity)
                            .frame(height: 42)
                            .contentShape(RoundedRectangle(cornerRadius: ControlShape.cornerRadius))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .pixelPanel(fill: .solid(theme.accentColor.opacity(0.35)),
                                elevation: .resting)
                }
                .padding(.horizontal, 44)
                .padding(.top, 6)
            }
        }
        .textCase(.uppercase)
    }

    private var headline: String {
        guard let outcome = match.outcome else { return "" }
        let winners = outcome.winners
        if winners.count > 1 { return "Draw" }
        guard let winner = winners.first else { return "" }
        return "\(match.displayName(for: winner)) Wins"
    }

    private var reason: String? {
        // Unwrapped explicitly rather than matching the case pattern
        // straight against the Optional. Swift's optional promotion in
        // pattern matching likely accepts the shorter form, but there is
        // no compiler here to confirm it and this costs nothing.
        guard let outcome = match.outcome,
              case .special(_, let reason) = outcome else { return nil }
        return reason
    }
}

// MARK: - Rolls

/// Rolls, round the table.
///
/// **Rolls was the only game in the suite with no second player.** Its
/// rules say two or more and `RollsGame.maxPlayers` is `Int.max`, but
/// `DiceGameScreen` had no `TurnMatch`: one person banked fifteen dice,
/// `TurnCompleteOverlay` showed a score and a praise word, and that was
/// the whole game. The N-player part existed only in the Messages
/// version, which reads seats off a conversation. So the standalone
/// shipped the one game whose own guide describes an opponent without
/// having one.
///
/// This is that opponent, and it is a HOST rather than a change to the
/// Rolls screen. `DiceGameScreen` already has the seam — `onRoundFinished`
/// hands back a `RollsPlayerResult` with the banked total on it, which is
/// exactly what the extension consumes — so nothing inside the screen,
/// its scene, its physics or its layout is touched. That matters more here
/// than it would elsewhere: this is the code path that produced the settle
/// crash, and the cheapest change to it is no change at all.
///
/// **One seed for the table.** Every seat is dealt the same fifteen dice,
/// which is what makes the scores comparable — it is also what
/// `RollsPayload` does for a conversation, for the same reason.
///
/// **No scoreboard strip over the board.** Every other game puts
/// `MatchScoreboard` above its playfield; this one must not, because
/// `DiceGameScreen` derives its square playfield from the height it is
/// handed and a strip would quietly reshape the board — the same reason
/// its own comment gives for drawing the back button in an overlay rather
/// than a navigation bar. The handover gate before each turn and the
/// result after the last one both show every seat's total, so nothing is
/// hidden; it is just not shown while you roll.
struct RollsPassAndPlayHost: View {

    let onExit: () -> Void

    @State private var match = TurnMatch.passAndPlay()

    /// The deal, shared by every seat and re-minted per match.
    @State private var seed = SeededGenerator.newSeed()

    /// Forces a fresh `DiceGameScreen` for each seat.
    ///
    /// A finished round leaves its pool empty and its screen showing a
    /// score, and the screen has no reset of its own — dismissing the
    /// overlay only hides the overlay. Rebuilding the view is therefore
    /// how a seat gets a round, and it has to be a token that only ever
    /// counts up: `match.activeIndex` returns to 0 on "play again" and
    /// `match.turnNumber` resets with the match, so either would hand the
    /// first seat of the second match the spent screen from the first.
    @State private var roundToken = 0

    /// What the last seat scored, for the gate between turns.
    @State private var lastSummary: String?

    /// Whether the active seat is between the gate and their round.
    ///
    /// True at the start, so the first seat begins rolling rather than
    /// being told to pass the device to themselves — which is what the
    /// other ten games do, and why `HogScreen` starts at `.ready` rather
    /// than `.handover`.
    @State private var seatReady = true

    var body: some View {
        ZStack {
            DiceGameScreen(onExit: onExit,
                           onRoundFinished: { result in bank(result) },
                           onRoundDismissed: { endTurn() },
                           seed: seed)
                .id(roundToken)

            if match.isOver {
                MatchResultView(match: match,
                                onPlayAgain: startNewMatch,
                                onExit: onExit)
                    .transition(.opacity)
            } else if !seatReady {
                HandoverGate(match: match, lastTurnSummary: lastSummary) {
                    seatReady = true
                    roundToken += 1
                }
                .transition(.opacity)
            }
        }
    }

    /// The active seat's round is over. Records it; does NOT advance.
    ///
    /// Advancing here would be the bug this split exists to avoid: the
    /// screen is still showing the player their own score at this point.
    /// See `DiceGameScreen.onRoundDismissed`.
    private func bank(_ result: RollsPlayerResult) {
        lastSummary = "\(match.activeDisplayName) scored \(result.score)"
        match.addScore(result.score)
    }

    /// The player has read their score. Next seat, or the result.
    private func endTurn() {
        if match.activeIsLastInRound {
            // One round each — see GAME_RULES.txt, "Bank all 15 dice;
            // lowest cumulative score wins". So the last seat's dismissal
            // ends the match rather than opening a second round.
            match.finish(lowestScoreWins: RollsGame.lowestScoreWins)
            return
        }
        match.advanceTurn()
        seatReady = false
    }

    private func startNewMatch() {
        match = TurnMatch.passAndPlay()
        seed = SeededGenerator.newSeed()
        lastSummary = nil
        seatReady = true
        roundToken += 1
    }
}
