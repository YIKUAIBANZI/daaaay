import Foundation
import DayCore

enum HTTPChecks {
    static func run() async throws {
        let project=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("daaaay-http-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root.appendingPathComponent("days"),withIntermediateDirectories:true)
        let service=project.appendingPathComponent("web/server.py").path
        let base=URL(string:"http://127.0.0.1:18767")!
        func launch() throws -> Process {
            let p=Process(); p.executableURL=URL(fileURLWithPath:"/usr/bin/env")
            p.arguments=["python3", "-c", Self.fixtureServer, service, root.path]
            try p.run(); return p
        }
        var process=try launch()
        // Foundation can wait indefinitely for a termination notification on this async
        // cleanup path even after the child exits. SIGTERM is enough for final teardown;
        // restart checks below still wait explicitly before rebinding the same port.
        defer { if process.isRunning { process.terminate() }; try? FileManager.default.removeItem(at:root) }
        let client=DayClient(baseURL:base)
        var connected=false
        for _ in 0..<30 {
            if (try? await client.bootstrap()) != nil { connected=true; break }
            try await Task.sleep(nanoseconds:100_000_000)
        }
        precondition(connected,"Isolated HTTP service must be ready")
        try await runEditorWorkflow(project: project, root: root, base: base)
        let day="2099-01-02"
        var original=try await client.read(day)
        precondition(original.revision == 0 && original.tasks.isEmpty)
        original.tasks=[DayTask(id:"timer-check",title:"隔离测试",start:"09:00",end:"10:00",status:.running)]
        let running=try await client.save(original)
        precondition(running.tasks[0].startedAt != nil,"Server starts the timer")
        try await Task.sleep(nanoseconds:1_100_000_000)
        var pause=running; pause.tasks[0].status = .paused; pause.tasks[0].startedAt=nil
        let paused=try await client.save(pause)
        precondition((paused.tasks[0].elapsedSeconds ?? 0)>=1,"Pause settles elapsed time")
        do { _=try await client.save(running); preconditionFailure("Stale revision overwrote a newer pause") }
        catch let error as ServiceError { precondition(error.code == 409) }
        let reopened=try await DayClient(baseURL:base).read(day)
        precondition(reopened.tasks[0].elapsedSeconds == paused.tasks[0].elapsedSeconds,"New client sees persisted timer")
        let ics=String(data:try await client.calendar(day),encoding:.utf8)!
        precondition(!ics.contains("BEGIN:VEVENT"),"Paused task must not be exported")
        process.terminate(); process.waitUntilExit()
        do { _=try await client.read(day); preconditionFailure("Stopped service should be offline") } catch {}
        process=try launch()
        for _ in 0..<30 {
            if (try? await DayClient(baseURL:base).read(day)) != nil { break }
            try await Task.sleep(nanoseconds:100_000_000)
        }
        // Existing client's token is stale. A safe 403 retry must re-bootstrap.
        var resume=paused; resume.tasks[0].status = .running
        let resumed=try await client.save(resume)
        precondition(resumed.tasks[0].elapsedSeconds == paused.tasks[0].elapsedSeconds)
        let calendar=String(data:try await client.calendar(day),encoding:.utf8)!
        precondition(calendar.contains("BEGIN:VEVENT") && calendar.contains("2099-01-02-timer-check@daaaay.local"))
        let raw=try String(contentsOf:root.appendingPathComponent("days/\(day).json"),encoding:.utf8)
        precondition(raw.contains("native_user"),"Native edits have accurate provenance")
        let sourceDay="2099-01-03", targetDay="2099-01-04"
        var source=try await client.read(sourceDay)
        source.tasks=[DayTask(id:"move-check",title:"跨日移动",start:"10:00",end:"11:00",status:.planned)]
        let savedSource=try await client.save(source)
        let target=try await client.read(targetDay)
        let moved=try await client.moveTask(savedSource.tasks[0],from:sourceDay,to:targetDay,
                                            sourceRevision:savedSource.revision,targetRevision:target.revision)
        precondition(moved.source.revision == savedSource.revision+1 && moved.source.tasks.isEmpty,
                     "Move removes the source task and advances its revision")
        precondition(moved.target.revision == target.revision+1 && moved.target.tasks.map(\.id) == ["move-check"],
                     "Move creates exactly one target task and advances its revision")
        process.terminate(); process.waitUntilExit()
        process=try launch()
        let restored=DayClient(baseURL:base)
        for _ in 0..<30 {
            if (try? await restored.read(sourceDay)) != nil { break }
            try await Task.sleep(nanoseconds:100_000_000)
        }
        let persistedSource=try await restored.read(sourceDay)
        let persistedTarget=try await restored.read(targetDay)
        precondition(persistedSource.revision == moved.source.revision && persistedSource.tasks.isEmpty,
                     "Restart preserves the moved-out source day")
        precondition(persistedTarget.revision == moved.target.revision && persistedTarget.tasks.map(\.id) == ["move-check"],
                     "Restart preserves the moved-in target day")
        print("PASS: HTTP save / timer persistence / conflict / calendar / move / service restart")
    }

    // Deterministically interleave another real Store.save between the model's target GET
    // and move POST. All other requests use the production handler and storage unchanged.
    static let fixtureServer = #"""
    import importlib.util, sys
    from pathlib import Path
    spec = importlib.util.spec_from_file_location('daylight_server', sys.argv[1])
    server = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(server)
    class InterleavingStore(server.Store):
        injected = False
        def move_task(self, source, target, task_id, source_revision, target_revision, replacement):
            if task_id == 'target-conflict' and not self.injected:
                self.injected = True
                latest = self.read(target)
                latest['tasks'][0]['note'] = 'changed after target read'
                latest['source'] = 'native_user'
                self.save(target, latest)
            return super().move_task(source, target, task_id, source_revision, target_revision, replacement)
    store = InterleavingStore(Path(sys.argv[2]))
    server.ThreadingHTTPServer(('127.0.0.1', 18767), server.make_handler(store, Path(sys.argv[1]).with_name('index.html'), False)).serve_forever()
    """#

    /// Compile the real UI model into a small harness, keeping the production package graph unchanged.
    static func runEditorWorkflow(project: URL, root: URL, base: URL) async throws {
        let harness = root.appendingPathComponent("EditorWorkflowChecks.swift")
        try editorWorkflow.write(to: harness, atomically: true, encoding: .utf8)
        let bin = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        let objects = try FileManager.default.contentsOfDirectory(at: bin.appendingPathComponent("DayCore.build"), includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasSuffix(".swift.o") }.map(\.path)
        let executable = root.appendingPathComponent("EditorWorkflowChecks")
        let compiler = Process()
        compiler.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        compiler.arguments = ["swiftc", "-parse-as-library", "-I", bin.appendingPathComponent("Modules").path,
                              project.appendingPathComponent("native/Sources/Daaaay/AppModel.swift").path,
                              project.appendingPathComponent("native/Sources/Daaaay/DaylightTheme.swift").path,
                              project.appendingPathComponent("native/Sources/Daaaay/ScrollTimePicker.swift").path,
                              project.appendingPathComponent("native/Sources/Daaaay/SchedulePicker.swift").path,
                              harness.path] + objects + ["-o", executable.path]
        try compiler.run(); compiler.waitUntilExit()
        guard compiler.terminationStatus == 0 else {
            throw NSError(domain: "EditorWorkflowChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: "Editor workflow harness did not compile"])
        }
        let check = Process(); check.executableURL = executable
        var environment = ProcessInfo.processInfo.environment
        environment["DAAAAY_SERVICE_URL"] = base.absoluteString
        check.environment = environment
        try check.run(); check.waitUntilExit()
        guard check.terminationStatus == 0 else {
            // Throw so the caller's defer terminates the isolated server even during a RED run.
            throw NSError(domain: "EditorWorkflowChecks", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Real AppModel editor workflow checks failed"])
        }
    }

    static let editorWorkflow = #"""
    import Foundation
    import SwiftUI
    import AppKit
    import DayCore
    @main struct EditorWorkflowChecks {
        @MainActor static func main() async throws {
            var draftTask = DayTask(title: "时间选择", start: "09:35", end: "10:35")
            var draftDate = "2099-03-01"
            var draftUntimed = false
            var validation: String?
            let picker = SchedulePicker(task: Binding(get: { draftTask }, set: { draftTask = $0 }),
                                        date: Binding(get: { draftDate }, set: { draftDate = $0 }),
                                        isUntimed: Binding(get: { draftUntimed }, set: { draftUntimed = $0 }),
                                        validation: Binding(get: { validation }, set: { validation = $0 }))
            picker.applyDuration(90)
            precondition(draftTask.end == "11:05" && !draftTask.nextDay)
            draftTask.start = "09:31"
            picker.applyDuration(90)
            precondition(draftDate == "2099-03-01" && draftTask.start == "09:30" && draftTask.end == "11:00" && !draftTask.nextDay,
                         "Rounding 09:31 down must not advance the start hour or date")
            draftTask.start = "23:31"
            picker.applyDuration(90)
            precondition(draftDate == "2099-03-01" && draftTask.start == "23:30" && draftTask.end == "01:00" && draftTask.nextDay,
                         "Rounding 23:31 down must keep the original task date while its end crosses midnight")
            draftTask.start = "23:40"
            picker.applyDuration(90)
            precondition(draftTask.end == "01:10" && draftTask.nextDay)
            picker.setUntimed(true)
            precondition(draftTask.start.isEmpty && draftTask.end.isEmpty && !draftTask.nextDay && draftUntimed)
            picker.setUntimed(false)
            precondition(draftTask.start.isEmpty && draftTask.end.isEmpty && !draftUntimed,
                         "Enabling scheduling must not silently invent confirmed times")
            picker.setClock("09:35", isStart: true)
            picker.applyDuration(90)
            precondition(draftTask.start == "09:35" && draftTask.end == "11:05")
            picker.applyDuration(1441)
            precondition(validation != nil && draftTask.end == "11:05", "Invalid duration is recoverable")
            let wheel = TimeWheelView(frame: NSRect(x: 0, y: 0, width: 80, height: 160))
            wheel.values = Array(stride(from: 0, through: 55, by: 5)); wheel.selected = 30
            func key(_ code: UInt16, _ text: String = "") {
                wheel.keyDown(with: NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                                    timestamp: 0, windowNumber: 0, context: nil,
                                                    characters: text, charactersIgnoringModifiers: text,
                                                    isARepeat: false, keyCode: code)!)
            }
            key(125); precondition(wheel.selected == 35, "Down moves one five-minute step")
            key(126); precondition(wheel.selected == 30, "Up moves one step")
            key(121); precondition(wheel.selected == 55, "PageDown moves five rows")
            key(116); precondition(wheel.selected == 30, "PageUp moves five rows")
            key(20, "3"); key(23, "5"); precondition(wheel.selected == 35, "Direct typing selects minutes")
            wheel.consumeScroll(delta: -12, precise: true)
            precondition(wheel.selected == 40, "Trackpad scroll changes centered selection")
            wheel.consumeScroll(delta: 1, precise: false)
            precondition(wheel.selected == 35, "Mouse wheel scroll changes selection")
            precondition(wheel.accessibilityValue() as? String == "35", "VoiceOver exposes current value")
            print("PASS: picker duration / untimed / midnight / invalid duration / Up Down PageUp PageDown / typing / wheel / trackpad / accessibility value")
            let model = AppModel()
            let client = model.client
            let day = "2099-03-01", other = "2099-03-02"
            model.selectedDate = day
            await model.refresh()
            let original = try await client.read(day)
            var task = DayTask(id: "editor-workflow", title: "编辑工作流", start: "09:35", end: "11:05")
            let same = await model.saveEditedTask(task, original: original, targetDate: day)
            precondition(same, "Same-day editor save should persist")
            let saved = try await client.read(day)
            precondition(saved.tasks[0].start == "09:35" && saved.tasks[0].end == "11:05")
            let moved = await model.saveEditedTask(task, original: saved, targetDate: other)
            precondition(moved, "Cross-day editor should move existing task")
            precondition(model.documents[day]?.tasks.isEmpty == true)
            precondition(model.documents[other]?.tasks.first?.id == task.id)
            let movedOriginal = try await client.read(other)
            var newer = movedOriginal; newer.tasks[0].note = "其他地方的新备注"
            _ = try await client.save(newer)
            var target = try await client.read(day)
            target.tasks.append(DayTask(id: "keep-target", title: "保留目标事项"))
            let latestTarget = try await client.save(target)
            task.note = "过期编辑"
            let staleMove = await model.saveEditedTask(task, original: movedOriginal, targetDate: day)
            precondition(!staleMove, "Stale source must not overwrite new data")
            precondition(model.documents[other]?.tasks[0].note == "其他地方的新备注", "Conflict reloads source")
            precondition(model.documents[day]?.revision == latestTarget.revision, "Conflict reloads target")
            precondition(model.error != nil)
            var runDoc = try await client.read(other); runDoc.tasks[0].status = .running
            let running = try await client.save(runDoc)
            let runningMove = await model.saveEditedTask(running.tasks[0], original: running, targetDate: day)
            precondition(!runningMove && model.error?.contains("暂停") == true, "Running task requires an explicit pause")
            var pauseDoc = running; pauseDoc.tasks[0].status = .paused
            let paused = try await client.save(pauseDoc)
            let pausedMove = await model.saveEditedTask(paused.tasks[0], original: paused, targetDate: day)
            precondition(pausedMove, "Paused task can move")
            let targetNow = try await client.read(day)
            precondition(targetNow.tasks.count == 2 && targetNow.tasks.contains { $0.id == "keep-target" })
            let newTask = DayTask(id: "new-other-day", title: "直接创建到另一天")
            let newSave = await model.saveEditedTask(newTask, original: targetNow, targetDate: "2099-03-03")
            precondition(newSave && model.documents["2099-03-03"]?.tasks.first?.id == newTask.id,
                         "A new task with a changed date must be created directly at its target")
            let conflictTask = DayTask(id: "target-conflict", title: "目标冲突检查")
            var conflictSource = try await client.read("2099-03-04"); conflictSource.tasks = [conflictTask]
            conflictSource = try await client.save(conflictSource)
            var conflictTarget = try await client.read("2099-03-05")
            conflictTarget.tasks = [DayTask(id: "target-kept", title: "目标原有事项")]
            conflictTarget = try await client.save(conflictTarget)
            let rejected = await model.saveEditedTask(conflictTask, original: conflictSource, targetDate: conflictTarget.date)
            precondition(!rejected, "Target revision conflict rejects move")
            precondition(model.documents[conflictSource.date]?.revision == conflictSource.revision,
                         "Target conflict does not alter source revision")
            precondition(model.documents[conflictTarget.date]?.tasks[0].note == "changed after target read",
                         "Target conflict reloads fresh destination")
            precondition(model.editorConflictDates == [conflictSource.date, conflictTarget.date],
                         "Unchanged source revision still requires explicit reload acknowledgment")
            let freshSource = try await client.read(conflictSource.date)
            model.editorConflictDates = [] // Mirrors the editor's explicit reload acknowledgment.
            let retry = await model.saveEditedTask(conflictTask, original: freshSource, targetDate: conflictTarget.date)
            precondition(retry && model.documents[conflictTarget.date]?.tasks.count == 2)
            print("PASS: AppModel editor same-day / move / source and target conflicts reload both / running pause guard / new task date")
        }
    }
    """#
}
