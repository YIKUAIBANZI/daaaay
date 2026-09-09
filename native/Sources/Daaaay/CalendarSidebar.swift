import SwiftUI
import DayCore

struct CalendarSidebar: View {
    @ObservedObject var model: AppModel
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("daaaay").font(.system(size: 27, weight: .semibold, design: .rounded)).tracking(-1)
                    Text("一件一件，慢慢来。").font(.system(size: 12)).foregroundStyle(DaylightTheme.slate)
                }
                calendar
                VStack(alignment: .leading, spacing: 6) {
                    Text("分类").font(.system(size: 12, weight: .semibold)).foregroundStyle(DaylightTheme.slate).padding(.bottom, 4)
                    categoryButton(nil)
                    ForEach(model.categories, id: \.self) { categoryButton($0) }
                }
                Rectangle().fill(DaylightTheme.hairline).frame(height: 1)
                VStack(alignment: .leading, spacing: 10) {
                    Label("Agent 草案", systemImage: "text.badge.plus").font(.system(size: 13, weight: .semibold))
                    Text("这里还没有草案。\n建议经过你确认后，才会进入日程。")
                        .font(.system(size: 12)).foregroundStyle(DaylightTheme.slate).lineSpacing(4)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("⌃⌥Space  悬浮窗")
                    Text("⌃⌥D  完整日程")
                    if let problem = model.shortcutError { Text(problem).foregroundStyle(DaylightTheme.ink) }
                }.font(.system(size: 11)).foregroundStyle(DaylightTheme.slate).padding(.top, 16)
            }.padding(20)
        }.background(DaylightTheme.canvas)
    }

    private var calendar: some View {
        let known = Set(model.documents.values.filter { !$0.tasks.isEmpty }.map(\.date))
        let cells = CalendarLogic.monthCells(containing: model.selectedDate, knownDays: known)
        return VStack(spacing: 8) {
            HStack {
                Text(String(model.selectedDate.prefix(7)).replacingOccurrences(of: "-", with: " / "))
                    .font(.system(size: 15, weight: .semibold)).monospacedDigit()
                Spacer()
                Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel("上个月").buttonStyle(DaylightIconButtonStyle())
                Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
                    .accessibilityLabel("下个月").buttonStyle(DaylightIconButtonStyle())
            }
            LazyVGrid(columns: columns, spacing: 3) {
                ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { day in
                    Text(day).font(.system(size: 11)).foregroundStyle(DaylightTheme.slate).frame(height: 24)
                }
                ForEach(cells, id: \.day) { cell in
                    Button { model.select(cell.day) } label: {
                        VStack(spacing: 2) {
                            Text("\(cell.number)").font(.system(size: 12, weight: cell.day == model.selectedDate ? .bold : .regular))
                            Circle().fill(cell.day == model.selectedDate ? DaylightTheme.surface : DaylightTheme.ink)
                                .frame(width: 3, height: 3).opacity(cell.hasData ? 1 : 0)
                        }
                        .frame(maxWidth: .infinity, minHeight: DaylightTheme.minimumTarget)
                        .foregroundStyle(cell.day == model.selectedDate ? DaylightTheme.surface : (cell.inMonth ? DaylightTheme.ink : DaylightTheme.slate))
                        .background(cell.day == model.selectedDate ? DaylightTheme.ink : .clear, in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                        .accessibilityLabel("\(cell.day)\(cell.hasData ? "，有已读取事项" : "")")
                        .accessibilityAddTraits(cell.day == model.selectedDate ? .isSelected : [])
                }
            }
            Text("圆点表示已读取的日程").font(.system(size: 10)).foregroundStyle(DaylightTheme.slate)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
        }
    }

    private func categoryButton(_ category: String?) -> some View {
        Button { model.category = category } label: {
            HStack(spacing: 8) {
                if let category {
                    Circle().fill(Color(taskHex: model.document.tasks.first(where: { $0.category == category })?.color ?? "#747474"))
                        .frame(width: 6, height: 6)
                } else { Image(systemName: "line.3.horizontal") }
                Text(category ?? "全部事项").lineLimit(1)
                Spacer()
                Text("\(model.document.tasks.filter { category == nil || $0.category == category }.count)").monospacedDigit()
                    .foregroundStyle(DaylightTheme.slate)
            }.font(.system(size: 12)).padding(.horizontal, 10).frame(minHeight: 36)
                .background(model.category == category ? DaylightTheme.hairline : .clear, in: RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(model.category == category ? .isSelected : [])
    }

    private func shiftMonth(_ offset: Int) {
        guard let date = DayClock.parseISO(model.selectedDate + "T12:00:00+08:00"),
              let next = DayClock.calendar.date(byAdding: .month, value: offset, to: date) else { return }
        model.select(DayClock.dayString(next))
    }
}
