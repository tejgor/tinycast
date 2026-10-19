import Foundation

/// One row of the notes ⌘K panel; `section` groups rows, so ⌘↑ and ⌘↓ can jump between groups.
struct NoteActionItem: Identifiable {
    let id: String
    let title: String
    let symbol: String
    var shortcut: String?
    var isDestructive = false
    let section: Int
    let perform: @MainActor () -> Void
}

extension NotesCoordinator {
    /// What the panel offers for the note on screen; with no note, only what needs none.
    var actionItems: [NoteActionItem] {
        var items = [
            NoteActionItem(
                id: "new", title: String(localized: "New Note"), symbol: "square.and.pencil", shortcut: "⌘N",
                section: 0, perform: createNote),
            NoteActionItem(
                id: "browse", title: String(localized: "Browse Notes"), symbol: "magnifyingglass",
                shortcut: "⌘P", section: 0, perform: searchNotes),
            NoteActionItem(
                id: "back", title: String(localized: "Go Back"), symbol: "chevron.left", shortcut: "⌘[",
                section: 0, perform: goBack),
            NoteActionItem(
                id: "forward", title: String(localized: "Go Forward"), symbol: "chevron.right", shortcut: "⌘]",
                section: 0, perform: goForward)
        ]
        if hasActiveNote {
            let pinned = isActiveNotePinned
            items += [
                NoteActionItem(
                    id: "pin", title: pinned ? String(localized: "Unpin Note") : String(localized: "Pin Note"),
                    symbol: pinned ? "pin.slash" : "pin", shortcut: "⇧⌘P", section: 1,
                    perform: togglePinActiveNote),
                NoteActionItem(
                    id: "duplicate", title: String(localized: "Duplicate Note"),
                    symbol: "plus.square.on.square", section: 1, perform: duplicateActiveNote),
                NoteActionItem(
                    id: "copy-markdown", title: String(localized: "Copy Note as Markdown"), symbol: "doc.on.doc",
                    section: 1, perform: { self.copyActiveNote(as: .markdown) }),
                NoteActionItem(
                    id: "copy-html", title: String(localized: "Copy Note as HTML"),
                    symbol: "chevron.left.forwardslash.chevron.right", section: 1,
                    perform: { self.copyActiveNote(as: .html) }),
                NoteActionItem(
                    id: "copy-plain", title: String(localized: "Copy Note as Plain Text"), symbol: "doc.plaintext",
                    section: 1, perform: { self.copyActiveNote(as: .plainText) }),
                NoteActionItem(
                    id: "copy-deeplink", title: String(localized: "Copy Deeplink"), symbol: "link", section: 1,
                    perform: copyActiveNoteDeepLink),
                NoteActionItem(
                    id: "export-markdown", title: String(localized: "Export as Markdown…"),
                    symbol: "square.and.arrow.up", section: 1, perform: { self.exportActiveNote(as: .markdown) }),
                NoteActionItem(
                    id: "export-html", title: String(localized: "Export as HTML…"), symbol: "square.and.arrow.up",
                    section: 1, perform: { self.exportActiveNote(as: .html) }),
                NoteActionItem(
                    id: "export-plain", title: String(localized: "Export as Plain Text…"),
                    symbol: "square.and.arrow.up", section: 1, perform: { self.exportActiveNote(as: .plainText) }),
                NoteActionItem(
                    id: "find", title: String(localized: "Find in Note"), symbol: "text.magnifyingglass",
                    shortcut: "⌘F", section: 2, perform: findInNote)
            ]
            if showsFormattingBar {
                items.append(
                    NoteActionItem(
                        id: "format-bar",
                        title: isFormattingBarExpanded
                            ? String(localized: "Hide Format Buttons") : String(localized: "Show Format Buttons"),
                        symbol: "paintbrush", shortcut: "⌥⌘T", section: 2, perform: toggleFormattingBar))
            }
            items += [
                NoteActionItem(
                    id: "auto-size",
                    title: autoSizesWindow
                        ? String(localized: "Disable Window Auto-Sizing")
                        : String(localized: "Enable Window Auto-Sizing"),
                    symbol: "arrow.up.and.down.square", section: 2, perform: toggleWindowAutoSizing),
                NoteActionItem(
                    id: "zoom-in", title: String(localized: "Zoom In"), symbol: "plus.magnifyingglass",
                    shortcut: "⌘+", section: 2, perform: zoomIn),
                NoteActionItem(
                    id: "zoom-out", title: String(localized: "Zoom Out"), symbol: "minus.magnifyingglass",
                    shortcut: "⌘−", section: 2, perform: zoomOut),
                NoteActionItem(
                    id: "zoom-reset", title: String(localized: "Actual Size"), symbol: "1.magnifyingglass",
                    shortcut: "⌘0", section: 2, perform: resetZoom)
            ]
        }
        items += [
            NoteActionItem(
                id: "folder", title: String(localized: "Open Notes Folder"), symbol: "folder", shortcut: "⌘O",
                section: 2, perform: openNotesFolder),
            NoteActionItem(
                id: "settings", title: String(localized: "Open Notes Settings"), symbol: "gearshape", section: 2,
                perform: openNotesSettings)
        ]
        if hasActiveNote {
            items.append(
                NoteActionItem(
                    id: "delete", title: String(localized: "Delete Note"), symbol: "trash", isDestructive: true,
                    section: 3, perform: trashActiveNote))
        }
        if !visibleNotes.isEmpty || hasActiveNote {
            items.append(
                NoteActionItem(
                    id: "delete-all", title: String(localized: "Delete All Notes"), symbol: "trash.fill",
                    isDestructive: true, section: 3, perform: trashAllNotes))
        }
        return items
    }

    /// Every word typed has to appear in the title, in any order.
    var visibleActions: [NoteActionItem] {
        let terms = actionsQuery.lowercased().split(whereSeparator: \.isWhitespace)
        guard !terms.isEmpty else { return actionItems }
        return actionItems.filter { item in
            let title = item.title.lowercased()
            return terms.allSatisfy { title.contains($0) }
        }
    }
}
