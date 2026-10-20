import Foundation

/// Fork: a pinned calculation keeps its query, so Calculator History can answer it again live.
struct CalcPin: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    /// Canonical text, the way `CalculatorHistoryStore` keeps its expressions.
    let query: String
    let createdAt: Date
}

/// Its own file beside the history, so the history cap never drops a pin.
@MainActor
@Observable
final class CalculatorPinStore {
    private let fileURL: URL

    private(set) var pins: [CalcPin]  // newest first

    init() {
        fileURL = AppPaths.applicationSupport().appendingPathComponent("calculator-pins.json")
        if let data = try? Data(contentsOf: fileURL),
            let decoded = try? JSONDecoder().decode([CalcPin].self, from: data)
        {
            pins = decoded
        } else {
            pins = []
        }
    }

    var ids: Set<UUID> { Set(pins.map(\.id)) }

    func pin(for query: String) -> CalcPin? {
        pins.first { $0.query == query }
    }

    func toggle(_ query: String) {
        if let existing = pin(for: query) {
            unpin(existing.id)
        } else {
            pins.insert(CalcPin(id: UUID(), query: query, createdAt: Date()), at: 0)
            persist()
        }
    }

    func unpin(_ id: UUID) {
        pins.removeAll { $0.id == id }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(pins) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
