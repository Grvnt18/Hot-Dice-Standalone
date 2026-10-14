import SwiftUI
import SceneKit

// MARK: - Scene host

/// Hosts a `DiceTraySession` — the shared scene view for every game that
/// rolls a tray of dice and reads them.
///
/// Separate from Rolls' `DiceSceneView` rather than generic over the
/// session type, because the two wire up genuinely different things —
/// Rolls needs a turn controller and tap handling, a tray needs neither.
///
/// What they do share is the view itself and the assembly timing, and that
/// is the part worth getting identical. The view now comes from
/// `LayoutReportingSCNView.makeConfigured()`, one copy for both. The timing
/// is still spelled twice because each calls a different assembler:
/// assembly waits until the view has real bounds, which
/// `LayoutReportingSCNView` reports rather than leaving to chance. See the
/// long note on `DiceSceneView.assembleIfReady` for what goes wrong
/// otherwise — a blank black playfield until something unrelated forces a
/// redraw.
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
    /// `.steel`. Baseball Dice took `.ballpark()` until its painted pitch
    /// was replaced by the house arena, so `.ballpark()` now has no
    /// callers — kept rather than deleted, because removing it also means
    /// BaseballField.swift, the texture path that draws it, and two tools,
    /// and that is a decision rather than a tidy-up.
    var arenaStyle: ArenaStyle = .house

    let onSessionCreated: (DiceTraySession) -> Void

    func makeUIView(context: Context) -> SCNView {
        LayoutReportingSCNView.makeConfigured()
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
        guard uiView.bounds.width > 0, uiView.bounds.height > 0 else { return }

        let aspect = PlayfieldLayout.aspect(of: uiView.bounds.size)

        // The arena is built for a SHAPE, not a size — see
        // PlayfieldLayout.needsRebuild. A view that changed shape since
        // assembly is showing walls and a camera for the shape it used to
        // be, which on a foldable happens every time the device opens.
        //
        // Of the eight screens on this path only Free Roll ever crosses
        // the threshold, and Free Roll is a sandbox: re-dealing its tray
        // costs nothing. The seven that would lose a scored turn have a
        // square playfield at every supported size and so a constant
        // aspect of 1.0 — asserted in tools_bandlayout_verify.py, because
        // "only Free Roll reaches it" is a claim about five header
        // fractions and two device tables, not something to assume.
        if coordinator.hasStartedAssembly,
           PlayfieldLayout.needsRebuild(assembled: coordinator.assembledAspect,
                                        now: aspect) {
            coordinator.hasStartedAssembly = false
        }

        guard !coordinator.hasStartedAssembly else { return }

        coordinator.hasStartedAssembly = true
        coordinator.assembledAspect = aspect

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

        /// The aspect ratio the arena in this view was built for. On the
        /// Coordinator because that is what survives a SwiftUI update.
        var assembledAspect: Float?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
}
