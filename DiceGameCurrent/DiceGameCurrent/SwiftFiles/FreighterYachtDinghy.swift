import Foundation

/// Freighter.Yacht.Dinghy: find a Ship, a Captain and a Crew, then sail with
/// whatever cargo is left.
///
/// Three rounds, each played as its own turn rather than batched, so every
/// round lands as its own reveal and the last is played knowing exactly
/// what is needed.
enum FreighterYachtDinghyRules {

    /// Rounds each player plays. Best of three on cumulative points.
    static let roundsPerPlayer = 3

    /// Five identical d6.
    static let diceCount = 5

    /// Rolls per turn, including the first.
    static let rollsPerTurn = 3

    /// Claimed strictly in this order: no Captain before a Ship, no Crew
    /// before a Captain. This ordering is the whole game — it is why 46%
    /// of turns score nothing at all.
    static let qualifiers = [6, 5, 4]

    /// What the two Cargo dice must beat for a reroll to be worth taking.
    ///
    /// Two d6 average 7, so a 7 is a wash and anything below it is not:
    /// rerolling at 6 or less gains, rerolling at 7 breaks even, and
    /// rerolling above it loses. Used only for the hint under the button —
    /// the choice stays the player's.
    static let cargoRerollHint = 6

    /// A fresh set: five d6, each a different colourway so the claimed
    /// dice are easy to pick out of the tray.
    static func makeDice() -> [Die] {
        var colorways = DiePalette.colorways.shuffled()
        return (0..<diceCount).compactMap { _ in
            guard !colorways.isEmpty else { return nil }
            return Die(sides: 6, colorway: colorways.removeLast())
        }
    }
}

// MARK: - One turn

extension FreighterYachtDinghyRules {

    /// The state of a single turn: what has been claimed, what is riding as
    /// cargo, and how many rolls are left.
    ///
    /// Claiming is forced by the rules rather than chosen, so this applies
    /// it itself and the screen never asks. The player's only decision is
    /// whether to rethrow the cargo.
    struct Turn: Equatable {

        /// Dice set aside as Ship, Captain, Crew — in that order.
        private(set) var claimed: [UUID] = []

        /// The two dice left once qualified, with their faces. Empty until
        /// the Crew is claimed.
        private(set) var cargo: [(id: UUID, value: Int)] = []

        /// Rolls taken so far, including the one in progress.
        private(set) var rollsUsed = 0

        /// Spelled out rather than relying on the memberwise initializer.
        /// Every property here is `private(set)`, and rather than work out
        /// exactly what access level that leaves the synthesized init with,
        /// this states it — a fresh turn has claimed nothing and rolled
        /// nothing, which is the only way one is ever made.
        init() {}

        var isQualified: Bool { claimed.count == FreighterYachtDinghyRules.qualifiers.count }

        var rollsRemaining: Int { max(0, FreighterYachtDinghyRules.rollsPerTurn - rollsUsed) }

        /// Cargo total, or 0 for a turn that never qualified.
        var score: Int { isQualified ? cargo.reduce(0) { $0 + $1.value } : 0 }

        /// Dice that must not move on the next throw: everything claimed,
        /// since cargo is the only thing a reroll ever rethrows.
        var keptIDs: Set<UUID> { Set(claimed) }

        /// True when there is nothing left to decide — out of rolls, or
        /// qualified with cargo the player has chosen to sail with.
        var isOutOfRolls: Bool { rollsRemaining == 0 }

        /// Folds one settled roll in, claiming whatever it can.
        ///
        /// Takes the whole hand, kept dice included, which is what
        /// `DiceTraySession` reports once a turn is underway — already
        /// claimed dice simply match themselves again.
        mutating func apply(_ results: [DiceTraySession.DieResult]) {
            rollsUsed += 1

            var unclaimed = results.filter { !claimed.contains($0.id) }

            // Strict order, one die per qualifier. A roll of 6-6-5-4-4
            // takes one 6, then the 5, then one 4 — never two 6's.
            while claimed.count < FreighterYachtDinghyRules.qualifiers.count,
                  let index = unclaimed.firstIndex(where: { $0.value == FreighterYachtDinghyRules.qualifiers[claimed.count] }) {
                claimed.append(unclaimed[index].id)
                unclaimed.remove(at: index)
            }

            cargo = isQualified ? unclaimed.map { (id: $0.id, value: $0.value) } : []
        }

        static func == (lhs: Turn, rhs: Turn) -> Bool {
            lhs.claimed == rhs.claimed
                && lhs.rollsUsed == rhs.rollsUsed
                && lhs.cargo.map(\.id) == rhs.cargo.map(\.id)
                && lhs.cargo.map(\.value) == rhs.cargo.map(\.value)
        }
    }
}

// MARK: - Describing a turn

extension FreighterYachtDinghyRules {

    /// The names, in claim order.
    static let qualifierNames = ["Ship", "Captain", "Crew"]

    /// What is still being looked for, for the line under the button.
    static func needed(after turn: Turn) -> String? {
        guard !turn.isQualified else { return nil }
        return qualifierNames[turn.claimed.count]
    }

    /// One line describing a finished turn, for the handover screen.
    static func summary(for turn: Turn, player: String) -> String {
        guard turn.isQualified else {
            let found = turn.claimed.count
            if found == 0 { return "\(player) never found a Ship — 0." }
            return "\(player) sailed short of a \(qualifierNames[found]) — 0."
        }
        return "\(player) put to sea with \(turn.score) cargo."
    }
}

// MARK: - Suite entry

enum FreighterYachtDinghyGame: SuiteGame {
    static let id = "fyd"
    static let displayName = "Freighter.Yacht.Dinghy"
    static let tagline = "Ship, captain, crew. Best of three."

    static let rules: [GameRuleSection] = [
        GameRuleSection(
            title: "Your Turn",
            body: "You get three rolls of five dice. You are looking for a Ship (6), a Captain (5) and a Crew (4) — in that order."
        ),
        GameRuleSection(
            title: "Claiming",
            body: "After each roll, the dice you need are set aside automatically. You cannot take a Captain before you have a Ship, or a Crew before you have a Captain — a roll full of 5's is worth nothing until a 6 turns up."
        ),
        GameRuleSection(
            title: "Cargo",
            body: "Once all three are claimed, the two dice left over are your Cargo, and their total is your score. If you have rolls left you may rethrow both together — but it is both or neither, and whatever comes up stands."
        ),
        GameRuleSection(
            title: "Coming Up Short",
            body: "Fail to claim all three within your three rolls and the turn scores nothing. That happens a little under half the time, which is why one round is a coin flip and three is a game."
        ),
        GameRuleSection(
            title: "Winning",
            body: "Three rounds each, played one at a time so you see every result as it happens. Highest total after the third round wins. A tie plays one sudden-death round."
        )
    ]
}
