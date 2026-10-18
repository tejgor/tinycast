import Foundation

/// A note's Markdown as ranged lines; one line is one TextKit paragraph and one restyle unit.
struct NoteMarkdown: Sendable, Equatable {
    struct Line: Sendable, Equatable {
        enum Kind: Sendable, Equatable {
            case blank
            case paragraph
            case heading(level: Int)
            case bullet
            case ordered(number: Int)
            case task(checked: Bool)
            case quote(depth: Int)
            case rule
            case fenceOpen(language: String?)
            case fenceClose
            case code
            /// A row of a GFM table, which stays literal: no inline spans, no block syntax.
            case table

            var isList: Bool {
                switch self {
                case .bullet, .ordered, .task: true
                default: false
                }
            }

            var isFenced: Bool {
                switch self {
                case .fenceOpen, .fenceClose, .code: true
                default: false
                }
            }
        }

        let kind: Kind
        /// The whole line including its terminator, so ranges tile the source with no gaps.
        let range: NSRange
        /// The line without leading block syntax and without its terminator.
        let contentRange: NSRange
        /// Leading indentation plus block marker plus the space after it; nil when there is none.
        let markerRange: NSRange?
        /// The three characters `[ ]` or `[x]` of a task; nil otherwise.
        let checkboxRange: NSRange?
        /// List nesting depth from the indent stack, 0 for top level and for non-list lines.
        let level: Int
    }

    struct Inline: Sendable, Equatable {
        enum Kind: Sendable, Hashable {
            case strong, emphasis, strongEmphasis, strikethrough, code
            case link(destination: String)
            case autolink
        }

        let kind: Kind
        let range: NSRange
        let contentRange: NSRange
        /// Every syntax run to hide: opening and closing delimiters, and `](url)` for a link.
        let markerRanges: [NSRange]
    }

    /// A GFM table over consecutive `.table` lines, header first and the delimiter row second.
    struct Table: Sendable, Equatable {
        enum Alignment: Sendable, Hashable { case leading, center, trailing }

        let lines: ClosedRange<Int>
        let alignments: [Alignment]
        /// One trimmed content range per column for each row; the delimiter row's is empty.
        let cells: [[NSRange]]

        var delimiterLine: Int { lines.lowerBound + 1 }
    }

    /// A cell as drawn: its text with Markdown markers removed, and the spans that style it.
    struct TableCell: Sendable, Hashable {
        struct Run: Sendable, Hashable {
            let kind: Inline.Kind
            let range: NSRange
        }

        let text: String
        let runs: [Run]
    }

    /// The source the lines were parsed from; line shapes alone do not identify a note.
    let units: [UInt16]
    let lines: [Line]
    /// Line index ranges of fenced blocks, open line through close line (or last line if unclosed).
    let fenceBlocks: [ClosedRange<Int>]
    let tables: [Table]

    static let empty = NoteMarkdown(units: [], lines: [], fenceBlocks: [], tables: [])

    func table(containing lineIndex: Int) -> Table? {
        var low = 0
        var high = tables.count
        while low < high {
            let middle = (low + high) / 2
            if tables[middle].lines.upperBound < lineIndex { low = middle + 1 } else { high = middle }
        }
        return low < tables.count && tables[low].lines.contains(lineIndex) ? tables[low] : nil
    }

    /// Scanned on demand like `inlines(of:)`; an escaped pipe reads as a pipe, as GFM has it.
    func cell(_ range: NSRange) -> TableCell {
        let content = range.location..<NSMaxRange(range)
        let inlines = NoteInlineScanner(units: units).inlines(in: content)
        var removed = IndexSet()
        for marker in inlines.flatMap(\.markerRanges) {
            removed.insert(integersIn: marker.location..<NSMaxRange(marker))
        }
        var index = content.lowerBound
        while index + 1 < content.upperBound {
            let escapesPipe =
                units[index] == NoteMarkdownParser.Unit.backslash
                && units[index + 1] == NoteMarkdownParser.Unit.pipe
            if escapesPipe { removed.insert(index) }
            index += escapesPipe ? 2 : 1
        }
        var kept: [UInt16] = []
        var position: [Int] = []
        for index in content {
            position.append(kept.count)
            if !removed.contains(index) { kept.append(units[index]) }
        }
        position.append(kept.count)
        let runs = inlines.compactMap { inline -> TableCell.Run? in
            let span = inline.kind == .autolink ? inline.range : inline.contentRange
            let start = position[span.location - content.lowerBound]
            let end = position[NSMaxRange(span) - content.lowerBound]
            return end > start ? TableCell.Run(kind: inline.kind, range: NSRange(start..<end)) : nil
        }
        return TableCell(text: String(decoding: kept, as: UTF16.self), runs: runs)
    }

    /// Scanned on demand: every consumer wants one line, and storing all of them costs more.
    func inlines(of line: Line) -> [Inline] {
        switch line.kind {
        case .paragraph, .heading, .quote, .bullet, .ordered, .task:
            NoteInlineScanner(units: units)
                .inlines(in: line.contentRange.location..<NSMaxRange(line.contentRange))
        default:
            []
        }
    }

    /// Binary search; the parser's trailing empty line is what a caret at the very end lands on.
    func lineIndex(at location: Int) -> Int? {
        guard let last = lines.last, 0...NSMaxRange(last.range) ~= location else { return nil }
        var low = 0
        var high = lines.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if lines[middle].range.location <= location {
                low = middle
            } else {
                high = middle - 1
            }
        }
        return low
    }

    /// An empty range touches its own line; a range ending at a line start does not reach it.
    func lineIndexes(intersecting range: NSRange) -> Range<Int> {
        guard let first = lineIndex(at: range.location) else { return 0..<0 }
        guard range.length > 0, let last = lineIndex(at: NSMaxRange(range) - 1) else {
            return first..<(first + 1)
        }
        return first..<(max(first, last) + 1)
    }
}
