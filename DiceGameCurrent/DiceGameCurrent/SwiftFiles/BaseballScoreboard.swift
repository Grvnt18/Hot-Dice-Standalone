import SceneKit
import UIKit

/// The scoreboard panel, as a plane on the pitch that can be repainted.
///
/// It used to be part of the floor texture, which is rendered once from the
/// innings count — so the grid and the outs pips were drawn empty and
/// nothing ever filled them. The board showed the inning numbers and no
/// game, for the whole game.
///
/// Shaped exactly like `BaseballColumns`, and mapping field fractions to
/// world space the same way, so the paint and the posts cannot disagree
/// about where anything on the pitch is.
enum BaseballScoreboard {

    static let containerName = "baseballScoreboard"

    /// The panel's texture, in pixels. Derived from the field canvas
    /// `DiceSceneEnvironment.surfaceTexture` uses (820x1100) times the
    /// panel's own fractions, so a pixel here is the same size as a pixel
    /// of the grass it sits on.
    private static let fieldPixels = CGSize(width: 820, height: 1100)

    /// Clear of the floor and of the floor title, both of which sit at
    /// +0.005, so nothing z-fights.
    private static let hover: Float = 0.010

    // MARK: Building

    /// Adds the panel once. Safe to call again — it replaces itself.
    static func install(in scene: SCNScene,
                        bounds: (x: ClosedRange<Float>, z: ClosedRange<Float>),
                        floorY: Float) {
        scene.rootNode.childNode(withName: containerName, recursively: false)?
            .removeFromParentNode()

        let metrics = BaseballField.boardMetrics
        let width = bounds.x.upperBound - bounds.x.lowerBound
        let depth = bounds.z.upperBound - bounds.z.lowerBound

        let plane = SCNPlane(width: CGFloat(width) * BaseballField.boardW,
                             height: CGFloat(depth) * metrics.height)
        let material = SCNMaterial()
        // Unlit, like the floor title: the panel is a painted sign and
        // should read the same under any lighting.
        material.lightingModel = .constant
        material.diffuse.wrapS = .clamp
        material.diffuse.wrapT = .clamp
        plane.materials = [material]

        let node = SCNNode(geometry: plane)
        node.name = containerName
        node.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)   // flat, facing up
        // The panel's CENTRE, from its top-left corner plus half its size.
        node.position = SCNVector3(
            bounds.x.lowerBound
                + Float(BaseballField.boardX + BaseballField.boardW / 2) * width,
            floorY + hover,
            bounds.z.lowerBound
                + Float(BaseballField.boardY + metrics.height / 2) * depth
        )
        // No physics body and no shadow: dice roll over the board, exactly
        // as they roll over the floor title.
        node.castsShadow = false

        scene.rootNode.addChildNode(node)
    }

    // MARK: Updating

    /// Repaints the panel for the game as it now stands.
    ///
    /// Called after every at-bat and every half-inning. The texture is
    /// about 345x210, so this is a fraction of re-rendering the 820x1100
    /// pitch — which is the other reason the panel has its own node.
    static func update(in scene: SCNScene, state: BaseballDiceState) {
        guard let node = scene.rootNode.childNode(withName: containerName,
                                                  recursively: false) else { return }

        let metrics = BaseballField.boardMetrics
        let size = CGSize(width: fieldPixels.width * BaseballField.boardW,
                          height: fieldPixels.height * metrics.height)

        node.geometry?.firstMaterial?.diffuse.contents =
            BaseballField.renderScoreboard(
                size: size,
                innings: state.innings,
                lineScore: state.lineScore,
                outs: state.outs,
                currentInning: state.inning
            )
    }
}
