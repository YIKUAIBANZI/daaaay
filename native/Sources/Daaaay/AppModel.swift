import SwiftUI
import AppKit
import DayCore

@MainActor
final class AppModel: ObservableObject {
    @Published var selectedDate = DayClock.dayString(Date())
    @Published var documents: [String:DayDocument] = [:]
    @Published var now = Date()
    @Published var online = false
    @Published var busy = false
    @Published var error: String?
    @Published var toast: String?
    @Published var category: String?
    @Published var sidebarCollapsed = false
    @Published var shortcutError: String?
    @Published var floatingVisible = false
    @Published var floatingPinned = true
    let client: DayClient
    let serviceURL: URL
    private var timer: Timer?
    private var refreshing = false
    private var ticks = 0
    var showMain: (() -> Void)?
    var toggleFloating: (() -> Void)?
    var setPinned: ((Bool) -> Void)?

    init() {
        let configured=ProcessInfo.processInfo.environment["DAAAAY_SERVICE_URL"] ?? "http://127.0.0.1:18765"
        let url=URL(string:configured)!
        self.serviceURL=url; self.client=DayClient(baseURL:url)
    }
    var today: String { DayClock.dayString(now) }
    var document: DayDocument { documents[selectedDate] ?? DayDocument(date:selectedDate) }
    var focus: FocusItem? { FocusItem.choose(today:documents[today],yesterday:documents[DayClock.shift(today,by:-1)],otherDays:Array(documents.values),now:now) }
    var categories: [String] { Array(Set(document.tasks.map(\.category))).sorted() }
    var filteredTasks: [DayTask] {
        document.tasks.filter { category == nil || $0.category == category }.sorted {
            let a=$0.start.isEmpty ? "99:99" : $0.start
            let b=$1.start.isEmpty ? "99:99" : $1.start
            return a == b ? $0.title < $1.title : a < b
        }
    }
    var canWrite: Bool { online && !busy && documents[selectedDate] != nil }

    func start() {
        Task { await refresh() }
        timer=Timer.scheduledTimer(withTimeInterval:1,repeats:true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let oldToday=self.today
                self.now=Date(); self.ticks += 1
                if oldToday != self.today && self.selectedDate == oldToday { self.selectedDate=self.today }
                if self.ticks % 3 == 0 { await self.refresh() }
            }
        }
        if let timer { RunLoop.main.add(timer,forMode:.common) }
    }
    func select(_ date: String) {
        selectedDate=date; category=nil
        Task { await refresh() }
    }
    func refresh() async {
        guard !refreshing && !busy else { return }
        refreshing=true
        defer { refreshing=false }
        var dates=Set([selectedDate,today,DayClock.shift(today,by:-1)])
        // Refresh a still-running historical day instead of retaining a stale blocker.
        dates.formUnion(documents.values.filter{$0.tasks.contains(where:{$0.status == .running})}.map(\.date))
        if let last=UserDefaults.standard.string(forKey:"lastRunningDay") { dates.insert(last) }
        do {
            var fresh: [String:DayDocument]=[:]
            for date in dates.sorted() { fresh[date]=try await client.read(date) }
            for (date,doc) in fresh { documents[date]=doc }
            if let running=documents.values.sorted(by:{$0.date>$1.date}).first(where:{$0.tasks.contains(where:{$0.status == .running})}) {
                UserDefaults.standard.set(running.date,forKey:"lastRunningDay")
            } else { UserDefaults.standard.removeObject(forKey:"lastRunningDay") }
            online=true
        } catch { online=false }
    }
    func save(_ value: DayDocument) async -> Bool {
        guard !busy && online else { return false }
        // Let an in-flight read finish first; never apply its older snapshot after a save.
        while refreshing { try? await Task.sleep(nanoseconds:30_000_000) }
        guard !busy && online else { return false }
        busy=true
        do {
            let result=try await client.save(value)
            documents[result.date]=result
            if result.tasks.contains(where:{$0.status == .running}) { UserDefaults.standard.set(result.date,forKey:"lastRunningDay") }
            busy=false; online=true; error=nil
            return true
        } catch {
            busy=false
            if let e=error as? ServiceError {
                self.error=e.message
            } else {
                self.error="保存结果尚未确认，请恢复连接并刷新后核对。\n"+error.localizedDescription
                online=false
            }
            await refresh()
            return false
        }
    }
    func changeStatus(_ task: DayTask, day: String, to status: TaskStatus) {
        guard var doc=documents[day], online, !busy else { return }
        guard let index=doc.tasks.firstIndex(where:{$0.id == task.id}) else { return }
        if status == .running {
            if documents.values.contains(where:{ $0.date != day && $0.tasks.contains(where:{$0.status == .running}) }) {
                error="另一天还有正在计时的事项，请先在悬浮窗暂停或完成它。"; return
            }
            for i in doc.tasks.indices where doc.tasks[i].status == .running {
                doc.tasks[i].status = .paused; doc.tasks[i].startedAt=nil
            }
        }
        doc.tasks[index].status=status
        doc.tasks[index].startedAt=nil
        Task {
            if await save(doc) { announce(status == .running ? "开始了，先做眼前这一小步。" : "已保存") }
        }
    }
    func remove(_ task: DayTask, from original: DayDocument) async -> Bool {
        var doc=original; doc.tasks.removeAll {$0.id == task.id}
        return await save(doc)
    }
    func announce(_ text: String) {
        toast=text
        Task { try? await Task.sleep(nanoseconds:3_000_000_000); if toast == text { toast=nil } }
    }
    func copySync() {
        let msg="同步网页日程：请读取 daaaay/days/\(selectedDate).json 的最新日程，保留用户状态；过滤已完成、暂缓、取消和已过时段，仅在有效时段内，在指定的‘执行检查’任务中更新有限的每 30 分钟检查。验证自动化后再清除 monitorSyncPending。"
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(msg,forType:.string)
        announce("已复制，请粘贴到“执行检查”任务。")
    }
    func exportCalendar() {
        let day=selectedDate
        Task {
            do {
                let data=try await client.calendar(day)
                let panel=NSSavePanel(); panel.nameFieldStringValue="daaaay-\(day).ics"
                panel.title="导出日历"; panel.canCreateDirectories=true
                guard panel.runModal() == .OK, let url=panel.url else { return }
                try data.write(to:url,options:.atomic)
                announce("日历已导出，双击文件即可导入。")
            } catch { self.error="导出失败："+error.localizedDescription }
        }
    }
}

extension Color {
    init(taskHex: String) {
        let value=UInt64(taskHex.dropFirst(),radix:16) ?? 0x7562b6
        self.init(red:Double((value>>16)&255)/255,green:Double((value>>8)&255)/255,blue:Double(value&255)/255)
    }
}

struct EditorSession: Identifiable {
    let id=UUID()
    var task: DayTask
    var original: DayDocument
    var isNew: Bool
}
