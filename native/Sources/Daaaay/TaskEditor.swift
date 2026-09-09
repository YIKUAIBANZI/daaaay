import SwiftUI
import DayCore

struct TaskEditor: View {
    @ObservedObject var model: AppModel
    let session: EditorSession
    @State private var task: DayTask
    @State private var original: DayDocument
    @State private var targetDate: String
    @State private var isUntimed: Bool
    @State private var validation: String?
    @State private var deleting = false
    @Environment(\.dismiss) private var dismiss
    private let palette=["#7562b6","#5684ad","#548c74","#bb8650","#c06877","#77808b"]

    init(model: AppModel, session: EditorSession) {
        self.model=model; self.session=session; self._task=State(initialValue:session.task)
        self._original=State(initialValue:session.original)
        self._targetDate=State(initialValue:session.original.date)
        self._isUntimed=State(initialValue:session.task.start.isEmpty && session.task.end.isEmpty)
    }
    var body: some View {
        VStack(alignment:.leading,spacing:18) {
            ScrollView {
            VStack(alignment:.leading,spacing:18) {
            HStack {
                VStack(alignment:.leading,spacing:5) {
                    Text(session.isNew ? "留一段时间" : "调整这个事项").font(.title2.weight(.semibold))
                    Text("让时间有个落点").font(.subheadline).foregroundStyle(DaylightTheme.slate)
                }
                Spacer()
                Button { dismiss() } label: { Image(systemName:"xmark").frame(width:DaylightTheme.minimumTarget,height:DaylightTheme.minimumTarget) }.buttonStyle(.plain).accessibilityLabel("关闭编辑")
            }
            VStack(alignment:.leading,spacing:6) {
                Text("事项名称").font(.caption).foregroundStyle(.secondary)
                TextField("想推进哪一件事？",text:$task.title).textFieldStyle(.roundedBorder).accessibilityLabel("事项名称")
            }
            HStack(spacing:16) {
                VStack(alignment:.leading,spacing:6) {
                    Text("分类").font(.caption).foregroundStyle(.secondary)
                    TextField("学习、项目、生活…",text:$task.category).textFieldStyle(.roundedBorder).accessibilityLabel("分类")
                }
                VStack(alignment:.leading,spacing:6) {
                    Text("颜色").font(.caption).foregroundStyle(.secondary)
                    HStack(spacing:7) {
                        ForEach(palette,id:\.self) { hex in
                            Button { task.color=hex } label: {
                                Circle().fill(Color(taskHex:hex)).frame(width:20,height:20)
                                    .overlay { if task.color == hex { Image(systemName:"checkmark").font(.system(size:10,weight:.bold)).foregroundStyle(.white) } }
                                    .frame(width:DaylightTheme.minimumTarget,height:DaylightTheme.minimumTarget)
                            }.buttonStyle(.plain).accessibilityLabel("颜色 \(hex)")
                        }
                        ColorPicker("自定义颜色",selection:Binding(get:{Color(taskHex:task.color)},set:{ color in
                            guard let rgb=NSColor(color).usingColorSpace(.deviceRGB) else { return }
                            task.color=String(format:"#%02x%02x%02x",Int(rgb.redComponent*255),Int(rgb.greenComponent*255),Int(rgb.blueComponent*255))
                        }),supportsOpacity:false).labelsHidden()
                    }
                }
            }
            SchedulePicker(task:$task,date:$targetDate,isUntimed:$isUntimed,validation:$validation)
            if movingRunningTask {
                VStack(alignment:.leading,spacing:6) {
                    Text("正在计时的事项需要先暂停，再移动到另一天。").font(.caption).foregroundStyle(DaylightTheme.slate)
                    Button { pauseForMove() } label: { Text("先暂停计时").frame(minHeight:DaylightTheme.primaryHeight) }.disabled(needsReload)
                }
            }
            VStack(alignment:.leading,spacing:6) {
                Text("最小启动动作 / 备注").font(.caption).foregroundStyle(.secondary)
                TextEditor(text:$task.note).font(.body).frame(height:70).padding(6)
                    .background(Color(nsColor:.textBackgroundColor)).clipShape(RoundedRectangle(cornerRadius:8))
                    .overlay(RoundedRectangle(cornerRadius:8).strokeBorder(.quaternary)).accessibilityLabel("备注")
            }
            Toggle("这个时段限制抖音",isOn:$task.block)
            Text("使用现有 Chrome 扩展；未设时间不会新建限制时段。").font(.caption).foregroundStyle(.secondary)
            if let validation { Text(validation).font(.callout).foregroundStyle(.red) }
            if let error=model.error { Text(error).font(.callout).foregroundStyle(.red).lineLimit(3) }
            if needsReload {
                VStack(alignment:.leading,spacing:6) {
                    Text("日程已有更新或保存结果尚未确认。重新载入两天会替换本次未保存的编辑。").font(.caption).foregroundStyle(.orange)
                    Button { reload() } label: { Text("重新载入最新内容").frame(minHeight:DaylightTheme.primaryHeight) }
                }
            }
            }.padding(.trailing,4)
            }.disabled(model.busy)
            Divider()
            HStack {
                if !session.isNew {
                    Button(role:.destructive) { deleting=true } label: { Text("删除事项").frame(minHeight:DaylightTheme.minimumTarget) }.disabled(needsReload)
                }
                Spacer()
                Button { dismiss() } label: { Text("取消").frame(minHeight:DaylightTheme.minimumTarget) }.keyboardShortcut(.cancelAction)
                Button { save() } label: { Text("保存事项").frame(minHeight:DaylightTheme.primaryHeight) }
                    .buttonStyle(.borderedProminent).tint(DaylightTheme.action).keyboardShortcut(.defaultAction)
                    .disabled(needsReload || movingRunningTask || !model.online)
            }.frame(minHeight:DaylightTheme.primaryHeight).disabled(model.busy)
        }.padding(28).frame(width:620,height:min(760,(NSScreen.main?.visibleFrame.height ?? 860)-100))
            .background(DaylightTheme.surface)
            .onAppear { model.error=nil; model.editorConflictDates=[] }
            .confirmationDialog("删除这个事项？",isPresented:$deleting,titleVisibility:.visible) {
                Button("删除事项",role:.destructive) { Task { if await model.remove(task,from:original) { dismiss() } } }
                Button("取消",role:.cancel) {}
            }
    }
    private var needsReload: Bool {
        (model.documents[original.date].map { $0.revision != original.revision } ?? false)
        || model.editorConflictDates.contains(original.date) || model.editorConflictDates.contains(targetDate)
    }
    private var movingRunningTask: Bool {
        targetDate != original.date && (task.status == .running || original.tasks.first(where:{$0.id == task.id})?.status == .running)
    }
    private func pauseForMove() {
        var paused = original
        guard let index = paused.tasks.firstIndex(where:{$0.id == task.id}) else { return }
        paused.tasks[index].status = .paused
        Task {
            if await model.save(paused), let latest=model.documents[original.date],
               let updated=latest.tasks.first(where:{$0.id == task.id}) {
                original=latest
                task.status=updated.status; task.startedAt=updated.startedAt; task.elapsedSeconds=updated.elapsedSeconds
            }
        }
    }
    private func reload() {
        Task {
            guard await model.reloadEditorDays(sourceDate:original.date,targetDate:targetDate),
                  let latest=model.documents[original.date] else { return }
            if session.isNew { original=latest }
            else if let updated=latest.tasks.first(where:{$0.id == task.id}) {
                task=updated; original=latest; isUntimed=updated.start.isEmpty && updated.end.isEmpty
            }
            else {
                validation="这个事项已被删除或移动，请关闭编辑窗口并核对日程。"; return
            }
            validation=nil; model.error=nil; model.editorConflictDates=[]
        }
    }
    private func save() {
        task.title=task.title.trimmingCharacters(in:.whitespacesAndNewlines)
        task.category=task.category.trimmingCharacters(in:.whitespacesAndNewlines)
        task.start=task.start.trimmingCharacters(in:.whitespaces); task.end=task.end.trimmingCharacters(in:.whitespaces)
        guard !task.title.isEmpty && !task.category.isEmpty else { validation="请填写事项名称和分类。"; return }
        guard isUntimed || (!task.start.isEmpty && !task.end.isEmpty) else {
            validation="请选择开始和结束时间，或打开“无固定时间”。"; return
        }
        guard task.start.isEmpty == task.end.isEmpty else { validation="请同时填写开始和结束时间，或都留空。"; return }
        if !task.start.isEmpty {
            guard task.start.range(of:#"^([01][0-9]|2[0-3]):[0-5][0-9]$"#,options:.regularExpression) != nil,
                  task.end.range(of:#"^([01][0-9]|2[0-3]):[0-5][0-9]$"#,options:.regularExpression) != nil,
                  let start=task.begins(on:targetDate), let end=task.deadline(on:targetDate), end>start, end.timeIntervalSince(start)<=86400
            else { validation="结束需晚于开始；较早的结束时间会自动记为次日，最长 24 小时。"; return }
        }
        validation=nil
        Task { if await model.saveEditedTask(task,original:original,targetDate:targetDate) { model.announce("日程已保存"); dismiss() } }
    }
}
