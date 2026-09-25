import SceneKit

// MARK: - Die physics

enum DiePhysicsFactory {

    /// Attaches a dynamic physics body to a die node, using a convex hull
    /// shape built directly from the die's own mesh. Dice are naturally
    /// convex (no dents or holes), so a convex hull shape is both exact —
    /// not an approximation — and cheap to simulate, which is a nice
    /// property specific to dice.
    ///
    /// Tuning notes — reset from first principles this round, not
    /// incrementally adjusted from the previous values:
    ///
    /// mass was 0.01 (very light) through several rounds of "increase the
    /// impulse more" requests — each round multiplied an already-large
    /// impulse number without re-deriving velocity from mass (Δv =
    /// impulse/mass), and with mass this small, that compounded into
    /// velocities of 500-900 units/sec — enough to cross the entire
    /// playfield in ~20 milliseconds. At that scale the physics engine
    /// almost certainly can't resolve collisions coherently between
    /// physics steps, which would look exactly like "stuck, minimal
    /// motion" rather than "too fast" — not a tuning problem, a scale
    /// problem. Raising mass to 1.0 (matching normal physics-engine
    /// convention) makes the impulse-to-velocity relationship intuitive
    /// again and far less error-prone going forward — see
    /// DiceRollImpulse for the impulse values this pairs with.
    /// - restitution kept high (0.7) for real, visible bounce.
    /// - friction/damping are dimensionless ratios, not mass-dependent,
    ///   so these didn't need retuning for the mass change.
    static func addPhysicsBody(to node: SCNNode) {
        guard let geometry = node.geometry else { return }

        // node.scale carries the per-shape size normalization baked in by
        // DieMeshLibrary — passing it as the shape's .scale option keeps
        // the collision hull matching the corrected visual size rather
        // than the raw (mismatched) mesh dimensions.
        let shape = SCNPhysicsShape(
            geometry: geometry,
            options: [
                SCNPhysicsShape.Option.type: SCNPhysicsShape.ShapeType.convexHull,
                SCNPhysicsShape.Option.scale: NSValue(scnVector3: node.scale)
            ]
        )

        let body = SCNPhysicsBody(type: .dynamic, shape: shape)
        body.mass = 1.0
        body.restitution = 0.7
        body.friction = 0.15
        body.rollingFriction = 0.04
        body.damping = 0.08
        body.angularDamping = 0.1
        // Contact reporting is opt-in and separate from collision
        // response: dice already bounced correctly with none of this set,
        // but SCNPhysicsContactDelegate received nothing. categoryBitMask
        // identifies what this body IS; contactTestBitMask declares what
        // it wants to be TOLD about.
        body.categoryBitMask = DicePhysicsCategory.die
        body.collisionBitMask = DicePhysicsCategory.die | DicePhysicsCategory.playfield
        body.contactTestBitMask = DicePhysicsCategory.die | DicePhysicsCategory.playfield

        node.physicsBody = body
    }
}

// MARK: - Playfield container physics

/// Builds the invisible static colliders (floor + four walls) that keep
/// rolling dice contained within the middle 70% play area rather than
/// letting them tumble off into empty space. These carry no visible
/// geometry — physics only, nothing to render — so they're free to draw.
///
/// Default wallHeight (500.0) — deliberately absurd, and that's the
/// point. This collider is invisible, so there's no visual cost to making
/// it tall enough that no bounce, however energetic, could ever clear it.
/// Picking an arbitrary huge number removes the need to re-derive a
/// "sufficient" height every time impulse or gravity is retuned. The
/// visible wall rendered in DiceSceneEnvironment.addWalls is sized
/// separately and much shorter, to actually look like a dice-tray rim.
enum DicePlayfieldPhysics {

    /// bounds should come from PlayfieldLayout.compute(...) — the same
    /// bounds passed to the camera, floor surface, and spawn pattern, so
    /// every piece of the scene agrees on the playfield's actual size.
    static func makeContainer(
        bounds: (x: ClosedRange<Float>, z: ClosedRange<Float>),
        floorY: Float,
        wallHeight: Float = 500.0,
        ceilingHeight: Float = PlayfieldVerticalBounds.ceilingHeight
    ) -> SCNNode {
        let container = SCNNode()
        container.name = "playfieldContainer"

        let width = bounds.x.upperBound - bounds.x.lowerBound
        let depth = bounds.z.upperBound - bounds.z.lowerBound
        let centerX = (bounds.x.upperBound + bounds.x.lowerBound) / 2
        let centerZ = (bounds.z.upperBound + bounds.z.lowerBound) / 2

        // Floor thickness increased again (0.5 -> 0.7) alongside this
        // round's higher linear impulse (max velocity now 18 units/sec at
        // mass 1.0) — verified this keeps a healthy ~4.7x safety margin
        // against tunneling at the new speed, consistent with the margin
        // the previous thickness gave at the previous speed.
        container.addChildNode(
            staticCollider(
                boxSize: SCNVector3(width, 0.7, depth),
                position: SCNVector3(centerX, floorY, centerZ)
            )
        )

        // Ceiling — same thickness/restitution treatment as the floor.
        // Originally added purely so a die could never climb high enough
        // to close the distance to the top-down camera and vanish through
        // its near clipping plane; now deliberately kept much LOWER (see
        // PlayfieldVerticalBounds.ceilingHeight for the full derivation,
        // including why it can't go arbitrarily low) so it also cuts
        // sharply into how much vertical room a die has to gain the height
        // a stack would need — DiceRollController's resolveStacking is
        // still what actually guarantees no stack survives a roll.
        container.addChildNode(
            staticCollider(
                boxSize: SCNVector3(width, 0.7, depth),
                position: SCNVector3(centerX, floorY + ceilingHeight, centerZ)
            )
        )

        // Four walls, one per edge. Thickness is NOT arbitrary — it was
        // 0.1, and that was a live escape bug.
        //
        // A body can tunnel straight through a collider if it moves
        // further in one physics step than the collider is thick. At
        // timeStep 1/120, a 0.1-thick wall is only safe up to 12 units/s
        // — but max roll impulse is 18.0 at mass 1.0, so dice at full
        // throw speed were already fast enough to pass through the walls
        // entirely. 1.0 thick raises the safe ceiling to 120 units/s,
        // well clear of anything the game can produce.
        //
        // Each wall is pushed OUTWARD by half its thickness so the inner
        // face still sits exactly on the bounds — thickening in place
        // would have silently shrunk the play area by 0.5 per side.
        //
        // Doubled again, 1.0 -> 2.0, when the throw doubled
        // (DiceRollImpulse.motionBoost). The worst horizontal speed the
        // game can now produce is 72 u/s — an 18.0 impulse doubled, and
        // boosted again for a single-die pool — against a 1.0-thick
        // wall's 120 u/s limit. That is a 1.7x margin, and this project
        // holds colliders to 2x; at 2.0 thick the limit is 240 u/s and
        // the margin is 3.3x.
        let wallThickness: Float = 2.0
        // Offset outward so the collider's INNER face lands exactly on the
        // visible rim's inner face, not on the nominal bounds. The
        // thickness is a tunneling-safety requirement (see above) and is
        // kept entirely behind the wood.
        let halfT = PlayfieldRim.colliderCentreOffset(thickness: wallThickness)
        // Extend the side walls' length so they still meet the end walls
        // at the corners after everything moves outward; otherwise
        // thickening opens a gap at each corner for a die to squeeze out.
        let sideDepth = depth + wallThickness * 2
        let endWidth = width + wallThickness * 2

        container.addChildNode(staticCollider( // -X wall
            boxSize: SCNVector3(wallThickness, wallHeight, sideDepth),
            position: SCNVector3(bounds.x.lowerBound - halfT, floorY + wallHeight / 2, centerZ)
        ))
        container.addChildNode(staticCollider( // +X wall
            boxSize: SCNVector3(wallThickness, wallHeight, sideDepth),
            position: SCNVector3(bounds.x.upperBound + halfT, floorY + wallHeight / 2, centerZ)
        ))
        container.addChildNode(staticCollider( // -Z wall
            boxSize: SCNVector3(endWidth, wallHeight, wallThickness),
            position: SCNVector3(centerX, floorY + wallHeight / 2, bounds.z.lowerBound - halfT)
        ))
        container.addChildNode(staticCollider( // +Z wall
            boxSize: SCNVector3(endWidth, wallHeight, wallThickness),
            position: SCNVector3(centerX, floorY + wallHeight / 2, bounds.z.upperBound + halfT)
        ))

        return container
    }

    private static func staticCollider(boxSize: SCNVector3, position: SCNVector3) -> SCNNode {
        let node = SCNNode() // no geometry — invisible, physics-only
        node.position = position

        let box = SCNBox(
            width: CGFloat(boxSize.x),
            height: CGFloat(boxSize.y),
            length: CGFloat(boxSize.z),
            chamferRadius: 0
        )
        let shape = SCNPhysicsShape(geometry: box, options: nil)
        let body = SCNPhysicsBody(type: .static, shape: shape)
        // Explicitly matched to the die's own restitution (0.7) — left
        // unset before, meaning floor/wall bounces were governed by
        // whatever SceneKit's default happens to be rather than something
        // actually tuned, which could silently damp a bounce regardless
        // of how bouncy the die itself was configured to be.
        body.restitution = 0.7
        body.categoryBitMask = DicePhysicsCategory.playfield
        body.collisionBitMask = DicePhysicsCategory.die
        // Only dice-vs-surface contacts are interesting; walls never move.
        body.contactTestBitMask = DicePhysicsCategory.die
        node.physicsBody = body

        return node
    }
}

// MARK: - Physics world tuning

enum DicePhysicsWorldConfigurator {

    /// Standard SceneKit gravity (-9.8, matching real-world meters) is
    /// tuned for meter-scale objects — applied to our normalized ~1-unit
    /// dice, it reads as unnaturally hard/fast drops and increases the
    /// floor-tunneling risk from the impact speed. Softened here to suit
    /// this world's actual scale.
    static func configure(_ physicsWorld: SCNPhysicsWorld) {
        // Tuned against the known ~1-unit normalized die scale (see
        // DieMeshLibrary) and a ~1-unit restHeight (see
        // DicePoolLifecycleController), targeting a quick ~0.4–0.5s
        // initial drop so most of the roll budget (1-5.0s, scaled by dice
        // count — see SettleTuning in DiceRollController) is spent on
        // actual tumbling/collision, not freefall. This pairs with — not
        // replaces — the hard cap DiceRollController already enforces via
        // force-settle: this tuning aims for a roll that naturally
        // finishes in-window most of the time, while the cap guarantees
        // it never overruns even when physics doesn't cooperate.
        // Reduced from -8.0 as a companion to this round's "more energy
        // without more raw impulse" pivot — softer gravity means the
        // upward component of each roll's impulse carries dice higher and
        // for longer before gravity pulls them back down, giving more
        // real opportunity for mid-air tumbling. This doesn't raise peak
        // velocity the way more impulse would, so it's a safer lever
        // against the floor-tunneling ceiling than pushing impulse
        // further was.
        physicsWorld.gravity = SCNVector3(0, -5.5, 0)

        // Reduced further (from 1/90) alongside this round's large
        // impulse increase — a smaller timestep means physics re-checks
        // collisions more often per second, which matters more at high
        // velocity since a die covers more distance between checks.
        // Costs more CPU per second of simulation, but these rolls only
        // run for a few seconds at a time.
        physicsWorld.timeStep = 1.0 / 120.0
    }
}
