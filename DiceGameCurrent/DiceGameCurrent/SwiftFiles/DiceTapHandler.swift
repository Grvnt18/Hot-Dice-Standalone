import SceneKit
import UIKit

/// Handles tap-to-select on the dice scene. Hit-tests the tap, walks up to
/// the tapped die's root node, confirms it's actually settled (a
/// still-tumbling die shouldn't be selectable — mirrors the game's own
/// rule that you can only bank a die once it's landed), then reports which
/// die was tapped.
///
/// It used to call `DiceTurnController.toggleSelection` itself, which was
/// its only tie to Rolls and the reason no other game could use it.
/// Generals needs exactly this hit-testing to choose which dice to keep,
/// so the handler now reports the die and lets the caller decide what a
/// tap means. Rolls passes the toggle it was making anyway.
final class DiceTapHandler: NSObject {

    private weak var sceneView: SCNView?
    private let rollController: DiceRollController
    private let requireSettled: Bool
    private let onDieTapped: (UUID) -> Void

    /// `requireSettled` is what Rolls needs and a keeping game cannot use.
    /// `settledDieIDs` holds only the dice of the *current* roll, and a
    /// reroll clears it — so in Generals, where the kept dice sit out the
    /// throw entirely, requiring it would leave a kept die untappable and
    /// the player unable to change their mind. A tray gates on the roll
    /// being over instead, which is the same rule stated over the whole
    /// table rather than over one throw.
    init(
        sceneView: SCNView,
        rollController: DiceRollController,
        requireSettled: Bool = true,
        onDieTapped: @escaping (UUID) -> Void
    ) {
        self.sceneView = sceneView
        self.rollController = rollController
        self.requireSettled = requireSettled
        self.onDieTapped = onDieTapped
        super.init()

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        sceneView.addGestureRecognizer(tapGesture)
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard let sceneView else { return }
        let location = gesture.location(in: sceneView)

        let hitResults = sceneView.hitTest(location, options: [
            .searchMode: SCNHitTestSearchMode.closest.rawValue
        ])

        guard let hit = hitResults.first,
              let dieID = dieID(for: hit.node) else { return }
        if requireSettled, !rollController.settledDieIDs.contains(dieID) { return }

        onDieTapped(dieID)
    }

    /// Node names are set to the die's UUID string in DicePoolSceneBuilder,
    /// but a tap can land on a child node (a face label, the selection
    /// glow) rather than the die's own root node, so walk up the parent
    /// chain until a named node is found.
    private func dieID(for node: SCNNode) -> UUID? {
        var current: SCNNode? = node
        while let candidate = current {
            if let name = candidate.name, let uuid = UUID(uuidString: name) {
                return uuid
            }
            current = candidate.parent
        }
        return nil
    }
}
