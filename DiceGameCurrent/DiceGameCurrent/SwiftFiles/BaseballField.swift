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

    static let grass = UIColor(hex: "#7BA07E")
    static let dirt = UIColor(hex: "#C9B18A")
    static let chalk = UIColor(hex: "#FFFFFF")
    static let baseWhite = UIColor(hex: "#F4F4F0")
    static let panel = UIColor(hex: "#111111")
    static let panelText = UIColor(hex: "#FFFFFF")
    static let cell = UIColor(hex: "#E9E9E9")

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

    /// Renders the field at `size`, with `innings` columns on the scoreboard.
    ///
    /// Only as many columns as the match has: nine empty boxes in a
    /// three-inning game reads as an unfinished game rather than a short one.
    static func render(size: CGSize, innings: Int) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let cg = context.cgContext
            let w = size.width
            let h = size.height
            func px(_ value: CGFloat) -> CGFloat { value * w }
            func py(_ value: CGFloat) -> CGFloat { value * h }
            func point(_ p: CGPoint) -> CGPoint { CGPoint(x: px(p.x), y: py(p.y)) }

            grass.setFill()
            cg.fill(CGRect(origin: .zero, size: size))

            // Infield skin: a dirt disc around the mound with the grass
            // infield laid back over it, which is how the real shape is made.
            dirt.setFill()
            cg.fillEllipse(in: circle(at: point(mound), radius: px(skinRadius)))
            grass.setFill()
            cg.addPath(diamondPath(centre: mound, half: 0.190, in: size))
            cg.fillPath()

            // Base paths, stroked along the diamond's edges.
            dirt.setStroke()
            cg.setLineWidth(px(pathWidth))
            cg.setLineJoin(.round)
            let bases = [home, first, second, third].map(point)
            cg.addLines(between: bases + [bases[0]])
            cg.strokePath()

            // Foul lines, running out past the corners.
            chalk.setStroke()
            cg.setLineWidth(px(0.008))
            for corner in [CGPoint(x: -0.05, y: 0.330), CGPoint(x: 1.05, y: 0.330)] {
                cg.move(to: point(home))
                cg.addLine(to: point(corner))
            }
            cg.strokePath()

            // Mound, its rubber, and the plate circle.
            dirt.setFill()
            cg.fillEllipse(in: circle(at: point(mound), radius: px(moundRadius)))
            chalk.setFill()
            cg.fill(CGRect(x: px(mound.x - 0.030), y: py(mound.y) - px(0.006),
                           width: px(0.060), height: px(0.012)))
            dirt.setFill()
            cg.fillEllipse(in: circle(at: point(home), radius: px(homeCircleRadius)))

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
                dirt.setFill()
                cg.fillEllipse(in: circle(at: CGPoint(x: px(x), y: py(onDeckY)),
                                          radius: px(onDeckRadius)))
                draw(index == 0 ? "VISITORS" : "HOME",
                     centredAt: CGPoint(x: px(x), y: py(onDeckY) + px(0.082)),
                     size: px(0.026), colour: chalk.withAlphaComponent(0.9))
            }

            drawScoreboard(in: cg, size: size, innings: innings)
        }
    }

    // MARK: Pieces

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

    private static func drawScoreboard(in cg: CGContext, size: CGSize, innings: Int) {
        let w = size.width
        let h = size.height
        func px(_ value: CGFloat) -> CGFloat { value * w }
        func py(_ value: CGFloat) -> CGFloat { value * h }

        let metrics = boardMetrics
        let panelRect = CGRect(x: px(boardX), y: py(boardY),
                               width: px(boardW), height: py(metrics.height))
        panel.withAlphaComponent(0.9).setFill()
        UIBezierPath(roundedRect: panelRect, cornerRadius: px(0.014)).fill()

        let labelW: CGFloat = 0.050
        let gridX = boardX + labelW
        let cellW = (boardW - labelW - 0.012) / CGFloat(innings)

        draw("INNING", centredAt: CGPoint(x: px(boardX + boardW / 2),
                                          y: py(boardY + 0.023)),
             size: px(0.028), colour: panelText)

        for index in 0..<innings {
            draw("\(index + 1)",
                 centredAt: CGPoint(x: px(gridX + cellW * (CGFloat(index) + 0.5)),
                                    y: py(metrics.gridTop) - px(0.008)),
                 size: px(0.024), colour: panelText)
        }

        for (row, name) in ["V", "H"].enumerated() {
            let top = metrics.gridTop + CGFloat(row) * rowHeight
            draw(name, at: CGPoint(x: px(boardX + 0.014),
                                   y: py(top + rowHeight * 0.74)),
                 size: px(0.028), colour: panelText)
            for index in 0..<innings {
                let box = CGRect(x: px(gridX + cellW * CGFloat(index)), y: py(top),
                                 width: px(cellW), height: py(rowHeight * 0.84))
                cell.setFill()
                cg.fill(box)
                panel.setStroke()
                cg.setLineWidth(1)
                cg.stroke(box)
            }
        }

        // The outs row gets its own band: it is the one thing on this panel
        // read at a glance mid-turn.
        let centreY = py(metrics.outsTop + outsHeight / 2)
        draw("OUTS", at: CGPoint(x: px(boardX + 0.014), y: centreY + px(0.012)),
             size: px(0.030), colour: panelText)
        panelText.setStroke()
        cg.setLineWidth(2.5)
        for index in 0..<3 {
            let centre = CGPoint(x: px(boardX + 0.175 + CGFloat(index) * 0.072),
                                 y: centreY)
            cg.strokeEllipse(in: circle(at: centre, radius: px(0.024)))
        }
    }

    // MARK: Lettering

    /// Everything on the board is Aguafina, the app's display face.
    ///
    /// Falls back rather than trapping: a wrong-looking font is a far smaller
    /// problem than a crash inside a texture render, which is the same call
    /// `renderScriptText` makes for the same reason.
    private static func font(_ size: CGFloat) -> UIFont {
        UIFont(name: AppFonts.aguafinaScriptPostScriptName, size: size)
            ?? UIFont.italicSystemFont(ofSize: size)
    }

    private static func draw(_ text: String, at origin: CGPoint,
                             size: CGFloat, colour: UIColor) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font(size), .foregroundColor: colour
        ]
        (text as NSString).draw(at: origin, withAttributes: attrs)
    }

    private static func draw(_ text: String, centredAt centre: CGPoint,
                             size: CGFloat, colour: UIColor) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font(size), .foregroundColor: colour
        ]
        let measured = (text as NSString).size(withAttributes: attrs)
        (text as NSString).draw(
            at: CGPoint(x: centre.x - measured.width / 2,
                        y: centre.y - measured.height / 2),
            withAttributes: attrs
        )
    }
}
