import SwiftUI
import UIKit

/// One shared accent color, used for the playing-surface (floor) background
/// and for the buttons/sliders inside the settings menu. Persisted the same
/// way SoundEngine persists its own settings, and observable the same way,
/// so any view holding it live-updates when the selection changes.
final class AppTheme: ObservableObject {

    static let shared = AppTheme()

    struct Swatch {
        let hex: String
        let name: String
    }

    /// Index 0 is the game's original green, kept first and as the default
    /// so a fresh install looks exactly as it always has.
    ///
    /// The other 23 are picked to sit away from every DieColorway.bodyHex
    /// (see DiceGame.swift's DiePalette) in hue/lightness, so a die of any
    /// color still reads clearly against the floor rather than blending
    /// into it — the die palette already spans yellow, light blue, sage
    /// green, magenta, red, orange, tan/brown and near-white, so these
    /// lean toward deep, muted blues/violets/reds/teals/neutrals that
    /// don't overlap any of those, plus two lighter shades (Pale Lavender,
    /// Dusty Periwinkle) to cover the "brighter shade" case (see
    /// AppTheme.rollsTextIsDark).
    ///
    /// The second batch of 12 (Deep Indigo onward) was picked to also stay
    /// clear of the first 12 — distinct hue OR distinct lightness/
    /// saturation from every earlier entry, not just a re-run of the same
    /// families (e.g. Petrol Teal is bluer than Deep Teal; Storm Blue is
    /// darker/grayer than Steel Blue; Espresso is a warm near-black
    /// pairing with Onyx's cool near-black) — so the full 24-swatch set
    /// reads as genuinely distinct choices rather than near-duplicates.
    static let swatches: [Swatch] = [
        Swatch(hex: "#36F422", name: "Green"),
        Swatch(hex: "#1B2A4A", name: "Midnight Navy"),
        Swatch(hex: "#2952CC", name: "Royal Blue"),
        Swatch(hex: "#5B2C91", name: "Deep Violet"),
        Swatch(hex: "#7A1F3D", name: "Wine"),
        Swatch(hex: "#0B4F4A", name: "Deep Teal"),
        Swatch(hex: "#14140F", name: "Onyx"),
        Swatch(hex: "#34568B", name: "Steel Blue"),
        Swatch(hex: "#6B2D5C", name: "Mauve Plum"),
        Swatch(hex: "#23424A", name: "Slate Cyan"),
        Swatch(hex: "#0C3B2E", name: "Forest"),
        Swatch(hex: "#C9C2E0", name: "Pale Lavender"),
        Swatch(hex: "#2B1B4E", name: "Deep Indigo"),
        Swatch(hex: "#1C2833", name: "Charcoal Blue"),
        Swatch(hex: "#4A1027", name: "Burgundy"),
        Swatch(hex: "#0F3B3E", name: "Petrol Teal"),
        Swatch(hex: "#45525C", name: "Cool Slate"),
        Swatch(hex: "#16325C", name: "Deep Sapphire"),
        Swatch(hex: "#3B1F3A", name: "Aubergine"),
        Swatch(hex: "#12261C", name: "Pine"),
        Swatch(hex: "#29394A", name: "Storm Blue"),
        Swatch(hex: "#8B93C4", name: "Dusty Periwinkle"),
        Swatch(hex: "#6E4550", name: "Rose Gray"),
        Swatch(hex: "#2E1C12", name: "Espresso")
    ]

    private enum Keys {
        static let colorwayIndex = "theme.colorwayIndex"
    }

    private let defaults = UserDefaults.standard

    @Published var colorwayIndex: Int {
        didSet {
            guard Self.swatches.indices.contains(colorwayIndex) else { return }
            defaults.set(colorwayIndex, forKey: Keys.colorwayIndex)
        }
    }

    private init() {
        defaults.register(defaults: [Keys.colorwayIndex: 0])
        let stored = defaults.integer(forKey: Keys.colorwayIndex)
        colorwayIndex = Self.swatches.indices.contains(stored) ? stored : 0
    }

    private var currentHex: String { Self.swatches[colorwayIndex].hex }

    /// For SwiftUI: tints the settings menu's buttons and sliders.
    var accentColor: Color { Color(hex: currentHex) }

    /// For SceneKit: the floor is rendered from this, darkened the same way
    /// the original hardcoded green always was (see
    /// DiceSceneEnvironment.addFloorSurface) — every shade goes through the
    /// identical faceted-surface + darken treatment, so only the hue
    /// changes, not the overall look.
    var floorBaseColor: UIColor { UIColor(hex: currentHex) }

    /// True when the floor is bright enough that the white "ROLLS" text
    /// would lose contrast against it and needs to switch to black.
    ///
    /// Judged against the SAME darkened tone addFloorSurface actually
    /// paints (floorBaseColor.darkened(by: 0.25)), not the raw swatch hex —
    /// otherwise this and the visible floor could disagree about how
    /// bright the surface really is. The default green, for instance, is
    /// bright enough undarkened to cross the threshold, but the darkening
    /// already applied to the real floor brings it back under — matching
    /// this game's existing (correct) white-on-green look rather than
    /// changing it.
    var rollsTextIsDark: Bool {
        floorBaseColor.darkened(by: 0.25).relativeLuminance > 0.6
    }
}
