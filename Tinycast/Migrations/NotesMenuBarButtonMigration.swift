import Foundation

/// Retires the fork's Show Notes Button in Menu Bar, which upstream's Show in Menu Bar replaced.
enum NotesMenuBarButtonMigration {
    static let retiredKey = "notes.showsMenuBarButton"
    /// Upstream's own retired key, which a fork file still carries alongside this one.
    private static let alsoRetired: [SettingsFileIssue] = [
        .unknownSetting(retiredKey), .unknownSetting("appearance.showFavoritesInCompactMode"),
    ]

    /// True when the retired button was on, so the caller can turn its replacement on.
    static func run(settingsFileEnabled: Bool) -> Bool {
        let defaults = UserDefaults.standard
        let wasShown = defaults.bool(forKey: "notesShowsMenuBarButton")
        defaults.removeObject(forKey: "notesShowsMenuBarButton")
        guard settingsFileEnabled else { return wasShown }
        let url = AppPaths.settingsFile()
        guard let data = try? Data(contentsOf: url), let migrated = migrated(data) else { return wasShown }
        try? migrated.write(to: url.resolvingSymlinksInPath(), options: .atomic)
        return wasShown
    }

    /// Nil when the key is absent or the file has other problems, which the import must report.
    static func migrated(_ data: Data) -> Data? {
        guard let parsed = try? SettingsFileFormat.parse(data),
            parsed.issues.contains(.unknownSetting(retiredKey)),
            parsed.issues.allSatisfy(alsoRetired.contains)
        else { return nil }
        return SettingsFileFormat.render(parsed.values)
    }
}
