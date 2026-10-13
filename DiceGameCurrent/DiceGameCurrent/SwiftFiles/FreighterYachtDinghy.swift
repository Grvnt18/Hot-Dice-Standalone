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

    /// What a single Cargo die must beat for throwing it again to be
    /// worth it.
    ///
    /// This was `cargoRerollHint = 6`, a threshold on the cargo's TOTAL,
    /// because the cargo could only be rethrown whole — "both or neither",
    /// in the document's own words. The cargo is now picked a die at a
    /// time, so a threshold on the total is the wrong unit and this is the
    /// right one: a d6 averages 3.5, so a die showing 1, 2 or 3 gains by
    /// going back in the cup and one showing 4, 5 or 6 loses by it. There
    /// is no judgement in the number at all — it is where the average
    /// falls.
    ///
    /// Still advice under a button rather than a rule. The rule is "any,
    /// all, or none" and the choice is the player's; this only names how
    /// many dice the arithmetic is against, and tools_fyd_verify.py uses
    /// it as the policy it measures the change with.
    static let cargoRethrowFloor = 4

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
    static let tagline = "Carry the boats! Don't drop the cargo!"

    /// Two or more, per GAME_RULES.txt. The turns alternate and the state
    /// is per seat, so nothing here is counting to two — see
    /// TurnMatch.local(playerCount:).
    static let maxPlayers = Int.max

    /// Pass-and-play seats the gate offers: as many as the scoreboard
    /// fits, which `MatchSetup.maxSeats` decides. `Int.max` here is the
    /// same claim `maxPlayers` makes, and it is true of this screen too —
    /// it hosts a `TurnMatch` and labels every seat in it.
    static let localSeats = Int.max

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
            body: "  * Players: 2 or more (alternating turns).\n  * Dice Pool: 6x d6.\n  * Structure: Best of 3 rounds."
        ),
        GameRuleSection(
            title: "Mechanics",
            body: "  1. Each player receives up to 4 rolls per round to unlock cargo sequence:\n   *Freighter: Requires a 6.\n    * Yacht: Requires a 5 (Must be claimed after Freighter).\n    * Dinghy: Requires a 4 (Must be claimed after Yacht).\n  *Required dice are set aside automatically as they land.*\n  2. Once all three vessels (6, 5, and 4) are claimed, remaining three dice form\n    Cargo.\n    * Combined total of remaining three dice is your round score.\n    * If rolls remain within 4-roll allowance, player may select any cargo dice to\n    re-roll (any, all, or none).\n  3.  Failure to Qualify: Failing to claim all three vessels within 4 rolls scores 0.\n  4.  Game End: Highest cumulative score after 3 rounds wins. Ties trigger\n    sudden-death round."
        )
    ]
}
