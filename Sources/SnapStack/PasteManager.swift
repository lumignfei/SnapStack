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
        AXIsProcessTrusted()
    }

    func paste(_ image: NSImage, into target: NSRunningApplication) async throws {
        try await paste(into: target) { $0.writeObjects([image]) }
    }

    func paste(text: String, into target: NSRunningApplication) async throws {
        try await paste(into: target) { $0.setString(text, forType: .string) }
    }

    private func paste(into target: NSRunningApplication,
                       write: (NSPasteboard) -> Bool) async throws {
        // Do not combine the user's still-held Control/Shift with the generated Command-V.
        for _ in 0..<50 {
            if NSEvent.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty { break }
            try await Task.sleep(for: .milliseconds(40))
        }
        guard NSEvent.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty else {
            throw PasteError.modifiersHeld
        }
        guard !target.isTerminated else { throw PasteError.targetUnavailable }
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
        let clipboard = NSPasteboard.general
        clipboard.clearContents()
        guard write(clipboard) else { throw PasteError.clipboardFailed }
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
              app.bundleIdentifier != "com.apple.systempreferences",
              app.bundleIdentifier != "com.apple.screencaptureui",
              app.bundleIdentifier != "com.apple.Screenshot" else { return }
        lastTarget = app
        onTargetChanged?(targetName)
    }
}

private enum PasteError: LocalizedError {
    case targetUnavailable, clipboardFailed, keyEventFailed, modifiersHeld

    var errorDescription: String? {
        switch self {
        case .targetUnavailable: "目标应用未能激活，请先点击需要粘贴的位置。"
        case .clipboardFailed: "内容写入剪贴板失败，请重试。"
        case .keyEventFailed: "未能发送粘贴快捷键。"
        case .modifiersHeld: "请松开快捷键后重试粘贴，队列保留。"
        }
    }
}
