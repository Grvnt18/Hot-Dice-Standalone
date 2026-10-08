import Foundation

/// Reports bundle resources the app needs and cannot find.
///
/// Everything here is a loose file — meshes, fonts, audio — as opposed to
/// the icons, which Swift Playgrounds keeps in its asset catalog. That
/// difference is why a project missing its Resources folder fails in a
/// way that looks like four unrelated faults at once: no dice on any
/// table, no music or effects, and the script face silently substituted.
///
/// Each of those failures is individually graceful and therefore
/// invisible. `DiceSceneBuilder.buildNodes` skips a die whose mesh is
/// missing and carries on; `AppFonts.register` prints and returns;
/// `DiceAudioEngine` finds no file and stays quiet. Nothing crashes, so
/// nothing says what is wrong.
///
/// `GameIconView` already solves this shape of problem for artwork by
/// drawing a box naming the file it wanted, rather than nothing at all.
/// This is the same idea for the resources that have no view of their own.
enum BundleCheck {

    /// One die mesh per shape the app can roll. Any of `.scn`, `.obj` or
    /// `.dae` will do — the same order `DieMeshLibrary` tries.
    private static let meshSides = [4, 6, 8, 10, 12, 20]
    private static let meshExtensions = ["scn", "obj", "dae"]


    /// What is absent, as filenames a person can search their project for.
    ///
    /// Computed once: the bundle does not change while the app is running,
    /// and this is read from a view body.
    static let missing: [String] = {
        var absent: [String] = []

        for sides in meshSides {
            let name = "d\(sides)"
            let found = meshExtensions.contains { ext in
                Bundle.main.url(forResource: name, withExtension: ext) != nil
            }
            if !found { absent.append("\(name).obj") }
        }

        // From AppFonts rather than restated here: the registration and
        // this check must look for the same files.
        for font in AppFonts.bundledFontResources
        where Bundle.main.url(forResource: font, withExtension: "ttf") == nil {
            absent.append("\(font).ttf")
        }

        // One track is enough to tell whether the audio came across; naming
        // every missing file would bury the point in a list.
        if Bundle.main.url(forResource: SoundEngine.tracks.first?.resource
                           ?? "music_baller", withExtension: "m4a") == nil {
            absent.append("music_*.m4a")
        }

        return absent
    }()

    static var isComplete: Bool { missing.isEmpty }

    /// A single line naming what to look for, or nil when all is well.
    static var summary: String? {
        // A font that is in the bundle but failed to REGISTER is a
        // different failure from one that is absent, and it is the worse
        // of the two: the file is there, nothing is missing, and the text
        // renders in a system fallback at a weight nobody chose. The hub's
        // game names are set in Poppins-Black and came back not reading
        // black, which is precisely what that looks like — and there was
        // no way, from a screenshot, to tell it from the weight simply
        // being wrong.
        let fallbacks = AppFonts.unresolvedFaces
        var notes: [String] = []
        if !isComplete {
            let names = missing.prefix(4).joined(separator: ", ")
            let more = missing.count > 4 ? " and \(missing.count - 4) more" : ""
            notes.append("Missing from the project: \(names)\(more).")
        }
        if !fallbacks.isEmpty {
            notes.append("Not rendering in their own face, so the system "
                         + "font is standing in: "
                         + fallbacks.joined(separator: ", ") + ".")
        }
        return notes.isEmpty ? nil : notes.joined(separator: " ")
    }
}
