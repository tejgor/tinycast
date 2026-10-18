import AppKit

extension NSAttributedString.Key {
    /// Set over a whole line so the paragraph TextKit vends carries it at index 0.
    static let noteBlockDecoration = NSAttributedString.Key("tinycast.note.blockDecoration")
}

/// What `NoteBlockLayoutFragment` draws for one line; immutable so it can cross to the layout pass.
final class NoteBlockDecoration: NSObject, Sendable {
    enum Shape: Sendable, Equatable, Hashable {
        enum CodeRow: Sendable, Hashable { case top, middle, bottom, single }
        case code(CodeRow, language: String?)
        case quote(depth: Int)
        case rule
        case bullet(level: Int)
        /// The source's own label, such as `3.` or `3)`.
        case ordered(level: Int, label: String)
        case task(level: Int, checked: Bool)
        case table(TableRow)

        /// One drawn row of a table; the hidden source underneath it stays the editable text.
        struct TableRow: Sendable, Hashable {
            enum Role: Sendable, Hashable { case header, delimiter, body }

            let role: Role
            /// The bottom row draws the closing edge and rounds the lower corners.
            let isLast: Bool
            let cells: [NoteMarkdown.TableCell]
            /// Natural widths, padding included, shared by every row; the fragment shrinks them to fit.
            let widths: [CGFloat]
            let alignments: [NoteMarkdown.Table.Alignment]
        }
    }

    let shape: Shape
    /// Band, bar, rule, bullet, box or table header.
    let fill: NSColor
    /// Number text, language label or cell text; a checkmark is cut out of the box instead.
    let ink: NSColor
    /// A table's grid lines.
    let stroke: NSColor
    /// A table cell's link text.
    let accent: NSColor
    let bodyPointSize: CGFloat

    init(
        shape: Shape, fill: NSColor, ink: NSColor, stroke: NSColor? = nil, accent: NSColor? = nil,
        bodyPointSize: CGFloat
    ) {
        self.shape = shape
        self.fill = fill
        self.ink = ink
        self.stroke = stroke ?? fill
        self.accent = accent ?? ink
        self.bodyPointSize = bodyPointSize
    }

    /// Value equality, so restyling a line to the same look does not read as a change.
    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? NoteBlockDecoration else { return false }
        return shape == other.shape && fill == other.fill && ink == other.ink
            && stroke == other.stroke && accent == other.accent && bodyPointSize == other.bodyPointSize
    }

    override var hash: Int {
        var hasher = Hasher()
        hasher.combine(shape)
        hasher.combine(fill)
        hasher.combine(ink)
        hasher.combine(stroke)
        hasher.combine(accent)
        hasher.combine(bodyPointSize)
        return hasher.finalize()
    }
}
