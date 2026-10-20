import Foundation

/// Fork: pinning a calculation from its card or a history row, and answering every pin live.
@MainActor
enum CalculatorPinning {
    /// Each pin answered now, as an entry the history list already knows how to draw.
    static func liveEntries(core: AppCore, rates: CurrencyRates?, matching search: String) -> [CalcHistoryEntry] {
        let needle = search.trimmingCharacters(in: .whitespaces)
        return core.calcPins.pins.compactMap { pin in
            let entry = CalcHistoryEntry(
                id: pin.id, expression: pin.query, result: answer(pin.query, rates: rates), createdAt: pin.createdAt)
            guard !needle.isEmpty else { return entry }
            let matches =
                entry.expression.localizedCaseInsensitiveContains(needle)
                || entry.result.localizedCaseInsensitiveContains(needle)
            return matches ? entry : nil
        }
    }

    static func isPinned(_ entry: CalcHistoryEntry, core: AppCore) -> Bool {
        core.calcPins.pins.contains { $0.id == entry.id }
    }

    /// ⌘. on the card: the query typed, not the card's echo, which drops a conversion's target.
    @discardableResult
    static func toggle(card result: CalcResult, core: AppCore) -> Bool {
        guard result.isActionable, let query = cardQuery(core) else { return false }
        core.calcPins.toggle(query)
        return true
    }

    /// A history row pins its expression only when that answers the same again, or is a date.
    @discardableResult
    static func toggle(entry: CalcHistoryEntry, core: AppCore, rates: CurrencyRates?) -> Bool {
        if isPinned(entry, core: core) {
            core.calcPins.unpin(entry.id)
            return true
        }
        guard canPin(entry, rates: rates) else { return false }
        core.calcPins.toggle(entry.expression)
        return true
    }

    static func cardItem(result: CalcResult, core: AppCore) -> PopoverMenuItem? {
        guard result.isActionable, let query = cardQuery(core) else { return nil }
        return item(pinned: core.calcPins.pin(for: query) != nil) { toggle(card: result, core: core) }
    }

    static func entryItem(entry: CalcHistoryEntry, core: AppCore, rates: CurrencyRates?) -> PopoverMenuItem? {
        let pinned = isPinned(entry, core: core)
        guard pinned || canPin(entry, rates: rates) else { return nil }
        return item(pinned: pinned) { toggle(entry: entry, core: core, rates: rates) }
    }

    /// The history menu with Pin or Unpin added at the top of its second section.
    static func menu(_ content: PopoverMenuContent, adding item: PopoverMenuItem?) -> PopoverMenuContent {
        guard let item else { return content }
        var items = content.items
        let index = items.firstIndex(where: \.startsSection) ?? items.endIndex
        var pinItem = item
        pinItem.startsSection = true
        if index < items.endIndex { items[index].startsSection = false }
        items.insert(pinItem, at: index)
        return PopoverMenuContent(header: content.header, items: items)
    }

    // MARK: - Private

    private static func item(pinned: Bool, action: @escaping () -> Void) -> PopoverMenuItem {
        PopoverMenuItem(
            title: pinned ? String(localized: "Unpin Entry") : String(localized: "Pin Entry"),
            systemImage: pinned ? "pin.slash" : "pin", shortcut: "⌘.", action: action)
    }

    private static func cardQuery(_ core: AppCore) -> String? {
        let typed = core.palette.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else { return nil }
        return core.calcNumberFormat.canonical(typed) ?? typed
    }

    private static func evaluate(_ query: String, rates: CurrencyRates?) -> CalcResult? {
        CalcEngine.evaluate(query, now: Date(), calendar: .current, rates: rates, region: RegionCurrency.code)
    }

    private static func answer(_ query: String, rates: CurrencyRates?) -> String {
        switch evaluate(query, rates: rates)?.payload {
        case .value(let display, _)?: return display
        case .error(let message)?: return message
        case nil: return "—"
        }
    }

    private static func canPin(_ entry: CalcHistoryEntry, rates: CurrencyRates?) -> Bool {
        guard let result = evaluate(entry.expression, rates: rates),
            case .value(let display, _) = result.payload
        else { return false }
        return display == entry.result || !result.canChain
    }
}
