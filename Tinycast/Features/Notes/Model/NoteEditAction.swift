import Foundation

enum NoteEditAction: Sendable, Equatable {
    enum InlineStyle: Sendable, CaseIterable { case bold, italic, strikethrough, code }
    enum ListStyle: Sendable { case bullet, ordered, task }

    case newline
    case deleteBackward
    case indent
    case outdent
    case toggleInline(InlineStyle)
    case toggleLink
    /// Level 0 turns the line back into a plain paragraph.
    case setHeading(level: Int)
    case toggleList(ListStyle)
    case toggleCodeBlock
    case toggleQuote
    /// An empty three-column table, on the caret's line when blank and below it otherwise.
    case insertTable
    case toggleTask(lineIndex: Int)
    /// The `[] ` input rule.
    case typedSpace
    case pasteURL(String)
}
