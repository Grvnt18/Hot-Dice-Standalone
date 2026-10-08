import SwiftUI

/// Every game's How to Play, as a cluster of bubbles.
///
/// Reached from the hub's Settings, where there is no game open and so no
/// single set of rules to show. The button there used to be hidden for
/// exactly that reason, which meant the one screen a player browses the
/// suite from was the one screen that could not tell them how anything
/// works.
///
/// A cluster rather than a list because it is a menu of eleven short
/// names, not a document: bubbles of the length of their own name,
/// staggered off the grid so the block reads as a scatter, and popped in
/// one after another so the set arrives rather than appearing.
///
/// The rules themselves are not duplicated here — each bubble opens the
/// same `HowToPlayView` the game's own Settings does, from
/// `GameCatalogEntry.rules`. One copy of every guide, in the game that
/// owns it.
struct GuideBubbleCluster: View {

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var theme = AppTheme.shared

    /// Which guide is open, if any. The entry itself rather than a flag,
    /// so the sheet cannot be shown without one.
    @State private var opened: GameCatalogEntry?

    /// How many bubbles have popped in. Driven once on appear.
    @State private var shown = 0

    private let columns = Array(repeating: GridItem(.flexible(),
                                                    spacing: GuideBubbleLayout.gap),
                                count: 2)

    var body: some View {
        // Same rebuild as Settings and HowToPlayView: no NavigationStack, no
        // toolbar, the app's own header bar instead. This sheet was missed in
        // that pass, which is why the cohesion check now covers this file too.
        ZStack {
            WoodTiledBackground(fraction: MenuTimber.fraction)
                .ignoresSafeArea()
            Color.black.opacity(0.35)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                MenuHeaderBar(title: "How to Play") { dismiss() }

                ScrollView {
                    VStack(spacing: 14) {
                        Text("Pick a game for its full rules — every table "
                             + "and every edge case. The short version is "
                             + "in each game's own Settings.")
                            .font(.poppins(13))
                            .foregroundStyle(.white.opacity(0.75))
                            .padding(.top, 8)

                        LazyVGrid(columns: columns, spacing: GuideBubbleLayout.gap) {
                            ForEach(Array(GameCatalog.all.enumerated()),
                                    id: \.element.id) { index, entry in
                                bubble(entry, index: index)
                            }
                        }
                        .padding(.horizontal, GuideBubbleLayout.margin)
                        .padding(.bottom, 24)
                    }
                }
            }
        }
        .sheet(item: $opened) { entry in
            // The guide. `GameCatalogEntry.rules` is the only one there
            // is now — a game's own Settings opens this same set.
            HowToPlayView(gameName: entry.displayName,
                          tagline: entry.tagline,
                          sections: entry.rules)
        }
        .onAppear(perform: popIn)
        // Pinned like every game screen (see DiceGameShell's note): these
        // layouts are geometric, and at the larger accessibility sizes the
        // labels win the fight with the frames they sit in. AppFonts' faces
        // use the relativeTo: overload, so shrink-to-fit still works inside
        // the pinned size.
        .dynamicTypeSize(.large)
    }

    private func bubble(_ entry: GameCatalogEntry, index: Int) -> some View {
        let isShown = index < shown

        return Button {
            SoundEngine.shared.play(.buttonTap)
            opened = entry
        } label: {
            // Poppins, not the script face. These are navigation labels —
            // the player reads them to pick whose rules to open — and at a
            // minimumScaleFactor of 0.5 a 24pt name can end up 12pt, which
            // is where a display script stops being readable first.
            Text(entry.tileName)
                .font(.poppins(GuideBubbleLayout.nameSize, .semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.5)
                .multilineTextAlignment(.center)
                .textCase(nil)
                .foregroundStyle(theme.accentTextColor)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity)
                .frame(height: GuideBubbleLayout.height)
                .contentShape(RoundedRectangle(cornerRadius: ControlShape.cornerRadius))
                // Rectangular, like every other control in the suite. These
                // were Capsules, which is the one shape the restyle replaced
                // everywhere else — a pill here made the guide read as a
                // different app's screen.
                .pixelPanel(fill: .solid(theme.accentColor), elevation: .lifted)
        }
        .buttonStyle(.plain)
        // Off the grid, alternating, so eleven bubbles read as a cluster
        // rather than as a table with one odd row at the end.
        .offset(y: index.isMultiple(of: 2)
                ? -GuideBubbleLayout.stagger
                : GuideBubbleLayout.stagger)
        .scaleEffect(isShown ? 1 : 0.4)
        .opacity(isShown ? 1 : 0)
        .animation(.spring(response: 0.34, dampingFraction: 0.62),
                   value: isShown)
    }

    /// Pops the bubbles in one at a time.
    ///
    /// A timer rather than a per-bubble delay so there is one thing to
    /// cancel and nothing left scheduled if the sheet is closed early:
    /// `shown` simply stops climbing, and every bubble is already drawn
    /// from it.
    private func popIn() {
        guard shown == 0 else { return }
        for index in GameCatalog.all.indices {
            DispatchQueue.main.asyncAfter(
                deadline: .now() + Double(index) * GuideBubbleLayout.popInterval
            ) {
                if shown == index { shown = index + 1 }
            }
        }
    }
}

// MARK: - The cluster's geometry

/// The bubbles' size and rhythm.
///
/// File scope, following `HubLayout` and `PlayfieldLayout`, which is the
/// shape the hub was rebuilt into after its statics-on-a-View version
/// would not build.
enum GuideBubbleLayout {
    static let height: CGFloat = 76
    static let gap: CGFloat = 14
    static let margin: CGFloat = 20

    /// How far each bubble sits off its row. Enough to break the grid,
    /// not enough to make two neighbours look misaligned.
    static let stagger: CGFloat = 10

    static let nameSize: CGFloat = 24

    /// Between one bubble arriving and the next.
    static let popInterval: Double = 0.045
}

// MARK: - Figures

/// A diagram a rule section can carry.
///
/// Three, and only three, because a figure earns its place by showing
/// something the sentence cannot. Everything here is drawn from the same
/// values the game plays by — the board's own path array, the board's own
/// rosette art, the real scoring function — so a rule change moves the
/// picture with it. A diagram that has to be redrawn by hand when the code
/// changes is a diagram that will eventually be wrong.
enum GuideFigure: String {
    /// What a rosette is, and what landing on one does.
    case rosette
    /// The sixteen squares each player walks, and where the routes meet.
    case royalUrPath
    /// A Boneheads board scored out, multiplier by multiplier.
    case boneheadsScoring
}

/// Renders a section's figure under its text.
struct GuideFigureView: View {
    let figure: GuideFigure

    var body: some View {
        content
            .frame(maxWidth: .infinity)
            .padding(10)
            .pixelWell(radius: ControlShape.cornerRadius)
    }

    @ViewBuilder
    private var content: some View {
        switch figure {
        case .rosette:         RosetteFigure()
        case .royalUrPath:     RoyalUrPathFigure()
        case .boneheadsScoring: BoneheadsScoringFigure()
        }
    }
}

// MARK: The rosette

/// One square, drawn by the board's own marking routine.
///
/// `RoyalUrArt.draw(.rosette:)` is what paints the five flowered squares on
/// the real board, so the guide cannot show a rosette the board does not.
private struct RosetteFigure: View {
    private let side: CGFloat = 92

    var body: some View {
        HStack(spacing: 14) {
            Canvas { context, size in
                let rect = CGRect(origin: .zero, size: size)
                context.fill(Path(rect), with: .color(Color(RoyalUrArt.tileBase)))
                RoyalUrArt.draw(.rosette, in: context, rect: rect)
            }
            .frame(width: side, height: side)

            Text("Land here and you roll again.")
                .font(.poppins(13))
                .foregroundStyle(MenuInk.text)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }
}

// MARK: The route

/// The board, with both routes numbered.
///
/// Squares come from `RoyalUrBoard.squares`, the route from
/// `RoyalUrBoard.path(for:)` and the flowers from `RoyalUrBoard.rosettes` —
/// the three facts the rule depends on, read rather than redrawn.
private struct RoyalUrPathFigure: View {

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Canvas { context, size in
                RoyalUrPathFigure.draw(in: context, size: size)
            }
            .frame(height: 112)

            Text("Your route runs from START to END. The middle row is shared — that is the only place a piece can be captured.")
                .font(.poppins(12))
                .foregroundStyle(MenuInk.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Out of the ViewBuilder: a Canvas closure doing this much arithmetic
    /// is exactly the shape Xcode 14.2's solver gives up on.
    private static func draw(in context: GraphicsContext, size: CGSize) {
        let cell = min(size.width / CGFloat(RoyalUrBoard.columns),
                       size.height / CGFloat(RoyalUrBoard.rows))
        let originX = (size.width - cell * CGFloat(RoyalUrBoard.columns)) / 2
        let originY = (size.height - cell * CGFloat(RoyalUrBoard.rows)) / 2

        func frame(_ square: RoyalUrBoard.Square) -> CGRect {
            CGRect(x: originX + cell * CGFloat(square.column - 1),
                   y: originY + cell * CGFloat(square.row - 1),
                   width: cell, height: cell)
        }

        for square in RoyalUrBoard.squares {
            let rect = frame(square).insetBy(dx: 1, dy: 1)
            context.fill(Path(rect), with: .color(Color(RoyalUrArt.tileBase)))
            if RoyalUrBoard.rosettes.contains(square) {
                RoyalUrArt.draw(.rosette, in: context, rect: rect)
            }
            context.stroke(Path(rect), with: .color(RoyalUrArt.ink.opacity(0.5)),
                           lineWidth: 1)
        }

        // The route as a route, rather than as sixteen numerals.
        //
        // Numbering every square asked the reader to find 1, then 2, then 3
        // — which is the work the diagram was supposed to do for them. A
        // line does it at a glance, and the only labels left are the two
        // that matter: where a piece comes on, and where it leaves.
        let path = RoyalUrBoard.path(for: RoyalUrBoard.bottomSeat)
        var route = Path()
        for (offset, square) in path.enumerated() {
            let centre = CGPoint(x: frame(square).midX, y: frame(square).midY)
            if offset == 0 { route.move(to: centre) } else { route.addLine(to: centre) }
        }
        context.stroke(
            route,
            with: .color(RoyalUrArt.seatColor(RoyalUrBoard.bottomSeat)),
            style: StrokeStyle(lineWidth: max(2, cell * 0.10),
                               lineCap: .round, lineJoin: .round,
                               dash: [cell * 0.22, cell * 0.16]))

        guard let first = path.first, let last = path.last else { return }
        marker("START", at: frame(first), in: context, cell: cell)
        marker("END", at: frame(last), in: context, cell: cell)
    }

    /// A label over the square it names, dark on the seat's colour so it
    /// reads against both the tile and a rosette.
    private static func marker(_ text: String, at rect: CGRect,
                               in context: GraphicsContext, cell: CGFloat) {
        let seat = RoyalUrArt.seatColor(RoyalUrBoard.bottomSeat)
        let pill = CGRect(x: rect.midX - cell * 0.44, y: rect.midY - cell * 0.20,
                          width: cell * 0.88, height: cell * 0.40)
        context.fill(Path(roundedRect: pill, cornerRadius: 2), with: .color(seat))
        let label = Text(text)
            .font(.poppins(8, .black))
            .foregroundColor(.white)
        context.draw(context.resolve(label),
                     at: CGPoint(x: pill.midX, y: pill.midY))
    }
}

// MARK: The multiplier

/// A worked board, scored by `BoneheadsRules.columnScore`.
///
/// The numbers are not typed in. Each row's product and each column's
/// subtotal are computed by the same function the game scores with, so the
/// worked example cannot disagree with the rule it is demonstrating.
private struct BoneheadsScoringFigure: View {

    /// Three columns that between them show all three multipliers: a pair,
    /// a triple, and three singles.
    private static let columns: [[Int]] = [[5, 5, 1], [3, 3, 3], [2, 5, 4]]

    private var total: Int {
        BoneheadsScoringFigure.columns
            .reduce(0) { $0 + BoneheadsRules.columnScore($1) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Columns across, dice DOWN — which is how a Boneheads column
            // is actually stacked, and how the worked chart this came from
            // is laid out. The first version ran each column's dice
            // left-to-right, so the picture disagreed with the board it was
            // explaining.
            HStack(alignment: .top, spacing: 14) {
                ForEach(Array(BoneheadsScoringFigure.columns.enumerated()), id: \.offset) { index, column in
                    BoneheadsColumnStack(label: BoneheadsRules.name(of: index),
                                         dice: column)
                }
                Spacer(minLength: 0)
            }

            Divider().overlay(MenuInk.dim)

            Text("TOTAL: \(total)")
                .font(.poppins(14, .bold))
                .foregroundStyle(MenuInk.text)
        }
    }
}

/// One column of the worked example, stacked the way the board stacks it.
private struct BoneheadsColumnStack: View {
    let label: String
    let dice: [Int]

    /// How many times `value` appears — the multiplier the rule applies.
    private func occurrences(of value: Int) -> Int {
        dice.filter { $0 == value }.count
    }

    var body: some View {
        VStack(spacing: 5) {
            Text(label)
                .font(.poppins(11, .bold))
                .foregroundStyle(MenuInk.dim)

            ForEach(Array(dice.enumerated()), id: \.offset) { _, die in
                HStack(spacing: 4) {
                    // Flat: no plate, no bevel, no shadow. A diagram of a
                    // rule is a diagram, and the drop shadow that makes a
                    // die read as a physical object on the board makes it
                    // read as blur at this size.
                    PipFace(value: die, tint: MenuInk.text)
                        .frame(width: 24, height: 24)
                    Text("x\(occurrences(of: die))")
                        .font(.poppins(11))
                        .foregroundStyle(MenuInk.dim)
                }
            }

            Text("= \(BoneheadsRules.columnScore(dice))")
                .font(.poppins(13, .bold))
                .foregroundStyle(MenuInk.text)
                .padding(.top, 2)
        }
    }
}

// MARK: - Laying out the document's own lines

/// One line of a guide section, as the rules document wrote it.
///
/// The guides are generated verbatim from GAME_RULES.txt — bullets, numbered
/// steps, sub-lists and column-aligned tables included. Flattening that into
/// paragraphs is what the first attempt did, and it lost the shape of every
/// rule that is a list or a table.
///
/// So the structure is kept in the text and read back here. Nothing is
/// reworded, reordered or summarised; the only thing this decides is how a
/// line is drawn.
enum GuideLine: Identifiable {
    case heading(String)
    case bullet(depth: Int, text: String)
    case step(marker: String, text: String)
    case plain(String)
    /// A column-aligned block: the document's header row, then its rows.
    case table(columns: [String], rows: [[String]])

    var id: String {
        switch self {
        case .heading(let s):             return "h:" + s
        case .bullet(let d, let s):       return "b:\(d):" + s
        case .step(let m, let s):         return "s:" + m + s
        case .plain(let s):               return "p:" + s
        case .table(let c, let r):        return "t:" + c.joined() + "\(r.count)"
        }
    }
}

enum GuideBody {

    /// Reads a section body back into lines.
    ///
    /// The document's conventions, and nothing cleverer: `*` starts a
    /// bullet and its indent sets the depth, `1.` starts a numbered step, a
    /// run of dashes turns the line above it into a table header, and a more
    /// deeply indented line with no marker of its own continues the item
    /// above it — which is how the document wraps long sentences.
    static func parse(_ body: String) -> [GuideLine] {
        var out: [GuideLine] = []
        var pending: [[String]] = []
        var columns: [String] = []
        var inTable = false
        /// Where the table's own columns start, so a wrapped cell can be
        /// told from a new row: the document indents a continuation under
        /// the column it belongs to, far past the first.
        var tableIndent = 0

        func closeTable() {
            if inTable, !columns.isEmpty {
                out.append(.table(columns: columns, rows: pending))
            }
            pending = []
            columns = []
            inTable = false
        }

        for raw in body.components(separatedBy: "\n") {
            let line = raw.replacingOccurrences(of: "\u{00A0}", with: " ")
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                closeTable()
                continue
            }

            // A rule of dashes promotes the line above it to a header.
            if trimmed.allSatisfy({ $0 == "-" }), trimmed.count >= 5 {
                if case .plain(let header)? = out.last {
                    out.removeLast()
                    columns = cells(header)
                    inTable = true
                }
                continue
            }

            let indent = line.prefix(while: { $0 == " " }).count

            if inTable {
                // A row's last cell wrapping, not a new row. Without this
                // the Baseball matrix grows a row reading only "even with a
                // runner on 1st)", which is half a sentence presented as a
                // rule of its own.
                if indent >= tableIndent + 4, !pending.isEmpty,
                   var last = pending.popLast() {
                    let tail = (last.popLast() ?? "") + " " + trimmed
                    last.append(tail)
                    pending.append(last)
                } else {
                    if tableIndent == 0 { tableIndent = indent }
                    pending.append(cells(trimmed))
                }
                continue
            }

            if trimmed.hasPrefix("* ") {
                out.append(.bullet(depth: indent >= 4 ? 1 : 0,
                                   text: String(trimmed.dropFirst(2))))
                continue
            }
            if let marker = stepMarker(trimmed) {
                out.append(.step(marker: marker,
                                 text: String(trimmed.dropFirst(marker.count + 1))
                                        .trimmingCharacters(in: .whitespaces)))
                continue
            }
            // A continuation of whatever came before it.
            if indent >= 4, let last = out.last {
                out.removeLast()
                out.append(extend(last, with: trimmed))
                continue
            }
            out.append(.plain(trimmed))
        }
        closeTable()
        return out
    }

    /// `  1.` and friends. Nil when the line does not start with one.
    private static func stepMarker(_ text: String) -> String? {
        var digits = ""
        for character in text {
            if character.isNumber { digits.append(character) }
            else if character == "." && !digits.isEmpty { return digits + "." }
            else { return nil }
        }
        return nil
    }

    private static func extend(_ line: GuideLine, with text: String) -> GuideLine {
        switch line {
        case .bullet(let depth, let body): return .bullet(depth: depth, text: body + " " + text)
        case .step(let marker, let body):  return .step(marker: marker, text: body + " " + text)
        case .plain(let body):             return .plain(body + " " + text)
        case .heading, .table:             return line
        }
    }

    /// Columns are separated by two or more spaces, which is what the
    /// document's alignment actually means.
    private static func cells(_ text: String) -> [String] {
        var out: [String] = []
        var current = ""
        var spaces = 0
        for character in text {
            if character == " " {
                spaces += 1
                continue
            }
            if spaces >= 2, !current.isEmpty {
                out.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else if spaces > 0, !current.isEmpty {
                current += " "
            }
            spaces = 0
            current.append(character)
        }
        if !current.isEmpty {
            out.append(current.trimmingCharacters(in: .whitespaces))
        }
        return out
    }
}

/// Draws a section's lines: bullets as bullets, steps as steps, tables as
/// rows. Nothing here changes a word.
struct GuideBodyView: View {
    let body0: String

    private var lines: [GuideLine] { GuideBody.parse(body0) }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(lines) { line in
                row(line)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func row(_ line: GuideLine) -> some View {
        switch line {
        case .heading(let text), .plain(let text):
            Text(text)
                .font(.poppins(14))
                .foregroundStyle(MenuInk.text)
                .fixedSize(horizontal: false, vertical: true)

        case .bullet(let depth, let text):
            marked("•", text, indent: CGFloat(depth) * 14)

        case .step(let marker, let text):
            marked(marker, text, indent: 0)

        case .table(let columns, let rows):
            GuideTableView(columns: columns, rows: rows)
        }
    }

    /// A marker in its own column so the wrapped text lines up under itself
    /// rather than under the bullet.
    private func marked(_ marker: String, _ text: String,
                        indent: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(marker)
                .font(.poppins(14, .semibold))
                .foregroundStyle(MenuInk.dim)
                .frame(minWidth: 16, alignment: .leading)
            Text(text)
                .font(.poppins(14))
                .foregroundStyle(MenuInk.text)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, indent)
    }
}

/// A table from the document, as rows rather than as aligned columns.
///
/// The document aligns with spaces, which needs a fixed-width face and more
/// width than a phone has. The words and their order are the document's; the
/// fitting is this view's. Each row leads with its first cell — the thing
/// being looked up — and the rest follow it.
private struct GuideTableView: View {
    let columns: [String]
    let rows: [[String]]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if columns.count > 1 {
                Text(columns.joined(separator: " · "))
                    .font(.poppins(10, .semibold))
                    .foregroundStyle(MenuInk.dim)
                    .padding(.bottom, 4)
            }

            ForEach(Array(rows.enumerated()), id: \.offset) { _, cells in
                HStack(alignment: .top, spacing: 8) {
                    Text(cells.first ?? "")
                        .font(.poppins(12, .semibold))
                        .foregroundStyle(MenuInk.text)
                        .frame(width: 96, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(cells.dropFirst().joined(separator: " — "))
                        .font(.poppins(12))
                        .foregroundStyle(MenuInk.dim)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 3)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pixelWell(radius: ControlShape.cornerRadius)
    }
}
