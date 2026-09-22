import SwiftUI

/// The arena's look: dark, neon, and deliberately unlike the rest of the
/// suite.
///
/// Every other game is a wooden table. This one is a net, so it gets its
/// own chrome — including its own handover gate and result screen, because
/// timber mid-duel would read as a bug. `PassAndPlayHost` stays untouched
/// and the other eight keep the wood. What *is* shared is the dice: same
/// physics, same tray, same tumble.
enum NetArt {

    static let backgroundHex = "#05070E"
    static let panelHex = "#0B1220"

    static let background = Color(hex: backgroundHex)
    static let panel = Color(hex: panelHex)
    static let line = Color(hex: "#16E0FF")
    static let text = Color(hex: "#C9F7FF")
    static let warn = Color(hex: "#FFB340")

    /// Seat colours, also used for that seat's dice.
    static func seat(_ index: Int) -> Color {
        index == 0 ? Color(hex: "#22E3FF") : Color(hex: "#FF2D78")
    }

    /// A faceted low-poly fill, from the same generator the playfield
    /// floor and the Royal UR board tiles use.
    ///
    /// This is what makes the arena read as the same app as the other
    /// nine while keeping its own palette: the surfaces are the house
    /// material, only the colours are the duel's. Cached inside
    /// LowPolyTextures by its parameters, so repeated panels cost one
    /// render between them.
    static func faceted(
        _ color: Color,
        variation: CGFloat = 0.14,
        seed: UInt64 = 5501
    ) -> Image {
        Image(uiImage: LowPolyTextures.facetedSurface(
            baseColor: UIColor(color),
            variation: variation,
            columns: 10,
            rows: 10,
            pixelSize: 256,
            seed: seed
        ))
    }

    static func seatHex(_ index: Int) -> String {
        index == 0 ? "#22E3FF" : "#FF2D78"
    }

    /// A die in the roller's colour, so you can tell whose throw is on the
    /// table at a glance.
    static func die(sides: Int, seat: Int) -> Die {
        Die(
            sides: sides,
            colorway: DieColorway(bodyHex: seatHex(seat), numberHex: "#05070E")
        )
    }
}

/// A faceted panel in the arena's material.
struct NetFacet: View {
    var color: Color = NetArt.panel
    var variation: CGFloat = 0.14
    var seed: UInt64 = 5501

    var body: some View {
        NetArt.faceted(color, variation: variation, seed: seed)
            .resizable()
    }
}

// MARK: - Background

/// A receding grid. Drawn rather than tiled, because the one thing the
/// wooden background gets from an image — a seam-free repeat — is exactly
/// what a perspective grid must not have.
struct NetGrid: View {
    var body: some View {
        ZStack {
            // Faceted, not drawn. The perspective grid this replaced was
            // the one surface in the app made of flat lines rather than
            // low-poly geometry, which is exactly what made the arena look
            // like a different program.
            NetFacet(color: NetArt.background, variation: 0.30, seed: 90210)

            // One neon seam across the horizon, so the space still reads as
            // a floor receding away rather than a flat wall.
            GeometryReader { geo in
                LinearGradient(
                    colors: [NetArt.line.opacity(0.22), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: geo.size.height * 0.30)
                .offset(y: geo.size.height * 0.30)
                .blendMode(.plusLighter)
            }
            .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Status

/// Both runners' integrity, and everything currently ticking on them.
struct NetStatusPanel: View {
    let state: RollbotsState
    let activeSeat: Int
    let names: [String]
    let subtitle: String?

    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                bar(0)
                bar(1)
            }
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.stackSans(11))
                    .foregroundStyle(NetArt.text.opacity(0.75))
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(NetFacet().opacity(0.92))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(NetArt.line.opacity(0.35))
                .frame(height: 1)
        }
    }

    private func bar(_ seat: Int) -> some View {
        let colour = NetArt.seat(seat)
        let isActive = seat == activeSeat
        let maximum = RollbotsRules.startingIP + RollbotsRules.secondSeatBonusIP
        let fraction = max(0, min(1, Double(state.ip[seat]) / Double(maximum)))

        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(names[seat])
                    .font(.stackSans(10))
                    .foregroundStyle(colour.opacity(isActive ? 1 : 0.6))
                Spacer(minLength: 0)
                Text("\(max(0, state.ip[seat])) IP")
                    .font(.stackSans(13))
                    .foregroundStyle(colour)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(colour.opacity(0.16))
                    NetFacet(color: colour, variation: 0.18, seed: 7700 + UInt64(seat))
                        .scaledToFill()
                        .frame(width: geo.size.width * fraction)
                        .clipped()
                }
            }
            .frame(height: 7)
            .overlay(Rectangle().stroke(colour.opacity(0.55), lineWidth: 1))

            Text(state.activeWeapon(seat).displayName)
                .font(.stackSans(9))
                .foregroundStyle(NetArt.text.opacity(0.6))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            if !statusPips(seat).isEmpty {
                Text(statusPips(seat).joined(separator: " · "))
                    .font(.stackSans(9))
                    .foregroundStyle(NetArt.warn)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .padding(7)
        .background(
            NetFacet(variation: 0.10, seed: 3310)
                .opacity(isActive ? 0.95 : 0.55)
                .clipShape(RoundedRectangle(cornerRadius: ControlShape.cornerRadius))
        )
        .overlay(
            RoundedRectangle(cornerRadius: ControlShape.cornerRadius)
                .stroke(colour.opacity(isActive ? 0.8 : 0.25), lineWidth: 1)
        )
    }

    /// Everything the player has to keep track of, in one line.
    private func statusPips(_ seat: Int) -> [String] {
        var pips: [String] = []
        if state.charged[seat] { pips.append("CHARGED") }
        if state.virusTurns[seat] > 0 { pips.append("VIRUS \(state.virusTurns[seat])") }
        if state.sidearmTurns[seat] > 0 { pips.append("SIDEARM \(state.sidearmTurns[seat])") }
        if state.exposed[seat] { pips.append("EXPOSED") }
        if state.overclocked[seat] { pips.append("OVERCLOCKED") }
        if state.phaseArmed[seat] { pips.append("PHASE ARMED") }
        return pips
    }
}

// MARK: - Cards

/// A selectable option: a weapon, an ability, or a defensive reaction.
struct NetCard: View {
    let title: String
    /// Named `summary` rather than `body`, which would collide with the
    /// View protocol's own requirement below.
    let summary: String
    var detail: String? = nil
    let tint: Color
    var isSelected: Bool = false
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button {
            SoundEngine.shared.play(.buttonTap)
            action()
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.stackSans(13))
                    .foregroundStyle(isEnabled ? tint : NetArt.text.opacity(0.3))
                Text(summary)
                    .font(.stackSans(10))
                    .foregroundStyle(NetArt.text.opacity(isEnabled ? 0.75 : 0.25))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail)
                        .font(.stackSans(10))
                        .foregroundStyle(NetArt.warn.opacity(isEnabled ? 0.9 : 0.3))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(
                ZStack {
                    NetFacet(variation: 0.12, seed: 4120)
                    if isSelected { tint.opacity(0.22) }
                }
                .clipShape(RoundedRectangle(cornerRadius: ControlShape.cornerRadius))
            )
            .overlay(
                RoundedRectangle(cornerRadius: ControlShape.cornerRadius)
                    .stroke(tint.opacity(isSelected ? 0.95 : 0.35), lineWidth: isSelected ? 2 : 1)
            )
        }
        .disabled(!isEnabled)
    }
}

// MARK: - Action bar

/// The neon counterpart of `TurnActionBar`.
struct NetActionBar: View {
    let primaryLabel: String
    let primaryEnabled: Bool
    var secondaryLabel: String? = nil
    var subtitle: String = ""
    let tint: Color
    let onPrimary: () -> Void
    var onSecondary: () -> Void = {}

    var body: some View {
        VStack(spacing: 4) {
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.stackSans(11))
                    .foregroundStyle(NetArt.text.opacity(0.8))
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: 10) {
                button(primaryLabel, filled: true, enabled: primaryEnabled, action: onPrimary)
                if let secondaryLabel {
                    button(secondaryLabel, filled: false, enabled: true, action: onSecondary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(NetFacet().opacity(0.95))
        .overlay(alignment: .top) {
            Rectangle().fill(NetArt.line.opacity(0.35)).frame(height: 1)
        }
    }

    private func button(
        _ label: String, filled: Bool, enabled: Bool, action: @escaping () -> Void
    ) -> some View {
        Button {
            SoundEngine.shared.play(.buttonTap)
            action()
        } label: {
            Text(label)
                .font(.stackSans(14))
                .foregroundStyle(enabled ? (filled ? NetArt.background : tint)
                                         : NetArt.text.opacity(0.3))
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(
                    Group {
                        if filled {
                            NetFacet(color: tint, variation: 0.16, seed: 6640)
                                .opacity(enabled ? 1 : 0.3)
                        } else {
                            Color.clear
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: ControlShape.cornerRadius))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: ControlShape.cornerRadius)
                        .stroke(tint.opacity(enabled ? 0.9 : 0.25), lineWidth: 1)
                )
        }
        .disabled(!enabled)
    }
}

// MARK: - Handover

/// The gate between turns, in the arena's own clothes.
struct NetHandoverGate: View {
    let nextName: String
    let nextSeat: Int
    let summary: String?
    let onReady: () -> Void

    var body: some View {
        ZStack {
            NetGrid()
            Color.black.opacity(0.72).ignoresSafeArea()

            VStack(spacing: 18) {
                if let summary, !summary.isEmpty {
                    Text(summary)
                        .font(.stackSans(14))
                        .foregroundStyle(NetArt.text)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                }

                Text("Hand over to")
                    .font(.stackSans(11))
                    .foregroundStyle(NetArt.text.opacity(0.6))

                Text(nextName)
                    .font(.stackSans(30))
                    .foregroundStyle(NetArt.seat(nextSeat))

                Button {
                    SoundEngine.shared.play(.buttonTap)
                    onReady()
                } label: {
                    Text("Jack In")
                        .font(.stackSans(15))
                        .foregroundStyle(NetArt.background)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(
                            NetFacet(color: NetArt.seat(nextSeat), variation: 0.16, seed: 8820)
                                .clipShape(RoundedRectangle(cornerRadius: ControlShape.cornerRadius))
                        )
                }
                .padding(.horizontal, 44)
            }
        }
        .textCase(.uppercase)
    }
}

// MARK: - Result

struct NetResultView: View {
    let state: RollbotsState
    let names: [String]
    /// Empty on a System Draw.
    let winners: [Int]
    let onPlayAgain: () -> Void
    let onExit: () -> Void

    var body: some View {
        ZStack {
            NetGrid()
            Color.black.opacity(0.8).ignoresSafeArea()

            VStack(spacing: 14) {
                Text(headline)
                    .font(.stackSans(28))
                    .foregroundStyle(winners.count == 1 ? NetArt.seat(winners[0]) : NetArt.warn)
                    .multilineTextAlignment(.center)

                Text(winners.count == 1 ? "Connection terminated" : "Both decks flatlined")
                    .font(.stackSans(11))
                    .foregroundStyle(NetArt.text.opacity(0.65))

                HStack(spacing: 18) {
                    ForEach([0, 1], id: \.self) { seat in
                        VStack(spacing: 2) {
                            Text(names[seat])
                                .font(.stackSans(10))
                                .foregroundStyle(NetArt.text.opacity(0.65))
                            Text("\(max(0, state.ip[seat]))")
                                .font(.stackSans(26))
                                .foregroundStyle(NetArt.seat(seat))
                        }
                    }
                }
                .padding(.top, 4)

                VStack(spacing: 8) {
                    Button {
                        SoundEngine.shared.play(.buttonTap)
                        onPlayAgain()
                    } label: {
                        Text("Run It Back")
                            .font(.stackSans(15))
                            .foregroundStyle(NetArt.background)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(
                                NetFacet(color: NetArt.line, variation: 0.16, seed: 9930)
                                    .clipShape(RoundedRectangle(cornerRadius: ControlShape.cornerRadius))
                            )
                    }
                    Button {
                        SoundEngine.shared.play(.buttonTap)
                        onExit()
                    } label: {
                        Text("Log Off")
                            .font(.stackSans(13))
                            .foregroundStyle(NetArt.text)
                            .frame(maxWidth: .infinity)
                            .frame(height: 42)
                            .overlay(
                                RoundedRectangle(cornerRadius: ControlShape.cornerRadius)
                                    .stroke(NetArt.text.opacity(0.5), lineWidth: 1)
                            )
                    }
                }
                .padding(.horizontal, 44)
                .padding(.top, 6)
            }
        }
        .textCase(.uppercase)
    }

    private var headline: String {
        guard winners.count == 1 else { return "System Draw" }
        return "\(names[winners[0]]) Wins"
    }
}
