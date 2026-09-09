import SwiftUI
import DayCore

struct DailyProgressView: View {
    let document: DayDocument

    var body: some View {
        let counts = CalendarLogic.completionCounts(document)
        VStack(alignment: .leading, spacing: 12) {
            Text("当日进度").font(.system(size: 12, weight: .semibold)).foregroundStyle(DaylightTheme.slate)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("\(counts.done)").font(.system(size: 32, weight: .medium, design: .rounded))
                Text("/ \(counts.total) 件已完成").font(.system(size: 12)).foregroundStyle(DaylightTheme.slate)
            }
            ProgressView(value: Double(counts.done), total: Double(max(1, counts.total))).tint(DaylightTheme.ink)
                .accessibilityLabel("\(counts.total) 件事项，已完成 \(counts.done) 件")
            Text(counts.total == 0 ? "还没有待完成的安排。" : counts.done == counts.total ? "都已标记完成，留一点时间休息。" : "按实际进展记录，一件一件来。")
                .font(.system(size: 12)).foregroundStyle(DaylightTheme.slate).fixedSize(horizontal: false, vertical: true)
        }
    }
}
