import Darwin
import Foundation

/// A folder's and its parents' ignore files, by git's rules: the last matching pattern decides.
final class FileSearchIgnoreRules: Sendable {
    /// The files a folder can hold, in rising precedence: a later file's rules override earlier.
    struct Sources: OptionSet, Sendable {
        let rawValue: UInt8

        static let gitExclude = Sources(rawValue: 1 << 0)
        static let gitignore = Sources(rawValue: 1 << 1)
        static let ignore = Sources(rawValue: 1 << 2)
        static let rayignore = Sources(rawValue: 1 << 3)

        /// What a folder holds, by the name the listing saw: `.git` carries `info/exclude`.
        static func named(_ name: UnsafeBufferPointer<UInt8>) -> Sources {
            switch name.count {
            case 4 where name.elementsEqual(".git".utf8): .gitExclude
            case 7 where name.elementsEqual(".ignore".utf8): .ignore
            case 10 where name.elementsEqual(".gitignore".utf8): .gitignore
            case 10 where name.elementsEqual(".rayignore".utf8): .rayignore
            default: []
            }
        }

        /// Relative to the folder, in the order their rules apply.
        var files: [String] {
            [
                (Sources.gitExclude, ".git/info/exclude"), (.gitignore, ".gitignore"), (.ignore, ".ignore"),
                (.rayignore, ".rayignore")
            ].compactMap { contains($0.0) ? $0.1 : nil }
        }
    }

    private struct Rule: Sendable {
        /// The folder whose file holds the rule; an anchored pattern is relative to it.
        let base: String
        /// NUL-terminated for `fnmatch`, one per path component; `**` spans any number of them.
        let segments: [ContiguousArray<CChar>]
        let anchored: Bool
        let negated: Bool
        let directoryOnly: Bool
    }

    private let rules: [Rule]

    var isEmpty: Bool { rules.isEmpty }

    private init(rules: [Rule]) {
        self.rules = rules
    }

    /// The parent's rules, then the folder's own files' in order; nil when there are none at all.
    static func adding(
        _ texts: [String], base: String, to parent: FileSearchIgnoreRules?
    ) -> FileSearchIgnoreRules? {
        let own = texts.flatMap { parse($0, base: base) }
        guard !own.isEmpty else { return parent }
        return FileSearchIgnoreRules(rules: (parent?.rules ?? []) + own)
    }

    func ignores(name: String, isDirectory: Bool, in folder: String) -> Bool {
        for rule in rules.reversed() where !rule.directoryOnly || isDirectory {
            if Self.matches(rule, name: name, folder: folder) { return !rule.negated }
        }
        return false
    }

    /// A rule reaches only beneath the folder whose file holds it.
    private static func matches(_ rule: Rule, name: String, folder: String) -> Bool {
        let inside = folder == rule.base || folder.hasPrefix(rule.base == "/" ? "/" : rule.base + "/")
        guard inside else { return false }
        guard rule.anchored else { return glob(rule.segments[0], matches: name) }
        let below = folder.dropFirst(rule.base.count).split(separator: "/").map(String.init)
        return matches(rule.segments[...], below + [name])
    }

    private static func glob(_ pattern: ContiguousArray<CChar>, matches component: String) -> Bool {
        component.withCString { component in
            pattern.withUnsafeBufferPointer { fnmatch($0.baseAddress!, component, FNM_CASEFOLD) == 0 }
        }
    }

    /// `**` stands for no component or several; a trailing one needs something beneath its folder.
    private static func matches(_ pattern: ArraySlice<ContiguousArray<CChar>>, _ path: [String]) -> Bool {
        var memo: [Int: Bool] = [:]
        func match(_ p: Int, _ q: Int) -> Bool {
            let key = p * (path.count + 1) + q
            if let known = memo[key] { return known }
            let result: Bool
            if p == pattern.endIndex {
                result = q == path.count
            } else if isGlobstar(pattern[p]) {
                result =
                    p + 1 == pattern.endIndex
                    ? q < path.count
                    : (q...path.count).contains { match(p + 1, $0) }
            } else {
                result = q < path.count && glob(pattern[p], matches: path[q]) && match(p + 1, q + 1)
            }
            memo[key] = result
            return result
        }
        return match(pattern.startIndex, 0)
    }

    private static func isGlobstar(_ segment: ContiguousArray<CChar>) -> Bool {
        segment.count == 3 && segment[0] == 0x2A && segment[1] == 0x2A
    }

    private static func parse(_ text: String, base: String) -> [Rule] {
        text.split(whereSeparator: \.isNewline).compactMap { rawLine in
            var line = Substring(rawLine)
            while let last = line.last, last == " " || last == "\t", !line.hasSuffix("\\ ") {
                line = line.dropLast()
            }
            // An interior NUL would silently truncate the pattern once it reaches `fnmatch`.
            guard !line.isEmpty, !line.hasPrefix("#"), !line.contains("\0") else { return nil }
            var negated = false
            if line.hasPrefix("!") {
                negated = true
                line = line.dropFirst()
            } else if line.hasPrefix("\\#") || line.hasPrefix("\\!") {
                line = line.dropFirst()
            }
            var directoryOnly = false
            while line.hasSuffix("/") {
                directoryOnly = true
                line = line.dropLast()
            }
            // A slash anywhere but the end ties the pattern to the folder holding the file.
            let anchored = line.contains("/")
            if line.hasPrefix("/") { line = line.drop { $0 == "/" } }
            let segments = line.split(separator: "/").map { ContiguousArray(String($0).utf8CString) }
            guard !segments.isEmpty else { return nil }
            return Rule(
                base: base, segments: segments, anchored: anchored, negated: negated, directoryOnly: directoryOnly)
        }
    }
}
