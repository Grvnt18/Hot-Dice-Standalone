import SceneKit
import UIKit

/// The scoreboard panel, as a plane on the pitch that can be repainted.
///
/// It used to be part of the floor texture, which is rendered once from the
/// innings count — so the grid and the outs pips were drawn empty and
/// nothing ever filled them. The board showed the inning numbers and no
/// game, for the whole game.
///
/// It does NOT share `BaseballColumns`' mapping, which it used to: the
/// posts stand on the floor mark and go through `BaseballField.Mark.frame`
/// to find it, while the board is a sign in a corner of the playfield and
/// is placed against the playfield's own edges. Two different jobs; the
/// board has nothing on the field to line up with.
enum BaseballScoreboard {

    static let containerName = "baseballScoreboard"

    /// The composition the board's fractions are measured against: the
    /// 820x1100 pitch `BaseballField.render` draws. Nothing renders that
    /// pitch onto a floor any more, but the board's own constants —
    /// `boardX`, `boardW`, `boardMetrics` — are still fractions of it, and
    /// `tools_baseball_field_verify.py` pins them there.
    private static let fieldPixels = CGSize(width: 820, height: 1100)

    /// The panel's own canvas, in pixels, and so its own shape.
    ///
    /// Everything the board draws — the grid, the row heights, the outs
    /// pips, the type — is laid out against this one canvas, so this
    /// ratio IS the board's proportion. 344 x 211 at today's fractions.
    static var panelPixels: CGSize {
        CGSize(width: fieldPixels.width * BaseballField.boardW,
               height: fieldPixels.height * BaseballField.boardMetrics.height)
    }

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

        let width = bounds.x.upperBound - bounds.x.lowerBound

        // The plane takes the PANEL's shape, not the playfield's.
        //
        // Its height used to be `depth * metrics.height` while its width
        // was `width * boardW` — two different axes of two different
        // things — so the board's proportion was the playfield's
        // proportion rather than its own. On a phone's tall tray that is
        // close enough to pass; on a near-square iPad playfield the same
        // texture arrived squashed about a third, which is a scoreboard
        // whose columns are no longer as wide as they are drawn. Taking
        // the depth from the panel's own pixels means it fills whatever
        // width it is given and can never stretch.
        let panel = panelPixels
        let boardWidth = CGFloat(width) * BaseballField.boardW
        let boardDepth = boardWidth * (panel.height / panel.width)

        let plane = SCNPlane(width: boardWidth, height: boardDepth)
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
        //
        // Both insets are fractions of the WIDTH now. boardY is a fraction
        // of the old composition's height, and read against the depth it
        // put the board further from the top edge on a tall tray than from
        // the left on any of them — an uneven margin in a corner, which is
        // the one place an uneven margin shows.
        node.position = SCNVector3(
            bounds.x.lowerBound
                + Float(BaseballField.boardX) * width + Float(boardWidth) / 2,
            floorY + hover,
            bounds.z.lowerBound
                + Float(BaseballField.boardY) * width + Float(boardDepth) / 2
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

        // The same canvas the plane took its shape from, so the texture
        // arrives at the proportion it is drawn at and lands on a plane of
        // that proportion — which is the whole of "fills rather than
        // stretches".
        node.geometry?.firstMaterial?.diffuse.contents =
            BaseballField.renderScoreboard(
                size: panelPixels,
                innings: state.innings,
                lineScore: state.lineScore,
                outs: state.outs,
                currentInning: state.inning
            )
    }
}
