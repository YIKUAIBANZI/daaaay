import Foundation

public struct ScheduleDraft: Equatable {
    public var date: String
    public var start: String
    public var end: String
    public var nextDay: Bool
    public var isUntimed: Bool

    public init(date: String, start: String, end: String, nextDay: Bool, isUntimed: Bool) {
        self.date = date
        self.start = start
        self.end = end
        self.nextDay = nextDay
        self.isUntimed = isUntimed
    }
}

public enum ScheduleSaveRoute: Equatable {
    case sameDay
    case move
}

public enum ScheduleEditingError: Error, Equatable {
    case invalidDate
    case invalidHour
    case invalidMinute
    case invalidDuration
}

public enum ScheduleEditing {
    /// Round a minute to the nearest five-minute wheel position.
    /// The wheel wraps 58...59 to 00; callers that need the carried hour use
    /// `snappedStartDate` below rather than treating 00 as the same hour.
    public static func snapMinute(_ minute: Int) -> Int {
        let value = ((minute % 60) + 60) % 60
        return ((value + 2) / 5 * 5) % 60
    }

    /// Apply a bounded duration to a local Shanghai start date.
    public static func applying(durationMinutes: Int, to start: Date) throws -> ScheduleDraft {
        guard (0...1440).contains(durationMinutes) else {
            throw ScheduleEditingError.invalidDuration
        }

        let snappedStart = snappedStartDate(start)
        let end = DayClock.calendar.date(byAdding: .minute, value: durationMinutes, to: snappedStart)!
        let date = DayClock.dayString(snappedStart)
        let startComponents = DayClock.calendar.dateComponents([.hour, .minute], from: snappedStart)
        let endComponents = DayClock.calendar.dateComponents([.hour, .minute], from: end)
        let endDate = DayClock.dayString(end)
        return ScheduleDraft(
            date: date,
            start: clockString(hour: startComponents.hour!, minute: startComponents.minute!),
            end: clockString(hour: endComponents.hour!, minute: endComponents.minute!),
            nextDay: endDate != date,
            isUntimed: false
        )
    }

    public static func normalized(date: String, startHour: Int, startMinute: Int,
                                  endHour: Int, endMinute: Int,
                                  isUntimed: Bool) throws -> ScheduleDraft {
        guard let noon = DayClock.parseISO("\(date)T12:00:00+08:00"), DayClock.dayString(noon) == date else {
            throw ScheduleEditingError.invalidDate
        }
        guard (0...23).contains(startHour), (0...23).contains(endHour) else {
            throw ScheduleEditingError.invalidHour
        }
        guard (0...59).contains(startMinute), (0...59).contains(endMinute) else {
            throw ScheduleEditingError.invalidMinute
        }
        if isUntimed {
            return ScheduleDraft(date: date, start: "", end: "", nextDay: false, isUntimed: true)
        }

        let start = snappedClock(hour: startHour, minute: startMinute)
        let end = snappedClock(hour: endHour, minute: endMinute)
        // The picker represents the end relative to the normalized start.
        // Equal times are a zero-length same-day slot; only an earlier end
        // crosses midnight automatically.
        let nextDay = end.dayOffset > start.dayOffset
            || (end.dayOffset == start.dayOffset && end.clockMinutes < start.clockMinutes)
        return ScheduleDraft(
            date: DayClock.shift(date, by: start.dayOffset),
            start: clockString(hour: start.hour, minute: start.minute),
            end: clockString(hour: end.hour, minute: end.minute),
            nextDay: nextDay,
            isUntimed: false
        )
    }

    public static func saveRoute(sourceDate: String, targetDate: String) -> ScheduleSaveRoute {
        sourceDate == targetDate ? .sameDay : .move
    }

    private struct SnappedClock {
        let hour: Int
        let minute: Int
        let dayOffset: Int
        var clockMinutes: Int { hour * 60 + minute }
    }

    private static func snappedClock(hour: Int, minute: Int) -> SnappedClock {
        let snapped = snapMinute(minute)
        let carriedHour = snapped < minute ? hour + 1 : hour
        return SnappedClock(hour: carriedHour % 24, minute: snapped, dayOffset: carriedHour / 24)
    }

    private static func snappedStartDate(_ date: Date) -> Date {
        let calendar = DayClock.calendar
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        var base = DateComponents()
        base.year = components.year
        base.month = components.month
        base.day = components.day
        base.hour = hour
        base.minute = 0
        base.second = 0
        let midnight = calendar.date(from: base)!
        let snapped = snapMinute(minute)
        let carry = snapped < minute ? 60 - minute + snapped : snapped - minute
        return calendar.date(byAdding: .minute, value: minute + carry, to: midnight)!
    }

    private static func clockString(hour: Int, minute: Int) -> String {
        String(format: "%02d:%02d", hour, minute)
    }
}
