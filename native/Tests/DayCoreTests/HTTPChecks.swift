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
        print("PASS: HTTP save / timer persistence / conflict / calendar / offline / service restart")
    }
}
