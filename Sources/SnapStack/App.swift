import AppKit
import SwiftUI

@main
enum SnapStackApp {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let state = CaptureState()
    private var floatingBar: FloatingBarController?
    private var hotKey: CaptureHotKey?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        let bar = FloatingBarController(state: state)
        floatingBar = bar
        state.onCaptureWillStart = { [weak bar] in bar?.hide() }
        state.onCaptureFinished = { [weak bar] in bar?.show() }
        installMenuBar()
        let hotKey = CaptureHotKey { [weak self] in self?.state.capture() }
        self.hotKey = hotKey
        do { try hotKey.register() }
        catch { state.message = "快捷键注册失败，请使用截图按钮。" }
        bar.show()
        FileHandle.standardOutput.write(Data("SnapStack: floating bar ready.\n".utf8))
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKey?.unregister()
        state.cleanup()
    }

    private func installMenuBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "连截"
        item.button?.toolTip = "SnapStack / 连截"
        item.button?.setAccessibilityLabel("SnapStack 连截")
        item.isVisible = true
        let menu = NSMenu()
        let capture = NSMenuItem(title: "区域截图（⌃⇧S）", action: #selector(captureArea), keyEquivalent: "")
        capture.target = self
        menu.addItem(capture)
        let show = NSMenuItem(title: "显示截图栏", action: #selector(showBar), keyEquivalent: "")
        show.target = self
        menu.addItem(show)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出 SnapStack", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApplication.shared
        menu.addItem(quit)
        item.menu = menu
        statusItem = item
    }

    @objc private func captureArea() { state.capture() }
    @objc private func showBar() { floatingBar?.show() }
}
