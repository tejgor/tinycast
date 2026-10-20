import Foundation

/// Fork: the Raycast-style date phrases in `CalcDatePhrases`, against calc-test's fixed clock.
@main
struct CalcPhrasesTests {
    nonisolated(unsafe) static var failures = 0
    nonisolated(unsafe) static var passes = 0

    /// Fri 2026-07-24 00:18 UTC, the same moment `calc-test` uses.
    static let clock: (now: Date, calendar: Calendar) = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_US")
        let now = calendar.date(from: DateComponents(year: 2026, month: 7, day: 24, hour: 0, minute: 18))!
        return (now, calendar)
    }()

    static func main() {
        // Phrasings that used to fall silent
        expect("in 45 days", "7 September", source: "Friday, 24 July", target: "Monday")
        expect("in 30 min", "24 July at 12:48 AM")
        expect("tomorrow 3pm", "25 July at 3:00 PM")
        expect("friday 5 pm", "24 July at 5:00 PM")
        expect("this friday", "24 July", target: "Friday")
        expect("this monday", "27 July", target: "Monday")
        expect("now in unix", "1,784,852,280", copy: "1784852280")
        expect("current timestamp", "1,784,852,280")
        expect("1733823083000 to date", "10 December, 2024 at 9:31:23 AM")
        expect("1700000000 to date", "14 November, 2023 at 10:13:20 PM")
        expect("time until 5pm", "16 hr 42 min", source: "Friday, 24 July at 12:18 AM")
        expect("how long since jan 1", "204 days")

        // Minutes written `m` beside hours or seconds
        expect("3:45pm + 2h 30m", "24 July at 6:15 PM")
        expect("3h 5m 10s in seconds", "11,110 s")
        expect("1h 30m to minutes", "90 min")
        expect("5m", "16 feet 4.850393701 inches")

        // Workdays are counted, never calendar days
        expect(
            "business days until dec 25", "110 business days",
            source: "Friday, 24 July", target: "Friday, 25 December")
        expect("workdays since monday", "4 workdays")
        expect("10 march to 17 march in workdays", "5 workdays")
        expect("workdays between 1 jan and 31 mar", "63 workdays")
        expect("saturday to monday in workdays", "1 workday")

        // Holidays
        expect("days until christmas", "154 days", target: "Friday, 25 December")
        expect("days since christmas", "211 days", source: "Thursday, 25 December, 2025")
        expect("how many days until christmas", "154 days")
        expect("christmas 2027", "25 December, 2027", target: "Saturday")
        expect("easter 2027", "28 March, 2027")
        expect("good friday 2027", "26 March, 2027")
        expect("thanksgiving 2026", "26 November")
        expect("chinese new year 2027", "6 February, 2027")
        expect("passover 2027", "22 April, 2027")
        expect("days until new year's eve", "160 days")
        expectNil("christmas")
        expectNil("chinese new year")
        expectNil("halloween costume ideas")

        // Ranges
        expect(
            "3 march to 30 may", "2 months 3 weeks 6 days",
            source: "Tuesday, 3 March", target: "Saturday, 30 May")
        expect("days between 3 march and 30 may", "88 days")
        expect("how many weeks between jan 1 and mar 1", "8.428571429 weeks")
        expect("april 1 through april 30 in days", "30 days")
        expect("1978 to 2021", "43 years")
        expect("years since 1990", "36 years")
        expect("7:30am to 8:45pm", "13 hr 15 min")
        expect("4pm to 3am", "11 hr")
        expect("dec 1 to jan 15", "1 month 2 weeks", target: "Friday, 15 January, 2027")
        expect("monday to friday", "4 days")
        expect("hours between 9am and 5pm", "8 hours")

        // Before and after
        expect("3 weeks after march 14, 2019", "4 April, 2019")
        expect("28 days before march 12", "12 February")
        expect("march 14th 2019 + 3 days", "17 March, 2019")

        // Calendar facts
        expect("what day is 4 july 2027", "Sunday", source: "4 July, 2027")
        expect("what day is christmas", "Friday")
        expect("weekday on march 9, 2024", "Saturday")
        expect("day of the week on january 24, 1984", "Tuesday")
        expect("week number", "Week 30", copy: "30", target: "ISO 8601")
        expect("week number on march 12, 2021", "Week 10")
        expect("days in february 2028", "29 days", source: "February 2028")
        expect("days in feb", "28 days")
        expect("days in 2028", "366 days")
        expect("days left in the year", "160 days")

        // Everything else stays where it was
        expect("10 km to mi", "6.213711922 mi")
        expect("255 to hex", "0xFF")
        expect("5pm ldn in sf", "9:00 AM")
        expect("jan 10 - feb 5", "-26 days")
        expectNil("back to the future")
        expectNil("how to train your dragon")
        expectNil("1 to 5")

        print("\n\(passes) passed, \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    static func expect(
        _ query: String, _ display: String, copy: String? = nil, source: String? = nil, target: String? = nil
    ) {
        guard let result = CalcEngine.evaluate(query, now: clock.now, calendar: clock.calendar),
            case .value(let shown, let copied) = result.payload
        else {
            fail(query, expected: display, got: "nil / error")
            return
        }
        check(query, expected: display, got: shown)
        if let copy { check("\(query) [copy]", expected: copy, got: copied) }
        if let source { check("\(query) [source]", expected: source, got: result.sourceBadge ?? "nil") }
        if let target { check("\(query) [target]", expected: target, got: result.targetBadge ?? "nil") }
    }

    static func expectNil(_ query: String) {
        let result = CalcEngine.evaluate(query, now: clock.now, calendar: clock.calendar)
        check(query, expected: "nil", got: result == nil ? "nil" : "\(result!.payload)")
    }

    static func check(_ query: String, expected: String, got: String) {
        if got == expected {
            passes += 1
        } else {
            fail(query, expected: expected, got: got)
        }
    }

    static func fail(_ query: String, expected: String, got: String) {
        failures += 1
        print("FAIL  \(query)\n      expected: \(expected)\n      got:      \(got)")
    }
}
