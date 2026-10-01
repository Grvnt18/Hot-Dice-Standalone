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
    /// The rest are picked to sit away from every DieColorway.bodyHex (see
    /// DiceGame.swift's DiePalette) in hue/lightness, so a die of any color
    /// still reads clearly against the floor rather than blending into it —
    /// the die palette already spans yellow, light blue, sage green,
    /// magenta, red, orange, tan/brown and near-white, so these lean
    /// toward deep, muted blues/violets/reds/teals/neutrals that don't
    /// overlap any of those, plus a handful of brighter shades (Pale
    /// Lavender, Dusty Periwinkle, and the five vivid ones below) to cover
    /// the "brighter shade" case (see AppTheme.rollsTextIsDark) and give
    /// the picker some genuinely vivid options, not just deep/muted ones.
    ///
    /// Five swatches from the original 24 (Forest, Charcoal Blue, Petrol
    /// Teal, Deep Sapphire, Storm Blue) were cut for being the most
    /// mutually similar — computed by pairwise RGB distance, they were
    /// clustered in the same dark navy/teal territory as Midnight Navy,
    /// Deep Teal, Slate Cyan and Steel Blue already covered, several under
    /// 25 units apart (Slate Cyan/Storm Blue were the closest pair in the
    /// whole set, at ~11) — genuinely hard to tell apart in the picker,
    /// unlike everything that remains.
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
        Swatch(hex: "#C9C2E0", name: "Pale Lavender"),
        Swatch(hex: "#2B1B4E", name: "Deep Indigo"),
        Swatch(hex: "#4A1027", name: "Burgundy"),
        Swatch(hex: "#45525C", name: "Cool Slate"),
        Swatch(hex: "#3B1F3A", name: "Aubergine"),
        Swatch(hex: "#12261C", name: "Pine"),
        Swatch(hex: "#8B93C4", name: "Dusty Periwinkle"),
        Swatch(hex: "#6E4550", name: "Rose Gray"),
        Swatch(hex: "#2E1C12", name: "Espresso"),
        Swatch(hex: "#1E6FFF", name: "Electric Blue"),
        Swatch(hex: "#8B2FE0", name: "Vivid Violet"),
        Swatch(hex: "#00E5C7", name: "Turquoise"),
        Swatch(hex: "#FF2D78", name: "Hot Rose"),
        Swatch(hex: "#00FF85", name: "Spring Green")
    ]

    private enum Keys {
        static let colorwayIndex = "theme.colorwayIndex"
    }

    private let defaults = UserDefaults.standard

    /// Written through `GameScope`, so a colour chosen inside a game stays
    /// that game's. See `reloadForScope()`.
    @Published var colorwayIndex: Int {
        didSet {
            guard Self.swatches.indices.contains(colorwayIndex) else { return }
            GameScope.set(colorwayIndex, Keys.colorwayIndex)
        }
    }

    private init() {
        defaults.register(defaults: [Keys.colorwayIndex: 0])
        colorwayIndex = Self.storedIndex()
    }

    /// Re-reads the colour for whichever game is now in force.
    ///
    /// Assigning `colorwayIndex` re-fires its own `didSet`, which writes
    /// the value straight back to the scope it was just read from — a
    /// no-op, and the reason this does not need to suppress it.
    ///
    /// Only `GameScope` calls this. It is not private because that type is
    /// what owns the decision of whose settings apply.
    func reloadForScope() {
        let wanted = Self.storedIndex()
        if wanted != colorwayIndex { colorwayIndex = wanted }
    }

    private static func storedIndex() -> Int {
        let stored = GameScope.int(Keys.colorwayIndex)
        return swatches.indices.contains(stored) ? stored : 0
    }

    private var currentHex: String { Self.swatches[colorwayIndex].hex }

    /// For SwiftUI: tints the settings menu's buttons and sliders.
    var accentColor: Color { Color(hex: currentHex) }

    /// For SceneKit: the four tones of the rolling area are derived from
    /// this — see `SmokeFloor.ramp(from:)`, which hangs them downward from
    /// the swatch so the brightest of the four IS the colour picked here.
    var floorBaseColor: UIColor { UIColor(hex: currentHex) }

    /// True when the floor is bright enough that the white "ROLLS" text
    /// would lose contrast against it and needs to switch to black.
    ///
    /// Judged against the BRIGHTEST of the four tones the floor actually
    /// paints, not the raw swatch and no longer the old
    /// `darkened(by: 0.25)` — script sitting on the lightest part of the
    /// field is where it loses contrast first, so that is the tone that
    /// decides. The principle is the one that was already here: this and the
    /// visible floor must not disagree about how bright the surface is. Only
    /// the floor changed.
    var rollsTextIsDark: Bool {
        let brightest = SmokeFloor.ramp(from: floorBaseColor).last ?? floorBaseColor
        return brightest.relativeLuminance > 0.6
    }
}
