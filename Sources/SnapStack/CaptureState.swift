import AppKit
import CoreGraphics
import ImageIO
import SwiftUI

struct ScreenshotItem: Identifiable {
    let id: UUID
    let fileURL: URL
    let thumbnail: NSImage
}

@MainActor
final class CaptureState: ObservableObject {
    @Published private(set) var items: [ScreenshotItem] = []
    @Published private(set) var isCapturing = false
    @Published private(set) var isPasting = false
    @Published private(set) var targetName = "请先选择目标应用"
    @Published var draggingID: UUID?
    @Published var message = "按 ⌃⌥⌘S 截取区域，可连续截图。"

    var isBusy: Bool { isCapturing || isPasting }

    var onCaptureWillStart: (() -> Void)?
    var onCaptureFinished: (() -> Void)?
    private var captureProcess: Process?
    private let pasteManager = PasteManager()
    private let sessionDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("SnapStack", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)

    init() {
        targetName = pasteManager.targetName
        pasteManager.onTargetChanged = { [weak self] name in self?.targetName = name }
    }

    func capture() {
        guard !isCapturing, !isPasting else { return }
        guard CGPreflightScreenCaptureAccess() else {
            _ = CGRequestScreenCaptureAccess()
            message = "请允许 SnapStack 的屏幕录制权限，再次点击截图。"
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
            process.terminationHandler = { [weak self] finished in
                let status = finished.terminationStatus
                Task { @MainActor in self?.finishCapture(id: id, fileURL: fileURL, status: status) }
            }
            captureProcess = process
            try process.run()
        } catch {
            finishCapture(id: id, fileURL: fileURL, status: -1)
            message = "截图未能启动：\(error.localizedDescription)"
        }
    }

    private func finishCapture(id: UUID, fileURL: URL, status: Int32) {
        captureProcess = nil
        isCapturing = false
        defer { onCaptureFinished?() }
        guard status == 0, FileManager.default.fileExists(atPath: fileURL.path) else {
            try? FileManager.default.removeItem(at: fileURL)
            message = status == -1 ? "截图未能启动。" : "截图已取消，队列保持不变。"
            return
        }
        guard let thumbnail = makeThumbnail(fileURL) else {
            try? FileManager.default.removeItem(at: fileURL)
            message = "截图文件无法读取，请重试。"
            return
        }
        items.append(ScreenshotItem(id: id, fileURL: fileURL, thumbnail: thumbnail))
        message = "已收集 \(items.count) 张截图，可继续按 ⌃⌥⌘S。"
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

    func remove(_ id: UUID) {
        guard !isBusy, let index = items.firstIndex(where: { $0.id == id }) else { return }
        let item = items.remove(at: index)
        if draggingID == id { draggingID = nil }
        try? FileManager.default.removeItem(at: item.fileURL)
        message = items.isEmpty ? "队列为空，按 ⌃⌥⌘S 开始截图。" : "已删除，剩余 \(items.count) 张。"
    }

    func move(_ id: UUID, beforeOrAfter destinationID: UUID) {
        guard !isBusy, id != destinationID,
              let source = items.firstIndex(where: { $0.id == id }),
              let destination = items.firstIndex(where: { $0.id == destinationID }) else { return }
        items.move(fromOffsets: IndexSet(integer: source),
                   toOffset: destination > source ? destination + 1 : destination)
        message = "顺序已更新，全部粘贴将按当前顺序执行。"
    }

    func clear() {
        guard !isBusy else { return }
        for item in items { try? FileManager.default.removeItem(at: item.fileURL) }
        items.removeAll()
        draggingID = nil
        message = "已清空，按 ⌃⌥⌘S 继续截图。"
    }

    func pasteAll() {
        guard !isBusy, !items.isEmpty else { return }
        guard pasteManager.hasAccessibilityPermission() else {
            message = "请允许 SnapStack 的辅助功能权限，再次点击粘贴。"
            return
        }
        guard let target = pasteManager.targetApplication() else {
            message = "请先点击目标应用中需要粘贴的位置。"
            return
        }
        let queue = items
        let targetName = target.localizedName ?? "目标应用"
        isPasting = true
        message = "正在粘贴 1/\(queue.count) → \(targetName)…"
        Task { @MainActor in
            defer { isPasting = false }
            var completed = 0
            do {
                for (index, item) in queue.enumerated() {
                    guard let image = NSImage(contentsOf: item.fileURL) else {
                        message = "第 \(index + 1) 张无法读取；已发送 \(completed) 张，队列保留。"
                        return
                    }
                    message = "正在粘贴 \(index + 1)/\(queue.count) → \(targetName)…"
                    try await pasteManager.paste(image, into: target)
                    completed += 1
                }
                message = "已向 \(targetName) 发送 \(completed) 张截图，队列保留。"
            } catch {
                message = "已发送 \(completed) 张。\(error.localizedDescription)"
            }
        }
    }

    func cleanup() {
        pasteManager.stopObserving()
        if let process = captureProcess, process.isRunning { process.terminate() }
        try? FileManager.default.removeItem(at: sessionDirectory)
    }
}
