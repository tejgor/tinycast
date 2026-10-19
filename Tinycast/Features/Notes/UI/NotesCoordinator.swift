import AppKit
import SwiftUI

@MainActor
@Observable
final class NotesCoordinator {
    private enum Presentation {
        case editor
        case create
        case search
    }

    private let store: NotesStore
    private let settings: AppSettings
    private let appIndex: AppIndex
    private unowned let core: AppCore
    @ObservationIgnored private lazy var windowController = NotesWindowController(coordinator: self)
    @ObservationIgnored private lazy var switcherController = NoteSwitcherWindowController(
        coordinator: self)
    @ObservationIgnored private lazy var headingMenuController = NoteHeadingMenuWindowController(
        coordinator: self)
    @ObservationIgnored private lazy var actionsController = NoteActionsWindowController(coordinator: self)
    private(set) var isActionsPresented = false
    private(set) var actionsQuery = ""
    private(set) var actionsSelection: String?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var issueTask: Task<Void, Never>?
    @ObservationIgnored private var operationTask: Task<Void, Never>?
    @ObservationIgnored private var operationID = 0
    @ObservationIgnored private var pendingIssue: NotesStore.Issue?
    private var pendingPresentation: Presentation?
    private var enablementGeneration = 0
    private(set) var isSwitcherPresented = false
    private(set) var switcherSelection: NoteID?
    private(set) var switcherFocusRevision = 0
    private(set) var characterCount = 0
    private(set) var formatting = NoteFormatting.plain
    private(set) var isFormattingBarExpanded: Bool
    private(set) var isHeadingMenuPresented = false
    /// A press closes the menu before its button fires, so the button must not reopen it.
    @ObservationIgnored private var headingMenuWasOpenAtPress = false
    /// The heading button in the panel's flipped content space, reported by the bar as it lays out.
    @ObservationIgnored var headingButtonFrame: CGRect = .zero
    private var switcherRename = NoteSwitcherRenameState()
    @ObservationIgnored private var history = NoteHistory()
    @ObservationIgnored private var countCache: [NoteID: (modified: Date, count: Int)] = [:]
    private(set) var noteCounts: [NoteID: Int] = [:]
    /// A deeplink that arrived while the window was hidden, opened once the editor shows.
    @ObservationIgnored private var pendingLinkedNote: NoteID?
    @ObservationIgnored private lazy var menuBarButton = NotesMenuBarButton { [weak self] in self?.toggle() }
    private var presentationGeneration = 0

    @ObservationIgnored private let saveFormattingBarExpanded: @Sendable (Bool) -> Void
    let local: NotesLocalState

    init(
        store: NotesStore,
        settings: AppSettings,
        appIndex: AppIndex,
        core: AppCore,
        isFormattingBarExpanded: Bool = false,
        saveFormattingBarExpanded: @escaping @Sendable (Bool) -> Void = { _ in },
        local: NotesLocalState
    ) {
        self.store = store
        self.settings = settings
        self.appIndex = appIndex
        self.core = core
        self.isFormattingBarExpanded = isFormattingBarExpanded
        self.saveFormattingBarExpanded = saveFormattingBarExpanded
        self.local = local
        store.onIssue = { [weak self] issue in self?.present(issue) }
        trackHistory()
        trackMenuBarButton()
    }

    var editorInput: NoteEditorInput {
        NoteEditorInput(
            id: store.activeID ?? NoteID(rawValue: ""),
            source: store.source,
            epoch: store.editorEpoch)
    }

    var hasActiveNote: Bool { store.activeID != nil }
    /// UTF-16 units, straight off the text storage: the only length TextKit hands back in O(1).
    var characterCountLabel: String {
        guard local.countsWords else { return String(localized: "\(characterCount) characters") }
        // Markdown markers such as `-` and `[ ]` hold no letter or digit, so they are not words.
        let words = store.source.split(whereSeparator: \.isWhitespace)
            .count { $0.contains { $0.isLetter || $0.isNumber } }
        return String(localized: "\(words) words")
    }

    func toggleCountMode() {
        local.countsWords.toggle()
    }

    var zoom: CGFloat { CGFloat(local.zoom) }

    func zoomIn() { setZoom { $0.stepZoom(by: 1) } }

    func zoomOut() { setZoom { $0.stepZoom(by: -1) } }

    func resetZoom() { setZoom { $0.zoom = 1 } }

    private func setZoom(_ change: (NotesLocalState) -> Void) {
        change(local)
        windowController.refit()
    }

    // MARK: - History

    func goBack() { stepHistory(-1) }

    func goForward() { stepHistory(1) }

    private func stepHistory(_ offset: Int) {
        let existing = Set(store.summaries.map(\.id))
        guard let id = history.step(offset, exists: existing.contains) else { return }
        select(id)
    }

    private func trackMenuBarButton() {
        let shown = withObservationTracking {
            settings.notesEnabled && settings.notesShowsMenuBarButton
        } onChange: { [weak self] in
            Task { @MainActor in self?.trackMenuBarButton() }
        }
        menuBarButton.setShown(shown)
    }

    /// Re-armed after every change, so each note the window shows lands in the history once.
    private func trackHistory() {
        // Read inside, act outside: writing the open time while tracking could re-trigger the tracking.
        let active = withObservationTracking {
            store.activeID
        } onChange: { [weak self] in
            Task { @MainActor in self?.trackHistory() }
        }
        guard let active else { return }
        history.visit(active)
        local.noteOpened(active, at: Date())
    }

    var searchQueryBinding: Binding<String> {
        Binding(
            get: { [weak self] in self?.store.searchQuery ?? "" },
            set: { [weak self] in self?.store.updateSearchQuery($0) })
    }

    var activeTitle: String { store.activeTitle }
    var rendersMarkdown: Bool { settings.notesRendersMarkdown }
    /// Settings > General > Transparency thins the note window's scrim as it does the launcher's.
    var scrimOpacity: Double { 1 - Double(settings.paletteTransparency) / 100 }
    var showsFormattingBar: Bool { settings.notesRendersMarkdown && settings.notesShowsFormattingBar }
    var isSearching: Bool { store.isSearching }
    var visibleNotes: [NoteSummary] {
        guard isBrowsingAll else { return store.searchResults.map(\.summary) }
        return pinnedNotes + recentNotes
    }

    var isBrowsingAll: Bool {
        store.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// In pin order; a pin whose file is gone is skipped rather than shown empty.
    var pinnedNotes: [NoteSummary] {
        let byID = Dictionary(store.summaries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return local.pinned.compactMap { byID[$0] }
    }

    /// Most recently opened first; a note never opened here counts from its last edit.
    var recentNotes: [NoteSummary] {
        store.summaries.filter { !local.isPinned($0.id) }.sorted { lastSeen($0) > lastSeen($1) }
    }

    func lastOpened(_ summary: NoteSummary) -> Date? {
        local.lastOpened[summary.id]
    }

    private func lastSeen(_ summary: NoteSummary) -> Date {
        local.lastOpened[summary.id] ?? summary.modifiedAt
    }

    func isPinned(_ id: NoteID) -> Bool {
        local.isPinned(id)
    }

    var isActiveNotePinned: Bool {
        store.activeID.map(local.isPinned) ?? false
    }

    func togglePin(_ id: NoteID) {
        local.togglePin(id)
    }

    func togglePinActiveNote() {
        guard let id = store.activeID else { return }
        local.togglePin(id)
    }

    func toggleSwitcherSelectionPin() {
        guard let id = switcherSelection else { return }
        local.togglePin(id)
    }

    /// ⌘1–⌘9, counted from one in the order the notes were pinned.
    func openPinned(_ slot: Int) {
        let pinned = pinnedNotes
        guard pinned.indices.contains(slot - 1) else { return }
        select(pinned[slot - 1].id)
    }

    // MARK: - Actions

    var actionsQueryBinding: Binding<String> {
        Binding(
            get: { [weak self] in self?.actionsQuery ?? "" },
            set: { [weak self] in
                self?.actionsQuery = $0
                self?.actionsSelection = self?.visibleActions.first?.id
            })
    }

    func toggleActions() {
        if isActionsPresented { closeActions() } else { openActions() }
    }

    func openActions() {
        guard settings.notesEnabled, windowController.isVisible else { return }
        closeHeadingMenu()
        closeSwitcher(focusEditor: false)
        actionsQuery = ""
        actionsSelection = visibleActions.first?.id
        isActionsPresented = true
        windowController.presentActions(actionsController)
    }

    func closeActions(focusEditor: Bool = true) {
        guard isActionsPresented else { return }
        isActionsPresented = false
        actionsController.hide()
        if focusEditor { windowController.focusEditor() }
    }

    func moveActionsSelection(by offset: Int) {
        let items = visibleActions
        guard !items.isEmpty else { return }
        let index = items.firstIndex { $0.id == actionsSelection } ?? (offset > 0 ? -1 : items.count)
        actionsSelection = items[(index + offset + items.count) % items.count].id
    }

    /// ⌘↓ lands on the next group's first row; ⌘↑ on this group's first, then the one before.
    func moveActionsSection(by offset: Int) {
        let items = visibleActions
        guard let index = items.firstIndex(where: { $0.id == actionsSelection }) else { return }
        let starts = items.indices.filter { $0 == 0 || items[$0].section != items[$0 - 1].section }
        let current = starts.last { $0 <= index } ?? 0
        let target =
            offset > 0
            ? starts.first { $0 > index }
            : (index > current ? current : starts.last { $0 < current })
        if let target { actionsSelection = items[target].id }
    }

    func performSelectedAction() {
        guard let item = visibleActions.first(where: { $0.id == actionsSelection }) else { return }
        perform(item)
    }

    /// Closes first, so an action that opens a window or sheet finds the note window key.
    func perform(_ item: NoteActionItem) {
        closeActions()
        item.perform()
    }

    func findInNote() {
        windowController.showFindBar()
    }

    func trashActiveNote() {
        guard let id = store.activeID else { return }
        trash(id)
    }

    func openNotesSettings() {
        core.settingsCoordinator.showSettings(tab: .notes)
    }

    // MARK: - Deeplinks

    /// True for any notes link, handled or not, so no other handler reads it as its own.
    func handleDeepLink(_ url: URL) -> Bool {
        guard let route = NoteDeepLink.route(url) else { return false }
        guard settings.notesEnabled else { return true }
        switch route {
        case .show:
            if !windowController.isVisible { request(.editor) }
        case .open(let id):
            if windowController.isVisible, store.isLoaded {
                select(id)
            } else {
                pendingLinkedNote = id
                request(.editor)
            }
        }
        return true
    }

    // MARK: - Copy and export

    func copyActiveNote(as format: NoteExport.Format) {
        guard hasActiveNote else { return }
        let text = NoteExport.string(format, source: store.source, title: activeTitle)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        switch format {
        case .html:
            // Rich text where the destination reads HTML; the plain rendering everywhere else.
            pasteboard.setString(text, forType: .html)
            pasteboard.setString(NoteExport.string(.plainText, source: store.source, title: activeTitle), forType: .string)
        case .markdown, .plainText:
            pasteboard.setString(text, forType: .string)
        }
        core.showMessage(String(localized: "Copied"))
    }

    func copyActiveNoteDeepLink() {
        guard let id = store.activeID, let url = NoteDeepLink.url(for: id) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
        core.showMessage(String(localized: "Copied Deeplink"))
    }

    func exportActiveNote(as format: NoteExport.Format) {
        guard hasActiveNote else { return }
        let text = NoteExport.string(format, source: store.source, title: activeTitle)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(activeTitle).\(format.fileExtension)"
        panel.canCreateDirectories = true
        windowController.presentSavePanel(panel) { [weak self] url in
            guard let url else { return }
            do {
                try Data(text.utf8).write(to: url, options: .atomic)
            } catch {
                self?.core.showMessage(String(localized: "Couldn't export the note"), tone: .danger)
            }
        }
    }

    // MARK: - Counts

    /// The live count for the open note; the rest are read off-main and kept until their file changes.
    func characterCount(of id: NoteID) -> Int? {
        id == store.activeID ? characterCount : noteCounts[id]
    }

    func refreshNoteCounts() {
        let directory = store.notesDirectory
        let stale = visibleNotes.prefix(200)
            .filter { countCache[$0.id]?.modified != $0.modifiedAt }
            .map { ($0.id, $0.modifiedAt) }
        guard !stale.isEmpty else { return }
        Task { [weak self] in
            let counted = await Task.detached(priority: .utility) {
                stale.compactMap { id, modified -> (NoteID, Date, Int)? in
                    let url = directory.appendingPathComponent(id.rawValue)
                    guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
                    return (id, modified, text.utf16.count)
                }
            }.value
            guard let self else { return }
            for (id, modified, count) in counted { countCache[id] = (modified, count) }
            noteCounts = countCache.mapValues(\.count)
        }
    }
    var switcherEditingID: NoteID? { switcherRename.id }
    var isRenamingSwitcherNote: Bool { switcherRename.isActive }
    var switcherTitleDraftBinding: Binding<String> {
        Binding(
            get: { [weak self] in self?.switcherRename.draft ?? "" },
            set: { [weak self] in self?.switcherRename.updateDraft($0) })
    }

    func applyEnabled() {
        enablementGeneration &+= 1
        let generation = enablementGeneration
        appIndex.setCommandsVisible([.showNotes, .createNote, .searchNotes], settings.notesEnabled)
        guard !settings.notesEnabled else { return }
        presentationGeneration &+= 1
        pendingPresentation = nil
        loadTask?.cancel()
        loadTask = nil
        operationTask?.cancel()
        closeHeadingMenu()
        closeSwitcher(focusEditor: false)
        windowController.hide(restoreFocus: false)
        Task { [weak self] in
            guard let self else { return }
            _ = await store.flush()
            guard generation == enablementGeneration, !settings.notesEnabled else { return }
            store.stop()
        }
    }

    /// Quit waits on this so the 300 ms autosave debounce cannot swallow the last edit.
    func prepareForTermination() async {
        await store.flush()
    }

    func toggle() {
        if windowController.isVisible {
            hide()
        } else {
            request(.editor)
        }
    }

    func createNote() {
        request(.create)
    }

    func searchNotes() {
        request(.search)
    }

    func openSwitcher() {
        guard settings.notesEnabled, store.isLoaded else { return }
        closeHeadingMenu()
        if isSwitcherPresented {
            switcherFocusRevision &+= 1
            return
        }
        isSwitcherPresented = true
        switcherSelection = store.activeID ?? store.summaries.first?.id
        switcherFocusRevision &+= 1
        windowController.presentSwitcher(switcherController)
    }

    func closeSwitcher(focusEditor: Bool = true) {
        guard isSwitcherPresented || !store.searchQuery.isEmpty else { return }
        switcherRename.cancel()
        isSwitcherPresented = false
        switcherSelection = nil
        store.cancelSearch()
        switcherController.hide()
        if focusEditor { windowController.focusEditor() }
    }

    func hide() {
        closeActions(focusEditor: false)
        closeHeadingMenu()
        presentationGeneration &+= 1
        pendingPresentation = nil
        closeSwitcher(focusEditor: false)
        windowController.hide(restoreFocus: true)
        Task { await store.flush() }
    }

    func handleEscape() {
        if isActionsPresented {
            closeActions()
        } else if isHeadingMenuPresented {
            closeHeadingMenu()
        } else if isSwitcherPresented {
            closeSwitcher()
        } else if settings.notesEscapeLosesFocus {
            windowController.releaseFocus()
        } else {
            hide()
        }
    }

    func reconcileSwitcherSelection() {
        let notes = visibleNotes
        guard !notes.isEmpty else {
            switcherSelection = nil
            return
        }
        if let switcherSelection, notes.contains(where: { $0.id == switcherSelection }) { return }
        switcherSelection = notes.first?.id
    }

    func moveSwitcherSelection(by offset: Int) {
        let notes = visibleNotes
        guard !notes.isEmpty else {
            switcherSelection = nil
            return
        }
        guard let current = switcherSelection,
            let index = notes.firstIndex(where: { $0.id == current })
        else {
            switcherSelection = notes[offset < 0 ? notes.count - 1 : 0].id
            return
        }
        switcherSelection = notes[(index + offset + notes.count) % notes.count].id
    }

    func selectSwitcherNote() {
        guard let switcherSelection else { return }
        select(switcherSelection)
    }

    func activateSwitcherNote(_ id: NoteID) {
        switcherRename.cancel()
        select(id)
    }

    /// Renaming edits the filename, so the field starts from that and never from a derived line.
    func beginSwitcherRename(_ summary: NoteSummary) {
        switcherRename.begin(id: summary.id, title: summary.title)
    }

    func commitSwitcherRename() {
        guard let committed = switcherRename.commit() else { return }
        rename(committed.id, to: committed.title)
        switcherFocusRevision &+= 1
    }

    func cancelSwitcherRename() {
        guard switcherRename.isActive else { return }
        switcherRename.cancel()
        switcherFocusRevision &+= 1
    }

    func select(_ id: NoteID) {
        runOperation { [weak self] generation in
            guard let self else { return }
            let selected = await store.select(id) { [weak self] in
                self?.permitsCompletion(generation) ?? false
            }
            guard selected, settings.notesEnabled, !Task.isCancelled else {
                if !settings.notesEnabled { store.stop() }
                return
            }
            guard permitsCompletion(generation) else { return }
            closeSwitcher()
            windowController.show(focusEditor: true)
        }
    }

    func rename(_ id: NoteID, to title: String) {
        runOperation { [weak self] generation in
            guard let self else { return }
            let renamedID = await store.rename(id, to: title)
            guard let renamedID, settings.notesEnabled, !Task.isCancelled else {
                if !settings.notesEnabled { store.stop() }
                return
            }
            switcherSelection = renamedID
            history.rename(id, to: renamedID)
            local.noteRenamed(id, to: renamedID)
            if renamedID == store.activeID, permitsCompletion(generation) {
                windowController.show(focusEditor: false)
            }
        }
    }

    func duplicateActiveNote() {
        guard let id = store.activeID else { return }
        runOperation { [weak self] generation in
            guard let self, await store.duplicate(id), permitsCompletion(generation) else { return }
            windowController.show(focusEditor: true)
        }
    }

    func trashAllNotes() {
        let count = store.summaries.count
        guard count > 0 else { return }
        runOperation { [weak self] generation in
            guard let self else { return }
            let confirmed = await core.confirm(
                title: String(localized: "Move all \(count) notes to Trash?"),
                message: String(localized: "You can recover them from the Trash in Finder."),
                symbol: nil,
                confirmTitle: String(localized: "Move to Trash"))
            guard confirmed, settings.notesEnabled, !Task.isCancelled else { return }
            let all = Set(store.summaries.map(\.id))
            _ = await store.trashAll()
            local.notesRemoved(all.subtracting(store.summaries.map(\.id)))
            closeSwitcher(focusEditor: false)
            guard permitsCompletion(generation) else { return }
            windowController.show(focusEditor: false)
        }
    }

    func trashSwitcherSelection() {
        guard let id = switcherSelection ?? store.activeID else { return }
        trash(id)
    }

    func handleDeleteShortcut() -> Bool {
        guard isSwitcherPresented, !switcherRename.isActive else { return false }
        trashSwitcherSelection()
        return true
    }

    func trash(_ id: NoteID) {
        guard let title = store.summaries.first(where: { $0.id == id })?.displayTitle else { return }
        runOperation { [weak self] generation in
            guard let self else { return }
            let confirmed = await core.confirm(
                title: String(localized: "Move “\(title)” to Trash?"),
                message: String(localized: "You can recover it from the Trash in Finder."),
                symbol: nil,
                confirmTitle: String(localized: "Move to Trash"))
            guard confirmed, settings.notesEnabled, !Task.isCancelled else { return }
            let switcherOrder = visibleNotes.map(\.id)
            let removed = await store.trash(id)
            guard removed, settings.notesEnabled, !Task.isCancelled else {
                if !settings.notesEnabled { store.stop() }
                return
            }
            local.notesRemoved([id])
            switcherSelection = NoteSwitcherSelection.replacement(
                afterRemoving: id,
                from: switcherOrder,
                fallback: store.activeID ?? store.summaries.first?.id)
            // Nothing left to browse, so the empty state owns the window rather than a bare list.
            if store.summaries.isEmpty { closeSwitcher(focusEditor: false) }
            guard permitsCompletion(generation) else { return }
            windowController.show(focusEditor: !isSwitcherPresented)
        }
    }

    /// Points Notes at a folder as it is; nothing is moved out of the old one.
    func chooseNotesFolder() {
        guard
            let url = FolderPicker.choose(
                message: String(localized: "Choose the folder your notes are kept in."),
                startingAt: store.notesDirectory)
        else { return }
        settings.notesFolder = AppPaths.contentFolderSetting(for: url, named: "Notes")
    }

    func resetNotesFolder() {
        settings.notesFolder = nil
    }

    func openNotesFolder() {
        guard let fileURL = store.activeFileURL else {
            NSWorkspace.shared.open(store.notesDirectory)
            return
        }
        AppLauncher.showInFinder(fileURL)
    }

    func moveToTopRight() {
        windowController.moveToTopRight()
    }

    var autoSizesWindow: Bool { local.autoSizesWindow }

    /// A size set by hand is the one wanted, so it ends auto-sizing until that is turned back on.
    func windowResizedByUser() {
        local.autoSizesWindow = false
    }

    func toggleWindowAutoSizing() {
        local.autoSizesWindow.toggle()
        if local.autoSizesWindow { windowController.refit() }
    }

    func updateSource(_ source: String) {
        closeHeadingMenu()
        store.updateSource(source)
    }

    func updateCharacterCount(_ input: NoteEditorInput, _ count: Int) {
        guard input == editorInput else { return }
        characterCount = count
    }

    /// Id and epoch, not the whole input: comparing a long source on every caret move is not free.
    func updateFormatting(_ input: NoteEditorInput, _ formatting: NoteFormatting) {
        let current = editorInput
        guard input.id == current.id, input.epoch == current.epoch, formatting != self.formatting else {
            return
        }
        self.formatting = formatting
    }

    func format(_ action: NoteEditAction) {
        windowController.format(action)
    }

    /// Collapsing takes the heading button with it, so its menu cannot outlive it.
    func toggleFormattingBar() {
        guard showsFormattingBar else { return }
        closeHeadingMenu()
        // Explicit, because the chord changes this from outside any view's transaction.
        withAnimation(Self.barMotion) { isFormattingBarExpanded.toggle() }
        saveFormattingBarExpanded(isFormattingBarExpanded)
    }

    private static var barMotion: Animation? {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            ? nil : Theme.MenuMotion.chevronAnimation
    }

    func toggleHeadingMenu() {
        guard !headingMenuWasOpenAtPress else {
            headingMenuWasOpenAtPress = false
            return
        }
        guard !isHeadingMenuPresented else { return closeHeadingMenu() }
        isHeadingMenuPresented = true
        windowController.presentHeadingMenu(headingMenuController)
    }

    func chooseHeading(_ level: Int) {
        closeHeadingMenu()
        format(.setHeading(level: level))
    }

    func closeHeadingMenu() {
        guard isHeadingMenuPresented else { return }
        isHeadingMenuPresented = false
        headingMenuController.hide()
    }

    func noteWindowMouseDown() {
        headingMenuWasOpenAtPress = isHeadingMenuPresented
        closeHeadingMenu()
    }

    func editorReady(_ textView: NoteTextView) {
        windowController.editorReady(textView)
    }

    private func request(_ presentation: Presentation) {
        guard settings.notesEnabled else { return }
        closeHeadingMenu()
        pendingPresentation = presentation
        guard loadTask == nil else { return }
        let generation = enablementGeneration
        loadTask = Task { [weak self] in
            guard let self else { return }
            // Create is its own load: the collection it would wait for is the one it adds to.
            let loaded = presentation == .create ? await store.create() : await store.start()
            guard generation == enablementGeneration else {
                if !settings.notesEnabled { store.stop() }
                return
            }
            loadTask = nil
            guard loaded, settings.notesEnabled, !Task.isCancelled else { return }
            // The note this task just made satisfies a create still pending; never make a second.
            if presentation == .create, pendingPresentation == .create {
                pendingPresentation = .editor
            }
            guard let next = pendingPresentation else { return }
            pendingPresentation = nil
            await present(next)
        }
    }

    private func present(_ presentation: Presentation) async {
        switch presentation {
        case .editor:
            closeSwitcher()
            windowController.show(focusEditor: true)
            if let linked = pendingLinkedNote {
                pendingLinkedNote = nil
                select(linked)
            }
        case .create:
            let generation = presentationGeneration
            guard await store.create(), settings.notesEnabled, !Task.isCancelled,
                generation == presentationGeneration
            else { return }
            closeSwitcher()
            windowController.show(focusEditor: true)
        case .search:
            // The switcher hangs off the note window, so that window has to exist first.
            windowController.show(focusEditor: false)
            openSwitcher()
        }
    }

    /// A newer show or hide retires an older operation's right to put what it loaded on screen.
    private func permitsCompletion(_ generation: Int) -> Bool {
        windowController.isVisible && generation == presentationGeneration
    }

    /// One collection operation at a time: a newer request cancels and supersedes an in-flight one.
    private func runOperation(_ body: @escaping @MainActor (Int) async -> Void) {
        operationTask?.cancel()
        operationID &+= 1
        let id = operationID
        let generation = presentationGeneration
        operationTask = Task { [weak self] in
            guard let self else { return }
            await body(generation)
            if self.operationID == id { self.operationTask = nil }
        }
    }

    private func present(_ issue: NotesStore.Issue) {
        guard issueTask == nil else {
            pendingIssue = issue
            return
        }
        issueTask = Task { [weak self] in
            guard let self else { return }
            switch issue {
            case .load(let failure):
                let retry = await core.reportFailure(
                    title: String(localized: "Couldn't Open Note"),
                    message: failure.localizedDescription,
                    symbol: "text.page",
                    recovery: String(localized: "Retry"))
                if retry { _ = await store.reload() }
            case .save(let failure):
                let retry = await core.reportFailure(
                    title: String(localized: "Couldn't Save Note"),
                    message: failure.localizedDescription,
                    symbol: "text.page",
                    recovery: String(localized: "Retry"))
                if retry { await store.retrySave() }
            case .operation(let failure):
                _ = await core.reportFailure(
                    title: String(localized: "Couldn't Update Note"),
                    message: failure.localizedDescription,
                    symbol: "text.page",
                    recovery: nil)
            }
            issueTask = nil
            if let pendingIssue {
                self.pendingIssue = nil
                present(pendingIssue)
            }
        }
    }
}
