import SwiftUI

// If you created this project via Swift Playgrounds' own "Create App"
// template, it already generated its own @main App struct in a different
// file. Since only one @main is allowed per app, DELETE THIS FILE and
// instead put `GameHubView()` inside that existing WindowGroup —
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
    // specific way Playgrounds doesn't fully support.
    //
    // Registration now happens from two places, both safely inside the
    // view lifecycle rather than before it: the first line of
    // DiceSceneAssembler.assemble(), which covers anything that builds a
    // SceneKit scene, and GameHubView.onAppear, which covers the hub
    // itself and any future 2D game that never builds one. (An earlier
    // comment here claimed DiceGameScreen.onAppear was the sole
    // registration point; it was not — the call had moved to the
    // assembler.) AppFonts.registerIfNeeded() is idempotent, so having
    // both costs nothing. What matters is that neither runs this early.
    var body: some Scene {
        WindowGroup {
            // The hub, not a game. Rolls is now one tile among eight
            // rather than the whole app — it opens from GameHubView,
            // unchanged.
            GameHubView()
                .preferredColorScheme(.dark)
        }
    }
}
