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

            VStack(spacing: 4) {
                if let totalRounds {
                    Text("Round \(min(match.round, totalRounds)) of \(totalRounds)")
                        .font(.poppins(12))
                        .foregroundStyle(.white.opacity(0.75))
                }

                HStack(spacing: 10) {
                    ForEach(match.participants, id: \.self) { participant in
                        seat(participant)
                    }
                }

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.poppins(11))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
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
                .font(.poppins(11))
                .foregroundStyle(.white.opacity(isActive ? 0.95 : 0.6))
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
        VStack(spacing: 2) {
            HStack(spacing: 10) {
                Button {
                    onPrimary()
                } label: {
                    Text(primaryLabel)
                        .font(.poppins(15))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: ControlShape.cornerRadius))
                .tint(theme.accentColor)
                .disabled(!primaryEnabled)

                if let secondaryLabel {
                    Button {
                        onSecondary()
                    } label: {
                        Text(secondaryLabel)
                            .font(.poppins(15))
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.roundedRectangle(radius: ControlShape.cornerRadius))
                    .tint(theme.accentColor)
                }
            }

            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.poppins(12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
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

                // Tells the next human to pick up the device, and names
                // them. Note this whole view is under .textCase(.uppercase),
                // so the script's lowercase forms — most of what gives a
                // script its character — were being discarded here anyway.
                Text("Pass to \(match.activeDisplayName)")
                    .font(.poppins(46, .semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)

                HStack(spacing: 14) {
                    ForEach(match.participants, id: \.self) { participant in
                        VStack(spacing: 2) {
                            Text(match.displayName(for: participant))
                                .font(.poppins(11))
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
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: ControlShape.cornerRadius))
                .tint(theme.accentColor)
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
/// and says who won. Rolls keeps its own overlay untouched.
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
                        .font(.poppins(14))
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                }

                HStack(spacing: 18) {
                    ForEach(match.participants, id: \.self) { participant in
                        VStack(spacing: 2) {
                            Text(match.displayName(for: participant))
                                .font(.poppins(11))
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
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.roundedRectangle(radius: ControlShape.cornerRadius))
                    .tint(theme.accentColor)

                    Button {
                        SoundEngine.shared.play(.buttonTap)
                        onExit()
                    } label: {
                        Text("Back to Games")
                            .font(.poppins(14))
                            .frame(maxWidth: .infinity)
                            .frame(height: 42)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.roundedRectangle(radius: ControlShape.cornerRadius))
                    .tint(.white)
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
