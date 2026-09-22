import SwiftUI

/// The Royal Path board, with its route traceable a square at a time.
///
/// **The rules are not built yet.** This is the board and a way to walk it:
/// tap Step to move one square along the active seat's route, and Switch
/// Seat to see the other player's — which is the one thing that has to be
/// right before any of the movement, capture or Setback code goes in. The
/// two routes share their last twelve squares and run the final loop in
/// opposite directions, and that is far easier to confirm by looking at it
/// than by reading an index table.
struct RoyalPathScreen: View {

    var onExit: (() -> Void)? = nil

    @State private var seat = RoyalPathBoard.bottomSeat
    @State private var index = 0
    @State private var showingSettings = false
    @ObservedObject private var theme = AppTheme.shared

    private var path: [RoyalPathBoard.Square] { RoyalPathBoard.path(for: seat) }

    /// Every square walked so far, so the route reads as a trail rather
    /// than a single marker.
    private var walked: Set<RoyalPathBoard.Square> {
        Set(path.prefix(index))
    }

    var body: some View {
        ZStack {
            // The same faceted surface as the playfield floor, so the board
            // sits on the table the rest of the suite is played on.
            Image(uiImage: LowPolyTextures.facetedSurface(
                baseColor: theme.floorBaseColor.darkened(by: 0.35),
                variation: 0.08,
                pixelSize: 512
            ))
            .resizable()
            .ignoresSafeArea()

            GeometryReader { geo in
                let headerHeight = geo.size.height * 0.17
                let buttonHeight: CGFloat = 108

                VStack(spacing: 0) {
                    header
                        .frame(height: headerHeight)

                    RoyalPathBoardView(
                        positions: positions,
                        highlighted: walked,
                        onTapSquare: { square in
                            // Tapping a square on the route jumps to it,
                            // which is quicker than stepping there when you
                            // are checking one particular crossing.
                            if let found = path.firstIndex(of: square) {
                                SoundEngine.shared.play(.buttonTap)
                                index = found + 1
                            }
                        }
                    )
                    .frame(height: max(geo.size.height - headerHeight - buttonHeight, 0))
                    .padding(.horizontal, 8)
                    .overlay(alignment: .topLeading) {
                        if let onExit {
                            overlayButton(systemName: "chevron.left") { onExit() }
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        overlayButton(systemName: "gearshape.fill") {
                            showingSettings = true
                        }
                    }

                    TurnActionBar(
                        primaryLabel: index >= RoyalPathBoard.pathLength ? "Start Over" : "Step",
                        primaryEnabled: true,
                        secondaryLabel: "Switch Seat",
                        subtitle: subtitle,
                        onPrimary: { step() },
                        onSecondary: { switchSeat() }
                    )
                    .frame(height: buttonHeight)
                }
            }
        }
        .textCase(.uppercase)
        .dynamicTypeSize(.large)
        .sheet(isPresented: $showingSettings) {
            SettingsView(gameName: RoyalPathGame.displayName, rules: RoyalPathGame.rules)
        }
        .onAppear { AppFonts.registerIfNeeded() }
    }

    /// One piece, on the square being traced. The opponent's pieces are off
    /// the board until the rules exist to move them.
    private var positions: [[Int]] {
        var result: [[Int]] = [[], []]
        if index >= 1 { result[seat] = [index] }
        return result
    }

    private var subtitle: String {
        guard index >= 1 else { return "Tap Step to walk the route" }
        let onRosette = RoyalPathBoard.isRosette(seat: seat, index: index)
        let shared = RoyalPathBoard.square(seat: seat, index: index).map(RoyalPathBoard.isShared) ?? false
        if onRosette { return "Square \(index) — rosette" }
        return shared ? "Square \(index) — contested" : "Square \(index) — your own"
    }

    private var header: some View {
        ZStack {
            WoodTiledBackground()
            VStack(spacing: 2) {
                Text(RoyalPathGame.displayName)
                    .font(.aguafina(38))
                    .foregroundStyle(.white)
                    .padding(.trailing, 6)
                Text(seat == RoyalPathBoard.bottomSeat ? "Player 1 — bottom row" : "Player 2 — top row")
                    .font(.stackSans(12))
                    .foregroundStyle(.white.opacity(0.8))
                Text("Board preview — rules still to come")
                    .font(.stackSans(10))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .padding(.vertical, 6)
        }
    }

    private func step() {
        SoundEngine.shared.play(.buttonTap)
        index = index >= RoyalPathBoard.pathLength ? 0 : index + 1
    }

    private func switchSeat() {
        SoundEngine.shared.play(.buttonTap)
        seat = seat == RoyalPathBoard.bottomSeat ? RoyalPathBoard.topSeat : RoyalPathBoard.bottomSeat
    }

    private func overlayButton(systemName: String, action: @escaping () -> Void) -> some View {
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

// MARK: - Suite entry

enum RoyalPathGame: SuiteGame {
    static let id = "royal_path"
    static let displayName = "The Royal Path"
    static let tagline = "Race, capture, come home."

    static let rules: [GameRuleSection] = [
        GameRuleSection(
            title: "Not Finished Yet",
            body: "The board is built; the game is not. Step walks one square along the route so you can see where it runs, and Switch Seat shows the other player's — they share everything from the fifth square on."
        ),
        GameRuleSection(
            title: "The Route",
            body: "Sixteen squares. Out along your own row, up the middle past the bridge, then around the far block — and back out through the rosette you started the loop from. Your opponent runs that last loop the opposite way round."
        ),
        GameRuleSection(
            title: "Rosettes",
            body: "The five flowered squares land on the 4th, 8th, 12th and 16th square of both players' routes. What they will do is still to be built."
        ),
        GameRuleSection(
            title: "Coming",
            body: "Five binary dice, three pieces each, capture on any shared square, a Setback when you cannot move, and first to bring two pieces home."
        )
    ]
}
