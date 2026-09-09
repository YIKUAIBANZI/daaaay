import SwiftUI
import DayCore

struct SchedulePicker: View {
    @Binding var task: DayTask
    @Binding var date: String
    @Binding var isUntimed: Bool
    @Binding var validation: String?
    @State private var dateOpen = false
    @State private var startOpen = false
    @State private var endOpen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button { dateOpen.toggle() } label: {
                    Label(DayClock.heading(date), systemImage: "calendar")
                        .frame(minHeight: DaylightTheme.primaryHeight)
                }
                .accessibilityLabel("事项日期").accessibilityValue(date)
                .popover(isPresented: $dateOpen) {
                    VStack {
                        DatePicker("事项日期", selection: Binding(get: {
                            DayClock.parseISO("\(date)T12:00:00+08:00") ?? Date()
                        }, set: { date = DayClock.dayString($0) }), displayedComponents: .date)
                            .datePickerStyle(.graphical)
                            .environment(\.timeZone, DayClock.calendar.timeZone)
                        Button("选好了") { dateOpen = false }.frame(minHeight: DaylightTheme.primaryHeight)
                    }.padding(16)
                }
                Spacer()
                Toggle("无固定时间", isOn: Binding(get: { isUntimed }, set: { setUntimed($0) }))
                    .toggleStyle(.switch).accessibilityLabel("无固定时间")
            }
            if !isUntimed {
                HStack(spacing: 12) {
                    timeButton(label: "开始时间", value: task.start, open: $startOpen, isStart: true)
                    Image(systemName: "arrow.right").foregroundStyle(DaylightTheme.slate)
                    timeButton(label: "结束时间", value: task.end, open: $endOpen, isStart: false)
                }
                HStack(spacing: 8) {
                    Text("时长").font(.caption).foregroundStyle(DaylightTheme.slate)
                    ForEach([30, 60, 90, 120], id: \.self) { duration in
                        Button { applyDuration(duration) } label: {
                            Text("\(duration) 分钟").frame(minWidth: DaylightTheme.minimumTarget, minHeight: DaylightTheme.minimumTarget)
                        }
                            .disabled(task.start.isEmpty)
                            .accessibilityLabel("设为 \(duration) 分钟")
                    }
                }
                HStack {
                    Text(task.start.isEmpty ? "先选择开始时间，再选择结束或快捷时长。" : "上海时间 · 可滚动或直接输入")
                        .font(.caption).foregroundStyle(DaylightTheme.slate)
                    Spacer()
                    if task.nextDay { Text("次日 \(task.end)").font(.caption.weight(.semibold)).foregroundStyle(DaylightTheme.action) }
                }
                if !task.start.isEmpty && task.start == task.end {
                    Toggle("持续到次日（24 小时）", isOn: $task.nextDay).font(.caption)
                }
            }
        }
        .padding(16).background(DaylightTheme.canvas, in: RoundedRectangle(cornerRadius: 12))
    }

    private func timeButton(label: String, value: String, open: Binding<Bool>, isStart: Bool) -> some View {
        Button { open.wrappedValue = true } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(label).font(.caption).foregroundStyle(DaylightTheme.slate)
                Text(value.isEmpty ? "选择时间" : ((!isStart && task.nextDay ? "次日 " : "") + value))
                    .font(.system(.title3, design: .monospaced).weight(.medium)).foregroundStyle(DaylightTheme.ink)
            }.frame(maxWidth: .infinity, minHeight: DaylightTheme.primaryHeight, alignment: .leading)
        }
        .accessibilityLabel(label).accessibilityValue(value.isEmpty ? "未设置" : (!isStart && task.nextDay ? "次日 " : "") + value)
        .popover(isPresented: open) {
            ScrollTimePicker(label: label, value: Binding(get: { isStart ? task.start : task.end },
                                                        set: { setClock($0, isStart: isStart) }))
        }
    }

    func setUntimed(_ untimed: Bool) {
        isUntimed = untimed
        if untimed { task.start = ""; task.end = ""; task.nextDay = false }
        validation = nil
    }

    func setClock(_ clock: String, isStart: Bool) {
        if isStart { task.start = clock } else { task.end = clock }
        if !task.start.isEmpty && !task.end.isEmpty { task.nextDay = task.end < task.start }
        validation = nil
    }

    func applyDuration(_ minutes: Int) {
        guard let start = DayClock.parseISO("\(date)T\(task.start):00+08:00") else {
            validation = "请先选择开始时间。"; return
        }
        do {
            let draft = try ScheduleEditing.applying(durationMinutes: minutes, to: start)
            date = draft.date; task.start = draft.start; task.end = draft.end; task.nextDay = draft.nextDay
            validation = nil
        } catch {
            validation = "无法应用这个时长，请选择 30、60、90 或 120 分钟，或重新调整时间。"
        }
    }
}
