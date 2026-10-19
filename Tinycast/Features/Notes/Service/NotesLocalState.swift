import Foundation
import Observation

/// Notes state local to this Mac that is neither a preference nor note content, so no backup carries it.
@MainActor
@Observable
final class NotesLocalState {
    private enum Key {
        static let autoSizesWindow = "notesWindowAutoSizes"
    }

    @ObservationIgnored private let defaults: UserDefaults

    /// The window follows the note's height until the user sizes it by hand.
    var autoSizesWindow: Bool {
        didSet { defaults.set(autoSizesWindow, forKey: Key.autoSizesWindow) }
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        autoSizesWindow = defaults.object(forKey: Key.autoSizesWindow) as? Bool ?? true
    }
}
