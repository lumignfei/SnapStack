import AppKit
import CoreGraphics
import ImageIO
import SwiftUI

struct ScreenshotItem: Identifiable {
    let id: UUID
    let fileURL: URL
    let thumbnail: NSImage
    var note = ""
}

enum CaptureOutcome {
    case success, cancelled, failed
}

@MainActor
final class CaptureState: ObservableObject {
    @Published private(set) var items: [ScreenshotItem] = []
    @Published private(set) var isCapturing = false
    @Published private(set) var isPasting = false
    @Published private(set) var targetName = "请先选择目标应用"
    @Published var editingNoteID: UUID?
    @Published var draggingID: UUID?
    @Published private(set) var reorderedID: UUID?
    private var reorderFeedbackTask: Task<Void, Never>?
    @Published var message = "按 ⌃⇧A 截取区域，可连续截图。"

    @Published private(set) var transientError: String?
    private var errorDismissTask: Task<Void, Never>?

    private func reportError(_ text: String) {
        message = text
        transientError = text
        errorDismissTask?.cancel()
        errorDismissTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(6)) } catch { return }
            self?.transientError = nil
        }
    }

    var isBusy: Bool { isCapturing || isPasting }

    var onCaptureWillStart: (() -> Void)?
    var onCaptureFinished: ((CaptureOutcome) -> Void)?
    var onQueueBecameEmpty: (() -> Void)?
    var onPermissionRequired: ((RecordingPermission) -> Void)?
    var onShowPermissions: (() -> Void)?
    private var captureProcess: Process?
    private let pasteManager = PasteManager()
    private let sessionDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("SnapStack", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)

    init(items: [ScreenshotItem] = []) {
        self.items = items
        targetName = pasteManager.targetName
        pasteManager.onTargetChanged = { [weak self] name in self?.targetName = name }
    }

    func capture() {
        guard !isCapturing, !isPasting else { return }
        guard CGPreflightScreenCaptureAccess() else {
            reportError("完成屏幕录制授权后，即可截图。")
            onPermissionRequired?(.screen)
            return
        }
        isCapturing = true
        onCaptureWillStart?()
        Task { @MainActor in
            // Release the hotkey before screencapture: Control redirects captures to the clipboard.
            for _ in 0..<25 {
                if NSEvent.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty { break }
                try? await Task.sleep(for: .milliseconds(40))
            }
            try? await Task.sleep(for: .milliseconds(120))
            startCaptureProcess()
        }
    }

    private func startCaptureProcess() {
        let id = UUID()
        let fileURL = sessionDirectory.appendingPathComponent("\(id.uuidString).png")
        do {
            try FileManager.default.createDirectory(at: sessionDirectory, withIntermediateDirectories: true)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = ["-i", "-s", "-x", "-t", "png", fileURL.path]
            let errors = Pipe()
            process.standardError = errors
            process.terminationHandler = { [weak self] finished in
                let status = finished.terminationStatus
                let errorText = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let exitedNormally = finished.terminationReason == .exit
                Task { @MainActor in
                    self?.finishCapture(id: id, fileURL: fileURL, status: status,
                                        errorText: errorText, exitedNormally: exitedNormally)
                }
            }
            captureProcess = process
            try process.run()
        } catch {
            finishCapture(id: id, fileURL: fileURL, status: -1, errorText: error.localizedDescription)
        }
    }

    private func finishCapture(id: UUID, fileURL: URL, status: Int32,
                               errorText: String = "", exitedNormally: Bool = true) {
        captureProcess = nil
        isCapturing = false
        var outcome = CaptureOutcome.failed
        defer { onCaptureFinished?(outcome) }
        guard status == 0, FileManager.default.fileExists(atPath: fileURL.path) else {
            try? FileManager.default.removeItem(at: fileURL)
            let details = errorText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !CGPreflightScreenCaptureAccess() {
                reportError("屏幕录制权限未生效，请在系统设置允许 SnapStack 后重新打开。")
            // Esc can return 0 without a PNG, as well as the older non-zero cancellation exit.
            } else if (status == 0 || status == 1), exitedNormally,
                      details.isEmpty || details.localizedCaseInsensitiveContains("cancel") {
                outcome = .cancelled
                message = "截图已取消，队列保持不变。"
            } else {
                reportError(details.isEmpty ? "截图失败，请重试。" : "截图失败：\(details)")
            }
            return
        }
        guard let thumbnail = makeThumbnail(fileURL) else {
            try? FileManager.default.removeItem(at: fileURL)
            reportError("截图文件无法读取，请重试。")
            return
        }
        items.append(ScreenshotItem(id: id, fileURL: fileURL, thumbnail: thumbnail))
        outcome = .success
        message = "已收集 \(items.count) 张截图，可继续按 ⌃⇧A。"
        FileHandle.standardOutput.write(Data("SnapStack: captured image \(items.count).\n".utf8))
    }

    private func makeThumbnail(_ url: URL) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 320
              ] as CFDictionary) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }

    func setNote(_ note: String, for id: UUID) {
        guard !isBusy, let index = items.firstIndex(where: { $0.id == id }), items[index].note != note else { return }
        items[index].note = note
    }

    func remove(_ id: UUID) {
        guard !isBusy, let index = items.firstIndex(where: { $0.id == id }) else { return }
        let item = items.remove(at: index)
        if draggingID == id { draggingID = nil }
        if editingNoteID == id { editingNoteID = nil }
        try? FileManager.default.removeItem(at: item.fileURL)
        message = items.isEmpty ? "队列为空，按 ⌃⇧A 开始截图。" : "已删除，剩余 \(items.count) 张。"
        if items.isEmpty { onQueueBecameEmpty?() }
    }

    func move(_ id: UUID, beforeOrAfter destinationID: UUID) {
        guard !isBusy, id != destinationID,
              let source = items.firstIndex(where: { $0.id == id }),
              let destination = items.firstIndex(where: { $0.id == destinationID }) else { return }
        items.move(fromOffsets: IndexSet(integer: source),
                   toOffset: destination > source ? destination + 1 : destination)
        reorderedID = id
        reorderFeedbackTask?.cancel()
        reorderFeedbackTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(850)) } catch { return }
            self?.reorderedID = nil
        }
        message = "顺序已更新，全部粘贴将按当前顺序执行。"
    }

    func clear() {
        guard !isBusy else { return }
        for item in items { try? FileManager.default.removeItem(at: item.fileURL) }
        items.removeAll()
        editingNoteID = nil
        draggingID = nil
        message = "已清空，按 ⌃⇧A 继续截图。"
        onQueueBecameEmpty?()
    }

    func pasteAll() {
        guard !isBusy, !items.isEmpty else { return }
        NoteEditor.commitCurrentInput()
        guard pasteManager.hasAccessibilityPermission() else {
            reportError("完成辅助功能授权后，即可自动粘贴。")
            onPermissionRequired?(.accessibility)
            return
        }
        guard let target = pasteManager.targetApplication() else {
            reportError("请先点击目标应用中需要粘贴的位置。")
            return
        }
        let queue = items
        let targetName = target.localizedName ?? "目标应用"
        isPasting = true
        message = "正在粘贴 1/\(queue.count) → \(targetName)…"
        Task { @MainActor in
            defer { isPasting = false }
            var completed = 0
            var hasPastedNote = false
            do {
                for (index, item) in queue.enumerated() {
                    guard let image = NSImage(contentsOf: item.fileURL) else {
                        reportError("第 \(index + 1) 张无法读取；已发送 \(completed) 张，队列保留。")
                        return
                    }
                    message = "正在粘贴 \(index + 1)/\(queue.count) → \(targetName)…"
                    try await pasteManager.paste(image, into: target)
                    if let note = ScreenshotNote.pasteText(item.note, imageNumber: index + 1, followsNote: hasPastedNote) {
                        do {
                            try await pasteManager.paste(text: note, into: target)
                            hasPastedNote = true
                        } catch {
                            reportError("第 \(index + 1) 张图片已发送，但备注未完成。\(error.localizedDescription) 队列保留。")
                            return
                        }
                    }
                    completed += 1
                }
                message = "已向 \(targetName) 发送 \(completed) 张截图，队列保留。"
            } catch {
                reportError("已发送 \(completed) 张。\(error.localizedDescription)")
            }
        }
    }

    func cleanup() {
        pasteManager.stopObserving()
        if let process = captureProcess, process.isRunning { process.terminate() }
        try? FileManager.default.removeItem(at: sessionDirectory)
    }
}
