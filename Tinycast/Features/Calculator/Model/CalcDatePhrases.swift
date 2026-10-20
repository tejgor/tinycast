import Foundation

/// Fork: Raycast-style date phrases, tried before `CalcDateTime` so upstream's grammar stays as is.
enum CalcDatePhrases {
    static func evaluate(_ query: String, now: Date, calendar: Calendar) -> CalcResult? {
        let echo = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = echo.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let words = lowered.split(separator: " ")
        guard words.count > 1 else { return nil }
        // `2h 30m` is a duration, never metres, and the rest of the engine reads it once fixed.
        if let fixed = minutesSpelledOut(lowered) {
            return CalcEngine.evaluate(fixed, now: now, calendar: calendar)
        }
        let text = normalized(lowered, now: now, calendar: calendar)
        guard text != lowered || mayBeDatePhrase(words, lowered) else { return nil }
        let result =
            answer(text, now: now, calendar: calendar)
            ?? (text != lowered ? CalcDateTime.evaluate(text, now: now, calendar: calendar) : nil)
        return result.map {
            CalcResult(
                expression: echo, sourceBadge: $0.sourceBadge, targetBadge: $0.targetBadge,
                payload: $0.payload, canChain: false)
        }
    }

    /// Every grammar here keys on one of these words, so an app search leaves after one pass.
    private static func mayBeDatePhrase(_ words: [Substring], _ text: String) -> Bool {
        if leadingWords.contains(words[0]) || rangeUnit(String(words[0])) != nil
            || CalcDateTime.isWorkdayUnit(String(words[0]))
        {
            return true
        }
        return words.contains { joiningWords.contains($0) || holidayWords.contains(String($0)) }
            || trailingClock(text) != nil
    }

    private static let leadingWords: Set<Substring> = [
        "how", "time", "countdown", "what", "which", "day", "weekday", "week", "current", "iso", "this",
        "in", "unix", "timestamp", "now", "between", "from", "business", "work", "working"
    ]

    private static let joiningWords: Set<Substring> = [
        "to", "through", "thru", "after", "before", "until", "till", "til", "since"
    ]

    private static func answer(_ text: String, now: Date, calendar: Calendar) -> CalcResult? {
        if text.hasPrefix("how many ") {
            var rest = String(text.dropFirst(9))
            for filler in [" are there", " are left", " left", " remaining", " is it"] {
                rest = rest.replacingOccurrences(of: filler, with: "")
            }
            return answer(rest, now: now, calendar: calendar)
                ?? CalcDateTime.evaluate(rest, now: now, calendar: calendar)
        }
        if let years = sinceYear(text) { return range(years, now: now, calendar: calendar) }
        return timeUntil(text, now: now, calendar: calendar)
            ?? workdaysUntil(text, now: now, calendar: calendar)
            ?? weekday(text, now: now, calendar: calendar)
            ?? weekNumber(text, now: now, calendar: calendar)
            ?? daysIn(text, now: now, calendar: calendar)
            ?? thisWeekday(text, now: now, calendar: calendar)
            ?? range(text, now: now, calendar: calendar)
            ?? rewritten(text, now: now, calendar: calendar).flatMap {
                CalcDateTime.evaluate($0, now: now, calendar: calendar)
            }
    }

    // MARK: - Grammars

    /// `time until 5pm`, `how long since jan 1`: a clock answers as a timespan, a date in days.
    private static func timeUntil(_ text: String, now: Date, calendar: Calendar) -> CalcResult? {
        let forward = [
            "time until ", "time till ", "time til ", "time left until ", "time left till ",
            "how long until ", "how long till ", "how long til ", "countdown to "
        ]
        let backward = ["time since ", "how long since ", "how long ago was ", "time elapsed since "]
        let past: Bool
        let rest: String
        if let prefix = forward.first(where: text.hasPrefix) {
            (past, rest) = (false, String(text.dropFirst(prefix.count)))
        } else if let prefix = backward.first(where: text.hasPrefix) {
            (past, rest) = (true, String(text.dropFirst(prefix.count)))
        } else {
            return nil
        }
        guard let moment = CalcDateTime.resolveMoment(rest, past: past, now: now, calendar: calendar)
        else { return nil }
        let reference = moment.hasTime ? now : calendar.startOfDay(for: now)
        let (start, end) = past ? (moment.date, reference) : (reference, moment.date)
        let display: String
        if moment.hasTime {
            display = CalcFormatter.timespan((end.timeIntervalSince(start) / 60).rounded() * 60)
        } else {
            display = count(days(from: start, to: end, calendar: calendar), "day")
        }
        return result(display, from: start, to: end, hasTime: moment.hasTime, now: now, calendar: calendar)
    }

    /// `business days until dec 25`, `workdays since monday`: weekends skipped, holidays not.
    private static func workdaysUntil(_ text: String, now: Date, calendar: Calendar) -> CalcResult? {
        guard let (noun, rest) = workdayNoun(text) else { return nil }
        for (connector, past) in [("until ", false), ("till ", false), ("til ", false), ("since ", true)]
        where rest.hasPrefix(connector) {
            guard
                let moment = CalcDateTime.resolveMoment(
                    String(rest.dropFirst(connector.count)), past: past, now: now, calendar: calendar)
            else { return nil }
            let today = calendar.startOfDay(for: now)
            let other = calendar.startOfDay(for: moment.date)
            let (start, end) = past ? (other, today) : (today, other)
            let display = count(workdays(from: start, to: end, calendar: calendar), noun)
            return result(display, from: start, to: end, hasTime: false, now: now, calendar: calendar)
        }
        return range("\(rest) in \(noun.replacingOccurrences(of: " ", with: ""))", now: now, calendar: calendar)
    }

    /// `years since 1990` → `1990 to today in years`, since a bare year is no moment upstream.
    private static func sinceYear(_ text: String) -> String? {
        let words = text.split(separator: " ").map(String.init)
        guard words.count == 3, isYear(words[2]), rangeUnit(words[0]) != nil else { return nil }
        switch words[1] {
        case "since": return "\(words[2]) to today in \(words[0])"
        case "until", "till", "til": return "today to \(words[2]) in \(words[0])"
        default: return nil
        }
    }

    /// `what day is 4 july 2027`, `day of the week on jan 24 1984`.
    private static func weekday(_ text: String, now: Date, calendar: Calendar) -> CalcResult? {
        let prefixes = [
            "what day of the week is ", "what day of the week was ", "what day is ", "what day was ",
            "which day is ", "day of the week on ", "day of the week for ", "day of week on ",
            "day of week for ", "weekday on ", "weekday of ", "weekday for "
        ]
        guard let prefix = prefixes.first(where: text.hasPrefix) else { return nil }
        var rest = String(text.dropFirst(prefix.count))
        if rest == "it" { rest = "today" }
        guard
            let moment = CalcDateTime.resolveMoment(
                rest, past: prefix.hasSuffix("was "), now: now, calendar: calendar)
        else { return nil }
        let name = CalcDateTime.formatted(moment.date, calendar: calendar, pattern: "EEEE")
        return CalcResult(
            expression: text,
            sourceBadge: CalcDateTime.answerText(
                moment.date, hasTime: moment.hasTime, now: now, calendar: calendar),
            payload: .value(display: name, copyText: name))
    }

    /// `week number`, `week number on march 12 2021`: the ISO 8601 week, as Raycast gives it.
    private static func weekNumber(_ text: String, now: Date, calendar: Calendar) -> CalcResult? {
        let today = [
            "week number", "week of year", "week of the year", "what week is it", "which week is it",
            "what week number is it", "current week", "current week number", "iso week"
        ]
        let prefixes = [
            "week number on ", "week number of ", "week number for ", "week of year for ",
            "week of the year for ", "what week is ", "what week number is ", "what week was ",
            "iso week of ", "week number "
        ]
        let date: Date
        if today.contains(text) {
            date = now
        } else if let prefix = prefixes.first(where: text.hasPrefix),
            let moment = CalcDateTime.resolveMoment(
                String(text.dropFirst(prefix.count)), past: nil, now: now, calendar: calendar)
        {
            date = moment.date
        } else {
            return nil
        }
        var iso = Calendar(identifier: .iso8601)
        iso.timeZone = calendar.timeZone
        let week = iso.component(.weekOfYear, from: date)
        return CalcResult(
            expression: text,
            sourceBadge: CalcDateTime.badgeText(date, hasTime: false, now: now, calendar: calendar),
            targetBadge: "ISO 8601",
            payload: .value(display: "Week \(week)", copyText: String(week)))
    }

    /// `days in february 2028`, `days in 2028`, `days left in the month`.
    private static func daysIn(_ text: String, now: Date, calendar: Calendar) -> CalcResult? {
        let left = ["days left in ", "days remaining in ", "days left this ", "days left of "]
        let remaining = left.first(where: text.hasPrefix)
        guard let prefix = remaining ?? (text.hasPrefix("days in ") ? "days in " : nil) else { return nil }
        var rest = String(text.dropFirst(prefix.count))
        for article in ["the ", "this ", "current "] where rest.hasPrefix(article) {
            rest.removeFirst(article.count)
        }
        let words = rest.split(separator: " ").map(String.init)
        let thisYear = calendar.component(.year, from: now)
        let component: Calendar.Component
        var parts = DateComponents(year: thisYear, month: 1, day: 1)
        switch words.count {
        case 1 where words[0] == "month":
            component = .month
            parts.month = calendar.component(.month, from: now)
        case 1 where words[0] == "year":
            component = .year
        case 1 where isYear(words[0]):
            component = .year
            parts.year = Int(words[0])
        case 1, 2:
            guard let month = CalcDateTime.month(named: words[0]),
                words.count == 1 || isYear(words[1])
            else { return nil }
            component = .month
            parts.month = month
            if words.count == 2 { parts.year = Int(words[1]) }
        default:
            return nil
        }
        guard let start = calendar.date(from: parts),
            let span = calendar.dateInterval(of: component, for: start)
        else { return nil }
        let pattern = component == .year ? "yyyy" : "MMMM yyyy"
        let label = CalcDateTime.formatted(start, calendar: calendar, pattern: pattern)
        let total: Int
        if remaining != nil {
            let today = calendar.startOfDay(for: now)
            guard span.contains(today) else { return nil }
            total = days(from: today, to: span.end, calendar: calendar) - 1
        } else {
            total = days(from: span.start, to: span.end, calendar: calendar)
        }
        let display = count(total, "day")
        return CalcResult(
            expression: text, sourceBadge: label, payload: .value(display: display, copyText: display))
    }

    /// `this friday`: the coming one, or today when today is Friday.
    private static func thisWeekday(_ text: String, now: Date, calendar: Calendar) -> CalcResult? {
        guard text.hasPrefix("this ") else { return nil }
        let rest = String(text.dropFirst(5))
        guard let name = rest.split(separator: " ").first.map(String.init),
            CalcDateTime.weekday(named: name) != nil,
            let moment = CalcDateTime.resolveMoment(rest, past: nil, now: now, calendar: calendar)
        else { return nil }
        let display = CalcDateTime.answerText(
            moment.date, hasTime: moment.hasTime, now: now, calendar: calendar)
        return CalcResult(
            expression: text,
            sourceBadge: CalcDateTime.badgeText(now, hasTime: false, now: now, calendar: calendar),
            targetBadge: CalcDateTime.formatted(moment.date, calendar: calendar, pattern: "EEEE"),
            payload: .value(display: display, copyText: display))
    }

    /// `3 march to 30 may`, `days between jan 1 and mar 15`, `7:30am to 8:45pm`, `1978 to 2021`.
    private static func range(_ text: String, now: Date, calendar: Calendar) -> CalcResult? {
        var body = text
        var unit: String?
        if let first = body.split(separator: " ").first.map(String.init), let leading = rangeUnit(first),
            body.dropFirst(first.count).hasPrefix(" between ") || body.dropFirst(first.count).hasPrefix(" from ")
        {
            unit = leading
            body = String(body.dropFirst(first.count + 1))
        }
        for connector in [" in ", " to ", " as "] {
            if unit == nil, let found = body.range(of: connector, options: .backwards),
                let trailing = rangeUnit(String(body[found.upperBound...]))
            {
                unit = trailing
                body = String(body[..<found.lowerBound])
            }
        }

        let pairs: [(prefix: String, connectors: [String])] = [
            ("between ", [" and "]), ("from ", [" to ", " until ", " till ", " through ", " thru "]),
            ("", [" to ", " through ", " thru "])
        ]
        guard let pair = pairs.first(where: { body.hasPrefix($0.prefix) }) else { return nil }
        let inner = String(body.dropFirst(pair.prefix.count))
        guard let connector = pair.connectors.first(where: inner.contains),
            let split = inner.range(of: connector)
        else { return nil }
        let left = String(inner[..<split.lowerBound])
        let right = String(inner[split.upperBound...])
        guard var end = rangeMoment(right, now: now, calendar: calendar),
            var start = rangeMoment(left, now: now, calendar: calendar)
        else { return nil }

        // A yearless pair or two bare clocks run forward: `dec 1 to jan 15`, `4pm to 3am`.
        if end.date < start.date, !namesYear(left), !namesYear(right) {
            let weekdays = CalcDateTime.weekday(named: left) != nil && CalcDateTime.weekday(named: right) != nil
            let step: Calendar.Component = start.hasTime ? .day : weekdays ? .weekOfYear : .year
            guard let rolled = calendar.date(byAdding: step, value: 1, to: end.date) else { return nil }
            end = CalcDateTime.ResolvedMoment(date: rolled, hasTime: end.hasTime)
        }
        if end.date < start.date { swap(&start, &end) }
        let hasTime = start.hasTime || end.hasTime
        var last = end.date
        if !hasTime, connector.contains("thr"),
            let next = calendar.date(byAdding: .day, value: 1, to: last)
        {
            last = next
        }

        let first = hasTime ? start.date : calendar.startOfDay(for: start.date)
        if !hasTime { last = calendar.startOfDay(for: last) }
        let display: String
        switch unit {
        case "days"?: display = count(days(from: first, to: last, calendar: calendar), "day")
        case "weeks"?:
            display = number(Double(days(from: first, to: last, calendar: calendar)) / 7, "week")
        case "months"?:
            display = count(calendar.dateComponents([.month], from: first, to: last).month ?? 0, "month")
        case "years"?:
            display = count(calendar.dateComponents([.year], from: first, to: last).year ?? 0, "year")
        case "hours"?: display = number(last.timeIntervalSince(first) / 3600, "hour")
        case "minutes"?: display = number(last.timeIntervalSince(first) / 60, "minute")
        case "seconds"?: display = number(last.timeIntervalSince(first), "second")
        case "workdays"?:
            display = count(
                workdays(
                    from: calendar.startOfDay(for: first), to: calendar.startOfDay(for: last),
                    calendar: calendar), "workday")
        case .some: return nil
        case nil:
            display =
                hasTime
                ? CalcFormatter.timespan(last.timeIntervalSince(first))
                : breakdown(from: first, to: last, calendar: calendar)
        }
        return result(display, from: start.date, to: end.date, hasTime: hasTime, now: now, calendar: calendar)
    }

    /// Phrases the upstream grammars already answer once reworded.
    private static func rewritten(_ text: String, now: Date, calendar: Calendar) -> String? {
        // `in 45 days` → `45 days from now`
        if text.hasPrefix("in "), CalcDateTime.isDuration(String(text.dropFirst(3))) {
            return "\(text.dropFirst(3)) from now"
        }
        // `3 weeks after march 14` → `march 14 + 3 weeks`
        for (word, op) in [(" after ", "+"), (" before ", "-")] {
            if let found = text.range(of: word),
                CalcDateTime.isDuration(String(text[..<found.lowerBound]))
            {
                return "\(text[found.upperBound...]) \(op) \(text[..<found.lowerBound])"
            }
        }
        switch text {
        case "current timestamp", "current unix timestamp", "current unix time", "unix time", "unix now",
            "timestamp now", "now unix", "now in unix", "now as unix":
            return "now to unix"
        default: break
        }
        for (suffix, target) in [
            (" in unix ms", " to unix ms"), (" as unix ms", " to unix ms"), (" in unix", " to unix"),
            (" as unix", " to unix"), (" in unix time", " to unix")
        ] where text.hasSuffix(suffix) {
            return text.dropLast(suffix.count) + target
        }
        // `1733823083000 to date`: twelve digits or more can only be milliseconds this century.
        for suffix in [" to date", " as date", " in date"] where text.hasSuffix(suffix) {
            let number = text.dropLast(suffix.count)
            guard number.count >= 9, number.allSatisfy(\.isNumber) else { break }
            return number.count >= 12 ? "unix \(number) ms" : "unix \(number)"
        }
        // `tomorrow 3pm` → `tomorrow at 3pm`
        if let clock = trailingClock(text) {
            let head = String(text.dropLast(clock.count + 1))
            if !head.hasSuffix(" at"),
                let day = CalcDateTime.resolveMoment(head, past: nil, now: now, calendar: calendar),
                !day.hasTime
            {
                return "\(head) at \(clock.replacingOccurrences(of: " ", with: ""))"
            }
        }
        return nil
    }

    // MARK: - Normalizing

    private static func normalized(_ text: String, now: Date, calendar: Calendar) -> String {
        var output = text
        if output.contains("'") || output.contains("’") {
            output = output.replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "’", with: "")
        }
        output = holidaysSpelledOut(output, now: now, calendar: calendar)
        guard output.contains(where: \.isNumber),
            output.contains(",") || output.contains(" of ") || ["st", "nd", "rd", "th"].contains(where: output.contains)
        else { return output }
        for (pattern, template) in datePatterns {
            output = pattern?.stringByReplacingMatches(
                in: output, range: NSRange(output.startIndex..., in: output), withTemplate: template)
                ?? output
        }
        return output
    }

    private static let monthAlternation =
        "january|february|march|april|may|june|july|august|september|october|november|december"
        + "|jan|feb|mar|apr|jun|jul|aug|sept|sep|oct|nov|dec"

    /// `march 14th, 2019` and `4th of july` → `march 14 2019` and `4 july`.
    private static let datePatterns: [(NSRegularExpression?, String)] = [
        (try? NSRegularExpression(pattern: #"\b(\d{1,2})(?:st|nd|rd|th)\b"#), "$1"),
        (try? NSRegularExpression(pattern: #"\b(\d{1,2}) of (\#(monthAlternation))\b"#), "$1 $2"),
        (try? NSRegularExpression(pattern: #"\b(\#(monthAlternation)) (\d{1,2}), (\d{4})\b"#), "$1 $2 $3"),
        (try? NSRegularExpression(pattern: #"\b(\d{1,2}) (\#(monthAlternation)),? (\d{4})\b"#), "$1 $2 $3")
    ]

    private static let minutePatterns: [(NSRegularExpression?, String)] = [
        (
            try? NSRegularExpression(
                pattern: #"(\d(?:\.\d+)?\s*(?:hours|hour|hrs|hr|h)\s*\d+(?:\.\d+)?\s*)m(?![a-z])"#),
            "$1min"
        ),
        (
            try? NSRegularExpression(
                pattern: #"(\d+(?:\.\d+)?\s*)m(\s*\d+(?:\.\d+)?\s*(?:seconds|second|secs|sec|s)(?![a-z]))"#),
            "$1min$2"
        )
    ]

    private static func minutesSpelledOut(_ text: String) -> String? {
        guard hasBareM(text) else { return nil }
        var output = text
        for (pattern, template) in minutePatterns {
            output = pattern?.stringByReplacingMatches(
                in: output, range: NSRange(output.startIndex..., in: output), withTemplate: template)
                ?? output
        }
        return output == text ? nil : output
    }

    /// An `m` straight after a number and before no letter: the only text the patterns rewrite.
    private static func hasBareM(_ text: String) -> Bool {
        let bytes = Array(text.utf8)
        for index in bytes.indices where bytes[index] == 109 {
            var before = index - 1
            while before >= 0, bytes[before] == 32 { before -= 1 }
            guard before >= 0, (48...57).contains(bytes[before]) else { continue }
            if index + 1 == bytes.count || !(97...122).contains(bytes[index + 1]) { return true }
        }
        return false
    }

    // MARK: - Holidays

    private enum HolidayRule: Sendable {
        case fixed(month: Int, day: Int)
        case easter(offset: Int)
        case nthWeekday(month: Int, weekday: Int, nth: Int)
        case lunar(Calendar.Identifier, month: Int, day: Int)
    }

    /// Longest names first, so `christmas eve` wins over `christmas`. Apostrophes are already gone.
    private static let holidays: [(name: String, rule: HolidayRule)] = {
        let table: [([String], HolidayRule)] = [
            (["christmas eve"], .fixed(month: 12, day: 24)),
            (["christmas day", "christmas", "xmas"], .fixed(month: 12, day: 25)),
            (["boxing day"], .fixed(month: 12, day: 26)),
            (["new years eve", "new year eve"], .fixed(month: 12, day: 31)),
            (["new years day", "new year day", "new years", "new year"], .fixed(month: 1, day: 1)),
            (["valentines day", "valentines"], .fixed(month: 2, day: 14)),
            (["st patricks day", "saint patricks day", "st paddys day"], .fixed(month: 3, day: 17)),
            (["april fools day"], .fixed(month: 4, day: 1)),
            (["independence day", "fourth of july"], .fixed(month: 7, day: 4)),
            (["halloween"], .fixed(month: 10, day: 31)),
            (["easter sunday", "easter"], .easter(offset: 0)),
            (["good friday"], .easter(offset: -2)),
            (["easter monday"], .easter(offset: 1)),
            (["thanksgiving day", "thanksgiving"], .nthWeekday(month: 11, weekday: 5, nth: 4)),
            (["chinese new year", "lunar new year"], .lunar(.chinese, month: 1, day: 1)),
            (["ramadan"], .lunar(.islamicUmmAlQura, month: 9, day: 1)),
            (["eid al-fitr", "eid al fitr", "eid ul fitr"], .lunar(.islamicUmmAlQura, month: 10, day: 1)),
            (["eid al-adha", "eid al adha", "eid ul adha"], .lunar(.islamicUmmAlQura, month: 12, day: 10)),
            (["rosh hashanah", "rosh hashana"], .lunar(.hebrew, month: 1, day: 1)),
            (["yom kippur"], .lunar(.hebrew, month: 1, day: 10)),
            (["hanukkah", "chanukah"], .lunar(.hebrew, month: 3, day: 25)),
            (["passover"], .lunar(.hebrew, month: 8, day: 15))
        ]
        return table.flatMap { names, rule in names.map { ($0, rule) } }
            .sorted { $0.name.count > $1.name.count }
    }()

    /// Each name's first word: a query naming none skips the holiday scan, which every search pays.
    private static let holidayWords = Set(holidays.compactMap { $0.name.split(separator: " ").first.map(String.init) })

    private static let monthAbbreviations = [
        "jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"
    ]

    /// A holiday becomes a dated phrase; one written with a year keeps it, otherwise context decides.
    private static func holidaysSpelledOut(_ text: String, now: Date, calendar: Calendar) -> String {
        guard text.split(separator: " ").contains(where: { holidayWords.contains(String($0)) }) else {
            return text
        }
        var padded = " \(text) "
        // A lone name stays a search, as a lone `christmas` does; a year or a grammar earns a card.
        guard !holidays.contains(where: { padded == " \($0.name) " }) else { return text }
        let past =
            padded.contains(" since ") || padded.hasSuffix(" ago ") || padded.contains(" was ")
            || padded.hasPrefix(" last ")
        for (name, rule) in holidays {
            guard let found = padded.range(of: " \(name) ") else { continue }
            var end = found.upperBound
            var year: Int?
            let after = padded[end...]
            if after.count >= 5, let value = Int(after.prefix(4)), after.dropFirst(4).first == " " {
                year = value
                end = padded.index(end, offsetBy: 5)
            }
            guard
                let date = holidayDate(rule, year: year, past: past, now: now, calendar: calendar)
            else { continue }
            let parts = gregorian(calendar).dateComponents([.year, .month, .day], from: date)
            guard let y = parts.year, let m = parts.month, let d = parts.day else { continue }
            padded.replaceSubrange(found.lowerBound..<end, with: " \(d) \(monthAbbreviations[m - 1]) \(y) ")
        }
        return padded.trimmingCharacters(in: .whitespaces)
    }

    private static func holidayDate(
        _ rule: HolidayRule, year: Int?, past: Bool, now: Date, calendar: Calendar
    ) -> Date? {
        let greg = gregorian(calendar)
        let today = greg.startOfDay(for: now)
        if case .lunar(let identifier, let month, let day) = rule {
            var other = Calendar(identifier: identifier)
            other.timeZone = calendar.timeZone
            let anchor: Date?
            if let year {
                anchor = greg.date(from: DateComponents(year: year, month: 1, day: 1))?.addingTimeInterval(-1)
            } else {
                anchor = past ? greg.date(byAdding: .day, value: 1, to: today) : today.addingTimeInterval(-1)
            }
            guard let anchor,
                let found = other.nextDate(
                    after: anchor, matching: DateComponents(month: month, day: day),
                    matchingPolicy: .strict, direction: past && year == nil ? .backward : .forward)
            else { return nil }
            if let year, greg.component(.year, from: found) != year { return nil }
            return greg.startOfDay(for: found)
        }
        let thisYear = year ?? greg.component(.year, from: today)
        guard let date = gregorianHoliday(rule, year: thisYear, calendar: greg) else { return nil }
        if year != nil || (past ? date <= today : date >= today) { return date }
        return gregorianHoliday(rule, year: thisYear + (past ? -1 : 1), calendar: greg)
    }

    private static func gregorianHoliday(_ rule: HolidayRule, year: Int, calendar: Calendar) -> Date? {
        switch rule {
        case .fixed(let month, let day):
            return calendar.date(from: DateComponents(year: year, month: month, day: day))
        case .easter(let offset):
            // The anonymous Gregorian computus.
            let a = year % 19, b = year / 100, c = year % 100
            let h = (19 * a + b - b / 4 - (b - (b + 8) / 25 + 1) / 3 + 15) % 30
            let l = (32 + 2 * (b % 4) + 2 * (c / 4) - h - c % 4) % 7
            let m = (a + 11 * h + 22 * l) / 451
            let month = (h + l - 7 * m + 114) / 31
            let day = (h + l - 7 * m + 114) % 31 + 1
            return calendar.date(from: DateComponents(year: year, month: month, day: day))
                .flatMap { calendar.date(byAdding: .day, value: offset, to: $0) }
        case .nthWeekday(let month, let weekday, let nth):
            guard let first = calendar.date(from: DateComponents(year: year, month: month, day: 1))
            else { return nil }
            let lead = (weekday - calendar.component(.weekday, from: first) + 7) % 7
            return calendar.date(byAdding: .day, value: lead + 7 * (nth - 1), to: first)
        case .lunar:
            return nil
        }
    }

    private static func gregorian(_ calendar: Calendar) -> Calendar {
        var greg = Calendar(identifier: .gregorian)
        greg.timeZone = calendar.timeZone
        return greg
    }

    // MARK: - Helpers

    private static func rangeMoment(_ phrase: String, now: Date, calendar: Calendar) -> CalcDateTime.ResolvedMoment? {
        if isYear(phrase), let year = Int(phrase),
            let date = calendar.date(from: DateComponents(year: year, month: 1, day: 1))
        {
            return CalcDateTime.ResolvedMoment(date: date, hasTime: false)
        }
        return CalcDateTime.resolveMoment(phrase, past: nil, now: now, calendar: calendar)
    }

    private static func rangeUnit(_ word: String) -> String? {
        switch word {
        case "day", "days", "d": return "days"
        case "week", "weeks", "wk", "wks": return "weeks"
        case "month", "months", "mo": return "months"
        case "year", "years", "yr", "yrs": return "years"
        case "hour", "hours", "hr", "hrs", "h": return "hours"
        case "minute", "minutes", "min", "mins": return "minutes"
        case "second", "seconds", "sec", "secs", "s": return "seconds"
        default:
            return CalcDateTime.isWorkdayUnit(word.replacingOccurrences(of: " ", with: "")) ? "workdays" : nil
        }
    }

    /// `business days`, `workdays`: the noun as typed, for the answer to echo.
    private static func workdayNoun(_ text: String) -> (noun: String, rest: String)? {
        let words = text.split(separator: " ").map(String.init)
        guard words.count >= 3 else { return nil }
        if CalcDateTime.isWorkdayUnit(words[0]) {
            return (words[0], words.dropFirst().joined(separator: " "))
        }
        if CalcDateTime.isWorkdayUnit(words[0] + words[1]) {
            return ("\(words[0]) \(words[1])", words.dropFirst(2).joined(separator: " "))
        }
        return nil
    }

    private static func trailingClock(_ text: String) -> String? {
        let words = text.split(separator: " ")
        guard words.count >= 2, let last = words.last else { return nil }
        if last == "am" || last == "pm", words.count >= 3 {
            let hour = words[words.count - 2]
            return hour.allSatisfy { $0.isNumber || $0 == ":" } ? "\(hour) \(last)" : nil
        }
        if last == "noon" || last == "midnight" { return String(last) }
        let body = last.hasSuffix("am") || last.hasSuffix("pm") ? last.dropLast(2) : last[...]
        guard !body.isEmpty, body.first?.isNumber == true,
            body.allSatisfy({ $0.isNumber || $0 == ":" }),
            body.contains(":") || body.count < last.count
        else { return nil }
        return String(last)
    }

    private static func isYear(_ word: String) -> Bool {
        word.count == 4 && word.allSatisfy(\.isNumber)
    }

    private static func namesYear(_ phrase: String) -> Bool {
        phrase.split(separator: " ").contains { isYear(String($0)) } || phrase.contains("-")
    }

    private static func days(from start: Date, to end: Date, calendar: Calendar) -> Int {
        calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: end)
        ).day ?? 0
    }

    /// Weekdays in `(start, end]`, so `saturday` to `monday` is one, the inverse of `+ 1 workday`.
    private static func workdays(from start: Date, to end: Date, calendar: Calendar) -> Int {
        let total = days(from: start, to: end, calendar: calendar)
        guard total > 0 else { return 0 }
        var result = total / 7 * 5
        var cursor = calendar.date(byAdding: .day, value: total / 7 * 7, to: start) ?? start
        for _ in 0..<(total % 7) {
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
            if !CalcDateTime.isWeekendDay(cursor, calendar: calendar) { result += 1 }
        }
        return result
    }

    /// `2 months 3 weeks 6 days`, the way Raycast spells a span between two dates.
    private static func breakdown(from start: Date, to end: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: start, to: end)
        let day = parts.day ?? 0
        let pieces = [
            (parts.year ?? 0, "year"), (parts.month ?? 0, "month"), (day / 7, "week"), (day % 7, "day")
        ].filter { $0.0 != 0 }.map { count($0.0, $0.1) }
        return pieces.isEmpty ? count(0, "day") : pieces.joined(separator: " ")
    }

    private static func count(_ value: Int, _ noun: String) -> String {
        let singular = noun.hasSuffix("s") ? String(noun.dropLast()) : noun
        let plural = noun.hasSuffix("s") ? noun : noun + "s"
        return "\(CalcFormatter.grouped(String(value))) \(abs(value) == 1 ? singular : plural)"
    }

    private static func number(_ value: Double, _ noun: String) -> String {
        "\(CalcFormatter.grouped(CalcFormatter.copyText(value))) \(value == 1 ? noun : noun + "s")"
    }

    private static func result(
        _ display: String, from start: Date, to end: Date, hasTime: Bool, now: Date, calendar: Calendar
    ) -> CalcResult {
        CalcResult(
            expression: "",
            sourceBadge: CalcDateTime.badgeText(start, hasTime: hasTime, now: now, calendar: calendar),
            targetBadge: CalcDateTime.badgeText(end, hasTime: hasTime, now: now, calendar: calendar),
            payload: .value(display: display, copyText: display.replacingOccurrences(of: ",", with: "")))
    }
}
