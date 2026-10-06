import AppKit
@preconcurrency import ApplicationServices

@MainActor
final class PasteManager: NSObject {
    private var lastTarget: NSRunningApplication?
    var onTargetChanged: ((String) -> Void)?

    var targetName: String { lastTarget?.localizedName ?? "请先选择目标应用" }

    override init() {
        super.init()
        remember(NSWorkspace.shared.frontmostApplication)
        NSWorkspace.shared.notificationCenter.addObserver(self,
            selector: #selector(applicationActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)
    }

    func targetApplication() -> NSRunningApplication? {
        remember(NSWorkspace.shared.frontmostApplication)
        guard let lastTarget, !lastTarget.isTerminated else { return nil }
        return lastTarget
    }

    func hasAccessibilityPermission() -> Bool {
        if AXIsProcessTrusted() { return true }
        _ = AXIsProcessTrustedWithOptions([
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary)
        return false
    }

    func paste(_ image: NSImage, into target: NSRunningApplication) async throws {
        guard !target.isTerminated else { throw PasteError.targetUnavailable }
        let clipboard = NSPasteboard.general
        clipboard.clearContents()
        guard clipboard.writeObjects([image]) else { throw PasteError.clipboardFailed }
        guard target.activate(options: [.activateIgnoringOtherApps]) else {
            throw PasteError.targetUnavailable
        }
        // Give the target time to regain its window and insertion point.
        for _ in 0..<25 {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier { break }
            try await Task.sleep(for: .milliseconds(40))
        }
        try await Task.sleep(for: .milliseconds(80))
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier else {
            throw PasteError.targetUnavailable
        }
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
            throw PasteError.keyEventFailed
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        try await Task.sleep(for: .milliseconds(400))
    }

    func stopObserving() { NSWorkspace.shared.notificationCenter.removeObserver(self) }

    @objc private func applicationActivated(_ notification: Notification) {
        remember(notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
    }

    private func remember(_ app: NSRunningApplication?) {
        guard let app, app.activationPolicy == .regular,
              app.bundleIdentifier != Bundle.main.bundleIdentifier,
              app.bundleIdentifier != "com.apple.screencaptureui",
              app.bundleIdentifier != "com.apple.Screenshot" else { return }
        lastTarget = app
        onTargetChanged?(targetName)
    }
}

private enum PasteError: LocalizedError {
    case targetUnavailable, clipboardFailed, keyEventFailed

    var errorDescription: String? {
        switch self {
        case .targetUnavailable: "目标应用未能激活，请先点击需要粘贴的位置。"
        case .clipboardFailed: "图片写入剪贴板失败，请重试。"
        case .keyEventFailed: "未能发送粘贴快捷键。"
        }
    }
}
