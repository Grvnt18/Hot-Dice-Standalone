import SwiftUI

/// Every game's How to Play, as a cluster of bubbles.
///
/// Reached from the hub's Settings, where there is no game open and so no
/// single set of rules to show. The button there used to be hidden for
/// exactly that reason, which meant the one screen a player browses the
/// suite from was the one screen that could not tell them how anything
/// works.
///
/// A cluster rather than a list because it is a menu of eleven short
/// names, not a document: bubbles of the length of their own name,
/// staggered off the grid so the block reads as a scatter, and popped in
/// one after another so the set arrives rather than appearing.
///
/// The rules themselves are not duplicated here — each bubble opens the
/// same `HowToPlayView` the game's own Settings does, from
/// `GameCatalogEntry.rules`. One copy of every guide, in the game that
/// owns it.
struct GuideBubbleCluster: View {

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var theme = AppTheme.shared

    /// Which guide is open, if any. The entry itself rather than a flag,
    /// so the sheet cannot be shown without one.
    @State private var opened: GameCatalogEntry?

    /// How many bubbles have popped in. Driven once on appear.
    @State private var shown = 0

    private let columns = Array(repeating: GridItem(.flexible(),
                                                    spacing: GuideBubbleLayout.gap),
                                count: 2)

    var body: some View {
        // Same rebuild as Settings and HowToPlayView: no NavigationStack, no
        // toolbar, the app's own header bar instead. This sheet was missed in
        // that pass, which is why the cohesion check now covers this file too.
        ZStack {
            WoodTiledBackground(fraction: MenuTimber.fraction)
                .ignoresSafeArea()
            Color.black.opacity(0.35)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                MenuHeaderBar(title: "How to Play") { dismiss() }

                ScrollView {
                    VStack(spacing: 14) {
                        Text("Pick a game for its full rules — every table "
                             + "and every edge case. The short version is "
                             + "in each game's own Settings.")
                            .font(.poppins(13))
                            .foregroundStyle(.white.opacity(0.75))
                            .padding(.top, 8)

                        LazyVGrid(columns: columns, spacing: GuideBubbleLayout.gap) {
                            ForEach(Array(GameCatalog.all.enumerated()),
                                    id: \.element.id) { index, entry in
                                bubble(entry, index: index)
                            }
                        }
                        .padding(.horizontal, GuideBubbleLayout.margin)
                        .padding(.bottom, 24)
                    }
                }
            }
        }
        .sheet(item: $opened) { entry in
            // The guide. `GameCatalogEntry.rules` is the only one there
            // is now — a game's own Settings opens this same set.
            HowToPlayView(gameName: entry.displayName,
                          tagline: entry.tagline,
                          sections: entry.rules)
        }
        .onAppear(perform: popIn)
        // Pinned like every game screen (see DiceGameShell's note): these
        // layouts are geometric, and at the larger accessibility sizes the
        // labels win the fight with the frames they sit in. AppFonts' faces
        // use the relativeTo: overload, so shrink-to-fit still works inside
        // the pinned size.
        .dynamicTypeSize(.large)
    }

    private func bubble(_ entry: GameCatalogEntry, index: Int) -> some View {
        let isShown = index < shown

        return Button {
            SoundEngine.shared.play(.buttonTap)
            opened = entry
        } label: {
            // Poppins, not the script face. These are navigation labels —
            // the player reads them to pick whose rules to open — and at a
            // minimumScaleFactor of 0.5 a 24pt name can end up 12pt, which
            // is where a display script stops being readable first.
            Text(entry.tileName)
                .font(.poppins(GuideBubbleLayout.nameSize, .semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.5)
                .multilineTextAlignment(.center)
                .textCase(nil)
                .foregroundStyle(theme.accentTextColor)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity)
                .frame(height: GuideBubbleLayout.height)
                .contentShape(RoundedRectangle(cornerRadius: ControlShape.cornerRadius))
                // Rectangular, like every other control in the suite. These
                // were Capsules, which is the one shape the restyle replaced
                // everywhere else — a pill here made the guide read as a
                // different app's screen.
                .pixelPanel(fill: .solid(theme.accentColor), elevation: .lifted)
        }
        .buttonStyle(.plain)
        // Off the grid, alternating, so eleven bubbles read as a cluster
        // rather than as a table with one odd row at the end.
        .offset(y: index.isMultiple(of: 2)
                ? -GuideBubbleLayout.stagger
                : GuideBubbleLayout.stagger)
        .scaleEffect(isShown ? 1 : 0.4)
        .opacity(isShown ? 1 : 0)
        .animation(.spring(response: 0.34, dampingFraction: 0.62),
                   value: isShown)
    }

    /// Pops the bubbles in one at a time.
    ///
    /// A timer rather than a per-bubble delay so there is one thing to
    /// cancel and nothing left scheduled if the sheet is closed early:
    /// `shown` simply stops climbing, and every bubble is already drawn
    /// from it.
    private func popIn() {
        guard shown == 0 else { return }
        for index in GameCatalog.all.indices {
            DispatchQueue.main.asyncAfter(
                deadline: .now() + Double(index) * GuideBubbleLayout.popInterval
            ) {
                if shown == index { shown = index + 1 }
            }
        }
    }
}

// MARK: - The cluster's geometry

/// The bubbles' size and rhythm.
///
/// File scope, following `HubLayout` and `PlayfieldLayout`, which is the
/// shape the hub was rebuilt into after its statics-on-a-View version
/// would not build.
enum GuideBubbleLayout {
    static let height: CGFloat = 76
    static let gap: CGFloat = 14
    static let margin: CGFloat = 20

    /// How far each bubble sits off its row. Enough to break the grid,
    /// not enough to make two neighbours look misaligned.
    static let stagger: CGFloat = 10

    static let nameSize: CGFloat = 24

    /// Between one bubble arriving and the next.
    static let popInterval: Double = 0.045
}

// MARK: - Figures

/// A diagram a rule section can carry.
///
/// Three, and only three, because a figure earns its place by showing
/// something the sentence cannot. Everything here is drawn from the same
/// values the game plays by — the board's own path array, the board's own
/// rosette art, the real scoring function — so a rule change moves the
/// picture with it. A diagram that has to be redrawn by hand when the code
/// changes is a diagram that will eventually be wrong.
enum GuideFigure: String {
    /// What a rosette is, and what landing on one does.
    case rosette
    /// The sixteen squares each player walks, and where the routes meet.
    case royalUrPath
    /// A Boneheads board scored out, multiplier by multiplier.
    case boneheadsScoring
}

/// Renders a section's figure under its text.
struct GuideFigureView: View {
    let figure: GuideFigure

    var body: some View {
        content
            .frame(maxWidth: .infinity)
            .padding(10)
            .pixelWell(radius: ControlShape.cornerRadius)
    }

    @ViewBuilder
    private var content: some View {
        switch figure {
        case .rosette:         RosetteFigure()
        case .royalUrPath:     RoyalUrPathFigure()
        case .boneheadsScoring: BoneheadsScoringFigure()
        }
    }
}

// MARK: The rosette

/// One square, drawn by the board's own marking routine.
///
/// `RoyalUrArt.draw(.rosette:)` is what paints the five flowered squares on
/// the real board, so the guide cannot show a rosette the board does not.
private struct RosetteFigure: View {
    private let side: CGFloat = 92

    var body: some View {
        HStack(spacing: 14) {
            Canvas { context, size in
                let rect = CGRect(origin: .zero, size: size)
                context.fill(Path(rect), with: .color(Color(RoyalUrArt.tileBase)))
                RoyalUrArt.draw(.rosette, in: context, rect: rect)
            }
            .frame(width: side, height: side)

            Text("Land here and you roll again.")
                .font(.poppins(13))
                .foregroundStyle(MenuInk.text)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }
}

// MARK: The route

/// The board, with both routes numbered.
///
/// Squares come from `RoyalUrBoard.squares`, the route from
/// `RoyalUrBoard.path(for:)` and the flowers from `RoyalUrBoard.rosettes` —
/// the three facts the rule depends on, read rather than redrawn.
private struct RoyalUrPathFigure: View {

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Canvas { context, size in
                RoyalUrPathFigure.draw(in: context, size: size)
            }
            .frame(height: 112)

            Text("Your route is numbered 1 to 16. The middle row is shared — that is the only place a piece can be captured.")
                .font(.poppins(12))
                .foregroundStyle(MenuInk.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Out of the ViewBuilder: a Canvas closure doing this much arithmetic
    /// is exactly the shape Xcode 14.2's solver gives up on.
    private static func draw(in context: GraphicsContext, size: CGSize) {
        let cell = min(size.width / CGFloat(RoyalUrBoard.columns),
                       size.height / CGFloat(RoyalUrBoard.rows))
        let originX = (size.width - cell * CGFloat(RoyalUrBoard.columns)) / 2
        let originY = (size.height - cell * CGFloat(RoyalUrBoard.rows)) / 2

        func frame(_ square: RoyalUrBoard.Square) -> CGRect {
            CGRect(x: originX + cell * CGFloat(square.column - 1),
                   y: originY + cell * CGFloat(square.row - 1),
                   width: cell, height: cell)
        }

        for square in RoyalUrBoard.squares {
            let rect = frame(square).insetBy(dx: 1, dy: 1)
            context.fill(Path(rect), with: .color(Color(RoyalUrArt.tileBase)))
            if RoyalUrBoard.rosettes.contains(square) {
                RoyalUrArt.draw(.rosette, in: context, rect: rect)
            }
            context.stroke(Path(rect), with: .color(RoyalUrArt.ink.opacity(0.5)),
                           lineWidth: 1)
        }

        // Seat 0's numbers only. Seat 1 walks the mirror of this, so two
        // sets of numerals would say the same thing twice and leave no room
        // in a cell this size.
        let path = RoyalUrBoard.path(for: RoyalUrBoard.bottomSeat)
        for (offset, square) in path.enumerated() {
            let rect = frame(square)
            let text = Text("\(offset + 1)")
                .font(.poppins(9, .bold))
                .foregroundColor(RoyalUrArt.ink)
            context.draw(context.resolve(text),
                         at: CGPoint(x: rect.midX, y: rect.midY))
        }
    }
}

// MARK: The multiplier

/// A worked board, scored by `BoneheadsRules.columnScore`.
///
/// The numbers are not typed in. Each row's product and each column's
/// subtotal are computed by the same function the game scores with, so the
/// worked example cannot disagree with the rule it is demonstrating.
private struct BoneheadsScoringFigure: View {

    /// Three columns that between them show all three multipliers: a pair,
    /// a triple, and three singles.
    private static let columns: [[Int]] = [[5, 5, 1], [3, 3, 3], [2, 5, 4]]

    private var total: Int {
        BoneheadsScoringFigure.columns
            .reduce(0) { $0 + BoneheadsRules.columnScore($1) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(BoneheadsScoringFigure.columns.enumerated()), id: \.offset) { index, column in
                BoneheadsColumnRow(label: BoneheadsRules.name(of: index),
                                   dice: column)
            }

            Divider().overlay(MenuInk.dim)

            Text("TOTAL: \(total)")
                .font(.poppins(14, .bold))
                .foregroundStyle(MenuInk.text)
        }
    }
}

/// One column of the worked example: its dice, each die's contribution, and
/// the column's score.
private struct BoneheadsColumnRow: View {
    let label: String
    let dice: [Int]

    /// How many times `value` appears — the multiplier the rule applies.
    private func occurrences(of value: Int) -> Int {
        dice.filter { $0 == value }.count
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.poppins(12, .bold))
                .foregroundStyle(MenuInk.dim)
                .frame(width: 16, alignment: .leading)

            ForEach(Array(dice.enumerated()), id: \.offset) { _, die in
                PipFace(value: die, tint: MenuInk.text)
                    .frame(width: 22, height: 22)
                Text("x\(occurrences(of: die))")
                    .font(.poppins(11))
                    .foregroundStyle(MenuInk.dim)
            }

            Spacer(minLength: 4)

            Text("= \(BoneheadsRules.columnScore(dice))")
                .font(.poppins(13, .bold))
                .foregroundStyle(MenuInk.text)
        }
    }
}
