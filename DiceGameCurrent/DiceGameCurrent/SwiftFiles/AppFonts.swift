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

    /// Deliberately `fileprivate`.
    ///
    /// Aguafina's terminal swashes overhang their own advance width, so
    /// anything that measures the advance — `Text`, `size(withAttributes:)`
    /// — cuts the last character. That has been fixed three times in three
    /// different ways in this project and come back each time, because
    /// each new call site started from the raw font again.
    ///
    /// So the raw name does not leave this file. SwiftUI goes through
    /// `ScriptText`; UIKit goes through `scriptFont(_:)` and
    /// `inkBounds(of:font:)` below. A new game that reaches for the font
    /// directly does not compile, and `tools_script_verify.py` catches
    /// anything that tries to reconstruct the name instead.
    fileprivate static let aguafinaScriptPostScriptName = "AguafinaScript-Regular"

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

    // MARK: Script text, for UIKit drawing

    /// Aguafina at a point size, falling back rather than trapping.
    ///
    /// A wrong-looking font is a far smaller problem than a crash inside a
    /// texture render — and a nil here once produced a zero-size image and
    /// an SCNPlane of height 0, which is degenerate geometry created
    /// mid-assembly (see `DiceSceneEnvironment.addFloorText`).
    static func scriptFont(_ size: CGFloat) -> UIFont {
        UIFont(name: aguafinaScriptPostScriptName, size: size)
            ?? UIFont.italicSystemFont(ofSize: size)
    }

    /// The rectangle a string actually INKS, which is not the rectangle it
    /// advances.
    ///
    /// `size(withAttributes:)` returns the typographic advance, and a
    /// script face's final swash is drawn past it by design — so a canvas
    /// sized from the advance clips that swash however much padding is put
    /// around it. `.usesDeviceMetrics` asks for the drawn bounds instead,
    /// including the overhang on the right and any negative left bearing.
    ///
    /// The origin is part of the answer: it is usually negative, and
    /// drawing at `-origin` is what puts every inked pixel inside the
    /// canvas. Callers that ignore it will still clip on the left.
    static func inkBounds(of text: String, font: UIFont) -> CGRect {
        let unbounded = CGSize(width: CGFloat.greatestFiniteMagnitude,
                               height: CGFloat.greatestFiniteMagnitude)
        return (text as NSString).boundingRect(
            with: unbounded,
            options: [.usesLineFragmentOrigin, .usesDeviceMetrics],
            attributes: [.font: font],
            context: nil
        )
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
    ///
    /// `fileprivate` for the same reason the PostScript name is: the only
    /// way to put Aguafina on screen is `ScriptText`, which reserves the
    /// room this face needs. See the note on
    /// `AppFonts.aguafinaScriptPostScriptName`.
    fileprivate static func aguafina(_ size: CGFloat) -> Font {
        // Same relativeTo: fix as stackSans above — this face is also used
        // with minimumScaleFactor (the turn-complete caption).
        .custom(AppFonts.aguafinaScriptPostScriptName, size: size, relativeTo: .body)
    }
}

// MARK: - Script text

/// Aguafina text that does not lose its last letter.
///
/// The face's terminal swashes overhang their own advance width, and
/// SwiftUI sizes a `Text` from the advance — so the final glyph is cut
/// against the trailing edge of its own frame. Five call sites had each
/// guessed their own `.padding(.trailing, 4...6)` at that, and two more
/// appended literal spaces to the string; all of them work at one point
/// size and fail at the next.
///
/// **This is now the only way Aguafina reaches SwiftUI.** `Font.aguafina`
/// and the PostScript name are `fileprivate`, so a new game cannot start
/// from the raw font and rediscover the bug — which is exactly how it came
/// back the last three times.
///
/// Three things hold the glyph inside its box, deliberately layered,
/// because none of them is provable without a device:
///
///  1. **A no-break space at each end.** `\u{00A0}` is not trimmed the way
///     an ordinary trailing space is, so it genuinely widens the advance
///     Core Text lays the line out from — the same mechanism that makes
///     `renderScriptText`'s ink-sized canvas work, applied to live text.
///     Symmetric, so centring is unchanged and the leading entry stroke is
///     covered too.
///  2. **Room proportional to the size**, so the reserve scales with the
///     type rather than being re-tuned per site.
///  3. **`fixedSize` vertically**, so a parent cannot squeeze the frame
///     back down and reintroduce the clip.
///
/// If a label still nicks on device, the guaranteed fix already exists and
/// is proven: draw it through `DiceSceneEnvironment.renderScriptText`,
/// whose canvas is sized from `AppFonts.inkBounds` — from drawn pixels
/// rather than from metrics — and therefore cannot clip.
struct ScriptText: View {
    let text: String
    let size: CGFloat
    var lineLimit: Int? = 1

    /// For the two sites that fit a headline into a fixed box. Left nil
    /// rather than defaulted to 1.0 so `Text` keeps its own behaviour
    /// where nobody asked for shrinking.
    var minimumScaleFactor: CGFloat?

    init(_ text: String,
         size: CGFloat,
         lineLimit: Int? = 1,
         minimumScaleFactor: CGFloat? = nil) {
        self.text = text
        self.size = size
        self.lineLimit = lineLimit
        self.minimumScaleFactor = minimumScaleFactor
    }

    /// The string with a no-break space at each end. See (1) above.
    ///
    /// `Text(verbatim:)` rather than `Text(_:)`: the latter treats its
    /// argument as a localisation key, and a key with padding spaces is
    /// not the key anyone wrote.
    private var reserved: String { "\u{00A0}" + text + "\u{00A0}" }

    var body: some View {
        Text(verbatim: reserved)
            .font(.aguafina(size))
            .lineLimit(lineLimit)
            .minimumScaleFactor(minimumScaleFactor ?? 1)
            .multilineTextAlignment(.center)
            .padding(.horizontal, size * 0.07)
            .fixedSize(horizontal: false, vertical: true)
    }
}
