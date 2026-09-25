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
/// equilibrium of Patient 36% / Contact 26% / Power 38% for the batter
/// against Fastball 35% / Changeup 34% / Slider 31% for the pitcher, worth
/// 0.105 runs an at-bat. Run value per at-bat, batter's gain:
///
///              Patient  Contact   Power
///   Fastball    +0.382   +0.044  -0.110
///   Changeup    -0.068   +0.319  +0.117
///   Slider      -0.018   -0.061  +0.330
///
/// Each pitch beats one swing, loses to another and ties the third, which is
/// what makes guessing worth doing.
///
/// That bottom-right corner used to read +0.002, and it was the one number
/// in the table that did not work: the Fastball did not punish the Power
/// Swing, it merely failed to reward it. So Power was the safe pick at 43%
/// of the mix and Breaking Ball, which Power answers, was played 15% — the
/// cycle was open. Giving the Fastball's unfavoured pair a second pitcher
/// die closed it: across the three swings the spread of run value fell from
/// 0.048 to 0.011, and the widest gap in either side's equilibrium mix from
/// 34 points to 12.
enum BaseballDiceRules {

    static let outsPerHalfInning = 3

    /// The three match lengths, and what they cost in at-bats.
    ///
    /// Measured at equilibrium play:
    ///
    ///   3 innings   2.8-2.8 runs    31 at-bats
    ///   6 innings   5.3-5.3 runs    59 at-bats
    ///   9 innings   7.9-7.9 runs    87 at-bats
    ///
    /// About 7% below the figures this shipped with, which is the price of
    /// the Fastball actually beating the Power Swing (see the note on the
    /// run-value table above). It moves the game toward a real score line
    /// rather than away from one.
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

    /// The bundled mark for this swing, shown on the selection card.
    ///
    /// Named for the case rather than carried as a second string per site,
    /// the way `CyberWeapon.iconName` already does it — so
    /// `tools_icons_verify.py` can harvest the names straight out of here.
    var iconName: String {
        switch self {
        case .patient: return "bb-patient"
        case .contact: return "bb-contact"
        case .power:   return "bb-power"
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
/// swing every time. Measured, that is 30.6 runs a game against 8.5 — the
/// figures behind this were taken before the Fastball's second pitcher die
/// and the ratio is what matters here, not the absolute.
///
/// So a style is a *mix*, not a pitch. The pitcher picks one for the
/// half-inning and the app draws the actual pitch from it each at-bat, which
/// keeps one hidden decision per half-inning while making the individual
/// pitch unknowable. Measured: 7.8 runs blind, and 14.3 as an
/// upper bound if the batter somehow read the style perfectly — against
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

    /// The bundled mark for this style, shown on the selection card.
    ///
    /// A style is a mix rather than a pitch, so it takes the mark of the
    /// pitch it throws most: the 60% entry in `weights`.
    var iconName: String {
        switch self {
        case .powerPitcher: return "bb-fastball"
        case .crafty:       return "bb-changeup"
        case .breakingBall: return "bb-slider"
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

    /// How many the pitcher throws. Two means keep the highest, the same
    /// way the batter's two work.
    var pitcherDice: Int = 1

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
            // The Fastball's unfavoured pair gets the pitcher a SECOND d12.
            //
            // d12 against d12 was a coin flip rather than a punishment —
            // worth +0.002 runs to the batter, so the Fastball did not
            // actually beat the Power Swing it is supposed to beat. That
            // made Power the safe swing at 44% of the equilibrium mix and
            // left Breaking Ball, which Power answers, played only 15%.
            //
            // Measured over every outcome: the swing spread falls from
            // 0.048 to 0.011 and the widest equilibrium mix gap from 34
            // points to 12 (pitcher 37/30/33, batter 36/26/38). It also
            // pulls this pair's extra-base hits into line with the other
            // two unfavoured pairs — 4.9%/4.2% doubles and triples down to
            // 2.8%/2.1% against their ~3.8%/~2.5% — which is what the
            // target table asks for and where the whole overshoot was.
            //
            // Giving all three unfavoured pairs a second die was tried
            // first and is the wrong change: it moves the swing spread the
            // wrong way, to 0.052, and costs 32% of all scoring.
            case .fastball: return Matchup(kind: .unfavored, batterSides: 12,
                                           batterDice: 1, pitcherSides: 12,
                                           pitcherDice: 2)
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
        let pitcherRolls: [Int]
        let result: AtBatResult

        /// True when a favoured swing rolled its die's maximum on both dice.
        let isJackpot: Bool

        var batterRoll: Int { batterRolls.max() ?? 0 }

        /// The pitcher's kept die — the highest, when there is more than
        /// one. Everything downstream reads this rather than the array,
        /// including the double play's even/odd test, so a second pitcher
        /// die changes what is rolled and not how it is read.
        var pitcherRoll: Int { pitcherRolls.max() ?? 0 }

        var differential: Int { batterRoll - pitcherRoll }
    }

    /// Reads a settled throw into an at-bat.
    ///
    /// The Double Max Jackpot overrides the table outright: two maximums on a
    /// favoured swing is a home run however the differential lands. It is the
    /// only way a Fastball-versus-Patient at-bat can leave the park at all,
    /// since that pairing's differential tops out at +7.
    static func atBat(pitch: Pitch, swing: Swing,
                      batterRolls: [Int], pitcherRolls: [Int]) -> AtBat {
        let matchup = matchup(pitch: pitch, swing: swing)
        let best = batterRolls.max() ?? 0
        let kept = pitcherRolls.max() ?? 0
        let jackpot = matchup.keepsHighest
            && batterRolls.count == matchup.batterDice
            && batterRolls.allSatisfy { $0 == matchup.batterSides }
        return AtBat(
            pitch: pitch,
            swing: swing,
            matchup: matchup,
            batterRolls: batterRolls,
            pitcherRolls: pitcherRolls,
            result: jackpot ? .homeRun : result(differential: best - kept),
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

        /// A deep out that ended the inning with a runner on third.
        ///
        /// The run does not count — the catch is the third out, which is
        /// how real baseball scores it — but a bare "Caught at the wall"
        /// is indistinguishable from a fault, and was read as one. The
        /// banner uses this to say why.
        var strandedOnThird = false
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
            if diamond.occupied[2] {
                if outs + 1 < outsPerHalfInning {
                    effect.runs = 1
                    effect.isSacrificeFly = true
                    diamond.occupied[2] = false
                } else {
                    effect.strandedOnThird = true
                }
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

    /// Runs by seat, by inning — the line score the board draws.
    ///
    /// `runs` is the two totals, which a grid of inning boxes has nothing
    /// to put in; this is what fills them. Extras append a column, so it
    /// is as long as the game turned out to be rather than as long as it
    /// was scheduled for.
    var lineScore: [[Int]] = [[], []]

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
        lineScore = [Array(repeating: 0, count: innings),
                     Array(repeating: 0, count: innings)]
    }

    /// Credits runs to the side at bat, in both places they are kept.
    ///
    /// One mutator rather than two assignments at the call site: the total
    /// and the line score are the same runs counted twice, and the way
    /// they drift apart is one of them being updated and the other not.
    mutating func score(_ count: Int) {
        guard count > 0 else { return }
        runs[battingSeat] += count
        extendLineScore()
        lineScore[battingSeat][inning - 1] += count
    }

    /// Grows both rows to cover the inning being played.
    ///
    /// Extras run past `innings`, and a half-inning can score before
    /// `endHalfInning` has had a chance to make room for it.
    private mutating func extendLineScore() {
        while lineScore[0].count < inning {
            lineScore[0].append(0)
            lineScore[1].append(0)
        }
    }

    /// Ends the half-inning and hands the bat over.
    mutating func endHalfInning() {
        outs = 0
        diamond.clear()
        // A half-inning that scored nothing still needs its zero, or the
        // board would show a blank box where a 0 belongs.
        extendLineScore()
        if isTopHalf {
            isTopHalf = false
        } else {
            isTopHalf = true
            inning += 1
        }
    }
}
