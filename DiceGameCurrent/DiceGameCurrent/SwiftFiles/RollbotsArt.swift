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

    /// A faceted low-poly fill.
    ///
    /// This once claimed to be "the same generator the playfield floor
    /// uses", and stopped being true the day the floor became a shader
    /// (SmokeFloor). It is now used for one thing only — the arena
    /// backdrop — because everything else on this screen wears a
    /// PixelPanel, which IS what the rest of the app wears. Cached inside
    /// LowPolyTextures by its parameters.
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
            // like a different program. This is the last faceted surface
            // on the screen — every panel over it is now a PixelPanel —
            // and it stays because a backdrop wants texture, not an edge.
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

/// One runner's integrity, down the edge of the screen.
///
/// This was a full-width band across the top holding both seats, which
/// cost a fifth of the height and left the dice squeezed into what was
/// left. As two narrow rails it costs almost no height at all, and the
/// whole middle of the screen belongs to the tray.
struct NetSeatRail: View {
    let state: RollbotsState
    let seat: Int
    let name: String

    /// The rail's own width, passed in rather than measured.
    ///
    /// Everything textual here is sized from it, so the widest rail stops
    /// being a third empty — which is what the 128pt clamp was raised for
    /// and what fixed 10-13pt labels then threw away. A GeometryReader
    /// would measure the same number, but it is greedy in both axes and
    /// this is a VStack of intrinsically-sized rows; the call site already
    /// computes the width, so it hands it over.
    let width: CGFloat

    private var colour: Color { NetArt.seat(seat) }

    /// Reading size. White, at this size, on both rails — both players read
    /// the same screen, so neither rail is the quiet one.
    private var label: CGFloat { max(11, width * 0.125) }
    private var iconSize: CGFloat { width * 0.44 }

    var body: some View {
        VStack(spacing: 6) {
            Text(name)
                .font(.poppins(label, .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text("\(max(0, state.ip[seat]))")
                .font(.poppins(width * 0.30, .black))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            Text("IP")
                .font(.poppins(max(9, label - 2), .medium))
                .foregroundStyle(NetArt.text.opacity(0.6))

            // Vertical, filling from the bottom: a tall thin bar reads far
            // better in a rail than a short wide one, and draining downward
            // is the direction the number is going.
            GeometryReader { geo in
                let maximum = RollbotsMaxIP
                let fraction = max(0, min(1, Double(state.ip[seat]) / Double(maximum)))
                ZStack(alignment: .bottom) {
                    Rectangle().fill(colour.opacity(0.16))
                    Rectangle().fill(colour)
                        .frame(height: geo.size.height * fraction)
                }
                .pixelWell(radius: PixelPanel.cellRadius)
            }
            .frame(maxHeight: .infinity)

            // Icon and label as ONE unit, in one panel, rather than a
            // picture floating above some words. The weapon and its name
            // are a single piece of information and now look like one.
            loadout(icon: state.activeWeapon(seat).iconName,
                    tint: colour,
                    text: state.activeWeapon(seat).displayName)

            // The ability, which had no mark at all although the art has
            // shipped since the icons went in. Dimmed once spent, so a rail
            // answers "what have they still got?" without opening a menu.
            loadout(icon: state.ware[seat].iconName,
                    tint: state.wareUsed[seat] ? NetArt.text.opacity(0.28) : NetArt.warn,
                    text: state.wareUsed[seat] ? "Spent" : state.ware[seat].displayName,
                    dimmed: state.wareUsed[seat])

            ForEach(statusPips, id: \.self) { pip in
                Text(pip)
                    .font(.poppins(max(10, label - 1), .semibold))
                    .foregroundStyle(NetArt.warn)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SteelTiledBackground())
        .background(NetArt.background.opacity(0.78))
        .overlay(
            Rectangle().stroke(colour, lineWidth: 2)
        )
    }

    /// One piece of kit: its mark and its name, boxed together.
    ///
    /// Both rails draw these at full strength. The rail used to stroke the
    /// waiting player's side at 0.25 against the active one's 0.8, which
    /// made sense when one person held the device — but both players read
    /// this same screen, and the opponent's loadout is exactly what the
    /// player on turn needs to see.
    private func loadout(icon: String,
                         tint: Color,
                         text: String,
                         dimmed: Bool = false) -> some View {
        VStack(spacing: 4) {
            NetIconView(name: icon, tint: tint)
                .frame(height: iconSize)
            Text(text)
                .font(.poppins(label, .semibold))
                .foregroundStyle(dimmed ? Color.white.opacity(0.5) : .white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .pixelPanel(fill: .solid(NetArt.panel), radius: PixelPanel.cellRadius)
    }

    /// Everything ticking on this runner, one short line each.
    private var statusPips: [String] {
        var pips: [String] = []
        if state.charged[seat] { pips.append("CHARGED") }
        if state.virusTurns[seat] > 0 { pips.append("VIRUS \(state.virusTurns[seat])") }
        if state.sidearmTurns[seat] > 0 { pips.append("SIDEARM \(state.sidearmTurns[seat])") }
        if state.exposed[seat] { pips.append("EXPOSED") }
        if state.overclocked[seat] { pips.append("OVERCLOCK") }
        if state.phaseArmed[seat] { pips.append("PHASE") }
        return pips
    }
}

/// The largest IP either runner can hold, for sizing the bars.
/// The denominator both seats' IP bars share.
///
/// Deliberately the higher of the two starting totals rather than each
/// seat's own: a bar only means anything next to the other one, so they
/// have to be drawn to the same scale. Seat 0 therefore reads a hair under
/// full at the start, which is honest — it IS a point behind.
private let RollbotsMaxIP = RollbotsState.startingIP(1)

// MARK: - Cards

/// A selectable option: a weapon, an ability, or a defensive reaction.
struct NetCard: View {
    let title: String
    /// Named `summary` rather than `body`, which would collide with the
    /// View protocol's own requirement below.
    let summary: String
    var detail: String? = nil
    /// A bundled mark drawn beside the text, tinted to match it.
    var icon: String? = nil
    let tint: Color
    var isSelected: Bool = false
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button {
            SoundEngine.shared.play(.buttonTap)
            action()
        } label: {
            HStack(spacing: 10) {
                if let icon {
                    NetIconView(name: icon, tint: isEnabled ? tint : NetArt.text.opacity(0.3))
                        .frame(width: 38, height: 38)
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.poppins(16))
                    .foregroundStyle(isEnabled ? tint : NetArt.text.opacity(0.3))
                Text(summary)
                    .font(.poppins(12))
                    .foregroundStyle(NetArt.text.opacity(isEnabled ? 0.75 : 0.25))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail)
                        .font(.poppins(12))
                        .foregroundStyle(NetArt.warn.opacity(isEnabled ? 0.9 : 0.3))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(
                ZStack {
                    Rectangle().fill(NetArt.panel)
                    if isSelected { tint.opacity(0.22) }
                }
            )
            .pixelPanel(elevation: isSelected ? .lifted : .resting)
            .overlay(
                RoundedRectangle(cornerRadius: ControlShape.cornerRadius, style: .continuous)
                    .stroke(tint.opacity(isSelected ? 0.95 : 0.45),
                            lineWidth: isSelected ? 3 : 2)
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
                    .font(.poppins(16))
                    .foregroundStyle(NetArt.text.opacity(0.95))
                    .lineLimit(3)
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
        .background(SteelTiledBackground())
        .background(NetArt.background.opacity(0.80))
        .overlay(alignment: .top) {
            Rectangle().fill(NetArt.line.opacity(0.55)).frame(height: 2)
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
                .font(.poppins(16))
                .foregroundStyle(enabled ? (filled ? NetArt.background : tint)
                                         : NetArt.text.opacity(0.3))
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .pixelPanel(fill: .solid(filled ? tint.opacity(enabled ? 1 : 0.3)
                                                : .clear),
                            elevation: enabled ? .lifted : .resting)
                .overlay(
                    RoundedRectangle(cornerRadius: ControlShape.cornerRadius, style: .continuous)
                        .stroke(tint.opacity(enabled ? 0.9 : 0.25), lineWidth: 2)
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
                        .font(.poppins(14))
                        .foregroundStyle(NetArt.text)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                }

                Text("Hand over to")
                    .font(.poppins(13))
                    .foregroundStyle(NetArt.text.opacity(0.6))

                Text(nextName)
                    .font(.poppins(30, .bold))
                    .foregroundStyle(NetArt.seat(nextSeat))

                Button {
                    SoundEngine.shared.play(.buttonTap)
                    onReady()
                } label: {
                    Text("Jack In")
                        .font(.poppins(15))
                        .foregroundStyle(NetArt.background)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .pixelPanel(fill: .solid(NetArt.seat(nextSeat)),
                                    elevation: .lifted)
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
                    .font(.poppins(28, .bold))
                    .foregroundStyle(winners.count == 1 ? NetArt.seat(winners[0]) : NetArt.warn)
                    .multilineTextAlignment(.center)

                Text(winners.count == 1 ? "Connection terminated" : "Both decks flatlined")
                    .font(.poppins(14))
                    .foregroundStyle(NetArt.text.opacity(0.65))

                HStack(spacing: 18) {
                    ForEach([0, 1], id: \.self) { seat in
                        VStack(spacing: 2) {
                            Text(names[seat])
                                .font(.poppins(13))
                                .foregroundStyle(NetArt.text.opacity(0.65))
                            Text("\(max(0, state.ip[seat]))")
                                .font(.poppins(26, .bold))
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
                            .font(.poppins(15))
                            .foregroundStyle(NetArt.background)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .pixelPanel(fill: .solid(NetArt.line), elevation: .lifted)
                    }
                    Button {
                        SoundEngine.shared.play(.buttonTap)
                        onExit()
                    } label: {
                        Text("Log Off")
                            .font(.poppins(13))
                            .foregroundStyle(NetArt.text)
                            .frame(maxWidth: .infinity)
                            .frame(height: 42)
                            .overlay(
                                RoundedRectangle(cornerRadius: ControlShape.cornerRadius,
                                                 style: .continuous)
                                    .stroke(NetArt.text.opacity(0.6), lineWidth: 2)
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
