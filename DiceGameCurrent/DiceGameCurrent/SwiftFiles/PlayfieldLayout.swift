import Foundation

/// Computes playfield world bounds and the matching camera orthographicScale
/// directly from the screen's aspect ratio — no SCNView/camera needs to
/// exist yet, which resolves a circular dependency in the original design:
/// DiceCameraFactory needed bounds to frame itself, but the old
/// PlayfieldBoundsCalculator needed an already-framed camera to unproject
/// through. Since we committed to an orthographic top-down camera, that
/// unprojection approach was solving a harder problem than necessary —
/// orthographic bounds have a simple closed-form relationship to
/// orthographicScale and aspect ratio (visible height = 2 x
/// orthographicScale, width = height x aspect), so we can compute
/// everything up front instead.
///
/// Width, not depth, is fixed as the reference dimension: phone screens
/// vary somewhat in exact aspect ratio, but portrait width is the more
/// consistently constrained dimension, and fixing it guarantees the
/// dice grid's column spacing is always safe regardless of device —
/// depth (rows) just gets more or less room on taller/shorter phones,
/// which DiceSpawnPattern already adapts to.
enum PlayfieldLayout {

    struct Result {
        let bounds: (x: ClosedRange<Float>, z: ClosedRange<Float>)
        let orthographicScale: Double
    }

    /// targetWorldWidth is a design choice, not derived from the device.
    /// Increased from 6.0 to 10.0 as part of pushing for more visibly
    /// energetic rolls without raising raw impulse further — the actual
    /// tunneling-safety math showed current impulse values are already
    /// 17-30x past a safe margin for the floor collider, so more force
    /// risks dice glitching through geometry rather than looking more
    /// lively. A bigger playfield gives the same velocity more real
    /// distance to travel and more room to collide with other dice before
    /// hitting a wall, which reads as "more energetic" without touching
    /// the part of the system that's already at its practical ceiling.
    static func compute(
        screenAspectRatio: Float, // view width / view height
        targetWorldWidth: Float = 10.0
    ) -> Result {
        let width = targetWorldWidth
        let depth = width / screenAspectRatio

        let bounds: (x: ClosedRange<Float>, z: ClosedRange<Float>) = (
            x: -width / 2 ... width / 2,
            z: -depth / 2 ... depth / 2
        )

        // Inverse of: width = (2 x orthographicScale) x aspect
        let orthographicScale = Double(width / (2 * screenAspectRatio))

        return Result(bounds: bounds, orthographicScale: orthographicScale)
    }

    // MARK: Staying right when the window changes size

    /// **The arena depends on the view's SHAPE, never on its size.** Read
    /// `compute` above: `targetWorldWidth` is a design constant, and both
    /// the bounds and the camera scale come from it and the aspect ratio
    /// alone. Nothing in there is in points.
    ///
    /// That is what makes the next part small. `DiceSceneAssembler`
    /// derives the aspect once, at assembly, and `assembleIfReady` is
    /// guarded so a later layout pass does nothing — so a view that
    /// changes shape after assembly keeps walls and a camera built for the
    /// shape it used to be. A view that merely changes SIZE is already
    /// correct and needs nothing.
    ///
    /// The shape moves in two ways on the devices this ships to: dragging
    /// an iPad Split View divider, which more than doubles it (0.395 ->
    /// 0.919, drift 0.524), and folding an iPhone Duo, which barely moves
    /// it (0.996 -> 0.973, drift 0.024). Both figures are measured in
    /// `tools_bandlayout_verify.py`, across every size in its table.
    ///
    /// Six screens fill their region and so follow the window: Rolls,
    /// Jackpot, Hog, Three Thousand, F.Y.D. and Generals. The rest keep a
    /// square playfield, which is square at any size. The arena is
    /// re-fitted either way — see `DiceSceneAssembler.refit`, which is
    /// what makes "either way" affordable.
    ///
    /// How far the shape may move before the arena is re-fitted to it.
    ///
    /// This used to be `aspectRebuildThreshold`, and it used to be a
    /// judgement about which error a player would rather have. Re-fitting
    /// re-assembled the scene, which re-dealt the dice, so the number had
    /// to be wide enough that an iPhone Duo fold (drift 0.024) could not
    /// reach it while an iPad Split View drag (drift 0.524) still could.
    /// 0.10 sat between them.
    ///
    /// `DiceSceneAssembler.refit` swaps the arena node and leaves the dice
    /// where they stand, so nothing is lost by re-fitting and there is no
    /// trade left to judge. What remains is only this: below some movement
    /// the walls are close enough that rebuilding them is work for
    /// nothing, and SwiftUI hands a view's size back many times during a
    /// layout pass. 0.005 is under a tenth of the smallest real change
    /// either device makes and well over the rounding in a view's bounds.
    static let aspectRefitThreshold: Float = 0.005

    static func aspect(of size: CGSize) -> Float {
        Float(size.width / max(size.height, 1))
    }

    /// Whether the arena was built for a different shape.
    ///
    /// Nil means nothing has been assembled yet, which is not a refit.
    static func needsRefit(built: Float?, now: Float) -> Bool {
        guard let built else { return false }
        return abs(now - built) > aspectRefitThreshold
    }
}

/// Single definition of the playfield rim, shared by the visible walls
/// (DiceSceneEnvironment.addWalls) and the physics colliders
/// (DicePlayfieldPhysics.makeContainer).
///
/// These were previously two independent sets of numbers, and they drifted:
/// widening the visible rim inward moved the wood 0.24 units into the play
/// area while the colliders stayed on the original bounds, so dice bounced
/// off thin air and visually sank into the frame. Deriving both from the
/// values here makes that class of mismatch impossible.
enum PlayfieldRim {

    /// Thickness of the visible wooden frame.
    static let visualThickness: Float = 0.30

    /// How far the frame's outer edge sits OUTSIDE the nominal bounds.
    /// Small, so the rim reads as sitting on the table's edge.
    static let outwardOverhang: Float = 0.06

    /// How far the frame's inner face intrudes INTO the nominal bounds.
    /// This is the number both the walls and the colliders align to — it's
    /// the real edge of the playable surface.
    static var innerInset: Float { visualThickness - outwardOverhang }

    /// Centre offset for a collider, measured OUTWARD from the nominal
    /// bound, such that its inner face lands exactly on `innerInset`.
    /// Colliders stay thick (see DicePlayfieldPhysics) for tunneling
    /// safety, so this offset keeps that thickness entirely behind the
    /// visible surface.
    static func colliderCentreOffset(thickness: Float) -> Float {
        thickness / 2 - innerInset
    }

    /// Fraction of the playfield's world width that one copy of the wood
    /// texture spans when tiled across the walls (DiceSceneEnvironment.
    /// addWalls, via its world-position-derived UV). DiceScoreBar's header
    /// background is painted with the same fraction of its own on-screen
    /// width, rather than stretching one copy across the whole bar —
    /// that's what keeps the plank pitch continuous across the seam
    /// between the header and the walls instead of jumping to a different
    /// scale right where they meet.
    /// Raised from 0.4 with the move to three boards. At the old value five
    /// planks landed at about 2% of the screen each, which reads as veneer;
    /// this puts a board at a size you could believe someone planed.
    static let woodTileFraction: Float = 0.75
}

/// Vertical containment shared between the camera (DiceCameraFactory), the
/// invisible ceiling collider (DicePlayfieldPhysics), and
/// DiceRollController's containment safety net — all three need to agree on
/// how high the play area extends.
///
/// Without any ceiling at all, nothing stops a die from climbing arbitrarily
/// high above the floor — the side walls are tall enough to block any
/// sideways escape at any height, so an unbounded top never let a die leave
/// the playfield horizontally, but it left one real way out: gaining enough
/// height (e.g. an energetic multi-die collision on top of an already-
/// energetic bounce) closes the distance to the top-down camera itself. The
/// camera's zNear plane clips anything closer than 0.1 units away, so a die
/// climbing past roughly (cameraHeight - 0.1) simply vanishes — which reads
/// exactly like "the die left the rolling area through the ceiling."
///
/// ceilingHeight is set far below that camera-clipping threshold, and the
/// number that actually decides it is the oversized die's room to turn
/// over — see `PlayfieldVerticalBounds.ceilingHeight`. Two other numbers
/// it has to respect, and the one it has had to give up:
///
/// - The STACKING threshold, i.e. the lowest a stacked die's center could
///   possibly be. The floor collider is a 0.7-thick box CENTERED on
///   floorY (see DicePlayfieldPhysics.makeContainer), so a resting die's
///   center actually sits at floorY + 0.35 (the floor's own half-
///   thickness) + its own half-height, not floorY + half-height alone.
///   With the smallest dice at ~0.5 half-height (targetSize is normalized
///   to ~1 world unit per DieMeshLibrary) resting at ~0.85, a second one
///   stacked on top needs its own center at roughly 0.85 + 0.5 (the
///   bottom die's remaining half) + 0.5 (its own half) ≈ 1.85. Below
///   that, in TERMS OF WHAT THE CEILING BLOCKS: a die's center can only
///   rise to (ceilingHeight - 0.35, the ceiling's own half-thickness -
///   its own half-height), so for the smallest, easiest-to-lift dice
///   (~0.5 half-height) to never reach 1.85, ceilingHeight must stay
///   below roughly 2.7.
/// - Spawn clearance: DicePoolLifecycleController positions the initial
///   15-die pyramid with its highest slot at (baseHeight + 2 stagger
///   tiers), and the pool ALWAYS includes one 1.5x-oversized die
///   (DicePoolSceneBuilder.oversizeMultiplier) with a ~0.75 half-height —
///   that combination has to fit entirely below the ceiling's own
///   underside, or the very first frame after spawn overlaps a static
///   collider and the physics solver violently ejects the die. With
///   DiceSpawnPattern's current baseHeight (1.0) and stagger (0.05/tier),
///   that highest point is ~1.85, so ceilingHeight needs to clear
///   1.85 + 0.35 (its own half-thickness) with a real margin — comfortably
///   satisfied above roughly 2.4.
///
/// Those two left a (2.4, 2.7) window, and the lid sat at 2.5 inside it
/// while the anti-stacking job was the reason it was low. Tumbling room
/// has since taken that window away: the oversized die needs 2.598 of
/// clear air and the lid is at 3.7, well above the top of it.
///
/// The upper bound was never the real guarantee against a stack, which is
/// what makes it affordable to lose. It was not airtight even at 2.5 —
/// an idealized stack would have needed a tighter lid than spawn
/// clearance allows — and DiceRollController's reactive anti-stacking
/// (attemptRollOff during a roll, and resolveStacking's final geometric
/// separation pass, whose own doc comment guarantees "a die physically
/// cannot be above another one" once a roll settles) is the absolute one.
/// What the lid still does is cap the vertical runway a stack would have
/// to be built in, at 3.7 against the unbounded version's 15.
///
/// Note that the stacking bullet above gets the half-thicknesses right.
/// The clearance arithmetic that replaced this window did not, for one
/// commit, and it is the same arithmetic — a collider's surface is half a
/// thickness off its centre, in both directions.
enum PlayfieldVerticalBounds {
    /// Camera height above the floor.
    static let cameraHeight: Float = 15

    /// How thick the floor and ceiling colliders are.
    ///
    /// It lives here rather than in `DicePlayfieldPhysics`, which builds
    /// them, because the clearance below is the only arithmetic that
    /// cares — and reading a copy of this number was how that arithmetic
    /// went wrong once. See `ceilingHeight`.
    static let colliderThickness: Float = 0.7

    /// Height of the invisible ceiling collider above the floor.
    ///
    /// **3.7. A die tumbles in the gap between two SURFACES, not between
    /// two centres, and 3.0 confused the two.**
    ///
    /// A tumbling cube sweeps a sphere of its own body diagonal: side x
    /// root three. For the 1.5x die that is 2.598, and it needs that much
    /// clear air to rotate through any axis without one end of it
    /// striking something. Every other die fits easily: 1.992 for the
    /// largest normal one, 1.732 for a standard, 1.472 for the smallest.
    ///
    /// The mistake is in what the 2.598 was compared against. Both lids
    /// are `colliderThickness` boxes CENTRED on their height, so the
    /// floor's upper surface is half a thickness up and the ceiling's
    /// underside is half a thickness down. At a lid of 3.0 the die had
    /// 3.0 - 0.7 = 2.300 of air, not 3.0 — still three tenths short of
    /// turning over, which is why the big die went on sliding after the
    /// lid was raised from 2.5. It is the same error as reading a
    /// half-diagonal for a full one, one level further out.
    ///
    /// So the requirement is on the GAP: sweep + both half-thicknesses =
    /// 3.298 at the lid's centre, and 3.7 is that with 15% of headroom on
    /// the sweep. `tools_impulse_verify.py` now subtracts the thickness
    /// before comparing, so the check measures the air and not the
    /// coordinate.
    ///
    /// Raising the lid costs nothing visible. The camera is orthographic,
    /// so a die at 3.7 is drawn exactly the size it is at 0.5 — this
    /// cannot change how the tray reads. It costs a little airtime, which
    /// the energy bleed absorbs, and it makes the ceiling SAFER rather
    /// than less safe: a die arrives at a higher lid having spent more of
    /// its climb against gravity, so it hits it slower.
    ///
    /// What it does cost is the ceiling's second job. The window argued
    /// for above wanted the lid under about 2.7 so a two-high stack could
    /// not fit beneath it; that was already given up at 3.0, and this
    /// gives up more of it. `DiceRollController.resolveStacking` is the
    /// actual guarantee — it separates stacked dice geometrically before
    /// a roll is allowed to end — and the lid is only ever an extra
    /// discouragement.
    static let ceilingHeight: Float = 3.7
}


// MARK: - The three bands a game screen is split into

/// Header, square scene, button band — the split every game makes.
///
/// It was made eight times, separately, with three different header
/// fractions and a `minButtonHeight` of 100 typed into each one. Three
/// more screens — Boneheads, Royal UR, Baseball Dice — fix their button
/// band outright at 100, 104 and 96.
///
/// Nothing checked any of them at any size. That matters because the band
/// has to hold a known stack of things, and the number guarding it was a
/// round figure that happened to be big enough: the content comes to 95
/// points, Baseball's band is 96, and the margin went from 7 points to 1
/// when the stack spacing in `TurnActionBar` moved from 2 to 8 to keep the
/// button's shadow off its caption. Nothing noticed, because there was
/// nothing to notice with.
///
/// So the arithmetic lives here once, the floor is summed from its own
/// parts rather than typed, and `tools_bandlayout_verify.py` walks it
/// across every size iOS can hand the app.
///
/// `PlayfieldLayout` above is the same idea for the 3D arena — a size in,
/// a measurement out, no view required — which is why this sits beside it
/// rather than in a file of its own.
enum GameBandLayout {

    // MARK: What the button band holds

    /// `.padding(.vertical, 12)`, top and bottom, on the action bar.
    static let bandPadding: CGFloat = 12

    /// The roll button itself.
    static let buttonHeight: CGFloat = 48

    /// Between the button and its caption. The SAME expression the bars
    /// use, so the floor moves when the spacing does instead of being
    /// quietly eaten by it.
    static var captionGap: CGFloat { Elevation.lifted.offset + 2 }

    /// One line of the 12pt caption under the button.
    ///
    /// 15, which is 12 at Poppins' own line height of roughly 1.25. One
    /// line and not two: both bars cap the caption at a single line — see
    /// the note on Rolls' subtitle, which did not and could wrap on a
    /// narrow screen.
    static let captionLine: CGFloat = 15

    /// Everything above, summed. The band may not be shorter than this.
    static var buttonBandFloor: CGFloat {
        bandPadding * 2 + buttonHeight + captionGap + captionLine
    }

    // MARK: The split

    /// The header's share, per game. Boneheads wants a shorter one than
    /// Jackpot, so the fraction stays the caller's business — only the
    /// arithmetic is shared.
    static func header(in size: CGSize, fraction: CGFloat) -> CGFloat {
        size.height * fraction
    }

    /// The square playfield: as wide as the screen, or as tall as what is
    /// left once the header and the button band have theirs.
    ///
    /// Square because the arena and its orthographic camera are built
    /// square — which is also why a wider screen buys the scene nothing,
    /// and why landscape costs these games height for width they cannot
    /// spend.
    /// It used to take whatever was left after the header and the band's
    /// FLOOR, which is why the band grew instead of the scene: on an
    /// iPhone 14 the scene capped out at its 393pt width and the other
    /// 237 points — 31% of the screen — all went to the button band. On
    /// an iPad in Slide Over it was 600 points, 54%. The band was never
    /// asking for that space; it was the only thing left holding it.
    ///
    /// Staying square also keeps the arena still through a window
    /// resize: `PlayfieldLayout.compute` takes an aspect ratio and nothing
    /// else, and a square is a square at any size. The screens that fill
    /// their region instead are re-fitted when the shape moves — see
    /// `needsRefit`.
    static func scene(in size: CGSize, fraction: CGFloat) -> CGFloat {
        min(size.width, max(size.height - header(in: size, fraction: fraction)
                            - buttonBandFloor, 0))
    }

    /// The region the playfield sits in. The timber well fills THIS, and
    /// the square scene is centred inside it — so where the screen is
    /// taller than the scene can use, what shows above and below is tray
    /// rather than a gap.
    static func sceneRegion(in size: CGSize, fraction: CGFloat) -> CGFloat {
        max(size.height - header(in: size, fraction: fraction)
            - bandShare(in: size, fraction: fraction), 0)
    }

    /// The button band: what is left over, but never more than a fifth.
    ///
    /// **A CAP, not a share, and that is the whole change.** The band used
    /// to take the remainder outright, which is how a screen too tall for
    /// its own square playfield ended up with a third of itself given to
    /// one button:
    ///
    ///     iPhone 14          17 / 52 / 31   ->   17 / 63 / 20
    ///     iPhone 15 Pro Max  17 / 51 / 32   ->   17 / 63 / 20
    ///     iPad Slide Over    17 / 29 / 54   ->   17 / 63 / 20
    ///     iPad mini          17 / 67 / 16   ->   17 / 67 / 16   unchanged
    ///     iPad Air           17 / 71 / 12   ->   17 / 71 / 12   unchanged
    ///
    /// The iPad rows are the point of writing it as a cap. Those layouts
    /// were signed off as they are, and their band is already under a
    /// fifth — so the clamp never binds and not one point moves. Only the
    /// screens that were actually broken change.
    ///
    /// The floor still wins underneath it, because a band that cannot hold
    /// a 48pt button and its caption is not a band.
    static func bandShare(in size: CGSize, fraction: CGFloat) -> CGFloat {
        let leftover = size.height - header(in: size, fraction: fraction)
            - scene(in: size, fraction: fraction)
        guard isTall(size) else { return max(leftover, buttonBandFloor) }
        return min(max(leftover, buttonBandFloor),
                   max(size.height * bandCeiling, buttonBandFloor))
    }

    /// Whether the window is much taller than it is wide.
    ///
    /// **This is what stops the fix reaching a screen that was not
    /// broken.** The whole problem is a window too tall for its own width:
    /// the playfield can only be as wide as the screen, so on a tall one
    /// every point of height past that fell to the button band. A window
    /// that is nearly as wide as it is tall never had the problem — its
    /// band was already small and its playfield already large.
    ///
    /// Measured, as height over width:
    ///
    ///     iPad Pro            1.31
    ///     iPad Air            1.41     full-screen iPads, all below
    ///     iPad mini           1.49
    ///     -------------------------   1.60
    ///     iPhone SE           1.71
    ///     iPhone 14           1.93     phones, all above
    ///     iPhone 15 Pro Max   1.95
    ///     iPad Slide Over     3.47     an iPad, and the worst case of all
    ///
    /// The gap either side of 1.60 is wide, and the Slide Over row is why
    /// this is about SHAPE and not about idiom: it is an iPad window and
    /// it had a 600-point button band, more than half the screen. A rule
    /// keyed on "is this an iPad" would have left it there.
    ///
    /// Below the line the band takes the remainder exactly as it always
    /// did, so the layouts reviewed on a full-screen iPad are the ones
    /// that ship.
    static func isTall(_ size: CGSize) -> Bool {
        size.width > 0 && size.height / size.width > tallAspect
    }

    static let tallAspect: CGFloat = 1.60

    /// The most of the screen the button band may hold.
    ///
    /// A tenth — and on a phone it never actually gets there, because
    /// `buttonBandFloor` binds first. 95 points is a 48pt button, its
    /// caption, the gap that keeps the button's shadow off it and the
    /// padding around the lot, so it is the smallest a band can be and
    /// still be one:
    ///
    ///     iPhone SE          95pt = 17.3%
    ///     iPhone 14          95pt = 12.5%
    ///     iPhone 15 Pro Max  95pt = 11.3%
    ///     iPad mini         111pt = 10.0%   the ceiling, at last
    ///
    /// Which is the honest answer to "as small as 10%": on the screens
    /// that prompted it, the content is the limit rather than the share.
    static let bandCeiling: CGFloat = 0.10

    /// Whatever the scene did not take. Never below `buttonBandFloor`,
    /// because the scene gives way first.
    static func buttonBand(in size: CGSize, fraction: CGFloat) -> CGFloat {
        bandShare(in: size, fraction: fraction)
    }

    /// The header fraction the alternating games share.
    ///
    /// Five screens had the literal `0.17` written three times each — the
    /// same number in fifteen places, and no way to change it without
    /// finding all of them. Free Roll is the exception and still passes its
    /// own, because its header genuinely moves when the totals panel opens.
    /// Still 0.17, deliberately. Raising it to a fifth would have matched
    /// the band's ceiling and looked tidier in this file — and it would
    /// have moved the iPad, whose layout was reviewed on the device and
    /// signed off. The header is the one band with real content in it, so
    /// it is not where slack belongs anyway.
    static let scoreboardFraction: CGFloat = 0.17

    // MARK: What the scoreboard holds
    //
    // The numbers `MatchScoreboard` is actually built from, stated here
    // rather than there, because the header is sized in this file and the
    // thing it has to hold is described in that one. Four seats on two
    // rows is the case where the two have to agree: a strip that wants
    // 167pt inside a header given 113 does not fail, it draws over the
    // tray below it — a ZStack does not clip — and nothing in the sweep
    // was looking. `tools_bandlayout_verify.py` reads these.

    /// The seat tile's two lines: the name and the score.
    static let scoreboardNameFont: CGFloat = 11
    static let scoreboardScoreFont: CGFloat = 22

    /// Poppins' own line box, ascent plus descent, as a multiple of the
    /// point size. Measured off the TTF: 1050 and 350 against a 1000 em.
    static let scoreboardLineFactor: CGFloat = 1.4

    /// `VStack(spacing: 1)` inside a tile, `.padding(.vertical, 4)` round
    /// it, `VStack(spacing: 4)` between the strip's own rows, and
    /// `.padding(.vertical, 6)` round the lot.
    static let scoreboardTileGap: CGFloat = 1
    static let scoreboardTilePadding: CGFloat = 4
    static let scoreboardRowGap: CGFloat = 4
    static let scoreboardPadding: CGFloat = 6

    /// The round counter above the seats and the status line below them.
    /// Both are optional per game; both are assumed present here, because
    /// a header that only fits while a game happens not to show its
    /// subtitle is a header that overflows the first time it does.
    static let scoreboardRoundFont: CGFloat = 12
    static let scoreboardSubtitleFont: CGFloat = 11

    /// One seat tile: name, score, and the padding round them.
    static var scoreboardTile: CGFloat {
        (scoreboardNameFont + scoreboardScoreFont) * scoreboardLineFactor
            + scoreboardTileGap + scoreboardTilePadding * 2
    }

    /// How many rows of seat tiles a given number of seats takes.
    ///
    /// Two only at exactly FOUR. Three seats in a 2x2 is a grid with a
    /// hole in it, which reads as a missing player rather than as a
    /// layout; and three tiles across are 110.3pt on the narrowest phone,
    /// comfortably wider than the 75pt a twelve-character name sets at.
    /// Four across are 80.2pt, which is where the names start shrinking —
    /// see MatchSetup.maxSeats, measured to exactly that limit.
    static func scoreboardRows(seats: Int) -> Int {
        seats == 4 ? 2 : 1
    }

    /// The height the strip's content needs, for that many seats.
    static func scoreboardHeight(seats: Int) -> CGFloat {
        let rows = CGFloat(scoreboardRows(seats: seats))
        let tiles = rows * scoreboardTile + (rows - 1) * scoreboardRowGap
        return scoreboardPadding * 2
            + scoreboardRoundFont * scoreboardLineFactor + scoreboardRowGap
            + tiles
            + scoreboardRowGap + scoreboardSubtitleFont * scoreboardLineFactor
    }

    /// The header's share for a game that can seat four.
    ///
    /// The fixed 0.17 holds one row everywhere — 113pt against 107 on the
    /// narrowest phone, which is thin but real. It does not hold two: four
    /// seats want 167pt, and no iPhone's 17% reaches that. So the share is
    /// the LARGER of the two, which leaves every signed-off layout exactly
    /// where it was — at two and three seats this returns 0.17 at every
    /// size the app meets, and on an iPad it returns 0.17 at four as well,
    /// because 17% of 1133 is already 193.
    ///
    /// What the extra costs is tray, not playfield: in portrait the scene
    /// is capped by WIDTH — see `scene` — so the points come out of the
    /// timber showing above and below a square that was not going to grow.
    /// The two shapes that are height-bound instead, the folded Duo and a
    /// landscape iPad mini, pay about 45pt of playfield and stay well
    /// clear of what the tray needs.
    static func scoreboardFraction(in size: CGSize, seats: Int) -> CGFloat {
        guard size.height > 0 else { return scoreboardFraction }
        return max(scoreboardFraction, scoreboardHeight(seats: seats) / size.height)
    }

    /// All three band heights at once.
    ///
    /// The five scoreboard games computed the same three values from the
    /// same fraction in the same order, four lines apiece. They each ask one
    /// question — how do I divide this screen — so there is one call that
    /// answers it.
    struct Bands {
        let header: CGFloat
        /// The 60% the tray fills.
        let sceneRegion: CGFloat
        /// The largest SQUARE the region could hold. Kept because the
        /// band's own arithmetic is written against it — the scene that
        /// actually draws fills `sceneRegion`.
        let scene: CGFloat
        let buttonBand: CGFloat
    }

    /// The bands for a game whose seat count decides its header.
    ///
    /// Separate from the overload below rather than a defaulted argument,
    /// because the three games that can seat four are the only callers:
    /// the other four scoreboard games are two-player by their own
    /// `localSeats` and have nothing to ask.
    static func bands(in size: CGSize, seats: Int) -> Bands {
        bands(in: size, fraction: scoreboardFraction(in: size, seats: seats))
    }

    static func bands(in size: CGSize,
                      fraction: CGFloat = scoreboardFraction) -> Bands {
        Bands(header: header(in: size, fraction: fraction),
              sceneRegion: sceneRegion(in: size, fraction: fraction),
              scene: scene(in: size, fraction: fraction),
              buttonBand: buttonBand(in: size, fraction: fraction))
    }

    /// Whether a fixed band height still holds its content.
    ///
    /// For the three screens that set their own rather than taking the
    /// remainder. Following `GeneralsCardLayout.fits(in:)`, which is the
    /// one place in the app that already asked this question.
    static func fits(band: CGFloat) -> Bool {
        band >= buttonBandFloor
    }
}
