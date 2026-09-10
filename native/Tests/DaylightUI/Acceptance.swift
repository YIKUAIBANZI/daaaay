import AppKit
import SwiftUI
import DayCore

/// Synthetic UI harness. No model timer/refresh is started and no production service is used.
/// Compile alongside the production views, excluding App.swift and HotKeys.swift.
@main @MainActor
final class Acceptance: NSObject, NSApplicationDelegate {
    var windows: WindowController!
    let model = AppModel()
    static func main() {
        precondition(ProcessInfo.processInfo.environment["DAAAAY_SERVICE_URL"] == "http://127.0.0.1:18769")
        let app = NSApplication.shared
        let delegate = Acceptance()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        model.now = DayClock.parseISO("2099-03-01T09:40:00+08:00")!
        model.selectedDate = model.today
        windows = WindowController(model: model)
        model.showMain = { self.windows.showMain() }
        model.toggleFloating = { self.windows.togglePanel() }
        model.setPinned = { self.windows.setPinned($0) }
        precondition(windows.panel.styleMask.contains(.nonactivatingPanel))
        precondition(windows.panel.canBecomeKey && !windows.panel.canBecomeMain)
        precondition(windows.panel.collectionBehavior.contains(.canJoinAllSpaces))
        precondition(windows.panel.collectionBehavior.contains(.fullScreenAuxiliary))
        precondition(windows.panel.isMovableByWindowBackground)
        precondition(windows.panel.frame.size == NSSize(width: 340, height: 340))
        windows.setPinned(false); precondition(windows.panel.level == .normal)
        windows.setPinned(true); precondition(windows.panel.level == .floating)
        windows.showMain()
        if CommandLine.arguments.contains("--capture") {
            Task { await captureMatrix() }
        } else {
            configure("running")
            windows.mainWindow.setFrame(NSRect(x: 50, y: 50, width: 1020, height: 680), display: true)
            windows.togglePanel()
        }
    }
    func configure(_ state: String) {
        var task = DayTask(id: "ui-fixture", title: "完成今天的第一小步", category: "学习", color: "#00BFC9",
                           start: "09:35", end: "11:05", status: state == "done" ? .done : state == "planned" ? .planned : .running,
                           note: "打开笔记，写下要验证的问题。")
        task.elapsedSeconds = 300
        if task.status == .running { task.startedAt = "2099-03-01T09:35:00+08:00" }
        var doc = DayDocument(date: model.today, revision: 1, tasks: state == "empty" ? [] : [task])
        doc.monitorSyncPending = state == "monitorSyncPending"
        model.documents = [model.today: doc]
        model.online = state != "offline"
    }
    func captureMatrix() async {
        let output = URL(fileURLWithPath: CommandLine.arguments.last!, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            let states = ["empty", "planned", "running", "done", "offline", "monitorSyncPending"]
            // Capture each window in its own pass. Reflowing the main window and snapshotting
            // the shared model's panel in the same pass can leave an intermediate SwiftUI
            // display transaction in the cached image even though the live panel is correct.
            for state in states {
                configure(state)
                for size in [NSSize(width: 1020, height: 680), NSSize(width: 1440, height: 900)] {
                    windows.mainWindow.setFrame(NSRect(origin: NSPoint(x: 20, y: 20), size: size), display: true)
                    try await Task.sleep(nanoseconds: 150_000_000)
                    try snapshot(windows.mainWindow.contentView!, to: output.appendingPathComponent("\(state)-\(Int(size.width))x\(Int(size.height)).png"))
                }
            }
            if !windows.panel.isVisible { windows.togglePanel() }
            try await Task.sleep(nanoseconds: 300_000_000)
            for state in states {
                configure(state)
                windows.panel.contentView = WindowController.makeFocusContent(model: model)
                try await Task.sleep(nanoseconds: 300_000_000)
                try snapshot(windows.panel.contentView!, to: output.appendingPathComponent("focus-\(state)-340x340.png"))
            }
            print("PASS: 12 main-window and 6 focus-panel synthetic captures; panel geometry/style/levels validated")
        } catch { print("FAIL: \(error)"); exit(1) }
        NSApp.terminate(nil)
    }
    func snapshot(_ view: NSView, to url: URL) throws {
        view.layoutSubtreeIfNeeded()
        markNeedsDisplay(view)
        view.displayIfNeeded()
        let image = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: image)
        try image.representation(using: .png, properties: [:])!.write(to: url)
    }
    func markNeedsDisplay(_ view: NSView) {
        view.needsDisplay = true
        for child in view.subviews { markNeedsDisplay(child) }
    }
}
