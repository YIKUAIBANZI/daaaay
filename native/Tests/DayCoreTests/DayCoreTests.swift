import Foundation
import DayCore

@main
struct DayCoreTests {
    let legacy = ##"{"date":"2026-09-07","revision":9,"tasks":[{"id":"study","title":"Agent","category":"学习","color":"#7562b6","start":"23:30","end":"00:30","nextDay":true,"status":"running","note":"两分钟","block":true,"startedAt":"2026-09-07T23:50:00+08:00"}]}"##

    static func main() async throws {
        let suite = DayCoreTests()
        try suite.testLegacyTimerAndMidnightDeadline()
        try suite.testPausedTimerStaysConstantAndResumedTimerAddsIntervals()
        try suite.testFocusKeepsYesterdayRunningTaskWhenBrowsingAnotherDay()
        try suite.testFocusExcludesDoneCancelledAndExpiredPlans()
        try suite.testPausedFocusCanResume()
        print("PASS: 5 DayCore behavior checks")
        if CommandLine.arguments.contains("--http") { try await HTTPChecks.run() }
    }

    func testLegacyTimerAndMidnightDeadline() throws {
        let day = try JSONDecoder().decode(DayDocument.self, from: Data(legacy.utf8))
        let task = try XCTUnwrap(day.tasks.first)
        let now = try XCTUnwrap(DayClock.parseISO("2026-09-08T00:10:00+08:00"))
        XCTAssertEqual(task.elapsed(at: now), 1200)
        XCTAssertEqual(task.deadline(on: day.date)?.timeIntervalSince(now), 1200)
        XCTAssertEqual(DayClock.dayString(now), "2026-09-08")
        XCTAssertEqual(DayClock.shift("2026-12-31", by: 1), "2027-01-01")
    }

    func testPausedTimerStaysConstantAndResumedTimerAddsIntervals() throws {
        var task = try JSONDecoder().decode(DayDocument.self, from: Data(legacy.utf8)).tasks[0]
        task.elapsedSeconds = 90
        task.status = .paused
        task.startedAt = nil
        let now = try XCTUnwrap(DayClock.parseISO("2026-09-08T00:10:00.123Z"))
        XCTAssertEqual(task.elapsed(at: now), 90)
        XCTAssertEqual(task.elapsed(at: now.addingTimeInterval(180)), 90)
        task.status = .running
        task.startedAt = DayClock.isoString(now.addingTimeInterval(-30))
        XCTAssertEqual(task.elapsed(at: now), 120, accuracy: 0.01)
        XCTAssertEqual(DayClock.duration(3661), "01:01:01")
    }

    func testFocusKeepsYesterdayRunningTaskWhenBrowsingAnotherDay() throws {
        let yesterday = try JSONDecoder().decode(DayDocument.self, from: Data(legacy.utf8))
        var task = yesterday.tasks[0]
        task.id = "next"; task.status = .planned; task.start = "09:00"; task.end = "10:00"; task.nextDay = false
        let today = DayDocument(date: "2026-09-08", tasks: [task])
        let now = try XCTUnwrap(DayClock.parseISO("2026-09-08T00:10:00+08:00"))
        let focus = FocusItem.choose(today: today, yesterday: yesterday, now: now)
        XCTAssertEqual(focus?.task.id, "study")
        XCTAssertEqual(focus?.day, "2026-09-07")
    }

    func testFocusExcludesDoneCancelledAndExpiredPlans() throws {
        var task = try JSONDecoder().decode(DayDocument.self, from: Data(legacy.utf8)).tasks[0]
        task.status = .done
        let now = try XCTUnwrap(DayClock.parseISO("2026-09-08T12:00:00+08:00"))
        XCTAssertNil(FocusItem.choose(today: DayDocument(date: "2026-09-08", tasks: [task]), yesterday: nil, now: now))
        task.status = .planned; task.start = "09:00"; task.end = "10:00"; task.nextDay = false
        XCTAssertNil(FocusItem.choose(today: DayDocument(date: "2026-09-08", tasks: [task]), yesterday: nil, now: now))
        task.start = ""; task.end = ""
        XCTAssertEqual(FocusItem.choose(today: DayDocument(date: "2026-09-08", tasks: [task]), yesterday: nil, now: now)?.task.id, "study")
    }

    func testPausedFocusCanResume() throws {
        var task = try JSONDecoder().decode(DayDocument.self, from: Data(legacy.utf8)).tasks[0]
        task.status = .paused; task.elapsedSeconds = 10; task.startedAt = nil
        let now = try XCTUnwrap(DayClock.parseISO("2026-09-07T23:55:00+08:00"))
        let focus = FocusItem.choose(today: DayDocument(date: "2026-09-07", tasks: [task]), yesterday: nil, now: now)
        XCTAssertEqual(focus?.task.status, .paused)
        XCTAssertEqual(focus?.task.elapsed(at: now), 10)
    }
}

func XCTUnwrap<T>(_ value: T?) throws -> T {
    guard let value else { throw NSError(domain: "DayCoreChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected non-nil value"]) }; return value
}
func XCTAssertEqual<T: Equatable>(_ a: T, _ b: T, file: StaticString = #file, line: UInt = #line) { precondition(a == b, "Expected \(b), got \(a)", file: file, line: line) }
func XCTAssertEqual(_ a: Double, _ b: Double, accuracy: Double, file: StaticString = #file, line: UInt = #line) { precondition(abs(a - b) <= accuracy, "Expected \(b), got \(a)", file: file, line: line) }
func XCTAssertNil<T>(_ value: T?, file: StaticString = #file, line: UInt = #line) { precondition(value == nil, "Expected nil", file: file, line: line) }
