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
            p.arguments=["python3",service,"--root",root.path,"--port","18767","--no-calendar-open"]
            try p.run(); return p
        }
        var process=try launch()
        defer { if process.isRunning { process.terminate(); process.waitUntilExit() }; try? FileManager.default.removeItem(at:root) }
        let client=DayClient(baseURL:base)
        var connected=false
        for _ in 0..<30 {
            if (try? await client.bootstrap()) != nil { connected=true; break }
            try await Task.sleep(nanoseconds:100_000_000)
        }
        precondition(connected,"Isolated HTTP service must be ready")
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
}
