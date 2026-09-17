import SceneKit
import QuartzCore

/// Physics category bits. Contacts are only reported for pairs whose
/// contactTestBitMask overlaps the other's categoryBitMask — collision
/// *response* works without these, which is why dice already bounced
/// correctly with none of this configured, but no didBegin callbacks were
/// ever delivered.
enum DicePhysicsCategory {
    static let die: Int       = 1 << 0
    static let playfield: Int = 1 << 1
}

/// Turns physics contacts into impact sounds.
///
/// The hard part here isn't playing sounds, it's *not* playing most of
/// them. Fifteen dice at restitution 0.7 generate far more contacts than
/// there are distinct audible events — a settling die produces a rapid
/// cluster of micro-contacts as it rocks to rest. Played back untouched,
/// that's a machine-gun buzz. Three gates handle it: a velocity floor, a
/// per-die cooldown, and a global rate cap.
final class DiceContactAudio: NSObject, SCNPhysicsContactDelegate {

    /// Impacts slower than this are inaudible in reality and are the bulk
    /// of the settling-jitter contacts. Dropped entirely.
    private let minVelocity: Float = 0.35

    /// Velocity mapped to the top of the loudness/tier range. Impacts at
    /// or above this play at full gain in the hard tier.
    private let maxVelocity: Float = 9.0

    /// Minimum gap between sounds *from the same die*. Without this, one
    /// die rocking to rest fires many times in a few frames.
    private let perDieCooldown: TimeInterval = 0.06

    /// Minimum gap between *any* two impact sounds. Backstop for the case
    /// where many different dice contact in the same instant — they'd each
    /// pass their own cooldown but collectively sound like a burst of
    /// static.
    private let globalCooldown: TimeInterval = 0.012

    /// Half-width of the playfield in X, used to map a die's world
    /// position to stereo pan. Set by the assembler.
    var playfieldHalfWidth: Float = 5

    private var lastPlayedPerDie: [ObjectIdentifier: TimeInterval] = [:]
    private var lastPlayedGlobal: TimeInterval = 0

    func physicsWorld(_ world: SCNPhysicsWorld, didBegin contact: SCNPhysicsContact) {
        let now = CACurrentMediaTime()
        guard now - lastPlayedGlobal >= globalCooldown else { return }

        // SCNPhysicsContact exposes the nodes and the contact normal but
        // not an impact impulse, so derive the closing speed ourselves:
        // the relative velocity of the two bodies projected onto the
        // contact normal. That projection matters — a die skidding along
        // the floor has high velocity but near-zero velocity *into* the
        // surface, and shouldn't sound like an impact.
        let vA = contact.nodeA.physicsBody?.velocity ?? SCNVector3Zero
        let vB = contact.nodeB.physicsBody?.velocity ?? SCNVector3Zero
        let rel = SCNVector3(vA.x - vB.x, vA.y - vB.y, vA.z - vB.z)
        let n = contact.contactNormal
        let closing = abs(rel.x * n.x + rel.y * n.y + rel.z * n.z)

        guard closing >= minVelocity else { return }

        // Attribute the hit to whichever node is a die (a die-vs-wall
        // contact has only one), so the cooldown tracks the right object.
        let dieNode = isDie(contact.nodeA) ? contact.nodeA
                    : isDie(contact.nodeB) ? contact.nodeB
                    : nil
        guard let dieNode else { return }

        let key = ObjectIdentifier(dieNode)
        if let last = lastPlayedPerDie[key], now - last < perDieCooldown { return }
        lastPlayedPerDie[key] = now
        lastPlayedGlobal = now

        // Normalized 0...1 impact strength.
        let t = min(1, max(0, (closing - minVelocity) / (maxVelocity - minVelocity)))

        let tier: ImpactTier = t < 0.33 ? .soft : (t < 0.68 ? .medium : .hard)

        // Gain curve within the tier. Squaring keeps quiet hits genuinely
        // quiet — linear gain makes light taps sit too close in level to
        // solid hits, which flattens the sense of impact force.
        let gain = 0.35 + 0.65 * (t * t)

        let pan = max(-1, min(1, dieNode.presentation.position.x / playfieldHalfWidth))

        DiceAudioEngine.shared.play(tier: tier, gain: gain, pan: pan)
    }

    private func isDie(_ node: SCNNode) -> Bool {
        (node.physicsBody?.categoryBitMask ?? 0) & DicePhysicsCategory.die != 0
    }

    /// Clears per-die cooldown state. Called when a pool is torn down —
    /// otherwise this dictionary grows by 15 ObjectIdentifiers per game,
    /// keyed on nodes that no longer exist.
    func reset() {
        lastPlayedPerDie.removeAll()
        lastPlayedGlobal = 0
    }
}
