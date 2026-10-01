import SwiftUI
import SceneKit

// MARK: - Scene host

/// Hosts a `DiceTraySession` — the shared scene view for every game that
/// rolls a tray of dice and reads them.
///
/// Separate from Rolls' `DiceSceneView` rather than generic over the
/// session type, because the two wire up genuinely different things —
/// Rolls needs a turn controller and tap handling, a tray needs neither. What they do share is the assembly
/// timing, and that is the part worth getting identical: assembly is
/// deferred until the view has real bounds, and `LayoutReportingSCNView`
/// reports when that happens rather than leaving it to chance. See the long
/// note on `DiceSceneView.assembleIfReady` for what goes wrong otherwise —
/// a blank black playfield until something unrelated forces a redraw.
struct DiceTraySceneView: UIViewRepresentable {
    @Binding var session: DiceTraySession?

    /// Made once, at assembly. Callers that generate dice freshly per call
    /// (Free Roll's `makeDice()` reshuffles colourways every time) must not
    /// hand the result in directly, or every body evaluation would build a
    /// new array and discard all but the first — so this takes a factory.
    let makeInitialDice: () -> [Die]

    var d4Style: DieFaceLabels.D4LabelStyle = .topRead

    /// What the playfield floor says under the dice. Each game passes its
    /// own, so the board no longer claims to be Rolls.
    let floorTitle: String

    /// How the playfield is dressed. Defaults to the house style, so a
    /// game that says nothing keeps the wood and the player's table
    /// colour — which is what every game but two now does. Rollbots passes
    /// `.steel` and Baseball Dice `.ballpark()`.
    var arenaStyle: ArenaStyle = .house

    let onSessionCreated: (DiceTraySession) -> Void

    func makeUIView(context: Context) -> SCNView {
        let view = LayoutReportingSCNView()
        // Never black. If any sliver of backdrop is ever visible — an aspect
        // ratio the overscanned floor somehow does not cover, a frame during
        // rotation, the instant before assembly finishes — it should read as
        // part of the field rather than as a hole punched in it.
        view.backgroundColor = SmokeFloor.backdrop(from: AppTheme.shared.floorBaseColor)
        // Off, for the pixel-art edge and because the Simulator aborts on
        // any multisampling — see SceneAntialiasing.
        view.antialiasingMode = SceneAntialiasing.mode
        view.isPlaying = true
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        // Re-set on every update, not only at creation, because the backdrop
        // follows the player's table colour. A value assigned once in
        // makeUIView would keep the colour the app launched with and show
        // through as the wrong shade after a swatch change.
        uiView.backgroundColor = SmokeFloor.backdrop(from: AppTheme.shared.floorBaseColor)
        (uiView as? LayoutReportingSCNView)?.onLayout = { view in
            assembleIfReady(view, coordinator: context.coordinator)
        }
        assembleIfReady(uiView, coordinator: context.coordinator)
    }

    private func assembleIfReady(_ uiView: SCNView, coordinator: Coordinator) {
        guard !coordinator.hasStartedAssembly else { return }
        guard uiView.bounds.width > 0, uiView.bounds.height > 0 else { return }

        coordinator.hasStartedAssembly = true

        let newSession = DiceSceneAssembler.assembleTray(
            into: uiView,
            pool: makeInitialDice(),
            d4Style: d4Style,
            title: floorTitle,
            style: arenaStyle
        )
        DispatchQueue.main.async {
            session = newSession
            onSessionCreated(newSession)
        }
    }

    final class Coordinator {
        var hasStartedAssembly = false
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
}
