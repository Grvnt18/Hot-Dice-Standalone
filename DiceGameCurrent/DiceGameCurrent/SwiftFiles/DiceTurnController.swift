import SceneKit
import QuartzCore

/// Ties the pure logic layer (DiceGameRound), the live scene layer
/// (DicePoolLifecycleController), and the roll animation layer
/// (DiceRollController) together into the actual turn flow.
///
/// The Roll button does two jobs at once, matching the game's own rule
/// that banking and rerolling are really one connected action: tapping it
/// confirms whatever dice are currently selected (banking them for score,
/// fading them out of the scene) and, once that's done, immediately rolls
/// whatever's left. There's no separate "confirm" step.
final class DiceTurnController {

    private var round: DiceGameRound
    private let lifecycle: DicePoolLifecycleController
    private let rollController: DiceRollController
    private let playAreaBounds: (x: ClosedRange<Float>, z: ClosedRange<Float>)

    private(set) var selectedDieIDs: Set<UUID> = []

    /// Fired whenever anything a UI would want to react to changes —
    /// selection, score, or turn-over state. DiceTurnController isn't an
    /// ObservableObject itself (keeping it UI-framework agnostic), so
    /// SwiftUI call sites should set this to trigger their own refresh,
    /// since taps handled by DiceTapHandler happen outside SwiftUI's
    /// normal state-observation path.
    var onStateChanged: (() -> Void)?

    /// Drives the Roll button's enabled state. Before the very first roll
    /// of the turn, there's nothing settled to select yet — so Roll is
    /// enabled with zero selection, and pressing it performs that first
    /// roll. Every roll after that requires at least one die selected,
    /// since a reroll only makes sense once you've banked something.
    ///
    /// Also blocks while a roll is actively in progress (rollController.
    /// isRolling) — a die that settles fast, while others from the same
    /// roll are still tumbling, becomes individually selectable, and
    /// without this check the button would let you trigger a second roll
    /// on top of the first, corrupting the still-in-flight one's tracking
    /// state. This was a real, confirmed bug found during review, not a
    /// hypothetical.
    var canConfirmAndRoll: Bool {
        guard !rollController.isRolling else { return false }
        if !round.hasRolledThisTurn {
            return true
        }
        return !selectedDieIDs.isEmpty
    }

    var currentScore: Int {
        round.bankedScore
    }

    /// Banked dice in order taken — drive the top bar's 3x5 grid fill
    /// directly from this after each confirm.
    var bankedOrder: [Die] {
        round.bankedOrder
    }

    /// Text for the Roll button itself, reflecting the current phase:
    /// "Begin" before the turn's very first roll (nothing selected yet,
    /// nothing to select), "Finish" once every remaining die in the pool
    /// is selected (confirming then banks everything and ends the turn,
    /// not just rerolls the rest), otherwise the normal "Roll".
    var rollButtonLabel: String {
        if !round.hasRolledThisTurn {
            return "Begin"
        }
        if !selectedDieIDs.isEmpty && selectedDieIDs.count == round.pool.count {
            return "Finish"
        }
        return "Roll"
    }

    /// Text to show beneath the Roll button. Empty before the first roll
    /// ("Begin" state, nothing to select yet) and empty once everything's
    /// selected (the button's own "Finish" label already says it — no
    /// need to repeat it in the subtitle too). Otherwise shows the live
    /// selection count.
    var rollButtonSubtitle: String {
        guard round.hasRolledThisTurn, !selectedDieIDs.isEmpty else {
            return ""
        }
        guard selectedDieIDs.count < round.pool.count else {
            return ""
        }

        let count = selectedDieIDs.count
        let dieWord = count == 1 ? "die" : "dice"
        return "(\(count) \(dieWord) selected)"
    }

    init(
        round: DiceGameRound,
        lifecycle: DicePoolLifecycleController,
        rollController: DiceRollController,
        playAreaBounds: (x: ClosedRange<Float>, z: ClosedRange<Float>)
    ) {
        self.round = round
        self.lifecycle = lifecycle
        self.rollController = rollController
        self.playAreaBounds = playAreaBounds
    }

    /// Records the value read from whichever face physically landed up for
    /// a settled die — called from DiceSceneAssembler's onDieSettled
    /// callback. This is now the die's actual scored result (no separate
    /// badge reveal anymore); proxies to whichever round is currently
    /// active, since startNewGame() below replaces `round` entirely when a
    /// finished game restarts, so a closure capturing the original round
    /// object directly would silently keep writing to a stale, abandoned
    /// round after the first game ends.
    func recordSettledValue(dieID: UUID, value: Int) {
        round.setValue(for: dieID, value: value)
        onStateChanged?()
    }

    /// Sources the timestamp itself, right here, rather than accepting one
    /// from the caller — this method gets called from inside an async
    /// completion closure (see confirmSelectionAndRoll below), so a
    /// timestamp captured back when the Roll button was originally tapped
    /// would already be ~0.25s stale by the time this actually runs,
    /// quietly eating into the roll's settle-time budget on every reroll.
    private func beginRoll() {
        // This was the missing link: without actually rolling the logic
        // layer, currentValue stays nil forever and hasRolledThisTurn
        // never becomes true — meaning canConfirmAndRoll would be
        // permanently false and the Roll button would never enable.
        round.rollPool()
        SoundEngine.shared.play(.diceRoll)

        let dice = lifecycle.rollableDice
        DiceRollImpulse.launch(dice: dice)
        rollController.startRoll(dice: dice, currentTime: CACurrentMediaTime())
    }

    /// Toggle a die's selected state — call from your tap/hit-test handler.
    /// Only settled, live dice should be selectable; gate that at the call
    /// site using DiceRollController's onDieSettled/onRollComplete.
    /// Automatically updates that die's selection glow to match.
    func toggleSelection(dieID: UUID) {
        if selectedDieIDs.contains(dieID) {
            selectedDieIDs.remove(dieID)
            SoundEngine.shared.play(.dieDeselect)
        } else {
            selectedDieIDs.insert(dieID)
            SoundEngine.shared.play(.dieSelect)
        }

        if let node = lifecycle.liveDice.first(where: { $0.id == dieID })?.node {
            DieSelectionHighlight.setSelected(selectedDieIDs.contains(dieID), on: node)
        }

        onStateChanged?()
    }

    /// The Roll button's action.
    ///
    /// Banks the current selection in the data layer immediately (so
    /// bankedOrder updates right away — bind your grid's fade-in transition
    /// to that array so new cells appear the instant this is called, not
    /// waiting on the 3D fade animation). In parallel, fades the confirmed
    /// dice out of the scene; once that visual fade finishes, either rolls
    /// whatever dice remain or reports the turn complete.
    func confirmSelectionAndRoll(onTurnComplete: (() -> Void)? = nil) {
        guard canConfirmAndRoll else { return }

        // Pool is already empty — a finished game. "Begin" here means
        // start an entirely new game (fresh round, fresh spawned dice,
        // roll immediately), not bank/reroll a pool that no longer
        // exists. A genuinely fresh launch never hits this branch, since
        // its pool starts at 15 (not empty) — this only fires once a
        // previous game has actually been finished.
        if round.isGameOver {
            startNewGameAndRoll()
            return
        }

        let confirmedIDs = selectedDieIDs
        selectedDieIDs.removeAll()

        // Data layer: bank immediately. bankedOrder is updated synchronously
        // here, so anything observing it (e.g. the top bar grid) can start
        // its fade-in right away, independent of the 3D fade below.
        round.bank(dieIDs: confirmedIDs)
        if !confirmedIDs.isEmpty {
            SoundEngine.shared.play(.bank)
        }
        onStateChanged?()

        // Visual layer: fade the confirmed dice out, then either roll
        // what's left or end the turn.
        lifecycle.bank(dieIDs: confirmedIDs) { [weak self] in
            guard let self = self else { return }
            if self.round.isGameOver {
                onTurnComplete?()
            } else {
                self.beginRoll()
            }
            self.onStateChanged?()
        }
    }

    /// Builds a brand-new round, replacing the finished one, respawns the
    /// full 15-die pool, and immediately rolls it — one tap fully starts
    /// the new game rather than requiring a separate spawn-then-roll step.
    private func startNewGameAndRoll() {
        let newRound = DiceGameRound()
        round = newRound
        selectedDieIDs.removeAll()
        lifecycle.setupPool(newRound.pool, playAreaBounds: playAreaBounds)
        // onStateChanged fires AFTER beginRoll (which sets
        // rollController.isRolling = true), not before — otherwise the UI
        // would refresh against the stale pre-roll state, momentarily (or
        // until some other event happened to trigger a refresh) showing
        // the Roll button as enabled right as a new roll actually starts.
        beginRoll()
        onStateChanged?()
    }
}
