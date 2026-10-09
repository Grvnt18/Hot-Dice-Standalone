import UIKit
import CoreText
import SwiftUI

/// Registers the bundled custom fonts (added as plain bundle
/// resources, same mechanism as the dice meshes/images) at runtime via
/// CoreText — Swift Playgrounds projects don't expose an editable
/// Info.plist the way a full Xcode project does, so the standard
/// UIAppFonts-key approach isn't available here. CTFontManagerRegisterFontsForURL
/// works regardless of Info.plist configuration, as long as the font
/// files are genuinely present in the bundle.
enum AppFonts {

    /// PostScript names read directly out of each file's `name` table
    /// rather than guessed from the filenames — UIFont(name:) and
    /// Font.custom(_:) require an exact match. For Poppins the two happen
    /// to agree; for the face this replaced they did not, which is the
    /// sort of thing that fails silently as a system-font fallback.
    ///
    /// Five static weights, where there used to be one.
    ///
    /// Stack Sans Notch was a VARIABLE font, and SwiftUI's `Font.custom`
    /// does not drive variable weight axes — so only its ExtraLight
    /// instance was ever registered and every size in the app, from an
    /// 11pt settings row to the 220pt turn-complete score, rendered in
    /// that one thin weight. That was a documented limitation. Poppins
    /// ships as separate static files, so a weight is now just a file.
    enum Weight: String, CaseIterable {
        case regular = "Poppins-Regular"
        case medium = "Poppins-Medium"
        case semibold = "Poppins-SemiBold"
        case bold = "Poppins-Bold"
        case black = "Poppins-Black"
    }

    /// Deliberately `fileprivate`, and still deliberately so after the swap.
    ///
    /// A display script's terminal glyphs overhang their own advance width,
    /// so anything that measures the advance — `Text`,
    /// `size(withAttributes:)` — cuts the last character. That was fixed
    /// three times in three different ways in this project and came back
    /// each time, because each new call site started from the raw font
    /// again.
    ///
    /// It would have been easy to assume Lobster, being a tamer face than
    /// Aguafina, made all of that unnecessary. Measured rather than assumed:
    /// Lobster's `L` still overhangs its advance by **+0.284 em** (Aguafina's
    /// worst was `Y` at +0.490). A quarter of an em is plenty to clip, and
    /// `L` is its worst offender while the two words that stay on this face
    /// are "Rolls" and "ROLLS". So the guard stays exactly as it was.
    ///
    /// The raw name does not leave this file. SwiftUI goes through
    /// `ScriptText`; UIKit goes through `scriptFont(_:)` and
    /// `inkBounds(of:font:)` below. A new game that reaches for the font
    /// directly does not compile, and `tools_script_verify.py` catches
    /// anything that tries to reconstruct the name instead.
    fileprivate static let lobsterPostScriptName = "Lobster-Regular"

    private static var didRegister = false

    /// Called as the literal first line of DiceSceneAssembler.assemble(),
    /// the one function guaranteed to run before anything in the scene
    /// (or the SwiftUI text around it) touches these fonts — not from
    /// app/view init, which runs too early relative to the sandboxed
    /// bundle context in a way that caused a real, hard-to-diagnose
    /// launch crash. Safe to call more than once; only the first call
    /// does anything.
    /// The font files this app expects in its bundle.
    ///
    /// Stated once and read by both the registration below and
    /// `BundleCheck`, which reports what is missing — two lists of the
    /// same filenames would drift, and the drift would be a check that
    /// looks for a file nobody ships any more.
    static let bundledFontResources =
        Weight.allCases.map(\.rawValue) + ["Lobster-Regular"]

    static func registerIfNeeded() {
        guard !didRegister else { return }
        didRegister = true

        for resource in bundledFontResources {
            register(resourceName: resource, extension: "ttf")
        }
    }

    /// Faces that did not resolve, after registration has run.
    ///
    /// `register` prints to the console and returns. A font that fails to
    /// register is therefore INVISIBLE on screen: `Font.custom` falls back
    /// to the system face and the text renders in a plausible-looking
    /// weight that is simply the wrong one. The hub's game names are set
    /// in Poppins-Black and were reported as not reading black — which is
    /// exactly what a silent fallback looks like, and there was no way to
    /// tell that from the font being right and the eye being wrong.
    ///
    /// So: ask UIKit to resolve each name and report the ones it cannot.
    /// `UIFont(name:size:)` returns nil when the PostScript name is not
    /// registered, and when it DOES resolve, `fontName` comes back as the
    /// face actually chosen — so a silent substitution is caught too.
    ///
    /// Checked against the files rather than assumed: all five PostScript
    /// names are exactly the enum's raw values (Poppins-Black,
    /// Poppins-Bold, Poppins-Medium, Poppins-Regular, Poppins-SemiBold),
    /// read out of each TTF's name table. So a miss here is a registration
    /// failure or a missing file, never a misspelling.
    static var unresolvedFaces: [String] {
        registerIfNeeded()
        var missing: [String] = []
        for name in bundledFontResources {
            guard let font = UIFont(name: name, size: 12) else {
                missing.append(name)
                continue
            }
            if font.fontName != name { missing.append(name) }
        }
        return missing
    }

    // MARK: Script text, for UIKit drawing

    /// Aguafina at a point size, falling back rather than trapping.
    ///
    /// A wrong-looking font is a far smaller problem than a crash inside a
    /// texture render — and a nil here once produced a zero-size image and
    /// an SCNPlane of height 0, which is degenerate geometry created
    /// mid-assembly (see `DiceSceneEnvironment.addFloorText`).
    /// The sans face as a `UIFont`, for the things drawn into textures
    /// rather than laid out by SwiftUI — chiefly the ballpark scoreboard.
    ///
    /// SemiBold: these are small numerals minified onto a texture, which is
    /// the same problem the die numerals had, and a real weight is the same
    /// answer.
    static func boardFont(_ size: CGFloat) -> UIFont {
        UIFont(name: Weight.semibold.rawValue, size: size)
            ?? UIFont.systemFont(ofSize: size, weight: .semibold)
    }

    static func scriptFont(_ size: CGFloat) -> UIFont {
        UIFont(name: lobsterPostScriptName, size: size)
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
    /// The rect a canvas must be to hold this text, and the offset to draw
    /// it at — the union of the INK box and the LINE box.
    ///
    /// `inkBounds` alone is not enough, and the floor wordmark proved it.
    /// The two measurements are in the same coordinate space but describe
    /// different things:
    ///
    ///   * ink   — where the glyphs actually put pixels. Can overhang the
    ///             line box on any side; a script face's swash routinely
    ///             overhangs right, and its descender overhangs below.
    ///   * line  — the typographic box, and what `draw(at:)` positions
    ///             from. Its origin is the line fragment origin, not the
    ///             first glyph's corner.
    ///
    /// Sizing from ink and then drawing with `draw(at:)` mixes the two
    /// conventions. Aguafina survived it; Lobster did not, and the floor
    /// title came out clipped along the bottom — a descender hanging below
    /// a canvas that had been measured without it.
    ///
    /// Taking the union cannot clip either way: the canvas holds the
    /// glyphs wherever they fall AND the line box the draw call lays out
    /// from. Returns the rect in line-origin space, so drawing at
    /// `-rect.origin` places the whole thing inside the canvas.
    static func canvasBounds(of text: String, font: UIFont) -> CGRect {
        let ink = inkBounds(of: text, font: font)
        let line = (text as NSString).size(withAttributes: [.font: font])
        let minX = min(ink.minX, 0)
        let minY = min(ink.minY, 0)
        let maxX = max(ink.maxX, line.width)
        let maxY = max(ink.maxY, line.height)
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

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
    /// Poppins, the default font for every piece of text in this app.
    ///
    /// The note that used to be here described Stack Sans Notch — a
    /// variable font whose only registered instance was ExtraLight, so
    /// every size in the app rendered thin and no call site could ask for
    /// heavier. That is history: Poppins ships as five separate static
    /// files and a weight is now just a file, with `.black` the heaviest
    /// the family has. Left stale, that note read as a live warning that
    /// weight could not be set at all, which is the opposite of true.
    ///
    /// The name passed here is the face's PostScript name, verified
    /// against each TTF's name table. If a weight still looks wrong on
    /// screen, the face did not register — see `unresolvedFaces`, which
    /// BundleCheck surfaces on the hub.
    static func poppins(_ size: CGFloat, _ weight: AppFonts.Weight = .regular) -> Font {
        // The relativeTo: overload, not plain .custom(_:size:) — the latter
        // puts the font on a code path where `.minimumScaleFactor` doesn't
        // reliably shrink the whole glyph run. Instead it can leave the
        // rightmost character clipped rather than scaled down, which is
        // exactly what was cutting off the last digit of the score on the
        // turn-complete screen (Text(...).font(.poppins(220, .black)) there
        // combines a huge fixed size with an aggressive minimumScaleFactor).
        // relativeTo: puts Text's shrink-to-fit on the code path that
        // actually scales the custom font instead of clipping it.
        .custom(weight.rawValue, size: size, relativeTo: .body)
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
    /// `AppFonts.lobsterPostScriptName`.
    fileprivate static func lobster(_ size: CGFloat) -> Font {
        // Same relativeTo: fix as poppins above — this face is also used
        // with minimumScaleFactor (the turn-complete caption).
        .custom(AppFonts.lobsterPostScriptName, size: size, relativeTo: .body)
    }
}

// MARK: - Script text

/// Script text that does not lose its last letter.
///
/// The face's terminal glyphs overhang their own advance width, and
/// SwiftUI sizes a `Text` from the advance — so the final glyph is cut
/// against the trailing edge of its own frame. Five call sites had each
/// guessed their own `.padding(.trailing, 4...6)` at that, and two more
/// appended literal spaces to the string; all of them work at one point
/// size and fail at the next.
///
/// **This is the only way the script face reaches SwiftUI.** `Font.lobster`
/// and the PostScript name are `fileprivate`, so a new game cannot start
/// from the raw font and rediscover the bug — which is exactly how it came
/// back the last three times.
///
/// Kept through the swap to Lobster on evidence, not habit: measured against
/// its own advance widths, Lobster's `L` overhangs by +0.284 em (Aguafina's
/// worst was `Y` at +0.490). Tamer, nowhere near tame enough to drop this —
/// and `L` is its worst glyph, in a face that now renders "Rolls" and
/// "ROLLS".
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
            .font(.lobster(size))
            .lineLimit(lineLimit)
            .minimumScaleFactor(minimumScaleFactor ?? 1)
            .multilineTextAlignment(.center)
            .padding(.horizontal, size * 0.07)
            .fixedSize(horizontal: false, vertical: true)
    }
}
