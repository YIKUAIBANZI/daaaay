import AppKit
import SwiftUI

final class FocusPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class WindowController: NSObject, NSWindowDelegate {
    let model: AppModel
    private(set) var mainWindow: NSWindow!
    private(set) var panel: FocusPanel!
    init(model: AppModel) {
        self.model=model
        super.init()
        mainWindow=NSWindow(contentRect:NSRect(x:0,y:0,width:1140,height:770),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
        mainWindow.title="daaaay · 每日安排"; mainWindow.minSize=NSSize(width:1020,height:680)
        mainWindow.isReleasedWhenClosed=false; mainWindow.contentView=NSHostingView(rootView:MainView(model:model))
        mainWindow.center(); mainWindow.setFrameAutosaveName("DaaaayMainWindow"); mainWindow.delegate=self
        panel=FocusPanel(contentRect:NSRect(x:0,y:0,width:340,height:340),styleMask:[.borderless,.nonactivatingPanel,.fullSizeContentView],backing:.buffered,defer:false)
        panel.title="daaaay · 悬浮计时"; panel.level = .floating; panel.isFloatingPanel=true
        panel.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary]
        panel.hidesOnDeactivate=false; panel.isMovableByWindowBackground=true
        panel.isOpaque=false; panel.backgroundColor = .clear; panel.hasShadow=true; panel.isReleasedWhenClosed=false
        panel.contentView=NSHostingView(rootView:FocusView(model:model,floating:true)
            .frame(width:340,height:340,alignment:.topLeading)
            .background(.regularMaterial,in:RoundedRectangle(cornerRadius:20))
            .overlay(RoundedRectangle(cornerRadius:20).strokeBorder(.white.opacity(0.16))))
        if let screen=NSScreen.main { let frame=screen.visibleFrame; panel.setFrameOrigin(NSPoint(x:frame.maxX-364,y:frame.maxY-370)) }
        if let saved=UserDefaults.standard.string(forKey:"focusFrame") {
            let rect=NSRectFromString(saved)
            if NSScreen.screens.contains(where:{$0.visibleFrame.intersects(rect)}) { panel.setFrameOrigin(rect.origin) }
        }
        panel.delegate=self
    }
    func showMain() {
        NSApp.activate(ignoringOtherApps:true); mainWindow.makeKeyAndOrderFront(nil)
        if mainWindow.isMiniaturized { mainWindow.deminiaturize(nil) }
    }
    func togglePanel() {
        if panel.isVisible { panel.orderOut(nil) } else { panel.orderFrontRegardless() }
        model.floatingVisible=panel.isVisible; UserDefaults.standard.set(panel.isVisible,forKey:"floatingVisible")
    }
    func setPinned(_ value: Bool) { panel.level = value ? .floating : .normal }
    func windowDidMove(_ notification: Notification) {
        if let window=notification.object as? NSWindow,window === panel { UserDefaults.standard.set(NSStringFromRect(panel.frame),forKey:"focusFrame") }
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { sender.orderOut(nil); return false }
}
