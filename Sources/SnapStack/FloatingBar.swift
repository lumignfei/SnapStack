import AppKit
import SwiftUI

@MainActor
final class FloatingBarController {
    private let panel: ScreenshotPanel

    init(state: CaptureState) {
        let size = NSSize(width: 650, height: 215)
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        panel = ScreenshotPanel(contentRect: NSRect(
            x: screen.maxX - size.width - 24, y: screen.minY + 24, width: size.width, height: size.height),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "SnapStack / 连截截图栏"
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovableByWindowBackground = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        let host = ScreenshotHostingView(rootView: ScreenshotBarView(state: state))
        host.frame = NSRect(origin: .zero, size: size)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
    }

    func show() { panel.orderFrontRegardless() }
    func hide() { panel.orderOut(nil) }
}

private final class ScreenshotPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class ScreenshotHostingView: NSHostingView<ScreenshotBarView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var needsPanelToBecomeKey: Bool { false }
}

struct ScreenshotBarView: View {
    @ObservedObject var state: CaptureState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack {
                    Image(systemName: "rectangle.stack.fill").foregroundStyle(.blue)
                    Text("连截").font(.headline)
                    Text("\(state.items.count) 张").font(.caption).foregroundStyle(.secondary)
                }
                .overlay(PanelDragHandle().accessibilityHidden(true))
                Spacer()
                Button { state.capture() } label: {
                    Label("截图", systemImage: "plus.viewfinder")
                }
                .disabled(state.isBusy)
                .help("区域截图 ⌃⌥⌘S")
                Button("全部粘贴") { state.pasteAll() }
                    .buttonStyle(.borderedProminent)
                    .disabled(state.items.isEmpty || state.isBusy)
                    .help("按当前顺序逐张粘贴，每张等待 400ms")
                Button("清空") { state.clear() }
                    .disabled(state.items.isEmpty || state.isBusy)
                Button("退出") { NSApplication.shared.terminate(nil) }
                    .disabled(state.isBusy)
                    .help("退出 SnapStack")
            }

            if state.items.isEmpty {
                VStack(spacing: 7) {
                    Image(systemName: "viewfinder").font(.title2).foregroundStyle(.secondary)
                    Text("连续截图，先收集到这里")
                        .font(.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity).frame(height: 100)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(Array(state.items.enumerated()), id: \.element.id) { index, item in
                            VStack(spacing: 5) {
                                ZStack(alignment: .topTrailing) {
                                    Image(nsImage: item.thumbnail)
                                        .resizable().scaledToFit()
                                        .frame(width: 112, height: 76)
                                        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                                        .accessibilityLabel("截图 \(index + 1)")
                                        .overlay(ThumbnailDragHandle(itemID: item.id, state: state)
                                            .accessibilityHidden(true))
                                    Button { state.remove(item.id) } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .symbolRenderingMode(.palette)
                                            .foregroundStyle(.white, .black.opacity(0.7))
                                            .font(.system(size: 17))
                                    }
                                    .buttonStyle(.plain)
                                    .padding(3)
                                    .disabled(state.isBusy)
                                    .accessibilityLabel("删除截图 \(index + 1)")
                                }
                                Text("\(index + 1)").font(.caption).foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                            .help("拖动缩略图调整顺序")
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(height: 100)
            }

            HStack(alignment: .top) {
                Text(state.message).lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("目标：\(state.targetName)").lineLimit(1)
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.primary.opacity(0.1)))
    }
}

private struct ThumbnailDragHandle: NSViewRepresentable {
    let itemID: UUID
    let state: CaptureState

    func makeNSView(context: Context) -> ThumbnailDragView {
        ThumbnailDragView(itemID: itemID, state: state)
    }

    func updateNSView(_ nsView: ThumbnailDragView, context: Context) {}
}

private final class ThumbnailDragView: NSView {
    let itemID: UUID
    let state: CaptureState
    private var startPoint: NSPoint?

    init(itemID: UUID, state: CaptureState) {
        self.itemID = itemID
        self.state = state
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var needsPanelToBecomeKey: Bool { false }

    override func mouseDown(with event: NSEvent) {
        guard !state.isBusy else { return }
        startPoint = event.locationInWindow
    }

    override func mouseDragged(with event: NSEvent) {
        guard !state.isBusy, let startPoint, let root = window?.contentView else { return }
        let point = event.locationInWindow
        guard hypot(point.x - startPoint.x, point.y - startPoint.y) >= 4 else { return }
        state.draggingID = itemID
        if let destination = thumbnail(in: root, at: point), destination.itemID != itemID {
            state.move(itemID, beforeOrAfter: destination.itemID)
        }
    }

    override func mouseUp(with event: NSEvent) {
        startPoint = nil
        state.draggingID = nil
    }

    private func thumbnail(in view: NSView, at windowPoint: NSPoint) -> ThumbnailDragView? {
        if let handle = view as? ThumbnailDragView,
           handle.bounds.contains(handle.convert(windowPoint, from: nil)) { return handle }
        for child in view.subviews {
            if let handle = thumbnail(in: child, at: windowPoint) { return handle }
        }
        return nil
    }
}

private struct PanelDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragHandleView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class DragHandleView: NSView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var needsPanelToBecomeKey: Bool { false }
    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
}
