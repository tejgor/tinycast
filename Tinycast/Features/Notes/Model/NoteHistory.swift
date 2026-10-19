import Foundation

/// The notes opened this session, walked by ⌘[ and ⌘] the way a browser walks its pages.
struct NoteHistory: Sendable, Equatable {
    private static let limit = 100

    private(set) var entries: [NoteID] = []
    private(set) var position = -1

    /// Opening a note drops anything ahead of the current one, as following a link does.
    mutating func visit(_ id: NoteID) {
        guard current != id else { return }
        entries = Array(entries.prefix(position + 1)) + [id]
        if entries.count > Self.limit { entries.removeFirst(entries.count - Self.limit) }
        position = entries.count - 1
    }

    /// Steps over notes that no longer exist, and stays put when nothing is left that way.
    mutating func step(_ offset: Int, exists: (NoteID) -> Bool) -> NoteID? {
        var index = position + offset
        while entries.indices.contains(index) {
            if exists(entries[index]), entries[index] != current {
                position = index
                return entries[index]
            }
            index += offset
        }
        return nil
    }

    /// A rename gives a note a new identity; its history follows it.
    mutating func rename(_ old: NoteID, to new: NoteID) {
        entries = entries.map { $0 == old ? new : $0 }
    }

    private var current: NoteID? {
        entries.indices.contains(position) ? entries[position] : nil
    }
}
