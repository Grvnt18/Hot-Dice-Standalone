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

    /// As tall as the dice that bounce off it.
    ///
    /// It was 0.85, against dice normalised to 1.0 (and 1.5 for the one
    /// oversized die a round carries), so a post was the shortest solid
    /// thing on the table. 1.15 puts it between the two, which is what
    /// makes it read as standing up rather than lying on the floor.
    static let height: CGFloat = 1.15

    /// Where a team's waiting runners stand, as offsets inside the on-deck
    /// circle. Three posts in a tight triangle: the gaps between them are far
    /// narrower than a die, so the cluster behaves as one obstacle rather
    /// than a trap a die could wedge into.
    private static let poolOffsets: [CGPoint] = [
        CGPoint(x: -0.034, y: -0.014),
        CGPoint(x: 0.034, y: -0.014),
        CGPoint(x: 0.0, y: 0.024)
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

        // Mark's bases, not the pitch texture's.
        //
        // These were `BaseballField.first/second/third`, which are
        // fractions of the 820x1100 composition `render` draws — a
        // different coordinate space from the one the floor mark is drawn
        // in, and on a different sized canvas. So a post stood where that
        // old composition put a base, which after the field was redrawn
        // was out on the grass: a runner on second was nowhere near
        // second. Index order is first, second, third, matching
        // `Diamond.occupied`, so a single puts a post on first and a
        // double puts one on second.
        for (index, base) in [BaseballField.Mark.first,
                              BaseballField.Mark.second,
                              BaseballField.Mark.third].enumerated() {
            container.addChildNode(
                column(named: "base\(index)",
                       at: base, bounds: bounds, floorY: floorY)
            )
        }

        for (seat, x) in BaseballField.Mark.onDeckX.enumerated() {
            for (slot, offset) in poolOffsets.enumerated() {
                let spot = CGPoint(x: x + offset.x,
                                   y: BaseballField.Mark.onDeckY + offset.y)
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
        // Casts a real shadow, which is most of what says a post has
        // height under a camera that sees almost nothing but top faces.
        // This was false, so the posts were the only solid objects on a
        // table where every die throws one — the key light is already
        // `.deferred` at 0.45 alpha, so this costs nothing to turn on and
        // puts the posts under the same light as the dice.
        node.castsShadow = true

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
    /// Deepened with the extra height: a taller post shows more side, so
    /// the step between the lit cap and the shaded wall has more room to
    /// do its job.
    private static let capLift: CGFloat = 0.34
    private static let sideDrop: CGFloat = 0.32

    /// Maps a point in the floor mark's composition onto the playfield.
    ///
    /// Through `BaseballField.Mark.frame`, which is the same fit
    /// `renderMarkings` performs on the canvas it draws into — ONE scale
    /// for both axes, centred. The old version read `x` as a fraction of
    /// the width and `y` as a fraction of the DEPTH, which is right only
    /// while the drawing stretches to fill the floor, and it does not: it
    /// is fitted, so a post placed that way drifts further from its base
    /// the further the playfield is from the composition's own shape.
    private static func world(_ spot: CGPoint,
                              bounds: (x: ClosedRange<Float>, z: ClosedRange<Float>),
                              floorY: Float) -> SCNVector3 {
        let width = CGFloat(bounds.x.upperBound - bounds.x.lowerBound)
        let depth = CGFloat(bounds.z.upperBound - bounds.z.lowerBound)
        let frame = BaseballField.Mark.frame(width: width, depth: depth)
        return SCNVector3(
            bounds.x.lowerBound + Float(frame.originX + spot.x * frame.scale),
            floorY,
            bounds.z.lowerBound + Float(frame.originZ + spot.y * frame.scale)
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
