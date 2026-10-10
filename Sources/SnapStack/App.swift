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
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private let state = CaptureState()
    private var floatingBar: FloatingBarController?
    private var hotKeys: [CaptureHotKey] = []
    private var statusItem: NSStatusItem?
    private var permissionGuide: PermissionGuideController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        let bar = FloatingBarController(state: state)
        floatingBar = bar
        let guide = PermissionGuideController { [weak bar] in bar?.present() }
        permissionGuide = guide
        state.onPermissionRequired = { [weak guide] permission in guide?.show(for: permission) }
        state.onShowPermissions = { [weak guide] in guide?.show() }
        state.onCaptureWillStart = { [weak bar, weak guide] in
            guide?.hide()
            bar?.beginCapture()
        }
        state.onCaptureFinished = { [weak bar] result in bar?.finishCapture(result) }
        // Keep the compact toolbar stable when the queue becomes empty.
        installMenuBar()
        var failedShortcuts: [String] = []
        for action in CaptureHotKey.Action.allCases {
            let hotKey = CaptureHotKey(action: action) { [weak self] in
                switch action {
                case .capture: self?.state.capture()
                case .pasteAll: self?.state.pasteAll()
                }
            }
            do {
                try hotKey.register()
                hotKeys.append(hotKey)
            } catch {
                failedShortcuts.append(action.label)
            }
        }
        if !failedShortcuts.isEmpty {
            state.message = "\(failedShortcuts.joined(separator: "、")) 未能注册，可能已被占用，请使用对应按钮。"
            bar.show()
        }
        bar.present()
        if PermissionLaunchPolicy.shouldPresent(
            screenGranted: CGPreflightScreenCaptureAccess(),
            hasPresented: UserDefaults.standard.bool(forKey: "permissionGuidePresented"),
            hasCompleted: UserDefaults.standard.bool(forKey: "permissionGuideCompleted")) {
            guide.show()
        }
        FileHandle.standardOutput.write(Data("SnapStack: floating bar ready.\n".utf8))
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeys.forEach { $0.unregister() }
        permissionGuide?.hide()
        state.cleanup()
    }

    private func installMenuBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "连截"
        item.button?.toolTip = "SnapStack / 连截"
        item.button?.setAccessibilityLabel("SnapStack 连截")
        item.isVisible = true
        let menu = NSMenu()
        let capture = NSMenuItem(title: "区域截图（⌃⇧A）", action: #selector(captureArea), keyEquivalent: "")
        capture.target = self
        menu.addItem(capture)
        let paste = NSMenuItem(title: "粘贴全部截图（⌃⇧S）", action: #selector(pasteAll), keyEquivalent: "")
        paste.target = self
        menu.addItem(paste)
        let show = NSMenuItem(title: "展开截图栏", action: #selector(toggleBar), keyEquivalent: "")
        show.target = self
        menu.addItem(show)
        let permissions = NSMenuItem(title: "权限与使用引导", action: #selector(showPermissions), keyEquivalent: "")
        permissions.target = self
        menu.addItem(permissions)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出 SnapStack", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApplication.shared
        menu.addItem(quit)
        item.menu = menu
        statusItem = item
    }

    @objc private func captureArea() { state.capture() }
    @objc private func pasteAll() { state.pasteAll() }
    @objc private func toggleBar() { floatingBar?.toggle() }
    @objc private func showPermissions() { permissionGuide?.show() }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleBar) {
            menuItem.title = floatingBar?.isExpanded == true ? "收起截图栏" : "展开截图栏"
            return !state.isCapturing
        }
        if menuItem.action == #selector(captureArea) { return !state.isBusy }
        if menuItem.action == #selector(pasteAll) { return !state.isBusy && !state.items.isEmpty }
        return true
    }
}
