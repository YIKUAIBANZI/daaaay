import SwiftUI
import DayCore

struct AgendaView: View {
    @ObservedObject var model: AppModel
    let edit: (DayTask?) -> Void

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(model.category ?? "全部日程").font(.system(size: 15, weight: .semibold))
                Spacer()
                Text("\(model.filteredTasks.count) 件事项").font(.system(size: 12)).foregroundStyle(DaylightTheme.slate)
            }.padding(.bottom, 16)
            if model.filteredTasks.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    Text(model.category == nil ? "这一天，还可以慢慢安排。" : "这个分类还没有事项。")
                        .font(.system(size: 21, weight: .medium))
                    Text("先放下一件想做的事，时间可以稍后再定。")
                        .font(.system(size: 13)).foregroundStyle(DaylightTheme.slate)
                    Button { edit(nil) } label: { Label("添加事项", systemImage: "plus") }
                        .buttonStyle(PrimaryPillButtonStyle()).disabled(!model.canWrite)
                }.padding(.vertical, 36).frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(model.filteredTasks) { task in
                    row(task)
                    Rectangle().fill(DaylightTheme.hairline).frame(height: 1)
                }
                Button { edit(nil) } label: { Label("添加下一件事", systemImage: "plus") }
                    .buttonStyle(SecondaryPillButtonStyle()).disabled(!model.canWrite).padding(.top, 18)
            }
        }
    }

    private func row(_ task: DayTask) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(task.start.isEmpty ? "待定" : task.start).font(.system(size: 14, weight: .medium)).monospacedDigit()
                if !task.end.isEmpty {
                    Text(task.end).monospacedDigit()
                    if task.nextDay { Text("次日") }
                }
            }.font(.system(size: 11)).foregroundStyle(DaylightTheme.slate).frame(width: 48, alignment: .leading)
            RoundedRectangle(cornerRadius: 2).fill(task.status == .running ? DaylightTheme.living : Color(taskHex: task.color))
                .frame(width: 3).frame(minHeight: 105)
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(task.title).font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(task.status == .done || task.status == .cancelled ? DaylightTheme.slate : DaylightTheme.ink)
                        .strikethrough(task.status == .done).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Text(task.status.label).font(.system(size: 11)).foregroundStyle(DaylightTheme.slate).fixedSize()
                }
                HStack(spacing: 8) {
                    Text(task.category)
                    if task.block { Label("限制抖音", systemImage: "shield.lefthalf.filled") }
                }.font(.system(size: 11)).foregroundStyle(DaylightTheme.slate)
                if !task.note.isEmpty {
                    Text(task.note).font(.system(size: 12)).foregroundStyle(DaylightTheme.slate)
                        .lineSpacing(3).lineLimit(3)
                }
                HStack(spacing: 6) {
                    if task.status == .running {
                        Button { model.changeStatus(task, day: model.selectedDate, to: .paused) } label: { Label("暂停", systemImage: "pause.fill") }
                            .buttonStyle(SecondaryPillButtonStyle())
                    } else if task.status == .planned || task.status == .paused {
                        Button { model.changeStatus(task, day: model.selectedDate, to: .running) } label: {
                            Label(task.status == .paused ? "继续" : "开始", systemImage: "play.fill")
                        }.buttonStyle(PrimaryPillButtonStyle())
                    }
                    if task.status != .done && task.status != .cancelled {
                        Button { model.changeStatus(task, day: model.selectedDate, to: .done) } label: { Label("完成", systemImage: "checkmark") }
                            .buttonStyle(SecondaryPillButtonStyle())
                    }
                    Button { edit(task) } label: { Label("编辑", systemImage: "square.and.pencil") }
                        .buttonStyle(SecondaryPillButtonStyle())
                }.disabled(!model.canWrite)
            }
        }.padding(.vertical, 20).fixedSize(horizontal: false, vertical: true)
    }
}
