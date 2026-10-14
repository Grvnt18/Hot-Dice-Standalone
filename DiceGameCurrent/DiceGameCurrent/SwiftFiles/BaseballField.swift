import UIKit

/// The Baseball Dice playfield, drawn as a texture for the scene floor.
///
/// This is the Core Graphics port of `tools_baseball_field_preview.py`. The
/// preview exists because there is no renderer in the container this was
/// written in, and a field that looked wrong would otherwise only be found
/// on device — which is how the hub's collapsed tiles shipped.
///
/// **The constants below are the preview's, copied across.**
/// `tools_baseball_field_verify.py` reads both files and asserts they agree,
/// so the composition that was approved cannot drift from the one that
/// draws. Change a number here and that check fails until the preview
/// matches.
///
/// Coordinates are fractions of their own axis — `x` of the width, `y` of
/// the height — and radii are fractions of the WIDTH so circles stay round
/// on a portrait canvas. Using one axis for both is what squashed the first
/// portrait attempt.
enum BaseballField {

    // MARK: Palette

    /// The turf's default, used when nothing else is supplied.
    ///
    /// The pitch is the one floor in the suite the colour picker could not
    /// touch, because this surface ignored `ArenaStyle.surfaceColor`
    /// entirely. It follows the picker now — but only the TURF. The dirt,
    /// the chalk, the bases and the panel keep their own colours: a blue
    /// infield stops reading as a ballpark, and the ask was the green.
    static let grass = UIColor(hex: "#7BA07E")
    static let dirt = UIColor(hex: "#C9B18A")
    static let chalk = UIColor(hex: "#FFFFFF")
    static let baseWhite = UIColor(hex: "#F4F4F0")
    static let panel = UIColor(hex: "#111111")
    static let panelText = UIColor(hex: "#FFFFFF")
    static let cell = UIColor(hex: "#E9E9E9")

    /// The inning being played, and a recorded out. Both are read at a
    /// glance mid-turn, so both are warm against the panel's greys.
    static let live = UIColor(hex: "#F3D9A4")
    static let out = UIColor(hex: "#D9463E")

    /// The scoreboard's edge: hard outline, one-step bevel.
    ///
    /// The panel is Core Graphics drawn onto a texture rather than a
    /// SwiftUI view, so `PixelPanel` cannot be applied to it — only its
    /// recipe hand-ported. These are that recipe's three tones, named here
    /// so `tools_baseball_field_verify.py` can hold the port and the
    /// preview to the same numbers.
    ///
    /// `panelOutline` is `PixelPanel.outlineColor`'s value, written out
    /// rather than read across: that is a SwiftUI `Color` and this file
    /// works in `UIColor`, and a conversion here would be a second source
    /// of truth dressed up as a shared one.
    static let panelOutline = UIColor(hex: "#1A120D")
    static let panelBevelLit = UIColor(white: 1, alpha: 0.18)
    static let panelBevelShade = UIColor(white: 0, alpha: 0.28)

    /// The outline and bevel widths, as a fraction of the field width, so
    /// they scale with the texture exactly as every other constant here.
    static let panelOutlineW: CGFloat = 0.0035
    static let panelBevelW: CGFloat = 0.0035

    // MARK: Geometry

    static let home = CGPoint(x: 0.500, y: 0.800)
    static let first = CGPoint(x: 0.760, y: 0.665)
    static let second = CGPoint(x: 0.500, y: 0.530)
    static let third = CGPoint(x: 0.240, y: 0.665)

    static let mound = CGPoint(x: 0.500, y: 0.665)
    static let moundRadius: CGFloat = 0.078
    static let skinRadius: CGFloat = 0.330
    static let homeCircleRadius: CGFloat = 0.125
    static let pathWidth: CGFloat = 0.034
    static let baseSize: CGFloat = 0.034

    static let onDeckRadius: CGFloat = 0.072
    static let onDeckY: CGFloat = 0.930
    static let onDeckX: [CGFloat] = [0.150, 0.850]

    // MARK: The scoreboard

    static let boardX: CGFloat = 0.050
    static let boardY: CGFloat = 0.030
    static let boardW: CGFloat = 0.420

    /// The panel's height FOLLOWS its contents rather than being declared.
    ///
    /// The first version fixed it and positioned the grid rows downward from
    /// the top while positioning the outs row upward from the bottom — two
    /// origins growing toward each other, which met and overlapped by 9.5px.
    /// One origin makes that impossible, and `boardMetrics` is the one.
    static let boardPad: CGFloat = 0.014
    static let headHeight: CGFloat = 0.030
    static let gridGap: CGFloat = 0.024
    static let rowHeight: CGFloat = 0.034
    static let outsGap: CGFloat = 0.016
    static let outsHeight: CGFloat = 0.040

    struct BoardMetrics {
        let gridTop: CGFloat
        let rowsBottom: CGFloat
        let outsTop: CGFloat
        let height: CGFloat
    }

    static var boardMetrics: BoardMetrics {
        let gridTop = boardY + headHeight + gridGap
        let rowsBottom = gridTop + 2 * rowHeight
        let outsTop = rowsBottom + outsGap
        return BoardMetrics(
            gridTop: gridTop,
            rowsBottom: rowsBottom,
            outsTop: outsTop,
            height: (outsTop + outsHeight + boardPad) - boardY
        )
    }

    // MARK: Drawing

    /// Renders the pitch at `size`.
    ///
    /// No innings parameter: the scoreboard left this texture (see the note
    /// where it used to be drawn), and the grass does not care how long the
    /// game is. `renderScoreboard` draws only as many columns as the match
    /// has, which is where that rule now lives.
    static func render(size: CGSize, turf: UIColor = grass) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let cg = context.cgContext
            let w = size.width
            let h = size.height
            func px(_ value: CGFloat) -> CGFloat { value * w }
            func py(_ value: CGFloat) -> CGFloat { value * h }
            func point(_ p: CGPoint) -> CGPoint { CGPoint(x: px(p.x), y: py(p.y)) }

            // NO ANTIALIASING ANYWHERE ON THIS PITCH.
            //
            // The faceted surfaces were always hard-edged, but the chalk, the
            // foul lines, the batter's boxes, the mound and the bases are
            // drawn with CoreGraphics strokes and fills — so they came out
            // smooth, and they were the only smooth thing left once the dice,
            // the floor and the rim had all gone to a pixel grid. A soft
            // white line over hard-edged turf reads as vector art laid on top
            // of pixel art rather than as part of it.
            cg.setShouldAntialias(false)
            cg.interpolationQuality = .none

            // The clay and the chalk belong to the chosen colourway now.
            //
            // The turf already followed the picker; these two were fixed
            // (#C9B18A and pure white), so a blue table gave a tinted pitch
            // with a sand infield that answered to nothing. They are TINTED
            // TOWARD the swatch rather than derived from it: clay that is
            // literally a ramp off a green turf stops being clay, and the
            // dirt's job is to be a different material from the grass. A
            // partial blend keeps that job and still ties both to the table.
            let clayColour = tinted(dirt, toward: turf, amount: 0.35)
            let chalkColour = tinted(chalk, toward: turf, amount: 0.18)
            let baseColour = tinted(baseWhite, toward: turf, amount: 0.18)

            // The turf and the dirt are FACETED, not flat.
            //
            // Every other playfield in the suite is a low-poly surface, and
            // a pitch painted in two flat colours read as a different app.
            // The layout is untouched — the same diamond, the same circles,
            // the same measurements — and only what fills them changes.
            // The turf posterises to the floor's own four tones; the dirt
            // does NOT.
            //
            // That asymmetry is the whole point rather than an oversight.
            // The dirt is what makes the green read as grass — it is the
            // one surface on this pitch whose job is to be a different
            // material, and flattening it to four tones off its own base
            // narrows exactly the contrast that does that work. Same
            // argument that keeps the chalk, the bases and the panel off
            // the picker.
            let turfTexture = faceted(turf, size: size, seed: 771001,
                                      posterised: true)
            // Posterised like the turf. It was deliberately left smooth —
            // "the one surface on this pitch whose job is to be a different
            // material" — and that argument held while the dirt's contrast
            // against the grass was the only thing telling them apart. It
            // does not hold now: the clay is tinted toward the swatch, so the
            // two are told apart by hue as well, and being the single
            // continuous-tone surface on a pixel-art pitch cost more than the
            // contrast was worth.
            let clay = faceted(clayColour, size: size, seed: 771002,
                               posterised: true)

            turfTexture.draw(in: CGRect(origin: .zero, size: size))

            // Infield skin: a dirt disc around the mound with the grass
            // infield laid back over it, which is how the real shape is made.
            fill(cg, with: clay, size: size) {
                $0.addEllipse(in: circle(at: point(mound), radius: px(skinRadius)))
            }
            fill(cg, with: turfTexture, size: size) {
                $0.addPath(diamondPath(centre: mound, half: 0.190, in: size))
            }

            // Base paths, stroked along the diamond's edges — clipped to the
            // stroke rather than stroked flat, so the facets run through the
            // basepath the way they do through the skin around it.
            fill(cg, with: clay, size: size) { ctx in
                let bases = [home, first, second, third].map(point)
                ctx.addLines(between: bases + [bases[0]])
                ctx.setLineWidth(px(pathWidth))
                ctx.setLineJoin(.round)
                ctx.replacePathWithStrokedPath()
            }

            // Foul lines, running out past the corners.
            chalkColour.setStroke()
            cg.setLineWidth(px(0.008))
            for corner in [CGPoint(x: -0.05, y: 0.330), CGPoint(x: 1.05, y: 0.330)] {
                cg.move(to: point(home))
                cg.addLine(to: point(corner))
            }
            cg.strokePath()

            // Mound, its rubber, and the plate circle.
            fill(cg, with: clay, size: size) {
                $0.addEllipse(in: circle(at: point(mound), radius: px(moundRadius)))
            }
            chalkColour.setFill()
            cg.fill(CGRect(x: px(mound.x - 0.030), y: py(mound.y) - px(0.006),
                           width: px(0.060), height: px(0.012)))
            fill(cg, with: clay, size: size) {
                $0.addEllipse(in: circle(at: point(home), radius: px(homeCircleRadius)))
            }

            // Batter's boxes.
            chalkColour.setStroke()
            cg.setLineWidth(px(0.006))
            for side in [-1.0, 1.0] as [CGFloat] {
                let left = home.x + (side > 0 ? 0.028 : -0.076)
                cg.stroke(CGRect(x: px(left), y: py(home.y) - px(0.055),
                                 width: px(0.048), height: px(0.100)))
            }

            baseColour.setFill()
            for centre in [first, second, third] {
                cg.addPath(diamondPath(centre: centre, half: baseSize, in: size))
                cg.fillPath()
            }
            cg.addPath(platePath(in: size))
            cg.fillPath()

            // On-deck circles, which double as the two runner pools.
            for (index, x) in onDeckX.enumerated() {
                fill(cg, with: clay, size: size) {
                    $0.addEllipse(in: circle(at: CGPoint(x: px(x), y: py(onDeckY)),
                                             radius: px(onDeckRadius)))
                }
                draw(index == 0 ? "VISITORS" : "HOME",
                     centredAt: CGPoint(x: px(x), y: py(onDeckY) + px(0.082)),
                     size: px(0.026), colour: chalk.withAlphaComponent(0.9))
            }

            // The scoreboard is NOT drawn here. It has to change as runs
            // and outs come in, and this texture is rendered once from the
            // innings count alone — which is exactly why the board showed
            // an empty grid and three empty circles for a whole game.
            // `renderScoreboard` draws it onto its own plane instead, and
            // `BaseballScoreboard` repaints that after every at-bat.
        }
    }

    /// The scoreboard panel on its own, with the game's live state in it.
    ///
    /// Separate from `render` so it can be repainted cheaply: this is
    /// roughly 345x210 against the pitch's 820x1100, so a repaint per
    /// at-bat costs a fraction of re-rendering the floor — and the floor's
    /// material is owned by the scene assembler and not reachable from the
    /// screen anyway.
    ///
    /// `size` is the panel's own canvas, but every constant in this file is
    /// a fraction of the FIELD, so the drawing scales by the field size it
    /// was cut from and offsets by the panel's own corner. That way one set
    /// of constants describes both, and the panel cannot drift from the
    /// place on the pitch it is painted over.
    static func renderScoreboard(size: CGSize,
                                 innings: Int,
                                 lineScore: [[Int]],
                                 outs: Int,
                                 currentInning: Int) -> UIImage {
        let metrics = boardMetrics
        let fieldSize = CGSize(width: size.width / boardW,
                               height: size.height / metrics.height)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let cg = context.cgContext
            // Move the field's origin so the panel's own corner lands at
            // (0, 0) of this canvas.
            cg.translateBy(x: -boardX * fieldSize.width,
                           y: -boardY * fieldSize.height)
            drawScoreboard(in: cg, size: fieldSize, innings: innings,
                           lineScore: lineScore, outs: outs,
                           currentInning: currentInning)
        }
    }

    // MARK: The floor mark

    /// The field's own composition, in units of its WIDTH.
    ///
    /// Separate from the constants above on purpose. Those describe the
    /// 820x1100 pitch `render` draws, where `y` is a fraction of the
    /// HEIGHT — which is exactly what went wrong when they were reused for
    /// the floor: on a square canvas the same fractions put first and
    /// third base 0.52 of the width apart and home and second 0.27 of it,
    /// so the diamond came out half as tall as it is wide and every angle
    /// with it. `tools_baseball_field_verify.py` pins those against the
    /// Python preview and they have not moved.
    ///
    /// Here `y` is a fraction of the WIDTH as well, running from the top
    /// of the composition rather than the top of the canvas, so the shape
    /// is the shape whatever it is drawn on. `height` is how tall the
    /// whole thing is in those same units.
    enum Mark {
        static let height: CGFloat = 1.344

        /// How much of the playfield the mark covers, both ways.
        ///
        /// Stated here rather than at the call site because the posts have
        /// to land on the bases the paint draws, and a second copy of this
        /// number is how they would stop agreeing.
        static let floorInset: CGFloat = 0.92

        static let home = CGPoint(x: 0.500, y: 0.953)
        static let first = CGPoint(x: 0.846, y: 0.600)
        static let second = CGPoint(x: 0.500, y: 0.256)
        static let third = CGPoint(x: 0.154, y: 0.600)
        static let mound = CGPoint(x: 0.500, y: 0.605)

        /// The skin is one disc around the mound, cut off down each side
        /// by a line parallel to the foul line — which is the silhouette a
        /// field diagram actually has, and the reason the first attempt's
        /// plain disc read as a running track. `wedgeApexY` is where those
        /// two lines would meet, below home.
        static let skinRadius: CGFloat = 0.419
        static let wedgeApexY: CGFloat = 1.060
        static let moundRadius: CGFloat = 0.116
        static let homeRadius: CGFloat = 0.195
        static let onDeckRadius: CGFloat = 0.126
        static let onDeckY: CGFloat = 1.219
        static let onDeckX: [CGFloat] = [0.153, 0.847]

        static let baseHalf: CGFloat = 0.047
        static let plateHalf: CGFloat = 0.033
        static let rubber = CGSize(width: 0.074, height: 0.019)
        static let box = CGSize(width: 0.102, height: 0.153)
        static let boxGap: CGFloat = 0.028
        static let foulWidth: CGFloat = 0.009
        static let boxLine: CGFloat = 0.007
        static let labelSize: CGFloat = 0.052

        /// How much of the floor the clay covers. Not opaque: the whole
        /// point of a mark rather than a material is that the surface's
        /// own cells carry on through it.
        static let clayAlpha: CGFloat = 0.80

        /// Where the composition lands on a playfield, in that playfield's
        /// own units.
        ///
        /// `renderMarkings` fits itself inside the canvas it is given and
        /// `addFloorText` hands it the playfield's proportion, so the
        /// drawing ends up scaled by whichever axis runs out first and
        /// centred in the other. This repeats that arithmetic for anything
        /// that has to stand ON the drawing — which is to say the runner
        /// posts, which were placed from the OLD composition's fractions
        /// and so stood in the outfield once the field was redrawn.
        ///
        /// `scale` is one composition unit. `originX` and `originZ` are the
        /// composition's top-left corner, measured from the playfield's.
        static func frame(width: CGFloat, depth: CGFloat)
            -> (scale: CGFloat, originX: CGFloat, originZ: CGFloat) {
            let scale = min(width * floorInset, depth * floorInset / height)
            return (scale,
                    (width - scale) / 2,
                    (depth - scale * height) / 2)
        }
    }

    /// The field alone, on a transparent background, in flat colour.
    ///
    /// **This is what Baseball Dice draws on its floor, and `render` above
    /// is not.** Three things were wrong with putting the pitch in the
    /// surface itself, and only the third is a matter of taste:
    ///
    ///   * it was composed at 820x1100 and clamped onto the floor, so
    ///     every chalk line arrived out of true;
    ///   * the turf and the clay were `pixelSurface` grids, which put a
    ///     texture at a contrast nothing else in the suite carries across
    ///     the whole floor rather than in the places a field needs it;
    ///   * and a game whose floor is a different material from the other
    ///     ten reads as a different app, whatever is drawn on it.
    ///
    /// So the floor is the house floor, in the player's own table colour,
    /// and this is laid on top of it the way the other games lay a script
    /// wordmark — a field SHAPE where they have a name.
    ///
    /// `size` is the canvas, and the composition is FITTED inside it:
    /// scaled by whichever of the two dimensions runs out first and
    /// centred in the other. So a caller that hands this the playfield's
    /// own shape gets a field that fills it with round circles, and one
    /// that hands it a square gets the same field with space above and
    /// below rather than a squashed one.
    static func renderMarkings(size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let cg = context.cgContext

            // Fit, never fill: one scale for both axes is what keeps the
            // mound round and the base paths at 45 degrees.
            let scale = min(size.width, size.height / Mark.height)
            let originX = (size.width - scale) / 2
            let originY = (size.height - scale * Mark.height) / 2
            func u(_ value: CGFloat) -> CGFloat { value * scale }
            func p(_ point: CGPoint) -> CGPoint {
                CGPoint(x: originX + point.x * scale,
                        y: originY + point.y * scale)
            }

            // All the clay in one transparency layer.
            //
            // The skin, the plate circle and the two on-deck circles
            // overlap, and four translucent fills stacked would darken
            // every overlap into a visible seam. Drawn opaque inside a
            // layer and faded once, they read as one continuous surface.
            cg.setAlpha(Mark.clayAlpha)
            cg.beginTransparencyLayer(auxiliaryInfo: nil)

            cg.saveGState()
            let apex = p(CGPoint(x: 0.5, y: Mark.wedgeApexY))
            let reach = u(2)
            let wedge = CGMutablePath()
            wedge.move(to: apex)
            wedge.addLine(to: CGPoint(x: apex.x - reach, y: apex.y - reach))
            wedge.addLine(to: CGPoint(x: apex.x - reach, y: originY - reach))
            wedge.addLine(to: CGPoint(x: apex.x + reach, y: originY - reach))
            wedge.addLine(to: CGPoint(x: apex.x + reach, y: apex.y - reach))
            wedge.closeSubpath()
            cg.addPath(wedge)
            cg.clip()
            cg.setFillColor(dirt.cgColor)
            cg.fillEllipse(in: circle(at: p(Mark.mound), radius: u(Mark.skinRadius)))
            cg.restoreGState()

            // The plate's own circle, which reaches past the wedge, and
            // the on-deck circles, which are outside it altogether.
            cg.setFillColor(dirt.cgColor)
            cg.fillEllipse(in: circle(at: p(Mark.home), radius: u(Mark.homeRadius)))
            for x in Mark.onDeckX {
                let centre = p(CGPoint(x: x, y: Mark.onDeckY))
                cg.fillEllipse(in: circle(at: centre, radius: u(Mark.onDeckRadius)))
            }

            // The mound, a shade up from the skin it sits in — the one
            // place the field needs a tone of its own to read at all.
            cg.setFillColor(tinted(dirt, toward: .white, amount: 0.16).cgColor)
            cg.fillEllipse(in: circle(at: p(Mark.mound), radius: u(Mark.moundRadius)))

            cg.endTransparencyLayer()
            cg.setAlpha(1)

            // Foul lines, running off the corners of the canvas rather
            // than stopping at the skin, which is what makes the shape
            // read as a field and not as a track.
            cg.setStrokeColor(chalk.withAlphaComponent(0.92).cgColor)
            cg.setLineWidth(u(Mark.foulWidth))
            cg.setLineCap(.butt)
            let plate = p(Mark.home)
            for side in [CGFloat(-1), 1] {
                cg.move(to: plate)
                cg.addLine(to: CGPoint(x: plate.x + side * u(1.4),
                                       y: plate.y - u(1.4)))
            }
            cg.strokePath()

            // Batter's boxes, outlined either side of the plate.
            cg.setLineWidth(u(Mark.boxLine))
            for side in [CGFloat(-1), 1] {
                let near = side < 0 ? -Mark.boxGap - Mark.box.width : Mark.boxGap
                cg.stroke(CGRect(x: plate.x + u(near),
                                 y: plate.y - u(Mark.box.height * 0.55),
                                 width: u(Mark.box.width),
                                 height: u(Mark.box.height)))
            }

            // The pitcher's rubber.
            cg.setFillColor(baseWhite.cgColor)
            let rubber = p(Mark.mound)
            cg.fill(CGRect(x: rubber.x - u(Mark.rubber.width / 2),
                           y: rubber.y - u(Mark.rubber.height / 2),
                           width: u(Mark.rubber.width),
                           height: u(Mark.rubber.height)))

            // The three bases, as squares on their corners, and the plate,
            // which has its own shape.
            for centre in [Mark.first, Mark.second, Mark.third] {
                cg.addPath(markDiamond(at: p(centre), half: u(Mark.baseHalf)))
            }
            cg.fillPath()
            cg.addPath(markPlate(at: plate, half: u(Mark.plateHalf)))
            cg.fillPath()

            // The two on-deck circles say whose they are, the way the
            // board does. They are the only lettering on the floor.
            for (index, x) in Mark.onDeckX.enumerated() {
                draw(index == 0 ? "VISITORS" : "HOME",
                     centredAt: p(CGPoint(x: x, y: Mark.onDeckY)),
                     size: u(Mark.labelSize),
                     colour: chalk.withAlphaComponent(0.85))
            }
        }
    }

    /// A base: a square stood on its corner, in POINTS rather than
    /// fractions, because the floor mark has already resolved its own
    /// scale by the time it draws one.
    private static func markDiamond(at centre: CGPoint, half: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: centre.x, y: centre.y - half))
        path.addLine(to: CGPoint(x: centre.x + half, y: centre.y))
        path.addLine(to: CGPoint(x: centre.x, y: centre.y + half))
        path.addLine(to: CGPoint(x: centre.x - half, y: centre.y))
        path.closeSubpath()
        return path
    }

    private static func markPlate(at centre: CGPoint, half: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: centre.x - half, y: centre.y - half))
        path.addLine(to: CGPoint(x: centre.x + half, y: centre.y - half))
        path.addLine(to: CGPoint(x: centre.x + half, y: centre.y + half * 0.3))
        path.addLine(to: CGPoint(x: centre.x, y: centre.y + half * 1.3))
        path.addLine(to: CGPoint(x: centre.x - half, y: centre.y + half * 0.3))
        path.closeSubpath()
        return path
    }

    // MARK: Pieces

    /// A faceted texture the size of the field, in one of its own colours.
    ///
    /// Through `LowPolyTextures.facetedSurface`, the same generator every
    /// other playfield uses, so the pitch is made of the same material as
    /// the rest of the suite rather than merely resembling it. Portrait, so
    /// the cell counts follow the canvas and the triangles stay roughly
    /// equilateral instead of stretching into slivers.
    /// Every surface on the pitch, as a pixel grid.
    ///
    /// This used to be `facetedSurface` — triangles, 22 columns wide — which
    /// was the suite's look when the ballpark was drawn and is not any more.
    /// The timber, the steel, the floor and the dice are all pixel grids, so
    /// a diamond built out of facets was the one surface in the app still
    /// speaking the old language.
    ///
    /// The cell is a fraction of the width rather than a fixed count, so the
    /// blocks are the same size on a phone and an iPad instead of growing
    /// with the canvas.
    ///
    /// `posterised` is gone with it: pixelSurface always draws off
    /// SmokeFloor's ramp, because posterising some surfaces and not others
    /// is what made the clay the one smooth thing on the pitch.
    private static func faceted(_ colour: UIColor, size: CGSize,
                                seed: UInt64,
                                posterised: Bool = false) -> UIImage {
        return LowPolyTextures.pixelSurface(
            baseColor: colour,
            cell: max(3, (size.width / 64).rounded()),
            pixelSize: size.width,
            pixelHeight: size.height,
            seed: seed
        )
    }

    /// Fills whatever `region` adds to the context with a texture.
    ///
    /// Clipping and drawing the whole image rather than using a pattern
    /// fill: a pattern tiles from the context's origin at its own size, so
    /// two regions filled with the same pattern show the same facets in the
    /// same places. Clipping one continuous image means the dirt under the
    /// mound and the dirt at first base are different parts of one surface,
    /// which is what stops the repetition reading as wallpaper.
    /// `base` moved `amount` of the way toward `tint`, in straight RGB.
    ///
    /// Partial on purpose. A full derivation would make the clay a ramp off
    /// the turf, and clay that is a shade of the grass stops reading as a
    /// different material — which is the one job the infield has.
    private static func tinted(_ base: UIColor, toward tint: UIColor,
                               amount: CGFloat) -> UIColor {
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        var tr: CGFloat = 0, tg: CGFloat = 0, tb: CGFloat = 0, ta: CGFloat = 0
        guard base.getRed(&br, green: &bg, blue: &bb, alpha: &ba),
              tint.getRed(&tr, green: &tg, blue: &tb, alpha: &ta) else { return base }
        let k = max(0, min(1, amount))
        return UIColor(red: br + (tr - br) * k,
                       green: bg + (tg - bg) * k,
                       blue: bb + (tb - bb) * k,
                       alpha: ba)
    }

    private static func fill(_ cg: CGContext, with texture: UIImage,
                             size: CGSize, region: (CGContext) -> Void) {
        cg.saveGState()
        region(cg)
        cg.clip()
        // UIImage.draw rather than CGContext.draw: a renderer's context is
        // already flipped for UIKit drawing, so the CG call would place the
        // texture upside down. Invisible on noise, wrong all the same, and
        // the sort of thing that only shows up once something directional
        // is drawn into one of these.
        texture.draw(in: CGRect(origin: .zero, size: size))
        cg.restoreGState()
    }

    private static func circle(at centre: CGPoint, radius: CGFloat) -> CGRect {
        CGRect(x: centre.x - radius, y: centre.y - radius,
               width: radius * 2, height: radius * 2)
    }

    /// A base, kept square on screen.
    ///
    /// `half` is a fraction of the WIDTH; the vertical half is scaled by the
    /// aspect so the shape stays a diamond rather than stretching with a
    /// portrait canvas.
    private static func diamondPath(centre: CGPoint, half: CGFloat,
                                    in size: CGSize) -> CGPath {
        let hx = half * size.width
        let hy = half * size.width          // deliberately width-based
        let c = CGPoint(x: centre.x * size.width, y: centre.y * size.height)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: c.x, y: c.y - hy))
        path.addLine(to: CGPoint(x: c.x + hx, y: c.y))
        path.addLine(to: CGPoint(x: c.x, y: c.y + hy))
        path.addLine(to: CGPoint(x: c.x - hx, y: c.y))
        path.closeSubpath()
        return path
    }

    private static func platePath(in size: CGSize) -> CGPath {
        let p = size.width * 0.022
        let c = CGPoint(x: home.x * size.width, y: home.y * size.height)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: c.x - p, y: c.y - p))
        path.addLine(to: CGPoint(x: c.x + p, y: c.y - p))
        path.addLine(to: CGPoint(x: c.x + p, y: c.y + p * 0.3))
        path.addLine(to: CGPoint(x: c.x, y: c.y + p * 1.3))
        path.addLine(to: CGPoint(x: c.x - p, y: c.y + p * 0.3))
        path.closeSubpath()
        return path
    }

    /// The panel, with the game in it.
    ///
    /// Runs go in the inning boxes, the inning being played is marked, and
    /// the outs pips are FILLED rather than outlined. None of that was
    /// drawn before: the grid and the circles were painted empty and
    /// nothing ever filled them, so the board showed the inning numbers
    /// and no game.
    private static func drawScoreboard(in cg: CGContext, size: CGSize,
                                       innings: Int,
                                       lineScore: [[Int]],
                                       outs: Int,
                                       currentInning: Int) {
        let w = size.width
        let h = size.height
        func px(_ value: CGFloat) -> CGFloat { value * w }
        func py(_ value: CGFloat) -> CGFloat { value * h }

        // Extras add columns. Drawing only the scheduled count would hide
        // the innings that decided the game.
        let columns = max(innings, lineScore.map(\.count).max() ?? innings)

        let metrics = boardMetrics
        let panelRect = CGRect(x: px(boardX), y: py(boardY),
                               width: px(boardW), height: py(metrics.height))
        // Square-cornered, opaque, hard-outlined, one-step bevel — the
        // variant that was previewed and chosen.
        //
        // Opaque rather than the 0.9 it used to carry: a bevel drawn over
        // a translucent panel picks up whatever turf is behind it and
        // reads as a smudge rather than as a turned edge, which is the one
        // way this treatment can look worse than the rounded rect it
        // replaces.
        panel.setFill()
        UIBezierPath(rect: panelRect).fill()

        let outlineW = px(panelOutlineW)
        let bevelW = px(panelBevelW)

        cg.setFillColor(panelOutline.cgColor)
        for edge in [
            CGRect(x: panelRect.minX, y: panelRect.minY,
                   width: panelRect.width, height: outlineW),
            CGRect(x: panelRect.minX, y: panelRect.maxY - outlineW,
                   width: panelRect.width, height: outlineW),
            CGRect(x: panelRect.minX, y: panelRect.minY,
                   width: outlineW, height: panelRect.height),
            CGRect(x: panelRect.maxX - outlineW, y: panelRect.minY,
                   width: outlineW, height: panelRect.height)
        ] {
            cg.fill(edge)
        }

        // Inside the outline, so the lit edge reads as the panel's own
        // turned corner rather than as a second border. Light from above
        // and the left, which is what PieceSheen.litFromTop states for the
        // whole app.
        let inner = panelRect.insetBy(dx: outlineW, dy: outlineW)
        cg.setFillColor(panelBevelLit.cgColor)
        cg.fill(CGRect(x: inner.minX, y: inner.minY,
                       width: inner.width, height: bevelW))
        cg.fill(CGRect(x: inner.minX, y: inner.minY,
                       width: bevelW, height: inner.height))
        cg.setFillColor(panelBevelShade.cgColor)
        cg.fill(CGRect(x: inner.minX, y: inner.maxY - bevelW,
                       width: inner.width, height: bevelW))
        cg.fill(CGRect(x: inner.maxX - bevelW, y: inner.minY,
                       width: bevelW, height: inner.height))

        let labelW: CGFloat = 0.050
        let gridX = boardX + labelW
        let cellW = (boardW - labelW - 0.012) / CGFloat(columns)

        draw("INNING", centredAt: CGPoint(x: px(boardX + boardW / 2),
                                          y: py(boardY + 0.023)),
             size: px(0.028), colour: panelText)

        // Centred in the gap ABOVE the grid rather than straddling its top
        // edge. The old placement hung the numerals half over the first
        // row's boxes, which read as numbers that had slipped out of their
        // spots — and did so before the boxes had anything in them to
        // compare against.
        let headerY = py(metrics.gridTop - gridGap / 2)
        for index in 0..<columns {
            draw("\(index + 1)",
                 centredAt: CGPoint(x: px(gridX + cellW * (CGFloat(index) + 0.5)),
                                    y: headerY),
                 size: px(0.024), colour: panelText)
        }

        for (row, name) in ["V", "H"].enumerated() {
            let top = metrics.gridTop + CGFloat(row) * rowHeight
            // Centred on the row's own boxes, in the gutter to their left.
            // It was drawn at a hand-tuned baseline offset, which put the
            // letter below the row it labels — `draw(at:)` takes the text's
            // TOP-left, not its baseline.
            draw(name,
                 centredAt: CGPoint(x: px(boardX + labelW / 2),
                                    y: py(top + rowHeight * 0.42)),
                 size: px(0.028), colour: panelText)
            for index in 0..<columns {
                let box = CGRect(x: px(gridX + cellW * CGFloat(index)), y: py(top),
                                 width: px(cellW), height: py(rowHeight * 0.84))
                // The inning being played is tinted, so a glance says where
                // the game is without counting boxes.
                (index + 1 == currentInning ? live : cell).setFill()
                cg.fill(box)
                // The same hard outline the panel wears, at the same
                // width, rather than a 1pt hairline — at the sizes this
                // texture is drawn and then sampled at, a 1pt line is
                // sub-pixel and the boxes lose their edges entirely.
                panelOutline.setStroke()
                cg.setLineWidth(outlineW)
                cg.stroke(box.insetBy(dx: outlineW / 2, dy: outlineW / 2))

                // A box is blank until that half-inning has been played —
                // an unplayed inning and a scoreless one are different
                // things, and a 0 everywhere would read as the latter.
                guard row < lineScore.count, index < lineScore[row].count else { continue }
                draw("\(lineScore[row][index])",
                     centredAt: CGPoint(x: box.midX, y: box.midY),
                     size: px(0.026), colour: panel)
            }
        }

        // The outs row gets its own band: it is the one thing on this panel
        // read at a glance mid-turn, which is why its pips are filled
        // rather than left as outlines to be counted.
        let centreY = py(metrics.outsTop + outsHeight / 2)
        // Centred on the pips' own line, in the space to their left, for
        // the same reason as the row labels: it was placed by a baseline
        // nudge and sat below the counter it names.
        draw("OUTS",
             centredAt: CGPoint(x: px(boardX + 0.094), y: centreY),
             size: px(0.030), colour: panelText)
        for index in 0..<3 {
            let centre = CGPoint(x: px(boardX + 0.175 + CGFloat(index) * 0.072),
                                 y: centreY)
            let pip = circle(at: centre, radius: px(0.024))
            if index < outs {
                out.setFill()
                cg.fillEllipse(in: pip)
            }
            panelText.setStroke()
            cg.setLineWidth(2.5)
            cg.strokeEllipse(in: pip)
        }
    }

    // MARK: Lettering

    /// Everything on the board is **Poppins SemiBold**, and that is the
    /// point of this change rather than a side effect of it.
    ///
    /// It used to be the script face, all of it: the inning numbers, the
    /// per-half-inning run totals, the V and H row labels, and OUTS —
    /// which the comment a few dozen lines down calls "the one thing on
    /// this panel read at a glance mid-turn" — every one of them set in a
    /// display script at between 2.4% and 3.0% of the texture width. This
    /// is a scoreboard. It is the entire numeric state of the game, and it
    /// was the hardest thing in the app to read.
    ///
    /// One funnel, so one line fixes all six draw sites.
    ///
    /// **These position by the ADVANCE, not by the ink, and that is
    /// deliberate.**
    ///
    /// Ink metrics are for sizing a canvas. `renderScriptText` and the
    /// ROLLS die face both derive their canvas from the text, so a swash
    /// drawn past its advance would be cut off and ink is the only correct
    /// measurement there. This file is the opposite case: the canvas is
    /// the panel, nothing clips, and an overhang simply draws.
    ///
    /// Positioning inside a fixed canvas wants the typographic box,
    /// because that is what lines rows up with one another. Ink extent
    /// varies per glyph — centring "1" and "10" on their ink puts them in
    /// visibly different places inside identical boxes, which is exactly
    /// what went wrong when these were switched to ink.
    ///
    /// The sans face makes that contract MORE correct, not less: with far
    /// less overhang than a script, the advance box and the ink now very
    /// nearly agree, so rows line up on both measurements instead of one.
    /// (This file is deliberately absent from `tools_script_verify.py`'s
    /// `drawers` list, which requires ink measurement. Adding it there
    /// once cost a release. It must stay out.)
    private static func draw(_ text: String, at origin: CGPoint,
                             size: CGFloat, colour: UIColor) {
        (text as NSString).draw(at: origin, withAttributes: attributes(size, colour))
    }

    private static func draw(_ text: String, centredAt centre: CGPoint,
                             size: CGFloat, colour: UIColor) {
        let attrs = attributes(size, colour)
        let measured = (text as NSString).size(withAttributes: attrs)
        (text as NSString).draw(
            at: CGPoint(x: centre.x - measured.width / 2,
                        y: centre.y - measured.height / 2),
            withAttributes: attrs
        )
    }

    private static func attributes(_ size: CGFloat,
                                   _ colour: UIColor) -> [NSAttributedString.Key: Any] {
        [.font: AppFonts.boardFont(size), .foregroundColor: colour]
    }
}
