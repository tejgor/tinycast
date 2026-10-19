import Foundation

/// A note as plain text or HTML, for Copy Note As and Export; Markdown is the source itself.
enum NoteExport {
    enum Format: Sendable, CaseIterable {
        case markdown, html, plainText

        var fileExtension: String {
            switch self {
            case .markdown: "md"
            case .html: "html"
            case .plainText: "txt"
            }
        }
    }

    static func string(_ format: Format, source: String, title: String) -> String {
        switch format {
        case .markdown: source
        case .html: htmlDocument(NoteMarkdownParser.parse(source), title: title)
        case .plainText: plainText(NoteMarkdownParser.parse(source))
        }
    }

    // MARK: - Plain text

    /// Markers dropped, list items kept recognisable, tables as tab-separated rows.
    static func plainText(_ markdown: NoteMarkdown) -> String {
        var lines: [String] = []
        for (index, line) in markdown.lines.enumerated() {
            let indent = String(repeating: "  ", count: line.level)
            let text = markdown.cell(line.contentRange).text
            switch line.kind {
            case .fenceOpen, .fenceClose:
                continue
            case .code:
                lines.append(raw(line.contentRange, in: markdown))
            case .rule:
                lines.append("———")
            case .table:
                guard let table = markdown.table(containing: index), index != table.delimiterLine else { continue }
                let row = table.cells[index - table.lines.lowerBound]
                lines.append(row.map { markdown.cell($0).text }.joined(separator: "\t"))
            case .bullet:
                lines.append(indent + "• " + text)
            case .ordered(let number):
                lines.append(indent + "\(number). " + text)
            case .task(let checked):
                lines.append(indent + (checked ? "☑ " : "☐ ") + text)
            case .blank:
                lines.append("")
            case .paragraph, .heading, .quote:
                lines.append(text)
            }
        }
        while lines.last?.isEmpty == true { lines.removeLast() }
        return lines.joined(separator: "\n")
    }

    // MARK: - HTML

    static func htmlDocument(_ markdown: NoteMarkdown, title: String) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <title>\(escape(title))</title>
        <style>
        body { font: 16px -apple-system, system-ui, sans-serif; line-height: 1.5; }
        body { max-width: 720px; margin: 2em auto; padding: 0 1em; }
        table { border-collapse: collapse; }
        th, td { border: 1px solid #ccc; padding: 4px 8px; }
        pre { background: #f4f4f4; padding: 8px 12px; border-radius: 6px; overflow: auto; }
        blockquote { border-left: 3px solid #ccc; margin-left: 0; padding-left: 1em; color: #555; }
        ul.tasks { list-style: none; padding-left: 1.2em; }
        </style>
        </head>
        <body>
        \(html(markdown))
        </body>
        </html>
        """
    }

    /// Consecutive lines of one kind share a block, as the editor draws them; a blank line ends it.
    static func html(_ markdown: NoteMarkdown) -> String {
        var writer = HTMLWriter(markdown: markdown)
        for index in markdown.lines.indices { writer.write(line: index) }
        writer.closeAll()
        return writer.output.joined(separator: "\n")
    }

    private struct HTMLWriter {
        enum Block: Equatable { case paragraph, quote, code, table }

        let markdown: NoteMarkdown
        var output: [String] = []
        private var block: Block?
        /// A newline straight after `<code>` would show as a blank first line, so the first line joins it.
        private var codeIsEmpty = false
        /// Open lists, outermost first; each has an `<li>` left open for its children.
        private var lists: [String] = []

        init(markdown: NoteMarkdown) {
            self.markdown = markdown
        }

        mutating func write(line index: Int) {
            let line = markdown.lines[index]
            switch line.kind {
            case .blank:
                closeAll()
            case .paragraph:
                enter(.paragraph, open: "<p>", separator: "<br>")
                append(inline(line))
            case .quote:
                enter(.quote, open: "<blockquote><p>", separator: "<br>")
                append(inline(line))
            case .heading(let level):
                closeAll()
                let tag = "h\(min(level, 6))"
                output.append("<\(tag)>\(inline(line))</\(tag)>")
            case .rule:
                closeAll()
                output.append("<hr>")
            case .fenceOpen(let language):
                closeAll()
                let attribute = language.map { " class=\"language-\(escape($0))\"" } ?? ""
                output.append("<pre><code\(attribute)>")
                block = .code
                codeIsEmpty = true
            case .code:
                if block != .code {
                    closeAll()
                    output.append("<pre><code>")
                    block = .code
                    codeIsEmpty = true
                }
                let code = escape(raw(line.contentRange, in: markdown))
                if codeIsEmpty { append(code) } else { output.append(code) }
                codeIsEmpty = false
            case .fenceClose:
                closeBlock()
            case .table:
                writeTableRow(index)
            case .bullet, .ordered, .task:
                writeListItem(line)
            }
        }

        mutating func closeAll() {
            closeBlock()
            while !lists.isEmpty { closeList() }
        }

        private mutating func enter(_ kind: Block, open: String, separator: String) {
            if block == kind {
                output[output.count - 1] += separator
                return
            }
            closeAll()
            output.append(open)
            block = kind
        }

        private mutating func append(_ html: String) {
            output[output.count - 1] += html
        }

        private mutating func closeBlock() {
            switch block {
            case .paragraph: append("</p>")
            case .quote: append("</p></blockquote>")
            case .code: append("</code></pre>")
            case .table: output.append("</tbody></table>")
            case nil: break
            }
            block = nil
        }

        private mutating func writeListItem(_ line: NoteMarkdown.Line) {
            closeBlock()
            let tag: String
            var start = ""
            switch line.kind {
            case .ordered(let number):
                tag = "ol"
                if number != 1 { start = " start=\"\(number)\"" }
            case .task: tag = "ul class=\"tasks\""
            default: tag = "ul"
            }
            while lists.count > line.level + 1 { closeList() }
            if lists.count == line.level + 1 {
                if lists.last == tag {
                    output.append("</li>")
                } else {
                    closeList()
                }
            }
            while lists.count < line.level + 1 {
                output.append("<\(tag)\(lists.count == line.level ? start : "")>")
                lists.append(tag)
            }
            var item = inline(line)
            if case .task(let checked) = line.kind {
                item = "<input type=\"checkbox\" disabled\(checked ? " checked" : "")> " + item
            }
            output.append("<li>\(item)")
        }

        private mutating func closeList() {
            guard let tag = lists.popLast() else { return }
            output.append("</li></\(tag.split(separator: " ")[0])>")
        }

        private mutating func writeTableRow(_ index: Int) {
            guard let table = markdown.table(containing: index) else { return }
            let offset = index - table.lines.lowerBound
            if index == table.lines.lowerBound {
                closeAll()
                output.append("<table><thead>")
                block = .table
            }
            if index == table.delimiterLine {
                output.append("</thead><tbody>")
                return
            }
            let cell = offset == 0 ? "th" : "td"
            let cells = zip(table.cells[offset], table.alignments).map { range, alignment in
                let align =
                    switch alignment {
                    case .leading: ""
                    case .center: " style=\"text-align: center\""
                    case .trailing: " style=\"text-align: right\""
                    }
                return "<\(cell)\(align)>\(NoteExport.inline(markdown.cell(range)))</\(cell)>"
            }
            output.append("<tr>\(cells.joined())</tr>")
        }

        private func inline(_ line: NoteMarkdown.Line) -> String {
            NoteExport.inline(markdown.cell(line.contentRange))
        }
    }

    /// Spans are well nested, so a stack closes each one where it ends.
    static func inline(_ cell: NoteMarkdown.TableCell) -> String {
        let text = cell.text as NSString
        let runs = cell.runs.sorted { ($0.range.location, -$0.range.length) < ($1.range.location, -$1.range.length) }
        var boundaries = Set([0, text.length])
        for run in runs {
            boundaries.insert(run.range.location)
            boundaries.insert(NSMaxRange(run.range))
        }
        let points = boundaries.sorted()
        var html = ""
        var open: [NoteMarkdown.TableCell.Run] = []
        var next = 0
        for (position, point) in points.enumerated() {
            while let top = open.last, NSMaxRange(top.range) <= point {
                html += tags(for: top.kind, text: text.substring(with: top.range)).close
                open.removeLast()
            }
            while next < runs.count, runs[next].range.location == point {
                html += tags(for: runs[next].kind, text: text.substring(with: runs[next].range)).open
                open.append(runs[next])
                next += 1
            }
            if position + 1 < points.count {
                html += escape(text.substring(with: NSRange(point..<points[position + 1])))
            }
        }
        return html
    }

    private static func tags(for kind: NoteMarkdown.Inline.Kind, text: String) -> (open: String, close: String) {
        switch kind {
        case .strong: ("<strong>", "</strong>")
        case .emphasis: ("<em>", "</em>")
        case .strongEmphasis: ("<strong><em>", "</em></strong>")
        case .strikethrough: ("<del>", "</del>")
        case .code: ("<code>", "</code>")
        case .link(let destination): ("<a href=\"\(escape(destination))\">", "</a>")
        case .autolink: ("<a href=\"\(escape(text))\">", "</a>")
        }
    }

    static func escape(_ text: String) -> String {
        var escaped = ""
        escaped.reserveCapacity(text.count)
        for character in text {
            switch character {
            case "&": escaped += "&amp;"
            case "<": escaped += "&lt;"
            case ">": escaped += "&gt;"
            case "\"": escaped += "&quot;"
            default: escaped.append(character)
            }
        }
        return escaped
    }

    private static func raw(_ range: NSRange, in markdown: NoteMarkdown) -> String {
        let units = markdown.units[range.location..<NSMaxRange(range)]
        return String(decoding: units, as: UTF16.self)
    }
}
