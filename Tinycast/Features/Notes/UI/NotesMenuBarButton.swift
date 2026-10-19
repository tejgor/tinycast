import AppKit

/// The status item Show Notes Button in Menu Bar adds: a click shows or hides the notes window.
@MainActor
final class NotesMenuBarButton: NSObject {
    private var item: NSStatusItem?
    private let onClick: () -> Void

    init(onClick: @escaping () -> Void) {
        self.onClick = onClick
    }

    func setShown(_ shown: Bool) {
        guard shown != (item != nil) else { return }
        guard shown else {
            if let item { NSStatusBar.system.removeStatusItem(item) }
            item = nil
            return
        }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: "note.text", accessibilityDescription: String(localized: "Notes"))
        item.button?.target = self
        item.button?.action = #selector(clicked)
        self.item = item
    }

    @objc private func clicked() {
        onClick()
    }
}
