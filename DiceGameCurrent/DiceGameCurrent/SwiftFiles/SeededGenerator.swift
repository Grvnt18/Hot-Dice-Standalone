import Foundation

/// Deterministic pseudo-random generator shared by every game in the suite.
///
/// Two reasons this exists rather than `SystemRandomNumberGenerator`:
///
/// 1. **Auditability.** A turn travels between devices as a message. If the
///    sender's device were the only thing that ever saw the dice, a modified
///    client could simply claim whatever result it liked. Carrying the seed
///    in the payload lets the receiver replay the exact same sequence and
///    confirm the sender's claimed results — cheating then requires forging
///    a seed that happens to produce the result you want, which is far more
///    work than editing a number.
/// 2. **Payload size.** A turn can be described as "seed + which dice were
///    kept" instead of a full listing of every die's face.
///
/// `SystemRandomNumberGenerator` gives neither: it cannot be seeded, so the
/// same inputs produce different output on every run and on every device.
///
/// **This does not apply to Rolls.** Rolls reads each die's value from
/// whichever face physically lands up in SceneKit (see
/// `DiceRollController`'s face-snap callback), not from a generator.
/// Floating-point physics is not reproducible across devices or OS
/// versions, so a Rolls result can never be replayed from a seed — its
/// payload carries the landed values outright. Seeding still governs the
/// parts of Rolls that *are* generated: which colorway gets which die type
/// when a round is built. Every other game in the suite is pure dice
/// arithmetic and is fully replayable.
struct SeededGenerator: RandomNumberGenerator {

    private var state: UInt64

    // The seed is used exactly as given. SplitMix64 has no bad seeds — its
    // state is an additive counter, so seed 0 produces a stream as good as
    // any other (checked: 20,000 distinct values in 20,000 draws, uniform to
    // within noise across deciles). An earlier version remapped 0 to a fixed
    // constant, which would have silently diverged from the texture
    // generator this type replaced.
    init(seed: UInt64) {
        self.state = seed
    }

    /// SplitMix64. Chosen over the alternatives because it is a fixed,
    /// published constant sequence with no platform-dependent behaviour —
    /// the whole point here is that two different devices agree exactly.
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform `0..<1`.
    ///
    /// Kept bit-for-bit as `LowPolyTextures` had it — the low 11 bits are
    /// dropped and the rest scaled by 2^-53, which is the standard way to
    /// fill a Double's mantissa exactly once. The texture art is generated
    /// from this, so any change to the arithmetic would change how the wood
    /// and floor look.
    mutating func nextUnit() -> Double {
        Double(next() >> 11) * (1.0 / 9007199254740992.0)
    }

    // MARK: - Deliberately not using the standard library's helpers

    // `Int.random(in:using:)` and `Collection.shuffled(using:)` consume the
    // generator, but the standard library does not promise *how many* words
    // they draw or in what order — that is an implementation detail which
    // has changed between Swift releases. Relying on it would mean two
    // devices on different Swift versions could disagree about what the
    // "same" seed produces, which defeats the entire purpose. The two
    // routines below are written out so the sequence is ours and is stable.

    /// Uniform integer in `0..<upperBound`, via rejection sampling so the
    /// result is unbiased (a plain `% upperBound` favours the low values
    /// whenever `upperBound` does not divide 2^64 evenly).
    mutating func nextInt(upperBound: Int) -> Int {
        precondition(upperBound > 0, "upperBound must be positive")
        let bound = UInt64(upperBound)
        // Largest multiple of `bound` that fits in UInt64; draws at or above
        // it are discarded rather than folded back in.
        let limit = UInt64.max - (UInt64.max % bound)
        var draw = next()
        while draw >= limit {
            draw = next()
        }
        return Int(draw % bound)
    }

    /// A single die roll, `1...sides`.
    mutating func roll(sides: Int) -> Int {
        nextInt(upperBound: sides) + 1
    }

    /// `count` independent die rolls.
    mutating func roll(count: Int, sides: Int) -> [Int] {
        (0..<count).map { _ in roll(sides: sides) }
    }

    /// Fisher-Yates, written out for the stability reason above.
    mutating func shuffled<T>(_ source: [T]) -> [T] {
        var result = source
        guard result.count > 1 else { return result }
        for i in stride(from: result.count - 1, to: 0, by: -1) {
            let j = nextInt(upperBound: i + 1)
            if i != j { result.swapAt(i, j) }
        }
        return result
    }
}

// MARK: - Seed creation

extension SeededGenerator {

    /// A fresh unpredictable seed, for starting a new game.
    ///
    /// This is the one place the suite *wants* real entropy: the seed itself
    /// must not be guessable, or an opponent could predict the whole game.
    /// Everything downstream of it is then deterministic.
    static func newSeed() -> UInt64 {
        var system = SystemRandomNumberGenerator()
        return system.next()
    }
}
