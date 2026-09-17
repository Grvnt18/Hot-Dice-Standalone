import SwiftUI

// If you created this project via Swift Playgrounds' own "Create App"
// template, it already generated its own @main App struct in a different
// file. Since only one @main is allowed per app, DELETE THIS FILE and
// instead put `DiceGameScreen()` inside that existing WindowGroup —
// everything else in this package works unchanged either way.

@main
struct DiceGameTestApp: App {
    // Font registration moved OUT of init() — an App struct's init runs
    // extremely early, before the view hierarchy (and possibly before the
    // sandboxed bundle/resource context) is fully set up. Registering
    // fonts via CoreText at that point is a plausible cause of a generic,
    // no-stack-trace "failed to launch" crash — the same class of silent
    // early-crash we hit several times earlier in this project, always
    // traced back to something happening too early or in an environment-
    // specific way Playgrounds doesn't fully support. DiceGameScreen's own
    // .onAppear call (see DiceGameShell.swift) is the sole registration
    // point now — it runs once the view hierarchy is actually up, a much
    // safer place for this kind of setup work.
    var body: some Scene {
        WindowGroup {
            DiceGameScreen()
                .preferredColorScheme(.dark)
        }
    }
}
