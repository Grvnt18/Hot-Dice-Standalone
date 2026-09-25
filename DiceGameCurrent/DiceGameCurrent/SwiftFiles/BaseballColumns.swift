import SceneKit
import UIKit

/// The runner columns: immovable posts on the bases and in the two pools.
///
/// They are real obstacles, not paint. Each carries a `.static` physics body,
/// so a die that reaches one bounces off it and the column does not move —
/// which is the whole point of putting the runners on the rolling surface
/// rather than in a side panel.
///
/// Restitution is matched to the die's own 0.7, the same explicit match
/// `DiePhysicsFactory.staticCollider` makes and for the same reason: left
/// unset, a bounce is governed by whatever SceneKit defaults to rather than
/// anything tuned.
enum BaseballColumns {

    /// Everything lives under one node so the whole set can be found, updated
    /// or removed without walking the scene graph.
    static let containerName = "baseballColumns"

    static let radius: CGFloat = 0.26
    static let height: CGFloat = 0.85

    /// Where a team's waiting runners stand, as offsets inside the on-deck
    /// circle. Three posts in a tight triangle: the gaps between them are far
    /// narrower than a die, so the cluster behaves as one obstacle rather
    /// than a trap a die could wedge into.
    private static let poolOffsets: [CGPoint] = [
        CGPoint(x: -0.030, y: -0.012),
        CGPoint(x: 0.030, y: -0.012),
        CGPoint(x: 0.0, y: 0.020)
    ]

    // MARK: Building

    /// Adds the full set once. Safe to call again — it replaces itself.
    static func install(in scene: SCNScene,
                        bounds: (x: ClosedRange<Float>, z: ClosedRange<Float>),
                        floorY: Float) {
        scene.rootNode.childNode(withName: containerName, recursively: false)?
            .removeFromParentNode()

        let container = SCNNode()
        container.name = containerName

        for (index, base) in [BaseballField.first,
                              BaseballField.second,
                              BaseballField.third].enumerated() {
            container.addChildNode(
                column(named: "base\(index)",
                       at: base, bounds: bounds, floorY: floorY)
            )
        }

        for (seat, x) in BaseballField.onDeckX.enumerated() {
            for (slot, offset) in poolOffsets.enumerated() {
                let spot = CGPoint(x: x + offset.x,
                                   y: BaseballField.onDeckY + offset.y)
                container.addChildNode(
                    column(named: "pool\(seat)_\(slot)",
                           at: spot, bounds: bounds, floorY: floorY)
                )
            }
        }

        scene.rootNode.addChildNode(container)
    }

    private static func column(named name: String,
                               at spot: CGPoint,
                               bounds: (x: ClosedRange<Float>, z: ClosedRange<Float>),
                               floorY: Float) -> SCNNode {
        let cylinder = SCNCylinder(radius: radius, height: height)
        // THREE materials, not one: SCNCylinder takes side, top and bottom
        // in that order, and giving them one shade is what made a post read
        // as a flat disc.
        //
        // The camera looks straight down, so the top cap is nearly all you
        // see of a post and the sides appear only as a rim around it. One
        // colour across both leaves nothing for the eye to read as height.
        // A lit top over darker sides is the whole of what says "this
        // stands up" from directly above — the same trick the faceted
        // floors use, where the shape comes from tone rather than from
        // geometry the camera cannot see.
        cylinder.materials = [sideMaterial(), topMaterial(), sideMaterial()]

        let node = SCNNode(geometry: cylinder)
        node.name = name
        node.position = world(spot, bounds: bounds,
                              floorY: floorY + Float(height) / 2)
        node.castsShadow = false

        let body = SCNPhysicsBody(type: .static,
                                  shape: SCNPhysicsShape(geometry: cylinder,
                                                         options: nil))
        body.restitution = 0.7
        node.physicsBody = body
        return node
    }

    /// The post's curved side: the base colour, darkened.
    private static func sideMaterial() -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .lambert     // matches the low-poly surfaces
        return material
    }

    /// The post's top cap: the base colour, lifted.
    ///
    /// Named apart from the side so `update` can tint the two differently
    /// without either call site having to remember which slot is which.
    private static func topMaterial() -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .lambert
        return material
    }

    /// How far the cap is lifted and the side dropped from the base colour.
    ///
    /// Enough to read as a lit top on a shaded post, not so much that a
    /// post stops looking like one object.
    private static let capLift: CGFloat = 0.30
    private static let sideDrop: CGFloat = 0.28

    /// Maps a field fraction onto the playfield.
    ///
    /// `x` is a fraction of the width and `y` a fraction of the DEPTH — the
    /// same split the texture uses, because the floor image and these posts
    /// have to agree about where second base is.
    private static func world(_ spot: CGPoint,
                              bounds: (x: ClosedRange<Float>, z: ClosedRange<Float>),
                              floorY: Float) -> SCNVector3 {
        let width = bounds.x.upperBound - bounds.x.lowerBound
        let depth = bounds.z.upperBound - bounds.z.lowerBound
        return SCNVector3(
            bounds.x.lowerBound + Float(spot.x) * width,
            floorY,
            bounds.z.lowerBound + Float(spot.y) * depth
        )
    }

    // MARK: Updating

    /// Shows the posts that should be standing, and colours them.
    ///
    /// The batting side's runners are the player's chosen table colour; the
    /// other side's are black. A team's pool holds whatever is not on base,
    /// so three posts between the diamond and the pool at all times — the
    /// runners are conserved, which is what makes the board readable.
    /// Tints a post: a lit cap over darker sides.
    ///
    /// Walks the material array rather than `firstMaterial`, which would
    /// paint the side and leave the cap — the slot order is side, top,
    /// bottom.
    private static func paint(_ node: SCNNode?, colour: UIColor) {
        guard let materials = node?.geometry?.materials, materials.count >= 3 else {
            node?.geometry?.firstMaterial?.diffuse.contents = colour
            return
        }
        materials[0].diffuse.contents = colour.darkened(by: sideDrop)
        materials[1].diffuse.contents = colour.lightened(by: capLift)
        materials[2].diffuse.contents = colour.darkened(by: sideDrop)
    }

    static func update(in scene: SCNScene,
                       diamond: Diamond,
                       battingSeat: Int,
                       battingColour: UIColor,
                       waitingColour: UIColor) {
        guard let container = scene.rootNode.childNode(withName: containerName,
                                                       recursively: false) else { return }

        for (index, occupied) in diamond.occupied.enumerated() {
            let node = container.childNode(withName: "base\(index)", recursively: false)
            node?.isHidden = !occupied
            paint(node, colour: battingColour)
        }

        let onBase = diamond.runnerCount
        for seat in 0..<2 {
            // Only the batting side spends runners; the other keeps all three.
            let standing = seat == battingSeat ? max(0, 3 - onBase) : 3
            let colour = seat == battingSeat ? battingColour : waitingColour
            for slot in 0..<poolOffsets.count {
                let node = container.childNode(withName: "pool\(seat)_\(slot)",
                                               recursively: false)
                node?.isHidden = slot >= standing
                paint(node, colour: colour)
            }
        }
    }
}
