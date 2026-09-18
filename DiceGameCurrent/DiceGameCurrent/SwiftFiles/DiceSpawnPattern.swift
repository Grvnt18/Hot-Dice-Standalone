import SceneKit

/// Predefined, deterministic spawn slot layout: a fixed triangular
/// arrangement of 5 rows containing 5, 4, 3, 2, and 1 dice respectively
/// (totaling exactly 15, matching the pool size) — a bowling-pin/pyramid
/// shape rather than a plain grid. The slot coordinates are the SAME every
/// time for given bounds — this is what guarantees zero spawn overlap,
/// since spacing is established by construction, not by chance.
///
/// What IS randomized is which physical die lands in which slot — see
/// DicePoolLifecycleController.setupPool, which shuffles the dice array
/// before zipping it with these fixed positions. So a player never sees
/// the same "shape" of layout twice in terms of color placement, while the
/// underlying pattern (and its collision-free guarantee) never changes.
enum DiceSpawnPattern {

    /// Row sizes from back to front. Cell width is derived from the widest
    /// row (5) so spacing stays consistent across the whole pattern;
    /// narrower rows are horizontally centered within that same span
    /// rather than stretched to fill the full width, which is what
    /// actually produces the triangle/pyramid look.
    private static let rowCounts = [5, 4, 3, 2, 1]

    static func positions(
        count: Int,
        bounds: (x: ClosedRange<Float>, z: ClosedRange<Float>),
        baseHeight: Float
    ) -> [SCNVector3] {
        guard count > 0 else { return [] }

        // Spawn inside the RIM, not the nominal bounds. The wooden frame
        // intrudes PlayfieldRim.innerInset into the playfield, and with the
        // widened rim the outermost spawn slot left only 0.01 units of
        // clearance for a 1.5x oversized die — close enough that it could
        // spawn intersecting the wall and be violently ejected by the
        // solver. Insetting here keeps every slot genuinely inside the
        // playable surface.
        let rim = PlayfieldRim.innerInset
        let usable = (
            x: (bounds.x.lowerBound + rim)...(bounds.x.upperBound - rim),
            z: (bounds.z.lowerBound + rim)...(bounds.z.upperBound - rim)
        )
        // Intentional parameter shadowing (same idiom as `guard let x = x`)
        // so every slot calculation below operates on the usable area
        // without needing to be rewritten.
        let bounds = usable

        let width = bounds.x.upperBound - bounds.x.lowerBound
        let depth = bounds.z.upperBound - bounds.z.lowerBound
        let centerX = (bounds.x.lowerBound + bounds.x.upperBound) / 2

        let maxRowCount = rowCounts.max() ?? 1
        let cellWidth = width / Float(maxRowCount)
        let cellDepth = depth / Float(rowCounts.count)

        var positions: [SCNVector3] = []

        for (rowIndex, rowCount) in rowCounts.enumerated() {
            guard positions.count < count else { break }

            let z = bounds.z.lowerBound + cellDepth * (Float(rowIndex) + 0.5)
            let rowWidth = cellWidth * Float(rowCount)
            let rowStartX = centerX - rowWidth / 2

            for slot in 0..<rowCount {
                guard positions.count < count else { break }

                let x = rowStartX + cellWidth * (Float(slot) + 0.5)
                // Small DETERMINISTIC height stagger (cycles through 3
                // fixed tiers by slot index) so all dice don't land in the
                // exact same instant — not random, so it stays part of the
                // fixed pattern rather than reintroducing per-spawn
                // variance.
                //
                // Reduced from 0.15 to 0.05 per tier alongside introducing
                // the low anti-stacking ceiling (PlayfieldVerticalBounds.
                // ceilingHeight, see its doc comment for the full
                // derivation) — that ceiling has to sit low enough to be a
                // real anti-stack constraint AND high enough to clear every
                // spawned die's starting position (including the one
                // oversized, 1.5x die every round always has — see
                // DicePoolSceneBuilder.oversizeMultiplier), and the old
                // 0.15 stagger made that window too narrow to have any
                // comfortable safety margin either way. This still spreads
                // spawns across 3 distinct heights, just over a smaller
                // range.
                let y = baseHeight + Float(positions.count % 3) * 0.05

                positions.append(SCNVector3(x, y, z))
            }
        }

        // Defensive fallback if this is ever called with more than the 15
        // dice the fixed row layout accounts for — shouldn't happen given
        // the game's fixed pool size, but avoids silently dropping dice.
        while positions.count < count {
            let z = bounds.z.upperBound - cellDepth * 0.5
            let y = baseHeight + Float(positions.count % 3) * 0.05 + 0.5
            positions.append(SCNVector3(centerX, y, z))
        }

        return positions
    }
}
