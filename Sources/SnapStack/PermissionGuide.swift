import AppKit
@preconcurrency import ApplicationServices
import SwiftUI

enum RecordingPermission: String, CaseIterable, Identifiable {
    case screen, accessibility
    var id: String { rawValue }
    var title: String { self == .screen ? "屏幕录制" : "辅助功能" }
    var detail: String { self == .screen ? "截取你选中的屏幕区域" : "把截图逐张粘贴到目标应用，可稍后开启" }
    var symbol: String { self == .screen ? "rectangle.dashed" : "cursorarrow.click" }
    var pane: String { self == .screen ? "Privacy_ScreenCapture" : "Privacy_Accessibility" }
    var listName: String { self == .screen ? "屏幕录制" : "辅助功能" }
}

@MainActor
final class PermissionStatus: ObservableObject {
    @Published private(set) var screen = false
    @Published private(set) var accessibility = false
    @Published var selected: RecordingPermission?
    @Published var notice = ""

    func refresh() {
        screen = CGPreflightScreenCaptureAccess()
        accessibility = AXIsProcessTrusted()
        if screen {
            UserDefaults.standard.set(true, forKey: "permissionGuideCompleted")
        }
    }
    func granted(_ permission: RecordingPermission) -> Bool {
        permission == .screen ? screen : accessibility
    }
}

@MainActor
final class PermissionGuideController: NSObject, NSWindowDelegate {
    private let status = PermissionStatus()
    private var window: NSWindow?
    private var helper: NSPanel?
    private var poll: Task<Void, Never>?
    private var activePermission: RecordingPermission?
    private var awaitingSettings = false
    private var dropped = false
    private let onContinue: () -> Void

    init(onContinue: @escaping () -> Void) {
        self.onContinue = onContinue
        super.init()
    }

    func show(for permission: RecordingPermission? = nil) {
        UserDefaults.standard.set(true, forKey: "permissionGuidePresented")
        status.selected = permission
        status.refresh()
        helper?.orderOut(nil)
        awaitingSettings = false
        if window == nil {
            let view = PermissionGuideView(status: status,
                openSettings: { [weak self] in self?.openSettings($0) },
                refresh: { [weak self] in self?.checkManually() },
                revealApp: { NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL]) },
                restart: { [weak self] in self?.restart() },
                finish: { [weak self] in self?.finish() })
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 450),
                                  styleMask: [.titled, .closable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            window.title = "准备好使用连截"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.backgroundColor = NSColor(InterfaceStyle.background)
            window.appearance = NSAppearance(named: .aqua)
            window.contentView = NSHostingView(rootView: view)
            window.delegate = self
            window.center()
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        startPolling()
    }

    func hide() {
        poll?.cancel()
        poll = nil
        helper?.orderOut(nil)
        window?.orderOut(nil)
        awaitingSettings = false
    }

    func windowWillClose(_ notification: Notification) {
        hide()
        onContinue()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        status.refresh()
        awaitingSettings = false
        helper?.orderOut(nil)
    }

    private func finish() {
        status.refresh()
        guard status.screen else { return }
        UserDefaults.standard.set(true, forKey: "permissionGuideCompleted")
        hide()
        onContinue()
    }

    private func checkManually() {
        status.refresh()
        status.notice = status.screen && status.accessibility
            ? "两项权限已就绪，可以开始使用。"
            : "系统尚未认可当前版本。若开关已打开，请移除列表里的旧连截，添加当前应用并重新打开。"
    }

    private func openSettings(_ permission: RecordingPermission) {
        status.selected = permission
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(permission.pane)") else { return }
        activePermission = permission
        dropped = false
        awaitingSettings = true
        status.notice = "完成设置后回到这里，授权状态会自动更新。"
        makeHelper(for: permission)
        window?.orderBack(nil)
        NSWorkspace.shared.open(url)
    }

    private func startPolling() {
        poll?.cancel()
        poll = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.status.refresh()
                self.updateHelper()
                do { try await Task.sleep(for: .milliseconds(500)) }
                catch { return }
            }
        }
    }

    private func makeHelper(for permission: RecordingPermission) {
        helper?.orderOut(nil)
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 470, height: 82),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "连截授权提示"
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.appearance = NSAppearance(named: .aqua)
        panel.contentView = NSHostingView(rootView: PermissionHelperView(permission: permission,
            onDrop: { [weak self] in
                self?.dropped = true
                self?.helper?.orderOut(nil)
                self?.window?.orderBack(nil)
            }, onReturn: { [weak self] in self?.show(for: permission) }))
        helper = panel
    }

    private func updateHelper() {
        guard awaitingSettings, !dropped, let permission = activePermission,
              !status.granted(permission),
              let settings = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences").first,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == settings.processIdentifier,
              let panel = helper else {
            helper?.orderOut(nil)
            return
        }
        // Window bounds remain available without screen-capture access; window titles are not needed.
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let bounds = windows.first {
            ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == settings.processIdentifier
                && ($0[kCGWindowLayer as String] as? NSNumber)?.intValue == 0
                && (($0[kCGWindowBounds as String] as? [String: Any])?["Width"] as? CGFloat ?? 0) > 300
        }?[kCGWindowBounds as String] as? [String: Any]
        guard let bounds, let cg = CGRect(dictionaryRepresentation: bounds as CFDictionary),
              let mainDisplay = NSScreen.screens.first else { panel.orderOut(nil); return }
        let frame = NSRect(x: cg.minX, y: mainDisplay.frame.maxY - cg.maxY, width: cg.width, height: cg.height)
        let screen = NSScreen.screens.first { $0.frame.intersects(frame) } ?? mainDisplay
        let visible = screen.visibleFrame
        let width = min(max(frame.width, 420), 560)
        var y = frame.minY - 90
        if y < visible.minY { y = min(frame.maxY + 8, visible.maxY - 82) }
        let x = min(max(frame.midX - width / 2, visible.minX + 8), visible.maxX - width - 8)
        panel.setFrame(NSRect(x: x, y: max(visible.minY, y), width: width, height: 82), display: true)
        panel.orderFrontRegardless()
    }

    private func restart() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { [weak self] _, error in
            Task { @MainActor [weak self] in
                if let error { self?.status.notice = "重新打开失败：\(error.localizedDescription)" }
                else { NSApplication.shared.terminate(nil) }
            }
        }
    }
}

private struct PermissionGuideView: View {
    @ObservedObject var status: PermissionStatus
    let openSettings: (RecordingPermission) -> Void
    let refresh: () -> Void
    let revealApp: () -> Void
    let restart: () -> Void
    let finish: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 9) {
                Image(systemName: "rectangle.stack.fill").foregroundStyle(InterfaceStyle.accent)
                Text("连截  /  SnapStack").font(.system(size: 12, weight: .medium))
            }
            VStack(alignment: .leading, spacing: 7) {
                Text("准备好连续截图").font(.system(size: 25, weight: .semibold))
                Text("完成授权，截图就能先收集、再一起粘贴。")
                    .font(.system(size: 13)).foregroundStyle(InterfaceStyle.muted)
            }
            VStack(spacing: 0) {
                ForEach(RecordingPermission.allCases) { permission in
                    HStack(spacing: 12) {
                        Image(systemName: permission.symbol).font(.system(size: 19)).frame(width: 26)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(permission.title).font(.system(size: 13, weight: .medium))
                            Text(permission.detail).font(.system(size: 11)).foregroundStyle(InterfaceStyle.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        if status.granted(permission) {
                            Label("已授权", systemImage: "checkmark.circle.fill")
                                .font(.system(size: 11)).foregroundStyle(InterfaceStyle.accent)
                        } else {
                            Button("打开设置") { openSettings(permission) }
                                .buttonStyle(SoftButtonStyle())
                        }
                    }
                    .padding(16)
                    .background(status.selected == permission && !status.granted(permission)
                                ? InterfaceStyle.accentBackground.opacity(0.55) : Color.clear)
                    if permission == .screen { Divider().padding(.horizontal, 16) }
                }
            }
            .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(InterfaceStyle.line))
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.2.circlepath")
                Text(status.notice.isEmpty ? "从系统设置回来后，会自动检查授权。" : status.notice)
            }
            .font(.system(size: 11)).foregroundStyle(InterfaceStyle.muted)
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            HStack {
                Menu("授权遇到问题") {
                    Button("重新检查", action: refresh)
                    Button("在 Finder 中显示当前应用", action: revealApp)
                    Button("重新打开连截（将清空当前截图）", action: restart)
                }
                .menuStyle(.borderlessButton).fixedSize().font(.system(size: 11))
                Spacer()
                Button(action: finish) {
                    HStack(spacing: 14) {
                        Text(status.accessibility ? "开始使用" : "先开始截图")
                        Image(systemName: "arrow.right")
                    }
                }
                .buttonStyle(SoftButtonStyle(prominent: true)).disabled(!status.screen)
            }
        }
        .padding(28).padding(.top, 16)
        .frame(width: 480, height: 450)
        .foregroundStyle(InterfaceStyle.ink)
        .background(InterfaceStyle.background)
    }
}

private struct PermissionHelperView: View {
    let permission: RecordingPermission
    let onDrop: () -> Void
    let onReturn: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            ApplicationDragIcon(onDrop: onDrop).frame(width: 42, height: 42)
            VStack(alignment: .leading, spacing: 5) {
                Text("找不到连截？").font(.system(size: 13, weight: .semibold))
                Text("把左侧图标拖入“\(permission.listName)”列表，再打开开关。")
                    .font(.system(size: 11)).foregroundStyle(InterfaceStyle.muted)
            }
            Spacer(minLength: 0)
            Button(action: onReturn) { Image(systemName: "arrow.uturn.backward") }
                .buttonStyle(.plain).help("回到授权引导")
        }
        .padding(16).frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(InterfaceStyle.ink)
        .background(InterfaceStyle.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(InterfaceStyle.line))
    }
}

private struct ApplicationDragIcon: NSViewRepresentable {
    let onDrop: () -> Void
    func makeNSView(context: Context) -> ApplicationDragView { ApplicationDragView(onDrop: onDrop) }
    func updateNSView(_ nsView: ApplicationDragView, context: Context) {}
}

private final class ApplicationDragView: NSView, NSDraggingSource {
    private let onDrop: () -> Void
    private let icon = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
    init(onDrop: @escaping () -> Void) {
        self.onDrop = onDrop
        super.init(frame: .zero)
        toolTip = "将连截拖到系统设置的应用列表"
        setAccessibilityElement(true)
        setAccessibilityLabel("连截应用图标，可拖入权限列表")
        setAccessibilityRole(.image)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func draw(_ dirtyRect: NSRect) { icon.draw(in: bounds) }
    override func mouseDown(with event: NSEvent) {
        let item = NSDraggingItem(pasteboardWriter: Bundle.main.bundleURL as NSURL)
        item.setDraggingFrame(bounds, contents: icon)
        beginDraggingSession(with: [item], event: event, source: self)
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        if !operation.isEmpty { onDrop() }
    }
}
