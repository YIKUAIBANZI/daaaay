import SwiftUI
import DayCore

struct FocusView: View {
    @ObservedObject var model: AppModel
    var floating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(floating ? "daaaay · 现在这一件" : "现在这一件")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(DaylightTheme.slate)
                Spacer(minLength: 0)
                if floating {
                    Button { model.floatingPinned.toggle(); model.setPinned?(model.floatingPinned) } label: {
                        Image(systemName: model.floatingPinned ? "pin.fill" : "pin")
                    }.buttonStyle(DaylightIconButtonStyle())
                        .accessibilityLabel(model.floatingPinned ? "取消置顶" : "置顶悬浮窗")
                        .accessibilityValue(model.floatingPinned ? "已置顶" : "未置顶")
                    Button { model.toggleFloating?() } label: { Image(systemName: "xmark") }
                        .buttonStyle(DaylightIconButtonStyle()).help("隐藏悬浮窗 ⌃⌥Space")
                        .accessibilityLabel("隐藏悬浮窗")
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if let focus = model.focus {
                        HStack(spacing: 7) {
                            Circle().fill(focus.task.status == .running ? DaylightTheme.living : Color(taskHex: focus.task.color))
                                .frame(width: 7, height: 7).accessibilityHidden(true)
                            Text(focus.task.category)
                            Spacer()
                            Text(focus.task.status.label)
                        }.font(.system(size: 11, weight: .medium)).foregroundStyle(DaylightTheme.slate)
                        Text(focus.task.title).font(.system(size: floating ? 17 : 21, weight: .semibold))
                            .lineLimit(floating ? 2 : 4).fixedSize(horizontal: false, vertical: true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(DayClock.duration(focus.task.elapsed(at: model.now)))
                                .font(.system(size: floating ? 40 : 44, weight: .light, design: .rounded)).monospacedDigit()
                            Text("累计用时").font(.system(size: 11)).foregroundStyle(DaylightTheme.slate)
                        }.accessibilityElement(children: .ignore)
                            .accessibilityLabel("累计用时")
                            .accessibilityValue(DayClock.duration(focus.task.elapsed(at: model.now)))
                        if let end = focus.task.deadline(on: focus.day) {
                            let remaining = end.timeIntervalSince(model.now)
                            Text(remaining >= 0 ? "距计划结束 \(DayClock.duration(remaining))" : "已超时 \(DayClock.duration(-remaining))")
                                .monospacedDigit().font(.system(size: 12)).foregroundStyle(DaylightTheme.slate)
                        } else {
                            Text("无固定结束时间").font(.system(size: 12)).foregroundStyle(DaylightTheme.slate)
                        }
                        HStack(spacing: 8) {
                            if focus.task.status == .running {
                                Button { model.changeStatus(focus.task, day: focus.day, to: .paused) } label: {
                                    Label("暂停", systemImage: "pause.fill").frame(maxWidth: .infinity)
                                }.buttonStyle(SecondaryPillButtonStyle())
                                Button { model.changeStatus(focus.task, day: focus.day, to: .done) } label: {
                                    Label("完成", systemImage: "checkmark").frame(maxWidth: .infinity)
                                }.buttonStyle(PrimaryPillButtonStyle())
                            } else {
                                Button { model.changeStatus(focus.task, day: focus.day, to: .running) } label: {
                                    Label("开始", systemImage: "play.fill").frame(maxWidth: .infinity)
                                }.buttonStyle(PrimaryPillButtonStyle())
                            }
                        }.disabled(!model.online || model.busy)
                        if !floating && !focus.task.note.isEmpty {
                            Text(focus.task.note).font(.system(size: 12)).foregroundStyle(DaylightTheme.slate).lineLimit(8)
                        }
                    } else {
                        Text("暂时没有待开始的事项").font(.system(size: 20, weight: .semibold)).padding(.top, 8)
                        Text("打开日程，安排下一小步。").font(.system(size: 12)).foregroundStyle(DaylightTheme.slate)
                    }
                    if !model.online && !floating {
                        HStack {
                            Label("本机服务未连接", systemImage: "wifi.slash").font(.system(size: 11))
                            Spacer(minLength: 0)
                            Button("重试连接") { Task { await model.refresh() } }.buttonStyle(SecondaryPillButtonStyle())
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            if floating {
                HStack {
                    if model.online {
                        Text("⌃⌥Space 呼出 / 隐藏").font(.system(size: 10)).foregroundStyle(DaylightTheme.slate)
                    } else {
                        Label("本机服务未连接", systemImage: "wifi.slash").font(.system(size: 10)).foregroundStyle(DaylightTheme.slate)
                        Button { Task { await model.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                            .buttonStyle(DaylightIconButtonStyle()).help("重试连接").accessibilityLabel("重试连接")
                    }
                    Spacer(minLength: 0)
                    Button { model.showMain?() } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                        .buttonStyle(DaylightIconButtonStyle()).help("打开完整日程").accessibilityLabel("打开完整日程")
                }
            }
        }.padding(floating ? 16 : 22).foregroundStyle(DaylightTheme.ink)
    }
}
