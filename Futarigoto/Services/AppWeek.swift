import Foundation

enum AppWeek {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "ja_JP")
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current
        calendar.firstWeekday = 2
        return calendar
    }

    static func start(of date: Date) -> Date {
        let cal = calendar
        let weekday = cal.component(.weekday, from: date)
        let daysFromMonday = (weekday + 5) % 7
        let day = cal.startOfDay(for: date)
        return cal.date(byAdding: .day, value: -daysFromMonday, to: day) ?? day
    }

    static func end(of weekStart: Date) -> Date {
        let cal = calendar
        let nextMonday = cal.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
        return nextMonday.addingTimeInterval(-1)
    }

    static func isSunday(_ date: Date) -> Bool {
        calendar.component(.weekday, from: date) == 1
    }

    static func previousWeekStart(from date: Date) -> Date {
        calendar.date(byAdding: .day, value: -7, to: start(of: date)) ?? start(of: date)
    }

    static func contains(_ date: Date, weekStart: Date) -> Bool {
        date >= weekStart && date <= end(of: weekStart)
    }

    static func weekdayLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }

    static func weekLabel(for weekStart: Date) -> String {
        let cal = calendar
        let month = cal.component(.month, from: weekStart)
        let weekOfMonth = cal.component(.weekOfMonth, from: weekStart)
        return "\(month)月 第\(weekOfMonth)週"
    }

    static func monthLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
        formatter.dateFormat = "M月"
        return formatter.string(from: date)
    }

    static func startOfDay(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    static func isSameDay(_ lhs: Date, _ rhs: Date) -> Bool {
        calendar.isDate(lhs, inSameDayAs: rhs)
    }

    static func dayLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
        formatter.dateFormat = "M月d日(EEE)"
        return formatter.string(from: date)
    }

    static func monthStart(of date: Date) -> Date {
        let cal = calendar
        let comps = cal.dateComponents([.year, .month], from: date)
        return cal.date(from: comps) ?? cal.startOfDay(for: date)
    }
}
