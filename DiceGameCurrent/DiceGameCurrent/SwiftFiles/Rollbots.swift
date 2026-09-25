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

    /// Self-damage on activation.
    ///
    /// The document gave the Overclock 4 IP of self-damage *and* an
    /// undefended turn. Together that is 8 to 10 IP of strain against a
    /// reward worth about 2, which is why it won 24% of matches. The
    /// self-damage went and the undefended turn stayed: the cost then
    /// lands on the opponent's turn, where they get to swing at an open
    /// target, which is worth more to this game than a private number
    /// going down. That measures 50.3%.
    var selfDamage: Int { 0 }

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
    static let floorMotif = FloorMotif.circuitry
    static let id = "rollbots"
    static let displayName = "Rollbots"
    static let tagline = "Duel in the net. Answer every shot."

    static let rules: [GameRuleSection] = [
        GameRuleSection(
            title: "At a Glance",
            body: "Two netrunners at \(RollbotsRules.startingIP) Integrity Points; take theirs to zero. Attacking throws a d10 for accuracy and the weapon's damage die together. The defender sees both before choosing: Dodge a d6, beating the accuracy outright for nothing, or Firewall a d8 subtracted from the damage, with a natural 8 stopping everything."
        ),
        GameRuleSection(
            title: "The Duel",
            body: "Two netrunners, \(RollbotsRules.startingIP) Integrity Points each. Take your opponent to zero. The second runner starts one point up, because striking first is worth about four percent."
        ),
        GameRuleSection(
            title: "Attacking",
            body: "Pick a weapon at setup. Attacking throws a d10 for accuracy — and your opponent sees it before they choose how to answer, which is what makes the answer a real decision."
        ),
        GameRuleSection(
            title: "Weapons",
            body: "Mono-Blade: d8, and it cuts through half of any Firewall. Smart Pistol: d6, doubled on an accuracy of 7 or more, and a crit cuts armour the same way. Rail Rifle: d12 and no Firewall stops it — but it spends a turn charging first. There is a fourth you never pick: the Sidearm, a d4 with no tricks at all, which is what the Emergency Sub-Routine leaves you holding."
        ),
        GameRuleSection(
            title: "Defending",
            body: "Dodge rolls a d6: beat their accuracy outright and take nothing, tie or miss and take all of it. Firewall rolls a d8 and subtracts it from the damage — and a natural 8 is a Hard Lockdown that stops everything, the Mono-Blade included."
        ),
        GameRuleSection(
            title: "Cyberware",
            body: "One ability each, once a match, and every one of them costs you something. Read the strain before you pick."
        ),
        GameRuleSection(
            title: "Winning",
            body: "First to take their opponent to zero. If you both hit zero in the same exchange it is a System Draw."
        )
    ]
}
