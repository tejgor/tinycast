import AppKit
import SwiftUI

/// The ⌘K panel: a child window hung above the note's bottom-trailing corner, as Raycast places it.
@MainActor
final class NoteActionsWindowController: NSObject, NSWindowDelegate {
    private static let width: CGFloat = 320
    private static let maxHeight: CGFloat = 400
    private static let inset = Theme.Spacing.md

    private unowned let coordinator: NotesCoordinator
    private var panel: NotesPanel?
    private var height = maxHeight

    init(coordinator: NotesCoordinator) {
        self.coordinator = coordinator
    }

    func show(over host: NSWindow) {
        let panel = ensurePanel()
        anchor(panel, over: host)
        if panel.parent !== host {
            panel.parent?.removeChildWindow(panel)
            host.addChildWindow(panel, ordered: .above)
        }
        panel.makeKeyAndOrderFront(nil)
        panel.invalidateShadow()
    }

    func hide() {
        guard let panel else { return }
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
    }

    // MARK: - NSWindowDelegate

    /// Closes like a popover; focus stays where the click landed.
    func windowDidResignKey(_ notification: Notification) {
        guard coordinator.isActionsPresented else { return }
        coordinator.closeActions(focusEditor: false)
    }

    // MARK: - Private

    private func ensurePanel() -> NotesPanel {
        if let panel { return panel }
        let root = NoteActionsView { [weak self] in self?.resize(toContentHeight: $0) }
            .environment(coordinator)
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []
        let panel = NotesPanel(
            content: hosting,
            size: CGSize(width: Self.width, height: Self.maxHeight),
            styleMask: .borderless,
            acceptsMain: false)
        panel.delegate = self
        let dismiss: () -> Void = { [weak coordinator] in coordinator?.closeActions() }
        panel.onEscape = dismiss
        panel.commandChords = ["k": dismiss, "w": dismiss]
        panel.interceptKeyDown = { [weak coordinator] event in
            let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
            guard modifiers == .command, let coordinator else { return false }
            switch event.specialKey {
            case .downArrow?: coordinator.moveActionsSection(by: 1)
            case .upArrow?: coordinator.moveActionsSection(by: -1)
            default: return false
            }
            return true
        }
        self.panel = panel
        return panel
    }

    private func anchor(_ panel: NotesPanel, over host: NSWindow) {
        let frame = host.frame
        let origin = CGPoint(
            x: frame.maxX - Self.width - Self.inset,
            y: frame.minY + Theme.Size.bottomBarHeight)
        panel.setFrame(NSRect(origin: origin, size: CGSize(width: Self.width, height: height)), display: false)
    }

    /// Grows upward from its bottom edge, so the search field stays put while the list changes.
    private func resize(toContentHeight content: CGFloat) {
        let fitted = min(Self.maxHeight, content)
        guard abs(fitted - height) > 0.5 else { return }
        height = fitted
        guard let panel, let host = panel.parent else { return }
        anchor(panel, over: host)
        panel.invalidateShadow()
    }
}
