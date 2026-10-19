import Foundation

/// `tinycast://notes` shows the notes window; `tinycast://notes/open?id=<file>` opens one note.
enum NoteDeepLink {
    enum Route: Sendable, Equatable {
        case show
        case open(NoteID)
    }

    private static let scheme = "tinycast"
    private static let host = "notes"

    static func url(for id: NoteID) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.path = "/open"
        components.queryItems = [URLQueryItem(name: "id", value: id.rawValue)]
        return components.url
    }

    /// Nil for any link that is not a notes link, so other handlers can still claim it.
    static func route(_ url: URL) -> Route? {
        guard url.scheme?.lowercased() == scheme, url.host?.lowercased() == host,
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }
        switch components.path {
        case "", "/":
            return .show
        case "/open":
            let id = components.queryItems?.first { $0.name == "id" }?.value
            guard let id, !id.isEmpty, !id.contains("/") else { return .show }
            return .open(NoteID(rawValue: id))
        default:
            return .show
        }
    }
}
