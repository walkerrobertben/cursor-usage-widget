import Foundation

/// Calendar used when the model turns dates into captions.
/// Production uses the device clock; tests pass a fixed value.
public struct DisplayCalendar: Equatable, Sendable {
    public var now: Date
    public var timeZone: TimeZone
    public var locale: Locale

    public init(now: Date = Date(), timeZone: TimeZone = .current, locale: Locale = .current) {
        self.now = now
        self.timeZone = timeZone
        self.locale = locale
    }

    public static var current: DisplayCalendar {
        DisplayCalendar()
    }

    public var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = locale
        return calendar
    }
}
