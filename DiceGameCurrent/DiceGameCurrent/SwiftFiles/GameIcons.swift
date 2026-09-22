import SwiftUI
import UIKit

/// The bundled icon artwork: one per game for the hub, plus the weapon and
/// Cyberware marks Rollbots uses on its cards.
///
/// Loaded from loose files in `Resources/` through `Bundle.main`, the same
/// way the fonts, the dice meshes and `pix_texture.png` already are.
/// SwiftUI's `Image(_:)` is deliberately not used — it looks in an asset
/// catalog, and this project has none; it is hand-assembled in Swift
/// Playgrounds on an iPad, where every resource is a plain bundle file.
enum GameIcons {

    /// Decoded images, kept because the hub draws ten of them at once and
    /// re-reading a 1024px PNG per redraw would be felt on a scroll.
    private static var cache: [String: UIImage] = [:]

    static func image(named name: String) -> UIImage? {
        if let cached = cache[name] { return cached }
        guard let path = Bundle.main.path(forResource: name, ofType: "png"),
              let image = UIImage(contentsOfFile: path) else {
            return nil
        }
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

/// A game's icon, or nothing at all if the file is missing.
///
/// Draws nothing rather than a placeholder box: the tile underneath still
/// carries the game's name, so an absent icon degrades to the layout this
/// screen had before the artwork existed.
struct GameIconView: View {
    let id: String

    var body: some View {
        if let image = GameIcons.game(id) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
        }
    }
}

/// A Rollbots weapon or ability mark, tinted.
///
/// The source art is greyscale line work on transparency, which would be
/// half invisible on the arena's near-black panels. Rendering it as a
/// template takes the silhouette from the alpha channel and fills it with
/// the tint instead, so a mark reads at the same strength as the text
/// beside it.
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
