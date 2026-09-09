import SwiftUI
import DayCore

struct DaylightRail: View {
    @ObservedObject var model: AppModel

    var body: some View {
        if model.selectedDate == model.today {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text("今天的日光轨道").font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text("现在 \(clockLabel)").monospacedDigit().font(.system(size: 12))
                }.foregroundStyle(DaylightTheme.slate)
                GeometryReader { geometry in
                    let width = max(0, geometry.size.width - 20)
                    ZStack(alignment: .leading) {
                        Capsule().fill(DaylightTheme.hairline).frame(height: 3)
                        if let range = activeRange {
                            Capsule().fill(DaylightTheme.living)
                                .frame(width: max(3, width * (range.upperBound - range.lowerBound)), height: 5)
                                .offset(x: width * range.lowerBound)
                        }
                        Image(systemName: "sun.max.fill").font(.system(size: 20)).foregroundStyle(DaylightTheme.sun)
                            .frame(width: 20, height: 26).offset(x: width * fraction(model.now) - 10)
                    }.padding(.horizontal, 10).frame(height: 26)
                }.frame(height: 26)
                HStack {
                    Text("00:00"); Spacer(); Text("12:00"); Spacer(); Text("24:00")
                }.font(.system(size: 10)).monospacedDigit().foregroundStyle(DaylightTheme.slate)
            }.accessibilityElement(children: .ignore)
                .accessibilityLabel("今天的日光轨道，现在 \(clockLabel)\(activeRange == nil ? "" : "，青色段为正在进行的事项")")
        }
    }

    private var clockLabel: String {
        let parts = DayClock.calendar.dateComponents([.hour, .minute], from: model.now)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }
    private func fraction(_ date: Date) -> Double {
        let midnight = DayClock.calendar.startOfDay(for: model.now)
        return min(1, max(0, date.timeIntervalSince(midnight) / 86_400))
    }
    private var activeRange: ClosedRange<Double>? {
        guard let focus = model.focus, focus.task.status == .running else { return nil }
        let start = focus.task.begins(on: focus.day) ?? focus.task.startedAt.flatMap(DayClock.parseISO) ?? model.now
        let end = focus.task.deadline(on: focus.day) ?? model.now
        let lower = fraction(start), upper = fraction(end)
        guard upper > lower else { return nil }
        return lower...upper
    }
}
