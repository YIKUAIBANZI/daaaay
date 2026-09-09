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
        try suite.testScheduleEditingSnapsAndCrossesMidnight()
        try suite.testScheduleEditingNormalizesUntimedAndTimedDrafts()
        try suite.testScheduleEditingRejectsInvalidClockValues()
        DaylightThemeChecks.run()
        print("PASS: 9 DayCore checks")
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

    func testScheduleEditingSnapsAndCrossesMidnight() throws {
        let start = try XCTUnwrap(DayClock.parseISO("2026-09-09T23:40:00+08:00"))
        let draft = try ScheduleEditing.applying(durationMinutes: 90, to: start)
        XCTAssertEqual(draft.date, "2026-09-09")
        XCTAssertEqual(draft.start, "23:40")
        XCTAssertEqual(draft.end, "01:10")
        XCTAssertEqual(draft.nextDay, true)
        XCTAssertEqual(draft.isUntimed, false)
        XCTAssertEqual(ScheduleEditing.snapMinute(58), 0)
        XCTAssertEqual(ScheduleEditing.snapMinute(3), 5)

        let fullDay = try ScheduleEditing.applying(durationMinutes: 1440, to: start)
        XCTAssertEqual(fullDay.end, "23:40")
        XCTAssertEqual(fullDay.nextDay, true)
    }

    func testScheduleEditingNormalizesUntimedAndTimedDrafts() throws {
        let timed = try ScheduleEditing.normalized(date: "2026-09-09", startHour: 23, startMinute: 40,
                                                   endHour: 1, endMinute: 10, isUntimed: false)
        XCTAssertEqual(timed, ScheduleDraft(date: "2026-09-09", start: "23:40", end: "01:10", nextDay: true, isUntimed: false))

        let untimed = try ScheduleEditing.normalized(date: "2026-09-09", startHour: 23, startMinute: 58,
                                                     endHour: 1, endMinute: 3, isUntimed: true)
        XCTAssertEqual(untimed, ScheduleDraft(date: "2026-09-09", start: "", end: "", nextDay: false, isUntimed: true))

        let roundedIntoNextDate = try ScheduleEditing.normalized(date: "2026-09-09", startHour: 23, startMinute: 58,
                                                                 endHour: 0, endMinute: 0, isUntimed: false)
        XCTAssertEqual(roundedIntoNextDate, ScheduleDraft(date: "2026-09-10", start: "00:00", end: "00:00", nextDay: false, isUntimed: false))
        XCTAssertEqual(ScheduleEditing.saveRoute(sourceDate: "2026-09-09", targetDate: "2026-09-09"), .sameDay)
        XCTAssertEqual(ScheduleEditing.saveRoute(sourceDate: "2026-09-09", targetDate: "2026-09-10"), .move)
    }

    func testScheduleEditingRejectsInvalidClockValues() throws {
        do {
            _ = try ScheduleEditing.normalized(date: "2026-09-09", startHour: 24, startMinute: 0,
                                               endHour: 1, endMinute: 0, isUntimed: false)
            preconditionFailure("An hour outside 0...23 must be rejected")
        } catch {
            // Expected: normalized input is a throwing boundary for invalid picker values.
        }

        do {
            _ = try ScheduleEditing.normalized(date: "not-a-date", startHour: 9, startMinute: 0,
                                               endHour: 10, endMinute: 0, isUntimed: false)
            preconditionFailure("An invalid date must be rejected")
        } catch {
            // Expected.
        }

        let start = try XCTUnwrap(DayClock.parseISO("2026-09-09T23:40:00+08:00"))
        do {
            _ = try ScheduleEditing.applying(durationMinutes: 1441, to: start)
            preconditionFailure("A duration above 24 hours must be rejected")
        } catch let error as ScheduleEditingError {
            XCTAssertEqual(error, .invalidDuration)
        } catch {
            preconditionFailure("Unexpected duration validation error: \(error)")
        }
    }
}

func XCTUnwrap<T>(_ value: T?) throws -> T {
    guard let value else { throw NSError(domain: "DayCoreChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected non-nil value"]) }; return value
}
func XCTAssertEqual<T: Equatable>(_ a: T, _ b: T, file: StaticString = #file, line: UInt = #line) { precondition(a == b, "Expected \(b), got \(a)", file: file, line: line) }
func XCTAssertEqual(_ a: Double, _ b: Double, accuracy: Double, file: StaticString = #file, line: UInt = #line) { precondition(abs(a - b) <= accuracy, "Expected \(b), got \(a)", file: file, line: line) }
func XCTAssertNil<T>(_ value: T?, file: StaticString = #file, line: UInt = #line) { precondition(value == nil, "Expected nil", file: file, line: line) }
