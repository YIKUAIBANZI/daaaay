import Foundation

public enum TaskStatus: String, Codable, CaseIterable {
    case planned, running, done, paused, cancelled
    public var label: String {
        switch self {
        case .planned: return "待开始"
        case .running: return "进行中"
        case .done: return "已完成"
        case .paused: return "已暂停"
        case .cancelled: return "已取消"
        }
    }
}

public struct DayTask: Codable, Identifiable, Equatable {
    public var id: String
    public var title: String
    public var category: String
    public var color: String
    public var start: String
    public var end: String
    public var nextDay: Bool
    public var status: TaskStatus
    public var note: String
    public var block: Bool
    public var startedAt: String?
    public var elapsedSeconds: Double?

    public init(id: String = UUID().uuidString, title: String = "", category: String = "学习", color: String = "#7562b6", start: String = "", end: String = "", nextDay: Bool = false, status: TaskStatus = .planned, note: String = "", block: Bool = false) {
        self.id=id; self.title=title; self.category=category; self.color=color
        self.start=start; self.end=end; self.nextDay=nextDay; self.status=status
        self.note=note; self.block=block; self.startedAt=nil; self.elapsedSeconds=0
    }

    public func elapsed(at now: Date) -> Double {
        let settled = max(0, elapsedSeconds ?? 0)
        guard status == .running, let startedAt, let began = DayClock.parseISO(startedAt) else { return settled }
        return settled + max(0, now.timeIntervalSince(began))
    }
    public func begins(on day: String) -> Date? { DayClock.parseISO("\(day)T\(start):00+08:00") }
    public func deadline(on day: String) -> Date? {
        guard !end.isEmpty else { return nil }
        return DayClock.parseISO("\(nextDay ? DayClock.shift(day, by: 1) : day)T\(end):00+08:00")
    }
    public var timeLabel: String { start.isEmpty ? "无固定时间" : "\(start) – \(end)\(nextDay ? " 次日" : "")" }
}

public struct DayDocument: Codable, Equatable {
    public var date: String
    public var revision: Int
    public var tasks: [DayTask]
    public var updatedAt: String?
    public var monitorSyncPending: Bool?
    public init(date: String, revision: Int = 0, tasks: [DayTask] = []) {
        self.date=date; self.revision=revision; self.tasks=tasks
    }
}

public enum DayClock {
    public static let zone = TimeZone(identifier: "Asia/Shanghai")!
    public static var calendar: Calendar { var c=Calendar(identifier: .gregorian); c.timeZone=zone; return c }
    public static func parseISO(_ text: String) -> Date? {
        let f=ISO8601DateFormatter(); f.formatOptions=[.withInternetDateTime,.withFractionalSeconds]
        if let d=f.date(from: text) { return d }
        f.formatOptions=[.withInternetDateTime]; return f.date(from: text)
    }
    public static func isoString(_ date: Date) -> String {
        let f=ISO8601DateFormatter(); f.formatOptions=[.withInternetDateTime,.withFractionalSeconds]; return f.string(from:date)
    }
    public static func dayString(_ date: Date) -> String {
        let f=DateFormatter(); f.locale=Locale(identifier:"en_US_POSIX"); f.timeZone=zone; f.dateFormat="yyyy-MM-dd"; return f.string(from:date)
    }
    public static func shift(_ day: String, by offset: Int) -> String {
        guard let d=parseISO(day+"T12:00:00+08:00"), let next=calendar.date(byAdding: .day, value:offset, to:d) else { return day }
        return dayString(next)
    }
    public static func heading(_ day: String) -> String {
        guard let d=parseISO(day+"T12:00:00+08:00") else { return day }
        let f=DateFormatter(); f.locale=Locale(identifier:"zh_CN"); f.timeZone=zone; f.dateFormat="M 月 d 日，EEEE"; return f.string(from:d)
    }
    public static func duration(_ seconds: Double) -> String {
        let value=Int(max(0,seconds).rounded(.down))
        if value>=3600 { return String(format:"%02d:%02d:%02d",value/3600,(value%3600)/60,value%60) }
        return String(format:"%02d:%02d",value/60,value%60)
    }
}

public struct FocusItem: Equatable {
    public let day: String
    public let task: DayTask
    public static func choose(today: DayDocument?, yesterday: DayDocument?, otherDays: [DayDocument] = [], now: Date) -> FocusItem? {
        for doc in [today,yesterday].compactMap({$0}) + otherDays.sorted(by:{$0.date>$1.date}) {
            if let t=doc.tasks.first(where:{$0.status == .running}) { return FocusItem(day:doc.date,task:t) }
        }
        guard let today else { return nil }
        // Keep a started, paused item available for a one-click resume.
        for doc in [today,yesterday].compactMap({$0}) {
            if let t=doc.tasks.first(where:{$0.status == .paused && ($0.elapsedSeconds ?? 0)>0}) {
                return FocusItem(day:doc.date,task:t)
            }
        }
        let planned=today.tasks.filter { $0.status == .planned && ($0.deadline(on:today.date) ?? .distantFuture)>now }
            .sorted { ($0.start.isEmpty ? "99:99" : $0.start)<($1.start.isEmpty ? "99:99" : $1.start) }
        guard let t=planned.first else { return nil }
        return FocusItem(day:today.date,task:t)
    }
}
