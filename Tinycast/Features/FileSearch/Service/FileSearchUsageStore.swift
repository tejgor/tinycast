import Foundation
import Synchronization

/// Read off the main actor by every search, so the usage sits behind a lock rather than an actor.
final class FileSearchUsageStore: Sendable {
    private let url: URL
    private let usage: Mutex<FileSearchUsage>

    init(directory: URL = AppPaths.applicationSupport()) {
        url = directory.appending(path: "file-search-usage.json")
        let stored = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(FileSearchUsage.self, from: $0) }
        usage = Mutex(stored ?? FileSearchUsage())
    }

    func boosts() -> [String: Int] {
        let now = Date().timeIntervalSince1970
        return usage.withLock { $0.boosts(now: now) }
    }

    func recordOpen(of path: String) {
        let now = Date().timeIntervalSince1970
        save(usage.withLock { usage in
            usage = usage.recording(path, at: now)
            return usage
        })
    }

    /// A trashed file is no longer one to put first.
    func forget(_ path: String) {
        save(usage.withLock { usage in
            usage = usage.removing(path)
            return usage
        })
    }

    private func save(_ snapshot: FileSearchUsage) {
        let url = url
        Task.detached(priority: .utility) {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }
}
