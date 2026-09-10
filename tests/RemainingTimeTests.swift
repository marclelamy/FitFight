import Foundation

@main
struct RemainingTimeTests {
    static func main() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US_POSIX")

        let now = date(2026, 9, 10, 12, 0, calendar: calendar)

        let oneDayFiveHours = RemainingTime.breakdown(
            from: now,
            until: date(2026, 9, 11, 17, 0, calendar: calendar),
            calendar: calendar
        )
        precondition(
            oneDayFiveHours == RemainingTime.Breakdown(days: 1, hours: 5),
            "Under two days must keep the day and show hours, not round up to 2 days"
        )

        let justUnderTwoDays = RemainingTime.breakdown(
            from: now,
            until: date(2026, 9, 12, 11, 0, calendar: calendar),
            calendar: calendar
        )
        precondition(
            justUnderTwoDays == RemainingTime.Breakdown(days: 1, hours: 23),
            "1 day 23 hours must stay 1 day plus hours"
        )

        let twoDaysPlus = RemainingTime.breakdown(
            from: now,
            until: date(2026, 9, 12, 13, 0, calendar: calendar),
            calendar: calendar
        )
        precondition(
            twoDaysPlus == RemainingTime.Breakdown(days: 2),
            "Two days and an hour must not show hours"
        )

        let tenDays = RemainingTime.breakdown(
            from: now,
            until: date(2026, 9, 20, 12, 0, calendar: calendar),
            calendar: calendar
        )
        precondition(
            tenDays == RemainingTime.Breakdown(weeks: 1, days: 3),
            "10 days should read as 1 week and 3 days"
        )

        let fiveHours = RemainingTime.breakdown(
            from: now,
            until: date(2026, 9, 10, 17, 20, calendar: calendar),
            calendar: calendar
        )
        precondition(
            fiveHours == RemainingTime.Breakdown(hours: 5, minutes: 20),
            "Under a day should show hours and minutes"
        )

        let fortyFiveMinutes = RemainingTime.breakdown(
            from: now,
            until: date(2026, 9, 10, 12, 45, calendar: calendar),
            calendar: calendar
        )
        precondition(
            fortyFiveMinutes == RemainingTime.Breakdown(minutes: 45),
            "Under an hour should show minutes"
        )

        let thirtySeconds = RemainingTime.breakdown(
            from: now,
            until: now.addingTimeInterval(30),
            calendar: calendar
        )
        precondition(
            thirtySeconds == RemainingTime.Breakdown(minutes: 1),
            "A few seconds left should still show 1 minute"
        )

        let oneMonth = RemainingTime.breakdown(
            from: now,
            until: calendar.date(byAdding: .month, value: 1, to: now)!,
            calendar: calendar
        )
        precondition(
            oneMonth == RemainingTime.Breakdown(months: 1),
            "A calendar month later should show 1 month"
        )

        let phrase = RemainingTime.phrase(
            from: now,
            until: date(2026, 9, 11, 17, 0, calendar: calendar),
            calendar: calendar
        )
        precondition(!phrase.isEmpty, "Remaining phrase must not be empty")
        precondition(
            !phrase.contains("2026") && !phrase.contains("Sep"),
            "Remaining phrase must not include a calendar date"
        )
    }

    private static func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        _ minute: Int,
        calendar: Calendar
    ) -> Date {
        calendar.date(
            from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        )!
    }
}
