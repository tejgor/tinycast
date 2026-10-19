import AppKit

@MainActor
@Observable
final class RunningAppsMonitor {
    private(set) var runningBundleIDs: Set<String> = []
    private var runningAppPaths: Set<String> = []
    @ObservationIgnored private var observers: [NotificationToken] = []
    @ObservationIgnored private var listObservation: NSKeyValueObservation?

    init() {
        refresh()
        let center = NSWorkspace.shared.notificationCenter
        for name in [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification
        ] {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
            observers.append(NotificationToken(token, center: center))
        }
        // The list itself lags the terminate notification, so its own change is a refresh too.
        listObservation = NSWorkspace.shared.observe(\.runningApplications) { [weak self] _, _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func isRunning(_ app: AppEntry) -> Bool {
        app.kind == .application && app.bundleID != nil && runningAppPaths.contains(app.id)
    }

    /// Helpers and agents fire these too, so republish only on a real change.
    private func refresh() {
        // At the terminate notification the quit app is still listed, already marked terminated.
        let apps = NSWorkspace.shared.runningApplications.filter { !$0.isTerminated }
        let bundleIDs = Set(apps.compactMap(\.bundleIdentifier))
        let paths = Set(apps.compactMap { $0.bundleURL?.resolvingSymlinksInPath().standardizedFileURL.path })
        if bundleIDs != runningBundleIDs { runningBundleIDs = bundleIDs }
        if paths != runningAppPaths { runningAppPaths = paths }
    }
}
