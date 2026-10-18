import AppKit

final class NoteBlockLayoutFragment: NSTextLayoutFragment {
    let decoration: NoteBlockDecoration

    private static let orderedLabelPadding: CGFloat = 4
    private static let bulletScale: CGFloat = 0.35
    private static let boxStroke: CGFloat = 1.25
    private static let boxRadius: CGFloat = 3
    private static let checkStroke: CGFloat = 1.5

    init(textElement: NSTextElement, range: NSTextRange?, decoration: NoteBlockDecoration) {
        self.decoration = decoration
        super.init(textElement: textElement, range: range)
    }

    required init?(coder: NSCoder) {
        nil
    }

    /// Drawing is clipped to this; it starts a slot left of the container so wide numbers show.
    override var renderingSurfaceBounds: CGRect {
        let bounds = super.renderingSurfaceBounds
        let frame = layoutFragmentFrame
        let chrome = CGRect(
            x: -frame.minX - slot, y: 0, width: containerWidth + slot, height: frame.height)
        return bounds.union(chrome)
    }

    override func draw(at point: CGPoint, in context: CGContext) {
        let left = point.x - layoutFragmentFrame.minX
        if case .code(let row, let language) = decoration.shape {
            drawBand(row: row, language: language, left: left, top: point.y, in: context)
        }
        super.draw(at: point, in: context)
        context.saveGState()
        defer { context.restoreGState() }
        switch decoration.shape {
        case .code:
            break
        case .quote(let depth):
            drawQuoteBars(depth: depth, left: left, top: point.y, in: context)
        case .rule:
            let y = (point.y + layoutFragmentFrame.height / 2).rounded(.down)
            context.setFillColor(decoration.fill.cgColor)
            let width = containerWidth.rounded()
            context.fill(CGRect(x: left.rounded(), y: y, width: width, height: Theme.Size.hairline))
        case .bullet(let level):
            drawBullet(level: level, left: left, top: point.y, in: context)
        case .ordered(let level, let label):
            drawLabel(label, level: level, left: left, top: point.y, in: context)
        case .task(let level, let checked):
            drawBox(level: level, checked: checked, left: left, top: point.y, in: context)
        case .table(let row):
            drawTableRow(row, left: left, top: point.y, in: context)
        }
    }

    // MARK: - Shapes

    private var slot: CGFloat { NoteCheckboxGeometry.slot(bodyPointSize: decoration.bodyPointSize) }

    private var containerWidth: CGFloat {
        textLayoutManager?.textContainer?.size.width ?? super.renderingSurfaceBounds.width
    }

    /// The first line of text, which markers align with when an item wraps.
    var firstLine: CGRect {
        firstTextLine?.typographicBounds ?? CGRect(origin: .zero, size: layoutFragmentFrame.size)
    }

    var firstBaseline: CGFloat {
        guard let line = firstTextLine else { return layoutFragmentFrame.height }
        return line.typographicBounds.minY + line.glyphOrigin.y
    }

    /// A word too wide for the first line wraps, leaving the hidden marker alone on a hairline.
    private var firstTextLine: NSTextLineFragment? {
        textLineFragments.first { $0.typographicBounds.height > decoration.bodyPointSize / 2 }
    }

    private func drawBand(
        row: NoteBlockDecoration.Shape.CodeRow, language: String?, left: CGFloat, top: CGFloat,
        in context: CGContext
    ) {
        let minY = top.rounded()
        let rect = CGRect(
            x: left.rounded(), y: minY, width: containerWidth.rounded(),
            height: (top + layoutFragmentFrame.height).rounded() - minY)
        let roundsTop = row == .top || row == .single
        let roundsBottom = row == .bottom || row == .single
        context.saveGState()
        context.addPath(
            Self.bandPath(
                rect, topRadius: roundsTop ? Theme.Radius.menu : 0,
                bottomRadius: roundsBottom ? Theme.Radius.menu : 0))
        context.setFillColor(decoration.fill.cgColor)
        context.fillPath()
        if roundsTop, let language {
            let font = NSFont.systemFont(ofSize: NSFont.preferredFont(forTextStyle: .caption1).pointSize)
            let line = Self.line(language, font: font, color: decoration.ink)
            let width = CTLineGetTypographicBounds(line, nil, nil, nil)
            let baseline = top + (layoutFragmentFrame.height + font.capHeight) / 2
            Self.draw(line, at: CGPoint(x: rect.maxX - Theme.Spacing.lg - width, y: baseline), in: context)
        }
        context.restoreGState()
    }

    private func drawQuoteBars(depth: Int, left: CGFloat, top: CGFloat, in context: CGContext) {
        context.setFillColor(decoration.fill.cgColor)
        let step = Theme.Size.markdownQuoteBar + Theme.Spacing.lg
        let minY = top.rounded()
        let height = (top + layoutFragmentFrame.height).rounded() - minY
        for level in 0..<depth {
            let bar = CGRect(
                x: (left + CGFloat(level) * step).rounded(), y: minY, width: Theme.Size.markdownQuoteBar,
                height: height)
            context.addPath(CGPath(roundedRect: bar, cornerWidth: 1, cornerHeight: 1, transform: nil))
        }
        context.fillPath()
    }

    private func drawBullet(level: Int, left: CGFloat, top: CGFloat, in context: CGContext) {
        let diameter = decoration.bodyPointSize * Self.bulletScale
        let center = CGPoint(x: left + CGFloat(level) * slot + slot / 2, y: top + firstLine.midY)
        context.setFillColor(decoration.fill.cgColor)
        context.fillEllipse(
            in: CGRect(
                x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter))
    }

    private func drawLabel(_ label: String, level: Int, left: CGFloat, top: CGFloat, in context: CGContext) {
        let font = NSFont.systemFont(ofSize: decoration.bodyPointSize)
        let line = Self.line(label, font: font, color: decoration.ink)
        let width = CTLineGetTypographicBounds(line, nil, nil, nil)
        let slotEnd = left + CGFloat(level + 1) * slot - Self.orderedLabelPadding
        Self.draw(line, at: CGPoint(x: slotEnd - width, y: top + firstBaseline), in: context)
    }

    private func drawBox(level: Int, checked: Bool, left: CGFloat, top: CGFloat, in context: CGContext) {
        let box = NoteCheckboxGeometry.rect(
            level: level, firstLineHeight: firstLine.height, bodyPointSize: decoration.bodyPointSize
        ).offsetBy(dx: left, dy: top + firstLine.minY)
        guard checked else {
            context.addPath(Self.roundedBox(box.insetBy(dx: Self.boxStroke / 2, dy: Self.boxStroke / 2)))
            context.setStrokeColor(decoration.fill.cgColor)
            context.setLineWidth(Self.boxStroke)
            context.strokePath()
            return
        }
        context.addPath(Self.roundedBox(box))
        context.setFillColor(decoration.fill.cgColor)
        context.fillPath()
        context.move(to: CGPoint(x: box.minX + box.width * 0.25, y: box.minY + box.height * 0.55))
        context.addLine(to: CGPoint(x: box.minX + box.width * 0.45, y: box.minY + box.height * 0.75))
        context.addLine(to: CGPoint(x: box.minX + box.width * 0.78, y: box.minY + box.height * 0.30))
        context.setBlendMode(.clear)
        context.setLineWidth(Self.checkStroke)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.strokePath()
    }

    /// Each row draws its top edge and sides, so stacked rows share one line at every seam.
    private func drawTableRow(
        _ row: NoteBlockDecoration.Shape.TableRow, left: CGFloat, top: CGFloat, in context: CGContext
    ) {
        guard row.role != .delimiter else { return }
        let widths = NoteTableGrid.fitted(row.widths, into: containerWidth.rounded(.down))
        let minY = (top + firstLine.minY).rounded()
        let rect = CGRect(
            x: left.rounded(), y: minY, width: widths.reduce(0, +),
            height: (top + firstLine.maxY).rounded() - minY)
        let isHeader = row.role == .header
        let radius = Theme.Radius.menu
        if isHeader {
            context.addPath(Self.bandPath(rect, topRadius: radius, bottomRadius: row.isLast ? radius : 0))
            context.setFillColor(decoration.fill.cgColor)
            context.fillPath()
        }

        let bodyFont = NoteTableGrid.font(bodyPointSize: decoration.bodyPointSize, isHeader: false)
        let baseline = rect.midY + (bodyFont.ascender + bodyFont.descender) / 2
        var x = rect.minX
        for (column, width) in widths.enumerated() {
            defer { x += width }
            let available = width - NoteTableGrid.cellPadding * 2
            guard available > 0, column < row.cells.count else { continue }
            let text = NoteTableGrid.text(
                row.cells[column], bodyPointSize: decoration.bodyPointSize, isHeader: isHeader,
                ink: decoration.ink, accent: decoration.accent)
            var line = CTLineCreateWithAttributedString(text)
            if CTLineGetTypographicBounds(line, nil, nil, nil) > available {
                let token = Self.line("…", font: bodyFont, color: decoration.ink)
                line = CTLineCreateTruncatedLine(line, Double(available), .end, token) ?? line
            }
            let slack = available - CTLineGetTypographicBounds(line, nil, nil, nil)
            let offset: CGFloat =
                switch row.alignments[column] {
                case .leading: 0
                case .center: (slack / 2).rounded()
                case .trailing: slack
                }
            Self.draw(line, at: CGPoint(x: x + NoteTableGrid.cellPadding + offset, y: baseline), in: context)
        }

        let inset = Theme.Size.hairline / 2
        context.addPath(
            Self.tableOutline(
                rect, topRadius: isHeader ? radius : 0, bottomRadius: row.isLast ? radius : 0,
                closesBottom: row.isLast))
        var boundary = rect.minX
        for width in widths.dropLast() {
            boundary += width
            context.move(to: CGPoint(x: boundary + inset, y: rect.minY))
            context.addLine(to: CGPoint(x: boundary + inset, y: rect.maxY))
        }
        context.setStrokeColor(decoration.stroke.cgColor)
        context.setLineWidth(Theme.Size.hairline)
        context.strokePath()
    }

    // MARK: - Geometry and text

    /// Open at the bottom unless the row closes the table, so the next row's top edge finishes it.
    private static func tableOutline(
        _ rect: CGRect, topRadius: CGFloat, bottomRadius: CGFloat, closesBottom: Bool
    ) -> CGPath {
        let edge = rect.insetBy(dx: Theme.Size.hairline / 2, dy: Theme.Size.hairline / 2)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: edge.minX, y: closesBottom ? edge.maxY - bottomRadius : rect.maxY))
        path.addArc(
            tangent1End: CGPoint(x: edge.minX, y: edge.minY), tangent2End: CGPoint(x: edge.midX, y: edge.minY),
            radius: topRadius)
        path.addArc(
            tangent1End: CGPoint(x: edge.maxX, y: edge.minY), tangent2End: CGPoint(x: edge.maxX, y: edge.midY),
            radius: topRadius)
        guard closesBottom else {
            path.addLine(to: CGPoint(x: edge.maxX, y: rect.maxY))
            return path
        }
        path.addArc(
            tangent1End: CGPoint(x: edge.maxX, y: edge.maxY), tangent2End: CGPoint(x: edge.midX, y: edge.maxY),
            radius: bottomRadius)
        path.addArc(
            tangent1End: CGPoint(x: edge.minX, y: edge.maxY), tangent2End: CGPoint(x: edge.minX, y: edge.midY),
            radius: bottomRadius)
        path.closeSubpath()
        return path
    }

    /// Rounds only the requested ends, so stacked rows of one band meet without a gap at the seams.
    private static func bandPath(_ rect: CGRect, topRadius: CGFloat, bottomRadius: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let corners = [
            (CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.midX, y: rect.minY), topRadius),
            (CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.midY), topRadius),
            (CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.midX, y: rect.maxY), bottomRadius),
            (CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.midY), bottomRadius)
        ]
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        for (corner, next, radius) in corners {
            path.addArc(tangent1End: corner, tangent2End: next, radius: radius)
        }
        path.closeSubpath()
        return path
    }

    private static func roundedBox(_ rect: CGRect) -> CGPath {
        CGPath(roundedRect: rect, cornerWidth: boxRadius, cornerHeight: boxRadius, transform: nil)
    }

    private static func line(_ string: String, font: NSFont, color: NSColor) -> CTLine {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        return CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attributes))
    }

    /// The view is flipped, so Core Text's y axis is flipped back before a line is drawn.
    private static func draw(_ line: CTLine, at baseline: CGPoint, in context: CGContext) {
        context.saveGState()
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        context.textPosition = baseline
        CTLineDraw(line, context)
        context.restoreGState()
    }
}

/// How a table cell is set and measured; the styler sizes columns with exactly what is drawn.
enum NoteTableGrid {
    static let cellPadding = Theme.Spacing.md
    private static let rowPadding = Theme.Spacing.xs

    static func font(bodyPointSize: CGFloat, isHeader: Bool) -> NSFont {
        NSFont.systemFont(ofSize: bodyPointSize, weight: isHeader ? .semibold : .regular)
    }

    static func rowHeight(bodyPointSize: CGFloat) -> CGFloat {
        let font = font(bodyPointSize: bodyPointSize, isHeader: false)
        return (font.ascender - font.descender + font.leading).rounded(.up) + rowPadding * 2
    }

    static func naturalWidth(_ cell: NoteMarkdown.TableCell, bodyPointSize: CGFloat, isHeader: Bool) -> CGFloat {
        let text = text(cell, bodyPointSize: bodyPointSize, isHeader: isHeader, ink: .black, accent: .black)
        let width = CTLineGetTypographicBounds(CTLineCreateWithAttributedString(text), nil, nil, nil)
        return width.rounded(.up) + cellPadding * 2
    }

    /// Columns narrower than an even share keep their width, and the wider ones split the rest.
    static func fitted(_ widths: [CGFloat], into available: CGFloat) -> [CGFloat] {
        guard widths.reduce(0, +) > available else { return widths }
        var fitted = widths
        var open = Array(widths.indices)
        var remaining = available
        while !open.isEmpty {
            let share = remaining / CGFloat(open.count)
            let narrow = open.filter { widths[$0] <= share }
            guard !narrow.isEmpty else {
                for column in open { fitted[column] = max(0, share.rounded(.down)) }
                break
            }
            remaining -= narrow.reduce(0) { $0 + widths[$1] }
            open.removeAll { narrow.contains($0) }
        }
        return fitted
    }

    static func text(
        _ cell: NoteMarkdown.TableCell, bodyPointSize: CGFloat, isHeader: Bool, ink: NSColor, accent: NSColor
    ) -> NSAttributedString {
        let text = NSMutableAttributedString(
            string: cell.text,
            attributes: [.font: font(bodyPointSize: bodyPointSize, isHeader: isHeader), .foregroundColor: ink])
        for run in cell.runs {
            switch run.kind {
            case .strong: addTraits(.bold, in: run.range, of: text)
            case .emphasis: addTraits(.italic, in: run.range, of: text)
            case .strongEmphasis: addTraits([.bold, .italic], in: run.range, of: text)
            case .strikethrough:
                text.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: run.range)
            case .code:
                let code = NSFont.monospacedSystemFont(ofSize: bodyPointSize, weight: isHeader ? .semibold : .regular)
                text.addAttribute(.font, value: code, range: run.range)
            case .link, .autolink:
                text.addAttribute(.foregroundColor, value: accent, range: run.range)
            }
        }
        return text
    }

    private static func addTraits(
        _ traits: NSFontDescriptor.SymbolicTraits, in range: NSRange, of text: NSMutableAttributedString
    ) {
        text.enumerateAttribute(.font, in: range) { value, span, _ in
            guard let font = value as? NSFont else { return }
            let descriptor = font.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(traits))
            text.addAttribute(.font, value: NSFont(descriptor: descriptor, size: font.pointSize) ?? font, range: span)
        }
    }
}
