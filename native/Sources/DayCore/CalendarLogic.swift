import Foundation

public struct MonthCell: Equatable {
    public let day: String
    public let number: Int
    public let inMonth: Bool
    public let hasData: Bool
}

public enum CalendarLogic {
    /// Monday-first grid, padded with adjacent dates to complete each week.
    public static func monthCells(containing day: String, knownDays: Set<String>) -> [MonthCell] {
        let calendar = DayClock.calendar
        guard let selected = DayClock.parseISO(day + "T12:00:00+08:00"),
              DayClock.dayString(selected) == day,
              let interval = calendar.dateInterval(of: .month, for: selected),
              let days = calendar.range(of: .day, in: .month, for: selected) else { return [] }
        let leading = (calendar.component(.weekday, from: interval.start) + 5) % 7
        let count = ((leading + days.count + 6) / 7) * 7
        return (0..<count).compactMap { index in
            guard let date = calendar.date(byAdding: .day, value: index - leading, to: interval.start) else { return nil }
            let value = DayClock.dayString(date)
            return MonthCell(day: value, number: calendar.component(.day, from: date),
                             inMonth: date >= interval.start && date < interval.end, hasData: knownDays.contains(value))
        }
    }

    public static func completionCounts(_ document: DayDocument) -> (done: Int, total: Int) {
        (document.tasks.filter { $0.status == .done }.count,
         document.tasks.filter { $0.status != .cancelled }.count)
    }
}
