import UIKit
import CoreText
import SwiftUI

/// Registers the two bundled custom fonts (added as plain bundle
/// resources, same mechanism as the dice meshes/images) at runtime via
/// CoreText — Swift Playgrounds projects don't expose an editable
/// Info.plist the way a full Xcode project does, so the standard
/// UIAppFonts-key approach isn't available here. CTFontManagerRegisterFontsForURL
/// works regardless of Info.plist configuration, as long as the font
/// files are genuinely present in the bundle.
enum AppFonts {

    /// PostScript names extracted directly from the font files' own
    /// metadata (via fontTools) rather than guessed from the filenames —
    /// UIFont(name:) / Font.custom(_:) require an exact match.
    static let stackSansPostScriptName = "StackSansNotch-ExtraLight"
    static let aguafinaScriptPostScriptName = "AguafinaScript-Regular"

    private static var didRegister = false

    /// Called as the literal first line of DiceSceneAssembler.assemble(),
    /// the one function guaranteed to run before anything in the scene
    /// (or the SwiftUI text around it) touches these fonts — not from
    /// app/view init, which runs too early relative to the sandboxed
    /// bundle context in a way that caused a real, hard-to-diagnose
    /// launch crash. Safe to call more than once; only the first call
    /// does anything.
    static func registerIfNeeded() {
        guard !didRegister else { return }
        didRegister = true

        register(resourceName: "StackSansNotch-VariableFont_wght", extension: "ttf")
        register(resourceName: "AguafinaScript-Regular", extension: "ttf")
    }

    private static func register(resourceName: String, extension ext: String) {
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: ext) else {
            print("[AppFonts] Missing bundled font: \(resourceName).\(ext)")
            return
        }
        var error: Unmanaged<CFError>?
        let success = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        if !success {
            let message = error?.takeRetainedValue().localizedDescription ?? "unknown error"
            print("[AppFonts] Failed to register font \(resourceName): \(message)")
        }
    }
}

// MARK: - SwiftUI convenience

extension Font {
    /// Stack Sans Notch, the default font for every piece of text in this
    /// app. Note: the bundled file is a variable font whose default
    /// (only-registered) instance is the ExtraLight weight — SwiftUI's
    /// Font.custom doesn't drive variable-font weight axes directly, so
    /// every size uses that same weight rather than a bolder cut for
    /// emphasis. If particular text needs to read heavier, that would need
    /// a separately-exported static weight instance of the font rather
    /// than something achievable purely at the call site here.
    static func stackSans(_ size: CGFloat) -> Font {
        // The relativeTo: overload, not plain .custom(_:size:) — the latter
        // puts the font on a code path where `.minimumScaleFactor` doesn't
        // reliably shrink the whole glyph run. Instead it can leave the
        // rightmost character clipped rather than scaled down, which is
        // exactly what was cutting off the last digit of the score on the
        // turn-complete screen (Text(...).font(.stackSans(220)) there
        // combines a huge fixed size with an aggressive minimumScaleFactor).
        // relativeTo: puts Text's shrink-to-fit on the code path that
        // actually scales the custom font instead of clipping it.
        .custom(AppFonts.stackSansPostScriptName, size: size, relativeTo: .body)
    }

    /// Aguafina Script — the decorative script used for the "ROLLS" floor
    /// text, the ROLLS die face, and the settings menu. Runs noticeably
    /// smaller than Stack Sans at the same point size (script faces have a
    /// small x-height relative to their em), so call sites generally want
    /// a larger number than the Stack Sans equivalent.
    static func aguafina(_ size: CGFloat) -> Font {
        // Same relativeTo: fix as stackSans above — this face is also used
        // with minimumScaleFactor (the turn-complete caption).
        .custom(AppFonts.aguafinaScriptPostScriptName, size: size, relativeTo: .body)
    }
}
