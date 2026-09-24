import SceneKit

/// Gives each die in a new roll its initial random push and spin, then
/// hands off entirely to gravity + collisions to do the actual tumbling.
/// This is a one-time "kick" (an impulse), not a sustained force —
/// matching how an actual toss works: you flick it once, physics does
/// the rest.
enum DiceRollImpulse {

    // Explicit ask this round: 2.5-3.5x more motion, on top of the just-
    // reset (correctly-scaled) baseline. Going 3x on linear and torque,
    // since those scale linearly with "distance traveled" / "rotation
    // achieved" — straightforward to reason about. Upward gets a more
    // modest 1.8x rather than the same 3x: peak bounce height scales with
    // the SQUARE of upward velocity (h = v²/2g), so a full 3x there would
    // send dice roughly 9x higher, needing an unreasonably tall wall to
    // contain. Wall height and floor thickness both increased below to
    // match (see DiePhysicsFactory).
    private static let minLinearImpulse: Float = 9.0
    private static let maxLinearImpulse: Float = 18.0
    private static let minUpwardImpulse: Float = 4.5
    private static let maxUpwardImpulse: Float = 7.2
    private static let minTorqueMagnitude: Float = 1.8
    private static let maxTorqueMagnitude: Float = 4.2

    /// How much harder a small pool is thrown.
    ///
    /// A single die gets the same kick as a pool of fifteen, but with
    /// nothing to collide with it just slides and stops — the throw reads
    /// as limp. So pools of four or fewer are scaled up: +25% at four
    /// rising to +100% at one.
    ///
    ///     dice   1      2      3      4      5+
    ///     scale  2.00x  1.75x  1.50x  1.25x  1.00x
    ///
    /// `DiceRollController.timeBudget(forDiceCount:)` applies the SAME
    /// number to the roll's time budget. That is not decoration: a one-die
    /// roll is force-settled at 1.0s today, and throwing it twice as hard
    /// without extending that would end every small roll in an abrupt
    /// freeze. Energy decays geometrically off the walls (restitution
    /// 0.7), so doubling the launch speed costs about ln(2)/ln(1/0.7) —
    /// roughly 1.9 — extra bounce cycles before the settle threshold. One
    /// function, read by both, so the throw and the time it is given can
    /// never disagree about how hard it was thrown.
    static func smallPoolBoost(forDiceCount count: Int) -> Double {
        guard count >= 1, count <= 4 else { return 1.0 }
        return 1.0 + 0.25 * Double(5 - count)
    }

    /// Call this for exactly the same dice being handed to
    /// DiceRollController.startRoll, right alongside that call. Un-freezes
    /// any die left kinematic from a previous settle, then tosses it with
    /// a random push and spin.
    static func launch(dice: [(id: UUID, node: SCNNode, sides: Int)]) {
        let boost = Float(smallPoolBoost(forDiceCount: dice.count))
        let upwardBoost = sqrt(boost)

        for die in dice {
            let node = die.node

            guard let body = node.physicsBody else { continue }
            body.type = .dynamic
            body.velocity = SCNVector3Zero
            body.angularVelocity = SCNVector4(0, 1, 0, 0)

            let direction = randomHorizontalDirection()
            let linearMagnitude = Float.random(in: minLinearImpulse...maxLinearImpulse) * boost
            // Upward takes the SQUARE ROOT of the boost, for the same
            // reason the 3x motion increase above gave it only 1.8x: peak
            // height goes as v²/2g, so doubling it would send a die four
            // times higher. The square root makes the vertical excursion
            // grow in step with the boost rather than with its square.
            let upward = Float.random(in: minUpwardImpulse...maxUpwardImpulse) * upwardBoost

            let impulse = SCNVector3(
                direction.x * linearMagnitude,
                upward,
                direction.z * linearMagnitude
            )
            body.applyForce(impulse, asImpulse: true)

            let axis = randomTumbleAxis()
            let torqueMagnitude = Float.random(in: minTorqueMagnitude...maxTorqueMagnitude) * boost
            let torque = SCNVector4(axis.x, axis.y, axis.z, torqueMagnitude)
            body.applyTorque(torque, asImpulse: true)
        }
    }

    private static func randomHorizontalDirection() -> SCNVector3 {
        let angle = Float.random(in: 0..<(2 * .pi))
        return SCNVector3(cos(angle), 0, sin(angle))
    }

    /// Random spin axis, deliberately biased toward horizontal (X/Z) over
    /// vertical (Y). A top-down camera makes vertical-axis spin (a die
    /// spinning in place like a top) barely register visually — the same
    /// colored square just rotates in the screen plane — while horizontal
    /// tumbling (the die actually flipping/rolling end over end) is what
    /// reads as lively motion from directly overhead. Once a die settles
    /// flat on the floor, continuing to spin around its own vertical axis
    /// also takes very little energy to sustain compared to genuine
    /// tumbling, so without this bias, physics naturally drifts toward
    /// exactly the "spinning in place" look this is meant to avoid.
    private static func randomTumbleAxis() -> SCNVector3 {
        let horizontalAngle = Float.random(in: 0..<(2 * .pi))
        let x = cos(horizontalAngle)
        let z = sin(horizontalAngle)
        // Small residual Y component so spin isn't perfectly flat/robotic,
        // just heavily de-emphasized relative to X/Z.
        let y = Float.random(in: -0.15...0.15)
        let length = sqrt(x * x + y * y + z * z)
        return SCNVector3(x / length, y / length, z / length)
    }
}
