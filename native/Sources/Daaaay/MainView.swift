import SwiftUI
import DayCore

struct MainView: View {
    @ObservedObject var model: AppModel
    @State private var editing: EditorSession?
    @State private var sidebarPopover = false

    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.width < 1120
            HStack(spacing: 0) {
                if !compact && !model.sidebarCollapsed {
                    CalendarSidebar(model: model).frame(width: 264)
                    Rectangle().fill(DaylightTheme.hairline).frame(width: 1)
                }
                VStack(alignment: .leading, spacing: 0) {
                    header(compact: compact).padding(.horizontal, 24).padding(.vertical, 20)
                    Rectangle().fill(DaylightTheme.hairline).frame(height: 1)
                    notices
                    if compact {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 24) {
                                HStack(alignment: .top, spacing: 30) {
                                    focus(compact: true).frame(maxWidth: .infinity, alignment: .leading)
                                    DailyProgressView(document: model.document).frame(width: 250)
                                }
                                Rectangle().fill(DaylightTheme.hairline).frame(height: 1)
                                DaylightRail(model: model)
                                AgendaView(model: model, edit: edit)
                            }.padding(24)
                        }
                    } else {
                        HStack(alignment: .top, spacing: 0) {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 26) {
                                    DaylightRail(model: model)
                                    AgendaView(model: model, edit: edit)
                                }.padding(24)
                            }.frame(maxWidth: .infinity)
                            Rectangle().fill(DaylightTheme.hairline).frame(width: 1)
                            ScrollView {
                                VStack(alignment: .leading, spacing: 28) {
                                    focus(compact: false)
                                    Rectangle().fill(DaylightTheme.hairline).frame(height: 1)
                                    DailyProgressView(document: model.document)
                                    floatingButton
                                }.padding(20)
                            }.frame(width: 260)
                        }
                    }
                    footer.padding(.horizontal, 24).padding(.vertical, 10)
                }.frame(maxWidth: .infinity, maxHeight: .infinity).background(DaylightTheme.surface)
            }
        }.foregroundStyle(DaylightTheme.ink).background(DaylightTheme.canvas)
            .frame(minWidth: 1020, minHeight: 640).preferredColorScheme(.light)
            .sheet(item: $editing) { session in TaskEditor(model: model, session: session) }
            .alert("操作未完成", isPresented: Binding(get: { model.error != nil && editing == nil }, set: { if !$0 { model.error = nil } })) {
                Button("知道了") { model.error = nil }
            } message: { Text(model.error ?? "") }
    }

    private func header(compact: Bool) -> some View {
        HStack(spacing: 12) {
            Button {
                if compact { sidebarPopover.toggle() } else { model.sidebarCollapsed.toggle() }
            } label: {
                Image(systemName: "sidebar.left").frame(width: 40, height: 40)
            }.buttonStyle(DaylightIconButtonStyle()).accessibilityLabel("展开或收起月历与分类")
                .popover(isPresented: $sidebarPopover, arrowEdge: .bottom) {
                    CalendarSidebar(model: model).frame(width: 272, height: 600).preferredColorScheme(.light)
                }
            VStack(alignment: .leading, spacing: 6) {
                Text(DayClock.heading(model.selectedDate)).font(.system(size: 24, weight: .semibold))
                Text(model.selectedDate == model.today ? "今天的事，一件一件来。" : "按实际进展记录。")
                    .font(.system(size: 12)).foregroundStyle(DaylightTheme.slate)
            }
            Spacer(minLength: 8)
            HStack(spacing: 4) {
                Button { model.select(DayClock.shift(model.selectedDate, by: -1)) } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(DaylightIconButtonStyle()).accessibilityLabel("前一天")
                Button("今天") { model.select(model.today) }.buttonStyle(SecondaryPillButtonStyle())
                Button { model.select(DayClock.shift(model.selectedDate, by: 1)) } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(DaylightIconButtonStyle()).accessibilityLabel("后一天")
            }
            Menu {
                Button("导出日历 .ics") { model.exportCalendar() }
                Button("打开网页版") { NSWorkspace.shared.open(model.serviceURL) }
                Button("刷新") { Task { await model.refresh() } }
            } label: { Image(systemName: "ellipsis").frame(width: 32, height: 40) }
                .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("更多日程操作")
            Button { edit(nil) } label: { Label("添加事项", systemImage: "plus") }
                .buttonStyle(PrimaryPillButtonStyle()).disabled(!model.canWrite)
        }
    }

    @ViewBuilder private var notices: some View {
        if !model.online {
            HStack(spacing: 12) {
                Label("本机服务未连接，显示上次读取的内容。", systemImage: "wifi.slash")
                Spacer()
                Button("重试连接") { Task { await model.refresh() } }.buttonStyle(SecondaryPillButtonStyle())
            }.font(.system(size: 12)).padding(.horizontal, 24).padding(.vertical, 8).background(DaylightTheme.canvas)
        }
        if model.document.monitorSyncPending == true {
            HStack(spacing: 12) {
                Label("日程已保存，监督检查时间待同步。", systemImage: "bell.badge")
                Spacer()
                Button("复制同步消息") { model.copySync() }.buttonStyle(SecondaryPillButtonStyle())
            }.font(.system(size: 12)).padding(.horizontal, 24).padding(.vertical, 8).background(DaylightTheme.canvas)
        }
    }

    private func focus(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("现在这一件").font(.system(size: 12, weight: .semibold)).foregroundStyle(DaylightTheme.slate)
                Spacer()
                if compact { floatingButton }
            }
            if let item = model.focus {
                if item.day != model.selectedDate {
                    Button { model.select(item.day) } label: { Label("来自 \(item.day)", systemImage: "arrow.up.right") }
                        .buttonStyle(SecondaryPillButtonStyle())
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(item.task.title).font(.system(size: compact ? 19 : 22, weight: .semibold))
                        .lineLimit(compact ? 2 : 4).fixedSize(horizontal: false, vertical: true)
                    if compact { Spacer() }
                    Text(item.task.status.label).font(.system(size: 11)).foregroundStyle(DaylightTheme.slate).fixedSize()
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(DayClock.duration(item.task.elapsed(at: model.now)))
                        .font(.system(size: compact ? 32 : 38, weight: .light, design: .rounded)).monospacedDigit()
                    Text("累计用时").font(.system(size: 11)).foregroundStyle(DaylightTheme.slate)
                }.accessibilityElement(children: .combine)
                HStack(spacing: 8) {
                    if item.task.status == .running {
                        Button { model.changeStatus(item.task, day: item.day, to: .paused) } label: { Label("暂停", systemImage: "pause.fill") }
                            .buttonStyle(SecondaryPillButtonStyle())
                        Button { model.changeStatus(item.task, day: item.day, to: .done) } label: { Label("完成", systemImage: "checkmark") }
                            .buttonStyle(PrimaryPillButtonStyle())
                    } else {
                        Button { model.changeStatus(item.task, day: item.day, to: .running) } label: {
                            Label("开始", systemImage: "play.fill")
                        }.buttonStyle(PrimaryPillButtonStyle())
                    }
                }.disabled(!model.online || model.busy)
                if !compact && !item.task.note.isEmpty {
                    Text(item.task.note).font(.system(size: 12)).foregroundStyle(DaylightTheme.slate).lineSpacing(4).lineLimit(6)
                }
            } else {
                Text("给自己一点留白。").font(.system(size: 21, weight: .medium))
                Text("暂时没有进行中或即将开始的事项。")
                    .font(.system(size: 12)).foregroundStyle(DaylightTheme.slate).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var floatingButton: some View {
        Button { model.toggleFloating?() } label: {
            Label(model.floatingVisible ? "隐藏小窗" : "显示小窗", systemImage: "pip")
        }.buttonStyle(SecondaryPillButtonStyle())
    }
    private var footer: some View {
        HStack {
            Text(model.toast ?? (model.online ? "已同步到本机 · 上海时间" : "连接恢复后可继续保存"))
            Spacer()
            if model.busy { ProgressView().controlSize(.mini) }
        }.font(.system(size: 11)).foregroundStyle(DaylightTheme.slate)
    }
    private func edit(_ task: DayTask?) {
        model.error = nil
        editing = EditorSession(task: task ?? DayTask(), original: model.document, isNew: task == nil)
    }
}
