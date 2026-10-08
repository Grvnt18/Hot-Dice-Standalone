import SwiftUI
import UIKit

/// The bundled icon artwork: one per game for the hub, plus the weapon and
/// Cyberware marks Rollbots uses on its cards.
///
/// Loaded through `BundleImageLoader`, the same lookup the dice texture
/// uses — asset catalog first, then a loose file in the bundle.
///
/// This used to go straight to `Bundle.main.path(forResource:ofType:)` on
/// the reasoning that "this project has no asset catalog; it is
/// hand-assembled in Swift Playgrounds, where every resource is a plain
/// bundle file". That was wrong, and it cost four phases of the icons
/// never appearing: **Swift Playgrounds on iPad puts images added to a
/// project into its asset catalog**, so `UIImage(named:)` finds them and a
/// path lookup does not. `pix_texture.png` worked the whole time precisely
/// because BundleImageLoader tries the catalog first.
///
/// Hence the delegation rather than a second copy of the lookup: one
/// proven path used everywhere beats two that can disagree.
enum GameIcons {

    /// Decoded images, kept because the hub draws ten of them at once and
    /// re-reading a 1024px PNG per redraw would be felt on a scroll.
    private static var cache: [String: UIImage] = [:]

    static func image(named name: String) -> UIImage? {
        if let cached = cache[name] { return cached }
        guard let image = BundleImageLoader.load(named: name) else { return nil }
        cache[name] = image
        return image
    }

    /// A game's tile icon, by its `SuiteGame.id`.
    ///
    /// Derived from the id rather than each game carrying a second string:
    /// one name to get wrong instead of two, and a missing file shows up
    /// in `tools_icons_verify.py` rather than as a blank tile on device.
    static func game(_ id: String) -> UIImage? {
        image(named: "icon-\(id)")
    }
}

// MARK: - Views

/// A game's icon — or, if it cannot be found, a box naming the file it
/// wanted.
///
/// It used to draw nothing at all, documented as a deliberate graceful
/// degradation. That is exactly how a loader bug hid for four phases: an
/// absent icon looked identical to a design choice, on a device with no
/// console to check. A missing resource now says so on screen, and says
/// which one.
struct GameIconView: View {
    let id: String

    var body: some View {
        if let image = GameIcons.game(id) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            MissingIconView(filename: "icon-\(id).png")
        }
    }
}

/// A game's mark with its own silhouette traced behind it.
///
/// The hub needs the artwork to read against timber without being put in a
/// box. The art is black line work on transparency, so `.renderingMode(
/// .template)` fills its alpha — the strokes — with a flat colour, and
/// four offset copies of that, one per diagonal, make an outline that
/// follows the drawing instead of enclosing it.
///
/// Four diagonals rather than a blur: a blur of line work on wood is the
/// smudge the drop shadow already was, and SwiftUI's `.shadow(radius:)`
/// on a template image costs an offscreen pass per tile. Offset copies are
/// cheap and read as a hard pixel outline, which is the house style.
struct GameIconHalo: View {
    let id: String

    /// How far the outline sits off the line work, as a fraction of the
    /// icon's side. Small: this traces the drawing, it does not bloom
    /// around it.
    private static let spread: CGFloat = 0.018

    var body: some View {
        GeometryReader { geo in
            let step = min(geo.size.width, geo.size.height) * Self.spread
            ZStack {
                if let image = GameIcons.game(id) {
                    ForEach(Array(Self.diagonals.enumerated()), id: \.offset) { _, corner in
                        Image(uiImage: image)
                            .renderingMode(.template)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .foregroundStyle(SmokeFloor.backdropColor.opacity(0.55))
                            .offset(x: corner.x * step, y: corner.y * step)
                    }
                }
                GameIconView(id: id)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    /// Out of the ViewBuilder: a literal array of tuples inside a ForEach
    /// inside a GeometryReader is the shape Xcode 14.2's solver gives up
    /// on, which is the same reason PipFace.pipOffset exists.
    private static let diagonals: [CGPoint] = [
        CGPoint(x: -1, y: -1), CGPoint(x: 1, y: -1),
        CGPoint(x: -1, y: 1), CGPoint(x: 1, y: 1)
    ]
}

/// The visible stand-in for a resource that would not load.
private struct MissingIconView: View {
    let filename: String

    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .strokeBorder(.white.opacity(0.55),
                          style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            .overlay(
                Text(filename)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.5)
                    .padding(4)
            )
    }
}

/// A bundled mark, tinted — Rollbots' weapons and abilities, and Baseball
/// Dice's pitching styles and swings.
///
/// The source art is black line work on transparency, which would be half
/// invisible on the arena's near-black panels. Rendering it as a template
/// takes the silhouette from the alpha channel and fills it with the tint
/// instead, so a mark reads at the same strength as the text beside it —
/// and lets Baseball Dice draw the same art in its card ink rather than in
/// flat black.
struct NetIconView: View {
    let name: String
    let tint: Color

    var body: some View {
        if let image = GameIcons.image(named: name) {
            Image(uiImage: image)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(tint)
        }
    }
}
