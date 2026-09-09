import AppKit
import SwiftUI

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel!
    private var windows: WindowController!
    private var hotKeys: HotKeys!
    private var statusItem: NSStatusItem!
    static func main() {
        let app=NSApplication.shared; let delegate=AppDelegate()
        app.delegate=delegate; app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .aqua)
        model=AppModel(); windows=WindowController(model:model)
        model.showMain={ [weak self] in self?.windows.showMain() }
        model.toggleFloating={ [weak self] in self?.windows.togglePanel() }
        model.setPinned={ [weak self] pinned in self?.windows.setPinned(pinned) }
        installMenus()
        hotKeys=HotKeys(); hotKeys.onPress={ [weak self] id in
            if id == 1 { self?.windows.togglePanel() } else { self?.windows.showMain() }
        }
        model.shortcutError=hotKeys.register(); model.start(); windows.showMain()
        if UserDefaults.standard.object(forKey:"floatingVisible") == nil || UserDefaults.standard.bool(forKey:"floatingVisible") { windows.togglePanel() }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication,hasVisibleWindows flag: Bool) -> Bool { windows.showMain(); return true }
    func applicationWillTerminate(_ notification: Notification) { hotKeys.unregister() }
    private func item(_ title: String,_ action: Selector,_ key: String = "") -> NSMenuItem {
        let i=NSMenuItem(title:title,action:action,keyEquivalent:key); i.target=self; return i
    }
    private func installMenus() {
        let root=NSMenu(); let app=NSMenu(title:"daaaay")
        app.addItem(item("关于 daaaay",#selector(about))); app.addItem(.separator())
        app.addItem(item("隐藏 daaaay",#selector(hideApp),"h")); app.addItem(item("退出 daaaay",#selector(quit),"q"))
        let appItem=NSMenuItem(); appItem.submenu=app; root.addItem(appItem)
        let edit=NSMenu(title:"编辑")
        for (title,selector,key) in [("撤销",Selector(("undo:")),"z"),("剪切",#selector(NSText.cut(_:)),"x"),("复制",#selector(NSText.copy(_:)),"c"),("粘贴",#selector(NSText.paste(_:)),"v"),("全选",#selector(NSText.selectAll(_:)),"a")] {
            edit.addItem(NSMenuItem(title:title,action:selector,keyEquivalent:key))
        }
        let editItem=NSMenuItem(); editItem.submenu=edit; root.addItem(editItem)
        let windowMenu=NSMenu(title:"窗口")
        windowMenu.addItem(item("打开日程",#selector(openMain),"1"))
        windowMenu.addItem(item("显示 / 隐藏悬浮窗",#selector(togglePanel),"2"))
        windowMenu.addItem(NSMenuItem(title:"关闭窗口",action:#selector(NSWindow.performClose(_:)),keyEquivalent:"w"))
        windowMenu.addItem(NSMenuItem(title:"最小化",action:#selector(NSWindow.performMiniaturize(_:)),keyEquivalent:"m"))
        let wi=NSMenuItem(); wi.submenu=windowMenu; root.addItem(wi); NSApp.mainMenu=root
        statusItem=NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength)
        statusItem.button?.image=NSImage(systemSymbolName:"sun.max",accessibilityDescription:"daaaay")
        statusItem.button?.toolTip="daaaay · 每日安排"
        let menu=NSMenu()
        menu.addItem(item("打开日程     ⌃⌥D",#selector(openMain)))
        menu.addItem(item("显示 / 隐藏悬浮窗     ⌃⌥Space",#selector(togglePanel)))
        menu.addItem(item("刷新日程",#selector(refresh))); menu.addItem(.separator())
        menu.addItem(item("退出 daaaay",#selector(quit))); statusItem.menu=menu
    }
    @objc private func openMain() { windows.showMain() }
    @objc private func togglePanel() { windows.togglePanel() }
    @objc private func refresh() { Task { await model.refresh() } }
    @objc private func hideApp() { NSApp.hide(nil) }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func about() {
        NSApp.orderFrontStandardAboutPanel(options:[.applicationName:"daaaay",.applicationVersion:"1.0",.credits:NSAttributedString(string:"一件一件，慢慢来。\n原生日程 · 悬浮计时 · 本机保存")])
    }
}
