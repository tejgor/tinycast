import Foundation

/// Decides which lines show their raw Markdown rather than its rendered form.
enum NoteRevealPolicy {
    /// Lines that show raw syntax: those under the selection, plus block fences and whole tables.
    static func revealedLines(
        selection: NSRange, markdown: NoteMarkdown, isFocused: Bool
    ) -> IndexSet {
        guard isFocused, selection.location != NSNotFound else { return IndexSet() }
        var revealed = IndexSet(integersIn: markdown.lineIndexes(intersecting: selection))
        guard let first = revealed.first, let last = revealed.last else { return revealed }
        for block in markdown.fenceBlocks where block.overlaps(first...last) {
            revealed.insert(block.lowerBound)
            revealed.insert(block.upperBound)
        }
        // A grid's columns size to every row, so it is edited as source all at once.
        for table in markdown.tables where table.lines.overlaps(first...last) {
            revealed.insert(integersIn: table.lines)
        }
        return revealed
    }

    /// Carries a revealed set across an edit so stale lines can still be found and re-hidden.
    static func shifted(
        _ revealed: IndexSet, editedOldLines: Range<Int>, editedNewLines: Range<Int>
    ) -> IndexSet {
        let delta = editedNewLines.count - editedOldLines.count
        var shifted = IndexSet()
        for index in revealed where !editedOldLines.contains(index) {
            shifted.insert(index < editedOldLines.lowerBound ? index : index + delta)
        }
        shifted.insert(integersIn: editedNewLines)
        return shifted
    }
}
