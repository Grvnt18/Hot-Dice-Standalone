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

    let onSessionCreated: (DiceTraySession) -> Void

    func makeUIView(context: Context) -> SCNView {
        let view = LayoutReportingSCNView()
        view.backgroundColor = .black
        view.antialiasingMode = .multisampling4X
        view.isPlaying = true
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
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
            d4Style: d4Style
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
