import Foundation

@main
@MainActor
struct FileSearchHiddenFilesMigrationTest {
    static var failures = 0

    static func main() throws {
        let retired = file(fileSearch: #""includeHidden": true, "enabled": true"#)
        let rewrite = FileSearchHiddenFilesMigration.migrated(retired)
        check("a file with the retired key is rewritten", rewrite != nil)
        if let rewrite {
            let parsed = try SettingsFileFormat.parse(rewrite)
            let original = try SettingsFileFormat.parse(retired)
            check("the rewrite reports nothing", parsed.issues.isEmpty)
            check("the rewrite keeps every other value", parsed.values == original.values)
        }

        let both = Data(
            #"{ "notes": { "showsMenuBarButton": true }, "fileSearch": { "includeHidden": true } }"#.utf8)
        let bothRewrite = FileSearchHiddenFilesMigration.migrated(both)
        check("the notes button's retired key does not block the rewrite", bothRewrite != nil)
        if let bothRewrite {
            let parsed = try SettingsFileFormat.parse(bothRewrite)
            check("both retired keys go", parsed.issues.isEmpty)
        }

        let typo = file(fileSearch: #""includeHidden": true, "enabld": true"#)
        check(
            "another unknown key leaves the file to the import",
            FileSearchHiddenFilesMigration.migrated(typo) == nil)
        check(
            "a clean file is left alone",
            FileSearchHiddenFilesMigration.migrated(file(fileSearch: #""enabled": true"#)) == nil)
        check("invalid JSON is left alone", FileSearchHiddenFilesMigration.migrated(Data("{".utf8)) == nil)

        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }

    private static func file(fileSearch: String) -> Data {
        Data(#"{ "general": { "language": "en" }, "fileSearch": { \#(fileSearch) } }"#.utf8)
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
