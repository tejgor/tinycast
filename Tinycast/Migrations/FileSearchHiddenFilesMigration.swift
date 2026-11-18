import Foundation

/// Retires the fork's Include hidden files, which upstream's own setting of that name replaced.
enum FileSearchHiddenFilesMigration {
    static let retiredKey = "fileSearch.includeHidden"
    /// Retired keys a fork file can still carry beside this one; runs first, so it clears them too.
    private static let alsoRetired: [SettingsFileIssue] = [
        .unknownSetting(retiredKey), .unknownSetting("notes.showsMenuBarButton"),
        .unknownSetting("appearance.showFavoritesInCompactMode"),
    ]

    /// True when the retired switch was on, so the caller can turn its replacement on.
    static func run(settingsFileEnabled: Bool) -> Bool {
        let defaults = UserDefaults.standard
        let wasOn = defaults.bool(forKey: "fileSearchIncludesHidden")
        defaults.removeObject(forKey: "fileSearchIncludesHidden")
        guard settingsFileEnabled else { return wasOn }
        let url = AppPaths.settingsFile()
        guard let data = try? Data(contentsOf: url), let migrated = migrated(data) else { return wasOn }
        try? migrated.write(to: url.resolvingSymlinksInPath(), options: .atomic)
        return wasOn
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
