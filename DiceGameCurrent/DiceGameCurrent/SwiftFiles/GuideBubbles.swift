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
        NavigationStack {
            ZStack {
                WoodTiledBackground()
                    .ignoresSafeArea()
                Color.black.opacity(0.35)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 14) {
                        Text("Pick a game for its full rules — every table "
                             + "and every edge case. The short version is "
                             + "in each game's own Settings.")
                            .font(.stackSans(13))
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("How to Play").font(.stackSans(17))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.stackSans(15))
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(
                            .roundedRectangle(radius: ControlShape.cornerRadius * 0.6))
                        .tint(theme.accentColor)
                }
            }
        }
        .sheet(item: $opened) { entry in
            // The FULL guide. `GameCatalogEntry.rules` is the detailed set;
            // the short one is `quickRules`, and a game's own Settings is
            // where that belongs.
            HowToPlayView(gameName: entry.displayName,
                          tagline: entry.tagline,
                          sections: entry.rules)
        }
        .onAppear(perform: popIn)
    }

    private func bubble(_ entry: GameCatalogEntry, index: Int) -> some View {
        let isShown = index < shown

        return Button {
            SoundEngine.shared.play(.buttonTap)
            opened = entry
        } label: {
            ScriptText(entry.tileName,
                       size: GuideBubbleLayout.nameSize,
                       lineLimit: 2,
                       minimumScaleFactor: 0.5)
                .textCase(nil)
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity)
                .frame(height: GuideBubbleLayout.height)
                .background(
                    Capsule().fill(theme.accentColor.opacity(0.92))
                )
                .overlay(
                    Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 1)
                )
                .elevated(.lifted)
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
