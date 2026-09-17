import SceneKit
import UIKit

/// Handles tap-to-select on the dice scene. Hit-tests the tap, walks up to
/// the tapped die's root node, confirms it's actually settled (a
/// still-tumbling die shouldn't be selectable — mirrors the game's own
/// rule that you can only bank a die once it's landed), then toggles
/// selection through the turn controller, which drives the glow highlight
/// automatically.
final class DiceTapHandler: NSObject {

    private weak var sceneView: SCNView?
    private let turnController: DiceTurnController
    private let rollController: DiceRollController

    init(sceneView: SCNView, turnController: DiceTurnController, rollController: DiceRollController) {
        self.sceneView = sceneView
        self.turnController = turnController
        self.rollController = rollController
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
              let dieID = dieID(for: hit.node),
              rollController.settledDieIDs.contains(dieID) else {
            return
        }

        turnController.toggleSelection(dieID: dieID)
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
