import SwiftUI
import DayCore

struct MainView: View {
    @ObservedObject var model: AppModel
    @State private var editing: EditorSession?
    @State private var datePicker = false

    var body: some View {
        HStack(spacing:0) {
            sidebar.frame(width:190)
            Divider()
            VStack(alignment:.leading,spacing:0) {
                header.padding(.horizontal,28).padding(.top,24).padding(.bottom,22)
                Divider()
                if !model.online {
                    HStack {
                        Label("本机日程服务未连接，正在显示上次读取的内容。",systemImage:"wifi.slash")
                        Spacer()
                        Button("重试连接") { Task { await model.refresh() } }
                    }.font(.system(size:12)).padding(12).background(Color.orange.opacity(0.09))
                }
                if model.document.monitorSyncPending == true {
                    HStack(spacing:8) {
                        Image(systemName:"bell.badge")
                        Text("日程已保存，监督检查时间待同步。").font(.system(size:12))
                        Spacer()
                        Button("复制同步消息") { model.copySync() }.controlSize(.small)
                    }.foregroundStyle(.secondary).padding(.horizontal,28).padding(.vertical,10)
                }
                HStack(alignment:.top,spacing:22) {
                    ScrollView {
                        LazyVStack(spacing:12) {
                            if model.filteredTasks.isEmpty {
                                VStack(spacing:14) {
                                    Image(systemName:"calendar.badge.plus").font(.system(size:36,weight:.light)).foregroundStyle(.tertiary)
                                    Text(model.category == nil ? "这一天，还可以慢慢安排。" : "这个分类还没有事项。").font(.headline)
                                    Text("先留一段时间，做一件想做的事。").font(.subheadline).foregroundStyle(.secondary)
                                    Button("添加事项") { edit(nil) }.disabled(!model.canWrite)
                                }.frame(maxWidth:.infinity).padding(.vertical,65)
                            }
                            ForEach(model.filteredTasks) { task in taskRow(task) }
                            if !model.filteredTasks.isEmpty {
                                Button { edit(nil) } label: { Label("添加下一件事",systemImage:"plus").frame(maxWidth:.infinity).padding(12) }
                                    .buttonStyle(.plain).foregroundStyle(.secondary).disabled(!model.canWrite)
                            }
                        }.padding(.bottom,20)
                    }.frame(maxWidth:.infinity)
                    VStack(spacing:16) {
                        FocusView(model:model).frame(maxWidth:.infinity,alignment:.leading)
                            .background(Color(nsColor:.controlBackgroundColor)).clipShape(RoundedRectangle(cornerRadius:16))
                            .overlay(RoundedRectangle(cornerRadius:16).strokeBorder(.quaternary))
                        progress
                        Button { model.toggleFloating?() } label: {
                            Label(model.floatingVisible ? "隐藏悬浮小窗" : "显示悬浮小窗",systemImage:"pip").frame(maxWidth:.infinity)
                        }.controlSize(.large)
                    }.frame(width:265)
                }.padding(.horizontal,28).padding(.top,22)
                Spacer(minLength:0)
                HStack {
                    Text(model.toast ?? (model.online ? "已同步到本机 · 上海时间" : "连接恢复后可继续保存"))
                    Spacer()
                    if model.busy { ProgressView().controlSize(.mini) }
                    Text("daaaay for Mac").foregroundStyle(.tertiary)
                }.font(.system(size:10)).foregroundStyle(.secondary).padding(.horizontal,28).padding(.vertical,12)
            }.frame(maxWidth:.infinity,maxHeight:.infinity).background(Color(nsColor:.windowBackgroundColor))
        }.frame(minWidth:1020,minHeight:640)
            .sheet(item:$editing) { session in TaskEditor(model:model,session:session) }
            .alert("操作未完成",isPresented:Binding(get:{model.error != nil && editing == nil},set:{if !$0 {model.error=nil}})) {
                Button("知道了") { model.error=nil }
            } message: { Text(model.error ?? "") }
    }
    private var sidebar: some View {
        VStack(alignment:.leading,spacing:0) {
            HStack(spacing:9) {
                Image(systemName:"sun.max.fill").font(.system(size:19))
                Text("daaaay").font(.system(size:25,weight:.semibold,design:.rounded)).tracking(-1)
            }.padding(.top,26).padding(.bottom,8)
            Text("一件一件，慢慢来。").font(.system(size:11)).foregroundStyle(.secondary).padding(.bottom,32)
            Text("日程").font(.system(size:10,weight:.semibold)).foregroundStyle(.tertiary).padding(.bottom,10)
            Button { model.category=nil } label: {
                HStack(spacing:8) { Image(systemName:"square.grid.2x2"); Text("全部事项"); Spacer(); Text("\(model.document.tasks.count)").foregroundStyle(.secondary) }
                    .font(.system(size:12,weight:.medium)).padding(10)
                    .background(model.category == nil ? Color.primary.opacity(0.07) : .clear,in:RoundedRectangle(cornerRadius:8))
            }.buttonStyle(.plain)
            Text("分类").font(.system(size:10,weight:.semibold)).foregroundStyle(.tertiary).padding(.top,25).padding(.bottom,10)
            ForEach(model.categories,id:\.self) { category in
                Button { model.category = model.category == category ? nil : category } label: {
                    HStack(spacing:9) {
                        Circle().fill(Color(taskHex:model.document.tasks.first(where:{$0.category == category})?.color ?? "#77808b")).frame(width:7,height:7)
                        Text(category).lineLimit(1); Spacer()
                        Text("\(model.document.tasks.filter{$0.category == category}.count)").foregroundStyle(.tertiary)
                    }.font(.system(size:12)).padding(.horizontal,10).padding(.vertical,10)
                        .background(model.category == category ? Color.primary.opacity(0.07) : .clear,in:RoundedRectangle(cornerRadius:8))
                }.buttonStyle(.plain)
            }
            Spacer()
            Divider().padding(.bottom,16)
            VStack(alignment:.leading,spacing:10) {
                Text("随时回到眼前这件事").font(.system(size:11,weight:.medium))
                HStack { Text("悬浮窗"); Spacer(); Text("⌃⌥Space").monospaced() }
                HStack { Text("完整日程"); Spacer(); Text("⌃⌥D").monospaced() }
            }.font(.system(size:10)).foregroundStyle(.secondary)
            if let problem=model.shortcutError { Text(problem).font(.caption2).foregroundStyle(.orange).padding(.top,10) }
            HStack(spacing:6) {
                Circle().fill(model.online ? Color.green : Color.orange).frame(width:5,height:5)
                Text(model.online ? "保存在这台 Mac 上" : "等待本机服务").font(.system(size:10)).foregroundStyle(.secondary)
            }.padding(.top,23).padding(.bottom,22)
        }.padding(.horizontal,16).frame(maxHeight:.infinity).background(.ultraThinMaterial)
    }
    private var header: some View {
        HStack {
            VStack(alignment:.leading,spacing:7) {
                Text(DayClock.heading(model.selectedDate)).font(.system(size:25,weight:.semibold))
                Text(model.selectedDate == model.today ? "今天的事，一件一件来。" : "按实际进展记录，不必填满每一分钟。").font(.system(size:12)).foregroundStyle(.secondary)
            }
            Spacer(minLength:12)
            HStack(spacing:6) {
                Button { model.select(DayClock.shift(model.selectedDate,by:-1)) } label: { Image(systemName:"chevron.left") }.accessibilityLabel("前一天")
                Button("今天") { model.select(model.today) }
                Button { model.select(DayClock.shift(model.selectedDate,by:1)) } label: { Image(systemName:"chevron.right") }.accessibilityLabel("后一天")
            }
            Button { datePicker.toggle() } label: { Image(systemName:"calendar") }.accessibilityLabel("选择日期")
                .popover(isPresented:$datePicker) {
                    DatePicker("选择日期",selection:Binding(get:{DayClock.parseISO(model.selectedDate+"T12:00:00+08:00") ?? model.now},set:{model.select(DayClock.dayString($0))}),displayedComponents:.date)
                        .environment(\.timeZone,DayClock.zone).padding(20)
                }
            Menu {
                Button("导出日历 .ics") { model.exportCalendar() }
                Button("打开网页版") { NSWorkspace.shared.open(model.serviceURL) }
                Button("刷新") { Task { await model.refresh() } }
            } label: { Image(systemName:"ellipsis") }.menuStyle(.borderlessButton).frame(width:25)
            Button { edit(nil) } label: { Label("新建事项",systemImage:"plus") }.buttonStyle(.borderedProminent).tint(.primary).controlSize(.large).disabled(!model.canWrite)
        }
    }
    private func taskRow(_ task: DayTask) -> some View {
        HStack(alignment:.top,spacing:12) {
            RoundedRectangle(cornerRadius:2).fill(Color(taskHex:task.color)).frame(width:3)
            VStack(alignment:.leading,spacing:11) {
                HStack(alignment:.top,spacing:10) {
                    Button { model.changeStatus(task,day:model.selectedDate,to:task.status == .done ? .planned : .done) } label: {
                        Image(systemName:task.status == .done ? "checkmark.circle.fill" : "circle").font(.system(size:19,weight:.light))
                            .foregroundStyle(task.status == .done ? Color(taskHex:task.color) : Color.secondary.opacity(0.6))
                    }.buttonStyle(.plain).padding(.top,1).disabled(!model.canWrite).accessibilityLabel(task.status == .done ? "恢复未完成：\(task.title)" : "完成：\(task.title)")
                    VStack(alignment:.leading,spacing:7) {
                        Text(task.title).font(.system(size:14,weight:.semibold)).foregroundStyle(task.status == .done ? .secondary : .primary)
                            .strikethrough(task.status == .done).fixedSize(horizontal:false,vertical:true)
                        HStack(spacing:6) {
                            Text(task.timeLabel).monospacedDigit(); Text("·")
                            Text(task.status.label).foregroundStyle(task.status == .running ? Color.green : Color.secondary)
                        }.font(.system(size:10)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength:0)
                    Button { edit(task) } label: { Image(systemName:"square.and.pencil") }.buttonStyle(.plain).foregroundStyle(.secondary).disabled(!model.canWrite).accessibilityLabel("编辑 \(task.title)")
                }
                if !task.note.isEmpty {
                    Text(task.note).font(.system(size:11)).foregroundStyle(.secondary).lineSpacing(3).lineLimit(3).padding(.leading,29)
                }
                HStack(spacing:8) {
                    Text(task.category).font(.system(size:10)).padding(.horizontal,7).padding(.vertical,4).background(Color(taskHex:task.color).opacity(0.1),in:Capsule())
                    if task.block { Image(systemName:"shield.lefthalf.filled").font(.system(size:10)).foregroundStyle(.secondary).help("此事项已选择抖音限制") }
                    Spacer()
                    if task.elapsed(at:model.now)>0 { Text(DayClock.duration(task.elapsed(at:model.now))).font(.system(size:10,design:.monospaced)).foregroundStyle(.secondary) }
                    if task.status == .running {
                        Button("暂停") { model.changeStatus(task,day:model.selectedDate,to:.paused) }
                    } else if task.status == .planned || task.status == .paused {
                        Button(task.status == .paused ? "继续" : "开始") { model.changeStatus(task,day:model.selectedDate,to:.running) }
                    }
                }.controlSize(.small).disabled(!model.canWrite)
            }.padding(.vertical,3)
        }.padding(16).background(Color(nsColor:.controlBackgroundColor),in:RoundedRectangle(cornerRadius:12))
            .overlay(RoundedRectangle(cornerRadius:12).strokeBorder(task.status == .running ? Color(taskHex:task.color).opacity(0.5) : Color.primary.opacity(0.08)))
            .fixedSize(horizontal:false,vertical:true)
    }
    private var progress: some View {
        let total=model.document.tasks.filter{$0.status != .cancelled}.count
        let done=model.document.tasks.filter{$0.status == .done}.count
        return VStack(alignment:.leading,spacing:11) {
            HStack { Text("本日进展").font(.system(size:12,weight:.medium)); Spacer(); Text("\(done) / \(total)").font(.system(size:12,design:.monospaced)).foregroundStyle(.secondary) }
            ProgressView(value:Double(done),total:Double(max(1,total))).tint(.primary)
            Text(total>0 && done == total ? "已记录全部完成，给自己一点休息。" : "开始第一步，就有进展。").font(.system(size:11)).foregroundStyle(.secondary)
        }.padding(18)
    }
    private func edit(_ task: DayTask?) {
        model.error=nil; editing=EditorSession(task:task ?? DayTask(),original:model.document,isNew:task == nil)
    }
}
