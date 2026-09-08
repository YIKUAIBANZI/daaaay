import SwiftUI
import DayCore

struct TaskEditor: View {
    @ObservedObject var model: AppModel
    let session: EditorSession
    @State private var task: DayTask
    @State private var original: DayDocument
    @State private var validation: String?
    @State private var deleting = false
    @Environment(\.dismiss) private var dismiss
    private let palette=["#7562b6","#5684ad","#548c74","#bb8650","#c06877","#77808b"]

    init(model: AppModel, session: EditorSession) {
        self.model=model; self.session=session; self._task=State(initialValue:session.task)
        self._original=State(initialValue:session.original)
    }
    var body: some View {
        VStack(alignment:.leading,spacing:18) {
            HStack {
                VStack(alignment:.leading,spacing:5) {
                    Text(session.isNew ? "留一段时间" : "调整这个事项").font(.title2.weight(.semibold))
                    Text(DayClock.heading(session.original.date)).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Button { dismiss() } label: { Image(systemName:"xmark") }.buttonStyle(.plain).accessibilityLabel("关闭编辑")
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
                            }.buttonStyle(.plain).accessibilityLabel("颜色 \(hex)")
                        }
                        ColorPicker("自定义颜色",selection:Binding(get:{Color(taskHex:task.color)},set:{ color in
                            guard let rgb=NSColor(color).usingColorSpace(.deviceRGB) else { return }
                            task.color=String(format:"#%02x%02x%02x",Int(rgb.redComponent*255),Int(rgb.greenComponent*255),Int(rgb.blueComponent*255))
                        }),supportsOpacity:false).labelsHidden()
                    }
                }
            }
            HStack(alignment:.bottom,spacing:12) {
                VStack(alignment:.leading,spacing:6) {
                    Text("开始 · 上海时间").font(.caption).foregroundStyle(.secondary)
                    TextField("09:00",text:$task.start).textFieldStyle(.roundedBorder).accessibilityLabel("开始时间")
                }
                VStack(alignment:.leading,spacing:6) {
                    Text("结束").font(.caption).foregroundStyle(.secondary)
                    TextField("10:00",text:$task.end).textFieldStyle(.roundedBorder).accessibilityLabel("结束时间")
                }
                Toggle("次日结束",isOn:$task.nextDay).padding(.bottom,4)
            }
            Text("没有确定时间时，两项都留空即可。").font(.caption).foregroundStyle(.secondary)
            VStack(alignment:.leading,spacing:6) {
                Text("最小启动动作 / 备注").font(.caption).foregroundStyle(.secondary)
                TextEditor(text:$task.note).font(.body).frame(height:95).padding(6)
                    .background(Color(nsColor:.textBackgroundColor)).clipShape(RoundedRectangle(cornerRadius:8))
                    .overlay(RoundedRectangle(cornerRadius:8).strokeBorder(.quaternary)).accessibilityLabel("备注")
            }
            Toggle("这个时段限制抖音",isOn:$task.block)
            Text("使用现有 Chrome 扩展；未设时间不会新建限制时段。").font(.caption).foregroundStyle(.secondary)
            if let validation { Text(validation).font(.callout).foregroundStyle(.red) }
            if let error=model.error { Text(error).font(.callout).foregroundStyle(.red).lineLimit(3) }
            if let latest=model.documents[original.date],latest.revision != original.revision {
                VStack(alignment:.leading,spacing:6) {
                    Text("其他地方更新了这一天。重新载入会替换本次未保存的编辑。").font(.caption).foregroundStyle(.orange)
                    Button("重新载入最新内容") {
                        if session.isNew { original=latest; model.error=nil }
                        else if let updated=latest.tasks.first(where:{$0.id == task.id}) {
                            task=updated; original=latest; validation=nil; model.error=nil
                        } else { validation="这个事项已在其他地方删除，请关闭编辑窗口。" }
                    }
                }
            }
            Divider()
            HStack {
                if !session.isNew { Button("删除事项",role:.destructive) { deleting=true } }
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存事项") { save() }.buttonStyle(.borderedProminent).tint(.primary).keyboardShortcut(.defaultAction)
            }.disabled(model.busy)
        }.padding(28).frame(width:500).fixedSize(horizontal:false,vertical:true)
            .confirmationDialog("删除这个事项？",isPresented:$deleting,titleVisibility:.visible) {
                Button("删除事项",role:.destructive) { Task { if await model.remove(task,from:original) { dismiss() } } }
                Button("取消",role:.cancel) {}
            }
    }
    private func save() {
        task.title=task.title.trimmingCharacters(in:.whitespacesAndNewlines)
        task.category=task.category.trimmingCharacters(in:.whitespacesAndNewlines)
        task.start=task.start.trimmingCharacters(in:.whitespaces); task.end=task.end.trimmingCharacters(in:.whitespaces)
        guard !task.title.isEmpty && !task.category.isEmpty else { validation="请填写事项名称和分类。"; return }
        guard task.start.isEmpty == task.end.isEmpty else { validation="请同时填写开始和结束时间，或都留空。"; return }
        if !task.start.isEmpty {
            guard task.start.range(of:#"^([01][0-9]|2[0-3]):[0-5][0-9]$"#,options:.regularExpression) != nil,
                  task.end.range(of:#"^([01][0-9]|2[0-3]):[0-5][0-9]$"#,options:.regularExpression) != nil,
                  let start=task.begins(on:session.original.date), let end=task.deadline(on:session.original.date), end>start, end.timeIntervalSince(start)<=86400
            else { validation="使用 HH:mm；结束需晚于开始，跨午夜请选次日，最长 24 小时。"; return }
        }
        var doc=original
        if let i=doc.tasks.firstIndex(where:{$0.id == task.id}) { doc.tasks[i]=task } else { doc.tasks.append(task) }
        Task { if await model.save(doc) { model.announce("日程已保存"); dismiss() } }
    }
}
