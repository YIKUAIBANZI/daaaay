import SwiftUI
import DayCore

struct FocusView: View {
    @ObservedObject var model: AppModel
    var floating = false

    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            HStack {
                Image(systemName:"timer").foregroundStyle(.secondary)
                Text(floating ? "daaaay · 现在这一件" : "现在这一件").font(.system(size:12,weight:.semibold)).foregroundStyle(.secondary)
                Spacer()
                if floating {
                    Button { model.floatingPinned.toggle(); model.setPinned?(model.floatingPinned) } label: {
                        Image(systemName:model.floatingPinned ? "pin.fill" : "pin")
                    }.help("切换置顶").accessibilityLabel("切换置顶").buttonStyle(.plain)
                    Button { model.toggleFloating?() } label: { Image(systemName:"xmark") }
                        .help("隐藏悬浮窗 ⌃⌥Space").accessibilityLabel("隐藏悬浮窗").buttonStyle(.plain).padding(.leading,6)
                }
            }
            if let focus=model.focus {
                HStack(spacing:7) {
                    Circle().fill(Color(taskHex:focus.task.color)).frame(width:7,height:7)
                    Text(focus.task.category).font(.system(size:11,weight:.medium)).foregroundStyle(.secondary)
                    Spacer()
                    Text(focus.task.status.label).font(.system(size:11,weight:.medium)).foregroundStyle(focus.task.status == .running ? Color.green : Color.secondary)
                }
                Text(focus.task.title).font(.system(size:floating ? 17 : 21,weight:.semibold)).lineLimit(floating ? 2 : 4).fixedSize(horizontal:false,vertical:true)
                VStack(alignment:.leading,spacing:5) {
                    Text(DayClock.duration(focus.task.elapsed(at:model.now)))
                        .font(.system(size:floating ? 40 : 44,weight:.light,design:.rounded)).monospacedDigit()
                        .accessibilityLabel("累计用时 \(DayClock.duration(focus.task.elapsed(at:model.now)))")
                    Text("累计用时").font(.system(size:11)).foregroundStyle(.secondary)
                }
                if let end=focus.task.deadline(on:focus.day) {
                    let remaining=end.timeIntervalSince(model.now)
                    HStack(spacing:5) {
                        Image(systemName:"clock")
                        Text(remaining >= 0 ? "距计划结束 \(DayClock.duration(remaining))" : "已超时 \(DayClock.duration(-remaining))")
                            .monospacedDigit()
                    }.font(.system(size:12)).foregroundStyle(remaining >= 0 ? Color.secondary : Color.orange)
                } else { Text("无固定结束时间").font(.system(size:12)).foregroundStyle(.secondary) }
                HStack(spacing:8) {
                    if focus.task.status == .running {
                        Button { model.changeStatus(focus.task,day:focus.day,to:.paused) } label: { Label("暂停",systemImage:"pause.fill").frame(maxWidth:.infinity) }
                        Button { model.changeStatus(focus.task,day:focus.day,to:.done) } label: { Label("完成",systemImage:"checkmark").frame(maxWidth:.infinity) }.buttonStyle(.borderedProminent).tint(.primary)
                    } else {
                        Button { model.changeStatus(focus.task,day:focus.day,to:.running) } label: { Label(focus.task.status == .paused ? "继续计时" : "开始这一件",systemImage:"play.fill").frame(maxWidth:.infinity) }.buttonStyle(.borderedProminent).tint(.primary)
                    }
                }.controlSize(.large).disabled(!model.online || model.busy)
                if !floating && !focus.task.note.isEmpty {
                    Divider()
                    Text(focus.task.note).font(.system(size:12)).foregroundStyle(.secondary).lineSpacing(4).lineLimit(8)
                }
            } else {
                Image(systemName:"leaf").font(.system(size:32,weight:.light)).foregroundStyle(.secondary).padding(.top,8)
                Text("给自己一点留白。").font(.system(size:20,weight:.semibold))
                Text("暂时没有进行中或即将开始的事项。\n想继续时，再安排下一小步。")
                    .font(.system(size:12)).foregroundStyle(.secondary).lineSpacing(4)
                if floating {
                    Button("打开日程") { model.showMain?() }.controlSize(.large)
                }
            }
            if !model.online {
                HStack {
                    Label("本机服务未连接",systemImage:"wifi.slash").font(.system(size:11)).foregroundStyle(.orange)
                    Spacer()
                    Button("重试") { Task { await model.refresh() } }.font(.system(size:11))
                }
            }
            if floating {
                HStack {
                    Text("⌃⌥Space 呼出 / 隐藏").font(.system(size:10)).foregroundStyle(.tertiary)
                    Spacer()
                    Button { model.showMain?() } label: { Image(systemName:"arrow.up.left.and.arrow.down.right") }
                        .buttonStyle(.plain).foregroundStyle(.secondary).help("打开完整日程").accessibilityLabel("打开完整日程")
                }
            }
        }.padding(floating ? 20 : 22)
    }
}
