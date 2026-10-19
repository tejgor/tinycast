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

    init(defaults: UserDefaults) {
        self.defaults = defaults
        autoSizesWindow = defaults.object(forKey: Key.autoSizesWindow) as? Bool ?? true
        let storedZoom = defaults.double(forKey: Key.zoom)
        zoom = Self.zoomSteps.contains(storedZoom) ? storedZoom : 1
        countsWords = defaults.bool(forKey: Key.countsWords)
    }

    /// One step along `zoomSteps`, stopping at either end.
    func stepZoom(by offset: Int) {
        let current = Self.zoomSteps.firstIndex(of: zoom) ?? Self.zoomSteps.firstIndex(of: 1) ?? 0
        zoom = Self.zoomSteps[min(max(current + offset, 0), Self.zoomSteps.count - 1)]
    }
}
