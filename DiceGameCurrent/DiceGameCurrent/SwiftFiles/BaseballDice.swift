import Foundation

/// Baseball Dice: a pitch and a swing chosen at the same time, resolved by
/// the gap between two dice.
///
/// Pure rules and state — no SwiftUI, no SceneKit — so the whole game can be
/// re-run in Python by `tools_baseball_verify.py` and checked against the
/// measurements that shaped it.
///
/// The heart of it is a rock-paper-scissors between three pitches and three
/// swings, and it measures as a real one: no dominant strategy, and a mixed
/// equilibrium of Patient 28% / Contact 28% / Power 43% for the batter
/// against Fastball 40% / Changeup 37% / Slider 23% for the pitcher, worth
/// 0.121 runs an at-bat. Run value per at-bat, batter's gain:
///
///              Patient  Contact   Power
///   Fastball    +0.382   +0.044  +0.002
///   Changeup    -0.068   +0.319  +0.117
///   Slider      -0.018   -0.061  +0.330
///
/// Each pitch beats one swing, loses to another and ties the third, which is
/// what makes guessing worth doing.
enum BaseballDiceRules {

    static let outsPerHalfInning = 3

    /// The three match lengths, and what they cost in at-bats.
    ///
    /// Measured over 30,000 games apiece at equilibrium play:
    ///
    ///   3 innings   3.0-3.0 runs    31 at-bats   extras in 23.0%
    ///   6 innings   5.7-5.7 runs    60 at-bats   extras in 13.7%
    ///   9 innings   8.5-8.5 runs    89 at-bats   extras in 10.8%
    ///
    /// Batting first is worth nothing measurable — 49.5% to 50.6% across all
    /// three lengths — so unlike Generals this needs no ordering fix.
    static let lengths = [3, 6, 9]
}

// MARK: - The choices

/// What the pitcher throws. Chosen every at-bat and kept hidden until the
/// dice land.
enum Pitch: String, CaseIterable, Codable, Identifiable {
    case fastball, changeup, slider

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fastball: return "Fastball"
        case .changeup: return "Changeup"
        case .slider:   return "Slider"
        }
    }

    /// The swing this pitch is strong against — the batter's worst guess.
    var beats: Swing {
        switch self {
        case .fastball: return .power
        case .changeup: return .patient
        case .slider:   return .contact
        }
    }

    /// The swing that punishes it. Cyclic, so every pitch has exactly one.
    var losesTo: Swing {
        switch self {
        case .fastball: return .patient
        case .changeup: return .contact
        case .slider:   return .power
        }
    }

    var tagline: String {
        switch self {
        case .fastball: return "Overpowers a Power Swing · patient hitters time it"
        case .changeup: return "Fools a Patient Swing · contact hitters wait on it"
        case .slider:   return "Ties up a Contact Swing · power hitters sit on it"
        }
    }
}

/// How the batter swings. Chosen every at-bat, without seeing the pitch.
enum Swing: String, CaseIterable, Codable, Identifiable {
    case patient, contact, power

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .patient: return "Patient Swing"
        case .contact: return "Contact Swing"
        case .power:   return "Power Swing"
        }
    }

    /// The die this swing rolls when the matchup is not unfavoured.
    var sides: Int {
        switch self {
        case .patient: return 8
        case .contact: return 10
        case .power:   return 12
        }
    }

    var tagline: String {
        switch self {
        case .patient: return "d8 · sits on the Fastball"
        case .contact: return "d10 · sits on the Changeup"
        case .power:   return "d12 · sits on the Slider"
        }
    }
}

/// A pitcher's approach for a whole half-inning.
///
/// The design sheet had the pitcher lock one pitch per half-inning while the
/// batter chose per at-bat. That breaks the game: the dice reveal the
/// matchup — 2d8 against a d4 looks nothing like d12 against d12 — so from
/// the second batter on the batter knows the pitch and takes the favoured
/// swing every time. Measured, that is 30.6 runs a game against 8.5.
///
/// So a style is a *mix*, not a pitch. The pitcher picks one for the
/// half-inning and the app draws the actual pitch from it each at-bat, which
/// keeps one hidden decision per half-inning while making the individual
/// pitch unknowable. Measured over 20,000 games: 8.4 runs blind, and 14.6 as
/// an upper bound if the batter somehow read the style perfectly — against
/// the 3.6x gap the fixed pitch produced. The ceiling is not reachable in
/// play anyway, since the style is hidden and resets every half-inning.
///
/// The three keep the same cycle as the pitches, softened: Power Pitcher is
/// answered by a Patient Swing, Crafty by Contact, Breaking Ball by Power.
enum PitchStyle: String, CaseIterable, Codable, Identifiable {
    case powerPitcher, crafty, breakingBall

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .powerPitcher: return "Power Pitcher"
        case .crafty:       return "Crafty"
        case .breakingBall: return "Breaking Ball"
        }
    }

    /// How often each pitch comes out, in sixteenths of a half-inning's worth
    /// of at-bats. Weights rather than a single pitch: 60/25/15 leaves the
    /// style an identity without making it readable.
    var weights: [(pitch: Pitch, weight: Int)] {
        switch self {
        case .powerPitcher:
            return [(.fastball, 60), (.changeup, 25), (.slider, 15)]
        case .crafty:
            return [(.fastball, 20), (.changeup, 60), (.slider, 20)]
        case .breakingBall:
            return [(.fastball, 20), (.changeup, 20), (.slider, 60)]
        }
    }

    var tagline: String {
        switch self {
        case .powerPitcher: return "Mostly fastballs · patient hitters sit on it"
        case .crafty:       return "Mostly changeups · contact hitters wait"
        case .breakingBall: return "Mostly sliders · power hitters guess it"
        }
    }

    /// Draws this half-inning's pitch for one at-bat.
    ///
    /// Takes the generator so a replayed match produces the same pitches —
    /// the same reason every roll in this suite is seeded.
    func pitch(using generator: inout SeededGenerator) -> Pitch {
        let total = weights.reduce(0) { $0 + $1.weight }
        var roll = generator.nextInt(upperBound: total)
        for entry in weights {
            roll -= entry.weight
            if roll < 0 { return entry.pitch }
        }
        return weights[weights.count - 1].pitch
    }
}

// MARK: - The matchup

/// Who the dice favour once both choices are on the table.
enum MatchupKind: String, Codable {
    case favored, neutral, unfavored

    var displayName: String {
        switch self {
        case .favored:   return "Favoured"
        case .neutral:   return "Even"
        case .unfavored: return "Unfavoured"
        }
    }

    var symbol: String {
        switch self {
        case .favored:   return "+"
        case .neutral:   return "="
        case .unfavored: return "−"
        }
    }
}

/// The dice a pitch/swing pairing throws.
struct Matchup: Equatable {
    let kind: MatchupKind

    /// Sides on each of the batter's dice.
    let batterSides: Int

    /// How many the batter throws. Two means keep the highest.
    let batterDice: Int

    let pitcherSides: Int

    var keepsHighest: Bool { batterDice > 1 }
}

extension BaseballDiceRules {

    /// The dice for a pairing.
    ///
    /// Favoured gives the batter two of their own die and drops the pitcher
    /// to a d4 — which is why a favoured at-bat can never strike out: the
    /// worst differential available is 1 - 4 = -3, and a strikeout needs -5.
    ///
    /// Unfavoured does not simply reverse it. Each unfavoured pairing has its
    /// own dice, taken from the design's chart rather than derived, because
    /// the three are deliberately not equally bad.
    static func matchup(pitch: Pitch, swing: Swing) -> Matchup {
        if pitch.losesTo == swing {
            return Matchup(kind: .favored,
                           batterSides: swing.sides,
                           batterDice: 2,
                           pitcherSides: 4)
        }
        if pitch.beats == swing {
            switch pitch {
            case .fastball: return Matchup(kind: .unfavored, batterSides: 12,
                                           batterDice: 1, pitcherSides: 12)
            case .changeup: return Matchup(kind: .unfavored, batterSides: 8,
                                           batterDice: 1, pitcherSides: 10)
            case .slider:   return Matchup(kind: .unfavored, batterSides: 10,
                                           batterDice: 1, pitcherSides: 12)
            }
        }
        return Matchup(kind: .neutral,
                       batterSides: swing.sides,
                       batterDice: 1,
                       pitcherSides: 8)
    }
}

// MARK: - The outcome

/// What an at-bat produced.
enum AtBatResult: String, Codable {
    case strikeout, fieldOut, walk, single, double, triple, deepOut, homeRun

    var displayName: String {
        switch self {
        case .strikeout: return "Strikeout"
        case .fieldOut:  return "Field Out"
        case .walk:      return "Walk"
        case .single:    return "Single"
        case .double:    return "Double"
        case .triple:    return "Triple"
        case .deepOut:   return "Deep Out"
        case .homeRun:   return "Home Run"
        }
    }

    var isOut: Bool {
        self == .strikeout || self == .fieldOut || self == .deepOut
    }

    /// How far the batter ends up, in bases. Zero for an out or a walk that
    /// is handled separately.
    var basesForBatter: Int {
        switch self {
        case .walk, .single: return 1
        case .double:        return 2
        case .triple:        return 3
        case .homeRun:       return 4
        default:             return 0
        }
    }
}

extension BaseballDiceRules {

    /// The differential table, straight from the design.
    ///
    /// The band at +7 to +9 is the one that surprises people: a very good
    /// swing that is still caught at the wall. It is not a rounding error —
    /// it fires on 37% of Slider-versus-Power at-bats, which is what keeps
    /// the strongest matchup in the game from being a run machine.
    static func result(differential: Int) -> AtBatResult {
        switch differential {
        case ...(-5):  return .strikeout
        case (-4)...1: return .fieldOut
        case 2:        return .walk
        case 3...4:    return .single
        case 5:        return .double
        case 6:        return .triple
        case 7...9:    return .deepOut
        default:       return .homeRun
        }
    }

    /// A finished at-bat, before the bases are moved.
    struct AtBat: Equatable {
        let pitch: Pitch
        let swing: Swing
        let matchup: Matchup
        let batterRolls: [Int]
        let pitcherRoll: Int
        let result: AtBatResult

        /// True when a favoured swing rolled its die's maximum on both dice.
        let isJackpot: Bool

        var batterRoll: Int { batterRolls.max() ?? 0 }
        var differential: Int { batterRoll - pitcherRoll }
    }

    /// Reads a settled throw into an at-bat.
    ///
    /// The Double Max Jackpot overrides the table outright: two maximums on a
    /// favoured swing is a home run however the differential lands. It is the
    /// only way a Fastball-versus-Patient at-bat can leave the park at all,
    /// since that pairing's differential tops out at +7.
    static func atBat(pitch: Pitch, swing: Swing,
                      batterRolls: [Int], pitcherRoll: Int) -> AtBat {
        let matchup = matchup(pitch: pitch, swing: swing)
        let best = batterRolls.max() ?? 0
        let jackpot = matchup.keepsHighest
            && batterRolls.count == matchup.batterDice
            && batterRolls.allSatisfy { $0 == matchup.batterSides }
        return AtBat(
            pitch: pitch,
            swing: swing,
            matchup: matchup,
            batterRolls: batterRolls,
            pitcherRoll: pitcherRoll,
            result: jackpot ? .homeRun : result(differential: best - pitcherRoll),
            isJackpot: jackpot
        )
    }
}

// MARK: - The diamond

/// Who is on base, and the runs an at-bat drove in.
///
/// Bases are three flags rather than a count, because every advancement rule
/// here depends on *which* bases are occupied: a forced walk, a double play,
/// and a sacrifice fly all read different corners of the diamond.
struct Diamond: Equatable, Codable {
    /// first, second, third.
    var occupied: [Bool] = [false, false, false]

    var isEmpty: Bool { !occupied.contains(true) }
    var runnerCount: Int { occupied.filter { $0 }.count }

    mutating func clear() { occupied = [false, false, false] }
}

extension BaseballDiceRules {

    /// What one at-bat did to the diamond.
    struct Advance: Equatable {
        var runs = 0
        var outs = 0
        /// True when the field out turned two, so the summary can say so.
        var isDoublePlay = false
        /// True when a deep out still brought a runner home.
        var isSacrificeFly = false
    }

    /// Moves the runners, and says how many scored and how many went out.
    ///
    /// A deep out scores a runner from third — the sacrifice fly. The design
    /// document did not say either way; scoring it matches baseball and gives
    /// the +7 to +9 band a purpose beyond being a near miss. It cannot score
    /// the third out's run, hence the outs check.
    static func advance(_ diamond: inout Diamond,
                        result: AtBatResult,
                        pitcherRoll: Int,
                        outs: Int) -> Advance {
        var effect = Advance()

        switch result {
        case .strikeout:
            effect.outs = 1

        case .deepOut:
            effect.outs = 1
            if diamond.occupied[2] && outs + 1 < outsPerHalfInning {
                effect.runs = 1
                effect.isSacrificeFly = true
                diamond.occupied[2] = false
            }

        case .fieldOut:
            // Ground-ball double play: a runner on first, fewer than two
            // outs, and an even pitcher roll. The pitcher's own die decides
            // it, which is the one place their roll matters after the
            // differential is read.
            if diamond.occupied[0] && outs < outsPerHalfInning - 1 && pitcherRoll % 2 == 0 {
                effect.outs = 2
                effect.isDoublePlay = true
                diamond.occupied[0] = false
            } else {
                effect.outs = 1
                effect.runs += forceRunners(&diamond)
            }

        case .walk:
            effect.runs += forceRunners(&diamond)
            diamond.occupied[0] = true

        case .single:
            if diamond.occupied[2] { effect.runs += 1 }
            diamond.occupied = [true, diamond.occupied[0], diamond.occupied[1]]

        case .double:
            if diamond.occupied[1] { effect.runs += 1 }
            if diamond.occupied[2] { effect.runs += 1 }
            diamond.occupied = [false, true, diamond.occupied[0]]

        case .triple:
            effect.runs += diamond.runnerCount
            diamond.occupied = [false, false, true]

        case .homeRun:
            effect.runs += diamond.runnerCount + 1
            diamond.clear()
        }

        return effect
    }

    /// Pushes only the runners who have nowhere to stand, and returns any
    /// that were forced home. First base is left for the caller to fill.
    private static func forceRunners(_ diamond: inout Diamond) -> Int {
        guard diamond.occupied[0] else { return 0 }
        var scored = 0
        if diamond.occupied[1] && diamond.occupied[2] {
            scored = 1
        } else if diamond.occupied[1] {
            diamond.occupied[2] = true
        } else {
            diamond.occupied[1] = true
        }
        diamond.occupied[0] = false
        return scored
    }
}

// MARK: - Match state

/// Everything a game of Baseball Dice is, between at-bats.
struct BaseballDiceState: Codable, Equatable {

    /// 3, 6 or 9 — chosen at setup.
    var innings: Int

    /// One-based. Goes past `innings` when a tie forces extras.
    var inning: Int = 1

    /// Seat 0 bats the top half, seat 1 the bottom. Same as baseball: the
    /// home team bats last, which is what makes a one-run lead worth having.
    var isTopHalf: Bool = true

    var outs: Int = 0
    var diamond = Diamond()
    var runs: [Int] = [0, 0]

    /// Whose turn it is to bat. The other seat pitches.
    var battingSeat: Int { isTopHalf ? 0 : 1 }
    var pitchingSeat: Int { isTopHalf ? 1 : 0 }

    var isExtraInnings: Bool { inning > innings }

    /// True once the last scheduled half-inning is done and someone leads.
    var isDecided: Bool {
        inning > innings && runs[0] != runs[1] && isTopHalf
    }

    init(innings: Int) {
        self.innings = innings
    }

    /// Ends the half-inning and hands the bat over.
    mutating func endHalfInning() {
        outs = 0
        diamond.clear()
        if isTopHalf {
            isTopHalf = false
        } else {
            isTopHalf = true
            inning += 1
        }
    }
}
