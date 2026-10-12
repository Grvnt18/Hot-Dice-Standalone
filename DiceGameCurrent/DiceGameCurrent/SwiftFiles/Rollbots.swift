import Foundation

/// Rollbots: two netrunners, one arena, and a reaction to every
/// single attack.
///
/// Built from a design document written for a chat bot. Every probability
/// that document states is correct — Dodge is 15/60, the Firewall absorbs
/// 4.5 on average and exactly 2.0 against the Mono-Blade — but it never
/// computed what happens once the defender plays well, and that is where
/// the balance was. See `CyberWeapon` and `Cyberware` for what changed and
/// by how much.
enum RollbotsRules {

    /// Integrity Points. The document says 20; that measures 15.7 turns,
    /// which is 31 messages in a thread and the longest game in the suite
    /// by a distance.
    ///
    /// | IP | turns | messages |
    /// |----|-------|----------|
    /// | 20 | 15.7  | 31       |
    /// | 16 | 12.5  | 25       |
    /// | 14 | 10.9  | 22       |
    ///
    /// Sixteen lands inside the document's own "10 to 14 turns" estimate.
    /// One constant, if it plays short.
    static let startingIP = 16

    /// The second seat starts one point up.
    ///
    /// A race to zero rewards striking first: the mirror match measured
    /// 54.5% for the opening seat. One extra point takes it to 50.4% —
    /// the same approach as Generals' snake order, fixing the imbalance in
    /// the structure rather than with a coin flip.
    static let secondSeatBonusIP = 1

    /// An accuracy roll at or above this crits.
    static let critAccuracy = 7

    /// The accuracy die, rolled by the attacker. Nothing else in the game
    /// uses a d10, which is what lets the tray report a throw's meaning
    /// from the die type alone.
    static let accuracySides = 10

    /// Damage the Overclock forces through, and the rail charge it skips.
    static let overclockAccuracy = 10
}

// MARK: - Weapons

enum CyberWeapon: String, CaseIterable, Codable, Identifiable {
    case monoBlade
    case smartPistol
    case railRifle
    /// What the Emergency Sub-Routine leaves you holding.
    case sidearm

    var id: String { rawValue }

    /// Weapons a player may choose at setup. The Sidearm is not one.
    static var selectable: [CyberWeapon] { [.monoBlade, .smartPistol, .railRifle] }

    var displayName: String {
        switch self {
        case .monoBlade:    return "Mono-Blade"
        case .smartPistol:  return "Smart Pistol"
        case .railRifle:    return "Rail Rifle"
        case .sidearm:      return "Sidearm"
        }
    }

    /// The damage die. Each weapon's is distinct, so a throw's meaning is
    /// readable off the table without a label.
    var damageSides: Int {
        switch self {
        case .monoBlade:   return 8
        case .smartPistol: return 6
        case .railRifle:   return 12
        case .sidearm:     return 4
        }
    }

    /// The Rail Rifle spends a turn spinning up before it can fire.
    var needsCharge: Bool { self == .railRifle }

    /// Halves the Firewall roll, rounded in the defender's favour.
    ///
    /// The Mono-Blade does this always; the Smart Pistol does it on a crit.
    var alwaysPierces: Bool { self == .monoBlade }

    /// No Firewall stops it — the Rail Rifle's whole identity.
    var ignoresFirewall: Bool { self == .railRifle }

    /// The bundled mark for this weapon.
    ///
    /// The Sidearm has one of its own. It borrowed the pistol's at first,
    /// for want of art, and that read wrong: the rail showed the same
    /// silhouette whether you had *chosen* the Smart Pistol or been cut
    /// down to the Sidearm, which are opposite situations.
    var iconName: String {
        switch self {
        case .monoBlade:   return "bot-blade"
        case .smartPistol: return "bot-pistol"
        case .railRifle:   return "bot-rail"
        case .sidearm:     return "bot-sidearm"
        }
    }

    var tagline: String {
        switch self {
        case .monoBlade:   return "d8 · cuts through half of any Firewall"
        case .smartPistol: return "d6 · crits on 7+, and a crit cuts armour"
        case .railRifle:   return "d12 · unblockable, but it needs a turn to charge"
        case .sidearm:     return "d4 · all you have left"
        }
    }
}

// MARK: - Defences

enum CyberDefence: String, Codable, Identifiable {
    case dodge
    case firewall
    /// Quantum Phase, when that Cyberware is armed.
    case phase
    /// Forced when the Overclock has left you open.
    ///
    /// Named `exposed` rather than `none`: a case called `none` on a type
    /// that also gets used as an Optional is the classic Swift ambiguity,
    /// and it reads better anyway.
    case exposed

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .dodge:    return "Dodge"
        case .firewall: return "Firewall"
        case .phase:    return "Quantum Phase"
        case .exposed:  return "Exposed"
        }
    }

    /// The die this reaction throws. Distinct from every damage die that
    /// could be in the air at the same moment, because each throw in this
    /// game carries exactly one role.
    var sides: Int? {
        switch self {
        case .dodge:    return 6
        case .firewall: return 8
        case .phase:    return 12
        case .exposed:  return nil
        }
    }
}

// MARK: - Cyberware

/// One high-risk ability per player, used once a match.
///
/// Two of the document's four were traps nobody should ever pick, measured
/// as win rate for a player who uses the ability against one who does not:
/// the Overclock won **24.3%** and the Sub-Routine **23.7%**. Both were
/// retuned until they landed near even. The Virus (56.7%) and the Phase
/// (51.9%) were already fine and are unchanged.
enum Cyberware: String, CaseIterable, Codable, Identifiable {
    case neuralOverclock
    case corrosiveVirus
    case quantumPhase
    case emergencySubroutine

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .neuralOverclock:     return "Neural Overclock"
        case .corrosiveVirus:      return "Corrosive Virus"
        case .quantumPhase:        return "Quantum Phase"
        case .emergencySubroutine: return "Emergency Sub-Routine"
        }
    }

    var iconName: String {
        switch self {
        case .neuralOverclock:     return "bot-overclock"
        case .corrosiveVirus:      return "bot-virus"
        case .quantumPhase:        return "bot-phase"
        case .emergencySubroutine: return "bot-repair"
        }
    }

    var reward: String {
        switch self {
        case .neuralOverclock:
            return "Your next attack lands at accuracy 10 and no Firewall stops it. The Rail Rifle fires without charging."
        case .corrosiveVirus:
            return "Infects them for 3 IP at the start of each of their next three turns — 9 in all."
        case .quantumPhase:
            return "Your next defence rolls a d12 instead. Beat their accuracy and take nothing, and hit back for 4."
        case .emergencySubroutine:
            return "Repairs 8 IP on the spot."
        }
    }

    var strain: String {
        switch self {
        case .neuralOverclock:
            return "You cannot defend at all on their next turn."
        case .corrosiveVirus:
            return "Roll a d6 first. On a 1 or 2 it turns on you instead."
        case .quantumPhase:
            return "Fail the roll and the attack hits you for double."
        case .emergencySubroutine:
            return "You are down to the Sidearm for your next four turns."
        }
    }
}

extension Cyberware {

    // No ability costs self-damage, and the Overclock is why that is worth
    // writing down. The document gave it 4 IP of self-damage *and* an
    // undefended turn: together, 8 to 10 IP of strain against a reward
    // worth about 2, which is how it came to win 24% of matches. The
    // self-damage went and the undefended turn stayed, so the cost lands on
    // the opponent's turn, where they get to swing at an open target —
    // worth more to this game than a private number going down. That
    // measures 50.3%.
    //
    // This used to be a `selfDamage: Int { 0 }` nothing read. A knob fixed
    // at zero that no code consults is not a rule, it is a note, so it is
    // one now.

    /// Turns the Corrosive Virus runs for, at 3 IP a turn.
    static let virusTurns = 3
    static let virusDamagePerTurn = 3

    /// A d6 at or above this activates the Virus; below it, it backfires.
    static let virusActivatesOn = 3

    /// What the Quantum Phase hits back for.
    static let phaseCounterDamage = 4

    /// The Sub-Routine's repair.
    static let repairAmount = 8

    /// How long the Sub-Routine leaves you on the Sidearm.
    ///
    /// The document said permanently, which collapsed damage output from
    /// 2.24 a turn to 0.31 and won 23.7% of matches. Four turns measures
    /// 50.6% and keeps the sting.
    static let sidearmTurns = 4
}

// MARK: - Resolving an attack

extension RollbotsRules {

    /// Everything one exchange produced, for the log line and the screen.
    struct Resolution: Equatable {
        let accuracy: Int
        let defence: CyberDefence
        let defenceRoll: Int?
        let damageRoll: Int
        let isCrit: Bool
        /// Damage the defender takes.
        let damage: Int
        /// Damage the attacker takes back — Quantum Phase only.
        let counter: Int
        let evaded: Bool
        let lockedDown: Bool
    }

    /// Whether a reaction can change the outcome at all.
    ///
    /// The defence menu is built from the defender's seat alone, so
    /// against a Rail Rifle it still offers a Firewall — and the card
    /// promises "a natural 8 stops everything", which against that weapon
    /// is false: `resolve` returns the raw damage before a natural 8 is
    /// ever looked at. The defender then throws a d8, watches it settle,
    /// reads the number, and takes the damage in full: a roll that could
    /// not have gone any other way.
    ///
    /// Three answers, each read straight off `resolve` below:
    ///
    ///   Dodge          only if a d6 can beat the accuracy — accuracy < 6
    ///   Firewall       only if the shot is not piercing it outright
    ///   Quantum Phase  always, since a d12 beats any d10 accuracy
    ///
    /// Exposed is not a choice and never helps, which is why it needs no
    /// arithmetic of its own.
    ///
    /// No probability moves: the roll that goes away never affected one.
    static func canHelp(
        _ defence: CyberDefence,
        weapon: CyberWeapon,
        accuracy: Int,
        ignoresFirewall: Bool = false
    ) -> Bool {
        switch defence {
        case .exposed:
            return false
        case .dodge, .phase:
            guard let sides = defence.sides else { return false }
            return sides > accuracy
        case .firewall:
            return !(ignoresFirewall || weapon.ignoresFirewall)
        }
    }

    /// Resolves one attack from its three dice.
    ///
    /// Takes the rolls rather than making them: the dice are thrown on the
    /// table by the tray, and every number here has to be the one the
    /// player watched land.
    static func resolve(
        weapon: CyberWeapon,
        accuracy: Int,
        damageRoll: Int,
        defence: CyberDefence,
        defenceRoll: Int?,
        ignoresFirewall: Bool = false
    ) -> Resolution {
        let isCrit = (weapon == .smartPistol && accuracy >= critAccuracy)
        let raw = isCrit ? damageRoll * 2 : damageRoll

        func result(
            damage: Int, counter: Int = 0, evaded: Bool = false, lockedDown: Bool = false
        ) -> Resolution {
            Resolution(
                accuracy: accuracy, defence: defence, defenceRoll: defenceRoll,
                damageRoll: damageRoll, isCrit: isCrit, damage: damage,
                counter: counter, evaded: evaded, lockedDown: lockedDown
            )
        }

        switch defence {
        case .exposed:
            return result(damage: raw)

        case .dodge:
            // Strictly higher — a tie fails, which is what makes Dodge a
            // 25% proposition rather than a 35% one.
            let evaded = (defenceRoll ?? 0) > accuracy
            return result(damage: evaded ? 0 : raw, evaded: evaded)

        case .phase:
            let evaded = (defenceRoll ?? 0) > accuracy
            return evaded
                ? result(damage: 0, counter: Cyberware.phaseCounterDamage, evaded: true)
                : result(damage: raw * 2)

        case .firewall:
            let roll = defenceRoll ?? 0
            if ignoresFirewall || weapon.ignoresFirewall {
                return result(damage: raw)
            }
            // Hard Lockdown: a natural 8 absorbs everything, and it beats
            // the Mono-Blade's penetration outright.
            if roll == 8 { return result(damage: 0, lockedDown: true) }
            if weapon.alwaysPierces || isCrit {
                // Half the roll is bypassed, rounded up — so what absorbs
                // is the floor of half.
                return result(damage: max(0, raw - roll / 2))
            }
            return result(damage: max(0, raw - roll))
        }
    }
}

// MARK: - Match state

/// Both runners, everything ticking on them, and whose deck is hot.
struct RollbotsState: Codable, Equatable {

    var ip: [Int]
    var weapon: [CyberWeapon]
    var ware: [Cyberware]
    var wareUsed: [Bool]
    var charged: [Bool]
    /// Turns of Corrosive Virus still burning this seat.
    var virusTurns: [Int]
    /// Turns this seat is stuck on the Sidearm.
    var sidearmTurns: [Int]
    /// Set by the Overclock: this seat cannot defend on the next attack.
    var exposed: [Bool]
    /// The Overclock is armed and applies to this seat's next attack.
    var overclocked: [Bool]
    /// The Quantum Phase is armed and replaces this seat's next defence.
    var phaseArmed: [Bool]

    init(weapons: [CyberWeapon], ware: [Cyberware]) {
        ip = [RollbotsState.startingIP(0), RollbotsState.startingIP(1)]
        weapon = weapons
        self.ware = ware
        wareUsed = [false, false]
        charged = [false, false]
        virusTurns = [0, 0]
        sidearmTurns = [0, 0]
        exposed = [false, false]
        overclocked = [false, false]
        phaseArmed = [false, false]
    }

    private enum CodingKeys: String, CodingKey {
        case ip, weapon, ware, wareUsed = "u", charged = "c"
        case virusTurns = "v", sidearmTurns = "s", exposed = "e"
        case overclocked = "o", phaseArmed = "q"
    }

    /// What this seat began the match on, which is not the same for both.
    ///
    /// Seat 1 carries the second-seat bonus point, so anything that caps a
    /// seat's IP has to ask for that seat's own ceiling rather than reach
    /// for RollbotsRules.startingIP. The Emergency Sub-Routine's repair did
    /// exactly that and quietly took seat 1's compensation point away the
    /// first time they healed.
    static func startingIP(_ seat: Int) -> Int {
        RollbotsRules.startingIP + (seat == 1 ? RollbotsRules.secondSeatBonusIP : 0)
    }

    /// What this seat is actually holding right now.
    func activeWeapon(_ seat: Int) -> CyberWeapon {
        sidearmTurns[seat] > 0 ? .sidearm : weapon[seat]
    }

    /// Whether this seat can fire, or has to spend the turn charging.
    func canFire(_ seat: Int) -> Bool {
        let weapon = activeWeapon(seat)
        return !weapon.needsCharge || charged[seat] || overclocked[seat]
    }

    /// What the defender may choose from.
    func defences(for seat: Int) -> [CyberDefence] {
        if exposed[seat] { return [.exposed] }
        if phaseArmed[seat] { return [.phase, .dodge, .firewall] }
        return [.dodge, .firewall]
    }

    /// Nil while both runners are up. A System Draw returns both seats.
    var defeated: [Int] {
        [0, 1].filter { ip[$0] <= 0 }
    }
}

// MARK: - Suite entry

enum RollbotsGame: SuiteGame {
    static let id = "rollbots"
    static let displayName = "Rollbots"
    static let tagline = "Duel in the net. Answer every shot."

    static let rules: [GameRuleSection] = [
        GameRuleSection(
            title: "Game Overview",
            body: "  * Players: 2.\n  * Starting Health: 16 Integrity Points (IP) for Player 1, Player 2\n    starts with 17 IP as an equalizer.\n  * Objective: Reduce opponent's IP to zero."
        ),
        GameRuleSection(
            title: "Loadout Selection",
            body: "  Each player selects 1 Weapon and 1 Cyberware Ability at match start.\n\n  Weapons\n  Weapon                  Effect\n  -----------------------------------------------------------------------------\n  Mono-Blade (d8)         Bypasses 50% of target's Firewall.\n\n  Smart Pistol (d6)       Damage doubles if Accuracy roll is 7+; critical\n                          damage bypasses 50% of Firewall.\n\n  Rail Rifle (d12)        Bypasses Firewall completely. Requires 1 turn to\n                          charge before firing.\n\n  Sidearm (d4)            Default fallback weapon when primary weapon is\n                          disabled.\n\n   Cyberware Abilities (One-Time Use Per Match)\n  Ability                 Effect                              Drawback / Cost\n  -----------------------------------------------------------------------------\n  Neural Overclock        Next attack deals forced Acc 10,    Disables defense\n                          bypasses Firewall, Rail fires       options on opponent's\n                          without charging.                   next turn.\n\n  Corrosive Virus         Deals 3 IP damage/turn at start     Roll d6 on activation:\n                          of opponent's next 3 turns.         1 or 2 turns virus\n                                                              back on self.\n\n  Quantum Phase           Defense uses d12. Beating           Failing roll causes\n                          accuracy negates damage and         taking double damage\n                          counter-attacks for 4 IP.           from attack.\n\n  Emergency Sub-Routine   Immediately repairs 8 IP.           Downgrades weapon to\n                                                              Sidearm (d4) for 4\n                                                              turns."
        ),
        GameRuleSection(
            title: "Mechanics",
            body: "  1. Attacker: Rolls Accuracy die (d10) and assigned Weapon Damage die together,\n     confirming attack to resolve.\n  2. Defender Choice:\n       * Dodge (d6): Roll higher than attacker's Accuracy to negate all damage.\n         Ties or lower take full damage.\n       * Firewall (d8): Subtract Firewall roll from incoming damage. Natural 8\n         (Hard Lockdown) negates all damage completely.\n  3. Game End: Immediately when either player reached 0 IP."
        )
    ]
}
