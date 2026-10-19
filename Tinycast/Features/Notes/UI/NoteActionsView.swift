import SwiftUI

struct NoteActionsView: View {
    let onContentHeight: (CGFloat) -> Void
    @Environment(NotesCoordinator.self) private var notes
    @FocusState private var searchFocused: Bool

    private var surface: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.Radius.menuPanel, style: .continuous)
    }

    var body: some View {
        VStack(spacing: 0) {
            list
            Divider().opacity(0.5)
            searchField
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .glassEffect(.regular, in: surface)
        .clipShape(surface)
        .onAppear(perform: focusSearch)
        .onKeyPress(keys: [.downArrow], phases: [.down, .repeat]) { _ in
            notes.moveActionsSelection(by: 1)
            return .handled
        }
        .onKeyPress(keys: [.upArrow], phases: [.down, .repeat]) { _ in
            notes.moveActionsSelection(by: -1)
            return .handled
        }
        .onKeyPress(keys: [.return, KeyEquivalent("\u{3}")]) { _ in
            notes.performSelectedAction()
            return .handled
        }
    }

    @ViewBuilder
    private var list: some View {
        let items = notes.visibleActions
        if items.isEmpty {
            Text("No Results")
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: Theme.Size.noteSwitcherEmptyHeight)
                .reportsHeight(plus: Theme.Size.noteSearchHeight, onContentHeight)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            if index > 0, item.section != items[index - 1].section {
                                Divider()
                                    .opacity(0.5)
                                    .padding(.vertical, Theme.Spacing.xs)
                            }
                            NoteActionRow(
                                item: item, selected: notes.actionsSelection == item.id,
                                onActivate: { notes.perform(item) })
                            .id(item.id)
                        }
                    }
                    .padding(Theme.Spacing.sm)
                    .reportsHeight(plus: Theme.Size.noteSearchHeight, onContentHeight)
                }
                .onChange(of: notes.actionsSelection) { _, selected in
                    if let selected { proxy.scrollTo(selected) }
                }
            }
        }
    }

    private var searchField: some View {
        TextField("Search for actions…", text: notes.actionsQueryBinding)
            .textFieldStyle(.plain)
            .focused($searchFocused)
            .onExitCommand { notes.closeActions() }
            .padding(.horizontal, Theme.Spacing.xl)
            .frame(height: Theme.Size.noteSearchHeight)
            .accessibilityLabel("Search Actions")
    }

    private func focusSearch() {
        Task { @MainActor in
            await Task.yield()
            searchFocused = true
        }
    }
}

extension View {
    /// The list reports its height plus the search band, which the window adds below it.
    fileprivate func reportsHeight(plus extra: CGFloat, _ report: @escaping (CGFloat) -> Void) -> some View {
        onGeometryChange(for: CGFloat.self) {
            $0.size.height
        } action: {
            report($0 + extra)
        }
    }
}

private struct NoteActionRow: View {
    let item: NoteActionItem
    let selected: Bool
    let onActivate: () -> Void
    @State private var hovered = false

    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: item.symbol)
                .frame(width: Theme.Size.noteGlyph, height: Theme.Size.noteGlyph)
                .foregroundStyle(item.isDestructive ? Theme.Colors.destructive : Theme.Colors.textSecondary)
            Text(item.title)
                .font(Theme.Typography.menuRow)
                .foregroundStyle(item.isDestructive ? Theme.Colors.destructive : Theme.Colors.textPrimary)
                .lineLimit(1)
            Spacer(minLength: Theme.Spacing.md)
            if let shortcut = item.shortcut {
                Text(verbatim: shortcut)
                    .font(Theme.Typography.menuShortcut)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).fill(fill))
        .contentShape(Rectangle())
        .onTapGesture(perform: onActivate)
        .onHover { hovered = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { onActivate() }
    }
}
