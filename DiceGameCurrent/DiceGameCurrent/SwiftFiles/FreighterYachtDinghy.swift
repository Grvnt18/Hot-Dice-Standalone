import Foundation

/// Freighter.Yacht.Dinghy: find a Freighter, a Yacht and a Dinghy, then
/// sail with whatever cargo is left.
///
/// Three rounds, each played as its own turn rather than batched, so every
/// round lands as its own reveal and the last is played knowing exactly
/// what is needed.
enum FreighterYachtDinghyRules {

    /// Rounds each player plays. Best of three on cumulative points.
    static let roundsPerPlayer = 3

    /// Six identical d6.
    ///
    /// Was five, which left exactly two dice as Cargo once the three
    /// vessels were claimed. The sixth makes it three, and nothing in the
    /// scoring had to move for that: `score` already sums whatever Cargo
    /// holds, and Cargo is already whatever is left unclaimed.
    static let diceCount = 6

    /// Rolls per turn, including the first.
    ///
    /// Four, not three. At three dice-five it qualified 54.1% of the time
    /// and 45.9% of rounds scored nothing — close to a coin flip on
    /// whether a turn happened at all; the fourth roll took that to 68.8%
    /// qualifying and 31.3% scoring zero.
    ///
    /// The sixth die moved it again, measured rather than assumed: 82.3%
    /// qualify and 17.7% of rounds score nothing. Three wasted rounds in
    /// ten became fewer than two, which is the point of the extra die —
    /// the allowance itself did not need to change.
    static let rollsPerTurn = 4

    /// Claimed strictly in this order: no Yacht before a Freighter, no
    /// Dinghy before a Yacht. This ordering is the whole game — it is why
    /// turns still score nothing even with four rolls and six dice.
    static let qualifiers = [6, 5, 4]

    /// What the Cargo dice must beat for a reroll to be worth taking.
    ///
    /// Two d6 averaged 7, so 7 was a wash: rerolling at 6 or less gained,
    /// at 7 broke even, above it lost. Three d6 average 10.5, so the
    /// break-even has moved and 6 is well below it — the hint now fires
    /// only on a genuinely bad Cargo and stays quiet the rest of the time.
    ///
    /// Left at 6 deliberately. It is advice under a button, not a rule,
    /// and the choice was always the player's.
    static let cargoRerollHint = 6

    /// A fresh set: six d6, each a different colourway so the claimed
    /// dice are easy to pick out of the tray.
    static func makeDice() -> [Die] {
        // The palette is refilled rather than exhausted. This asked for a
        // die and got nil once the shuffled colourways ran out, which is
        // the pattern that silently dropped five dice from a twenty-die
        // Free Roll pool. Safe here at 6 against 15 colourways — but safe
        // by a margin nobody was watching, which was equally true of Free
        // Roll while its cap was 10.
        var colorways: [DieColorway] = []
        return (0..<diceCount).map { _ in
            if colorways.isEmpty { colorways = DiePalette.colorways.shuffled() }
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

        /// Dice set aside as Freighter, Yacht, Dinghy — in that order.
        private(set) var claimed: [UUID] = []

        /// The two dice left once qualified, with their faces. Empty until
        /// the Dinghy is claimed.
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
            // takes one 6 as the Freighter, then the 5, then one 4 —
            // never two 6's.
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
    static let qualifierNames = ["Freighter", "Yacht", "Dinghy"]

    /// What is still being looked for, for the line under the button.
    static func needed(after turn: Turn) -> String? {
        guard !turn.isQualified else { return nil }
        return qualifierNames[turn.claimed.count]
    }

    /// One line describing a finished turn, for the handover screen.
    static func summary(for turn: Turn, player: String) -> String {
        guard turn.isQualified else {
            let found = turn.claimed.count
            if found == 0 { return "\(player) never found a Freighter — 0." }
            return "\(player) sailed short of a \(qualifierNames[found]) — 0."
        }
        return "\(player) put to sea with \(turn.score) cargo."
    }
}

/// Freighter.Yacht.Dinghy as it travels in a message.
///
/// The match length, because it is chosen before the first round and every
/// device has to agree on when the match ends.
///
/// `Turn` deliberately does not travel, and could not as written: its cargo
/// is an array of tuples, which Swift cannot synthesise Codable for. That
/// is the right shape anyway — a round is four rolls resolved on one
/// device, and what crosses is the score it produced.
struct FreighterYachtDinghyState: Codable, Equatable {

    /// Rounds each player takes this match.
    var roundsThisMatch: Int = FreighterYachtDinghyRules.roundsPerPlayer

    private enum CodingKeys: String, CodingKey { case roundsThisMatch = "r" }

    init(roundsThisMatch: Int = FreighterYachtDinghyRules.roundsPerPlayer) {
        self.roundsThisMatch = roundsThisMatch
    }
}

// MARK: - Suite entry

enum FreighterYachtDinghyGame: SuiteGame {
    static let id = "fyd"
    static let displayName = "Freighter.Yacht.Dinghy"
    static let tagline = "Freighter, yacht, dinghy. Best of three."

    /// Two or more, per GAME_RULES.txt. The turns alternate and the state
    /// is per seat, so nothing here is counting to two — see
    /// TurnMatch.local(playerCount:).
    static let maxPlayers = Int.max


    /// The full name is three words and two full stops, which at 45% of
    /// the playfield width would be unreadable under the dice.
    static let floorTitle = "F.Y.D."

    /// The full name, with the break stated rather than left to chance.
    ///
    /// The tile used to read "F.Y.D." because the name has no spaces to
    /// wrap on, so SwiftUI runs it as one line and truncates: 327pt at the
    /// iPad's 28pt label against 280pt of tile, and worse proportionally on
    /// a phone. A newline is the fix, and it has to be explicit — a
    /// zero-width space would let the layout choose, and the choice is only
    /// ever this one.
    ///
    /// Measured off the real TTF at the narrowest width this app meets:
    /// "Freighter." is 83pt and "Yacht.Dinghy" 117pt against the iPhone
    /// SE's 117pt of label. That second line lands exactly on the limit,
    /// which is why the label also carries a scale floor — see GameHubView.
    static let tileName = "Freighter.\nYacht.Dinghy"


    static let rules: [GameRuleSection] = [
        GameRuleSection(
            title: "Game Overview",
            body: "Two or more players, alternating turns. The dice pool is six d6. The structure is best of 3 rounds."
        ),
        GameRuleSection(
            title: "Turn Mechanics",
            body: "Each player receives up to four rolls per round to unlock the cargo sequence. Freighter requires a 6. Yacht requires a 5, and must be claimed after the Freighter. Dinghy requires a 4, and must be claimed after the Yacht. Required dice are set aside automatically as they land."
        ),
        GameRuleSection(
            title: "Cargo Scoring and Rerolls",
            body: "Once all three vessels — the 6, the 5 and the 4 — are claimed, the remaining three dice form your Cargo, and their combined total is your round score. If rolls remain within the four-roll allowance, you may re-roll all three cargo dice together, all or none. Failing to claim all three vessels within four rolls scores 0. The highest cumulative score after 3 rounds wins, and ties trigger a sudden-death round."
        )
    ]
}
