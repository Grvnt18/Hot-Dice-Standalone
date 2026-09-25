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

            // The turf and the dirt are FACETED, not flat.
            //
            // Every other playfield in the suite is a low-poly surface, and
            // a pitch painted in two flat colours read as a different app.
            // The layout is untouched — the same diamond, the same circles,
            // the same measurements — and only what fills them changes.
            let turfTexture = faceted(turf, size: size, seed: 771001)
            let clay = faceted(dirt, size: size, seed: 771002)

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
            chalk.setStroke()
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
            chalk.setFill()
            cg.fill(CGRect(x: px(mound.x - 0.030), y: py(mound.y) - px(0.006),
                           width: px(0.060), height: px(0.012)))
            fill(cg, with: clay, size: size) {
                $0.addEllipse(in: circle(at: point(home), radius: px(homeCircleRadius)))
            }

            // Batter's boxes.
            chalk.setStroke()
            cg.setLineWidth(px(0.006))
            for side in [-1.0, 1.0] as [CGFloat] {
                let left = home.x + (side > 0 ? 0.028 : -0.076)
                cg.stroke(CGRect(x: px(left), y: py(home.y) - px(0.055),
                                 width: px(0.048), height: px(0.100)))
            }

            baseWhite.setFill()
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

    // MARK: Pieces

    /// A faceted texture the size of the field, in one of its own colours.
    ///
    /// Through `LowPolyTextures.facetedSurface`, the same generator every
    /// other playfield uses, so the pitch is made of the same material as
    /// the rest of the suite rather than merely resembling it. Portrait, so
    /// the cell counts follow the canvas and the triangles stay roughly
    /// equilateral instead of stretching into slivers.
    private static func faceted(_ colour: UIColor, size: CGSize,
                                seed: UInt64) -> UIImage {
        let columns = 22
        let rows = Int((CGFloat(columns) * size.height / size.width).rounded())
        return LowPolyTextures.facetedSurface(
            baseColor: colour,
            variation: 0.085,
            columns: columns,
            rows: rows,
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
        panel.withAlphaComponent(0.9).setFill()
        UIBezierPath(roundedRect: panelRect, cornerRadius: px(0.014)).fill()

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
                panel.setStroke()
                cg.setLineWidth(1)
                cg.stroke(box)

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

    /// Everything on the board is Aguafina, through `AppFonts.scriptFont`
    /// — the only way this file can reach the face, and one that falls
    /// back rather than trapping, since a wrong-looking font is a far
    /// smaller problem than a crash inside a texture render.
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
        [.font: AppFonts.scriptFont(size), .foregroundColor: colour]
    }
}
