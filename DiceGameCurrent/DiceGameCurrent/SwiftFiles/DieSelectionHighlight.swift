import SceneKit
import UIKit

/// Marks a die as currently selected for banking — the dice about to be
/// removed from the pool when Roll/Finish is pressed.
///
/// This used to be an inverted-hull emissive glow (enlarged, inside-out
/// copy of the die's own mesh). Confirmed, by direct testing, to be
/// completely invisible in practice — abandoned rather than continuing to
/// tune a technique that isn't working. Replaced with something far
/// simpler and harder to get subtly wrong: a repeating opacity pulse
/// (100% -> 20% -> 100%, once per second) directly on the die node itself.
/// SceneKit inherits opacity down the node hierarchy, so this fades the
/// die's face labels along with its body automatically — no separate
/// handling needed for them.
enum DieSelectionHighlight {

    private static let pulseActionKey = "selectionPulse"

    /// How a die held back from a reroll reads once it is no longer a
    /// choice: the pulse stops and it sits dimmed.
    ///
    /// Three Thousand needs "already banked this turn" to look different
    /// from "choosing right now" — a pulsing die invites a tap, and a
    /// locked one will refuse it. Steady rather than animated is the point:
    /// nothing about it is asking for attention any more.
    private static let lockedOpacity: CGFloat = 0.55

    /// Marks a die as locked — set aside for good, for this turn.
    static func setLocked(_ locked: Bool, on dieNode: SCNNode) {
        dieNode.removeAction(forKey: pulseActionKey)
        dieNode.opacity = locked ? lockedOpacity : 1.0
    }

    /// Call this whenever a die's selected state changes — e.g. from
    /// DiceTurnController.toggleSelection. Safe to call repeatedly.
    static func setSelected(_ selected: Bool, on dieNode: SCNNode) {
        dieNode.removeAction(forKey: pulseActionKey)

        guard selected else {
            dieNode.opacity = 1.0
            return
        }

        // Half a second down, half a second back up — one full cycle per
        // second, matching "fade in and out every second."
        let fadeDown = SCNAction.fadeOpacity(to: 0.2, duration: 0.5)
        let fadeUp = SCNAction.fadeOpacity(to: 1.0, duration: 0.5)
        fadeDown.timingMode = .easeInEaseOut
        fadeUp.timingMode = .easeInEaseOut
        let pulse = SCNAction.repeatForever(.sequence([fadeDown, fadeUp]))

        dieNode.runAction(pulse, forKey: pulseActionKey)
    }
}
