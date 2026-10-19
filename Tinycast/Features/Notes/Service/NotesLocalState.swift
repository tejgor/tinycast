import Foundation
import Observation

/// Notes state local to this Mac that is neither a preference nor note content, so no backup carries it.
@MainActor
@Observable
final class NotesLocalState {
    private enum Key {
        static let autoSizesWindow = "notesWindowAutoSizes"
        static let zoom = "notesZoom"
        static let countsWords = "notesCountsWords"
        static let pinned = "notesPinned"
        static let lastOpened = "notesLastOpened"
    }

    /// The steps ⌘+ and ⌘− walk; 1 is actual size.
    static let zoomSteps: [Double] = [0.75, 0.85, 1, 1.15, 1.3, 1.5, 1.75, 2]

    @ObservationIgnored private let defaults: UserDefaults

    /// The window follows the note's height until the user sizes it by hand.
    var autoSizesWindow: Bool {
        didSet { defaults.set(autoSizesWindow, forKey: Key.autoSizesWindow) }
    }

    var zoom: Double {
        didSet { defaults.set(zoom, forKey: Key.zoom) }
    }

    /// The footer counts words instead of characters.
    var countsWords: Bool {
        didSet { defaults.set(countsWords, forKey: Key.countsWords) }
    }

    /// Pinned notes in the order they were pinned; ⌘1–⌘9 open the first nine.
    private(set) var pinned: [NoteID] {
        didSet { defaults.set(pinned.map(\.rawValue), forKey: Key.pinned) }
    }

    /// When each note was last shown; the browser lists the most recent first.
    private(set) var lastOpened: [NoteID: Date] {
        didSet {
            let stored = Dictionary(uniqueKeysWithValues: lastOpened.map { ($0.key.rawValue, $0.value) })
            defaults.set(stored, forKey: Key.lastOpened)
        }
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        autoSizesWindow = defaults.object(forKey: Key.autoSizesWindow) as? Bool ?? true
        let storedZoom = defaults.double(forKey: Key.zoom)
        zoom = Self.zoomSteps.contains(storedZoom) ? storedZoom : 1
        countsWords = defaults.bool(forKey: Key.countsWords)
        pinned = (defaults.stringArray(forKey: Key.pinned) ?? []).map(NoteID.init(rawValue:))
        let opened = defaults.dictionary(forKey: Key.lastOpened) as? [String: Date] ?? [:]
        lastOpened = Dictionary(uniqueKeysWithValues: opened.map { (NoteID(rawValue: $0.key), $0.value) })
    }

    func isPinned(_ id: NoteID) -> Bool {
        pinned.contains(id)
    }

    func togglePin(_ id: NoteID) {
        if let index = pinned.firstIndex(of: id) {
            pinned.remove(at: index)
        } else {
            pinned.append(id)
        }
    }

    func noteOpened(_ id: NoteID, at date: Date) {
        lastOpened[id] = date
    }

    /// A rename is a new identity, so the pin and the open time move to it.
    func noteRenamed(_ old: NoteID, to new: NoteID) {
        guard old != new else { return }
        pinned = pinned.map { $0 == old ? new : $0 }
        if let opened = lastOpened.removeValue(forKey: old) { lastOpened[new] = opened }
    }

    func notesRemoved(_ ids: Set<NoteID>) {
        pinned.removeAll { ids.contains($0) }
        for id in ids { lastOpened.removeValue(forKey: id) }
    }

    /// One step along `zoomSteps`, stopping at either end.
    func stepZoom(by offset: Int) {
        let current = Self.zoomSteps.firstIndex(of: zoom) ?? Self.zoomSteps.firstIndex(of: 1) ?? 0
        zoom = Self.zoomSteps[min(max(current + offset, 0), Self.zoomSteps.count - 1)]
    }
}
