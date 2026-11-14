import Foundation

@main
@MainActor
struct NotesMenuBarButtonMigrationTest {
    static var failures = 0

    static func main() throws {
        let retired = file(notes: #""showsMenuBarButton": true, "enabled": true"#)
        let rewrite = migrated(retired)
        check("a file with the retired key is rewritten", rewrite != nil)
        if let rewrite {
            let parsed = try SettingsFileFormat.parse(rewrite)
            let original = try SettingsFileFormat.parse(retired)
            check("the rewrite reports nothing", parsed.issues.isEmpty)
            check("the rewrite keeps every other value", parsed.values == original.values)
        }

        let both = Data(
            #"{ "appearance": { "showFavoritesInCompactMode": true }, "notes": { "showsMenuBarButton": true } }"#
                .utf8)
        let bothRewrite = migrated(both)
        check("upstream's retired key does not block the rewrite", bothRewrite != nil)
        if let bothRewrite {
            let parsed = try SettingsFileFormat.parse(bothRewrite)
            check("both retired keys go", parsed.issues.isEmpty)
        }

        let typo = file(notes: #""showsMenuBarButton": true, "enabld": true"#)
        check("another unknown key leaves the file to the import", migrated(typo) == nil)
        check("a clean file is left alone", migrated(file(notes: #""enabled": true"#)) == nil)
        check("invalid JSON is left alone", migrated(Data("{".utf8)) == nil)

        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }

    private static func migrated(_ data: Data) -> Data? {
        NotesMenuBarButtonMigration.migrated(data)
    }

    private static func file(notes: String) -> Data {
        Data(#"{ "general": { "language": "en" }, "notes": { \#(notes) } }"#.utf8)
    }

    private static func check(_ description: String, _ condition: @autoclosure () -> Bool) {
        if condition() {
            print("PASS  \(description)")
        } else {
            print("FAIL  \(description)")
            failures += 1
        }
    }
}
