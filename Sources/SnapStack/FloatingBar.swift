import AppKit
import SwiftUI

@MainActor
final class FloatingBarController {
    private let panel: ScreenshotPanel
    private let presentation = BarPresentation()
    private var expandedBeforeCapture: Bool?
    private static let expandedSize = NSSize(width: 650, height: 215)
    private static let collapsedSize = NSSize(width: 56, height: 48)

    var isExpanded: Bool { presentation.isExpanded }

    init(state: CaptureState) {
        let size = Self.collapsedSize
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
        let host = ScreenshotHostingView(rootView: FloatingBarRootView(
            state: state, presentation: presentation,
            onExpand: { [weak self] in self?.show() },
            onCollapse: { [weak self] in self?.collapse() }))
        host.frame = NSRect(origin: .zero, size: size)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
    }

    func show() { setExpanded(true) }
    func collapse() { setExpanded(false) }
    func toggle() { setExpanded(!isExpanded) }
    func present() { panel.orderFrontRegardless() }

    func beginCapture() {
        expandedBeforeCapture = isExpanded
        panel.orderOut(nil)
    }

    func finishCapture(_ outcome: CaptureOutcome) {
        let previous = expandedBeforeCapture ?? isExpanded
        expandedBeforeCapture = nil
        switch outcome {
        case .success, .failed: show()
        case .cancelled: setExpanded(previous)
        }
    }

    private func setExpanded(_ expanded: Bool) {
        guard expandedBeforeCapture == nil else { return }
        let size = expanded ? Self.expandedSize : Self.collapsedSize
        let frame = panel.frame
        var next = NSRect(x: frame.maxX - size.width, y: frame.minY,
                          width: size.width, height: size.height)
        let screen = panel.screen ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            next.origin.x = min(max(next.minX, visible.minX), max(visible.minX, visible.maxX - size.width))
            next.origin.y = min(max(next.minY, visible.minY), max(visible.minY, visible.maxY - size.height))
        }
        presentation.isExpanded = expanded
        panel.setFrame(next, display: true)
        panel.orderFrontRegardless()
    }
}

@MainActor
private final class BarPresentation: ObservableObject {
    @Published var isExpanded = false
}

private struct FloatingBarRootView: View {
    @ObservedObject var state: CaptureState
    @ObservedObject var presentation: BarPresentation
    let onExpand: () -> Void
    let onCollapse: () -> Void

    var body: some View {
        if presentation.isExpanded {
            ScreenshotBarView(state: state, onCollapse: onCollapse)
        } else {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.regularMaterial)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.12)))
                Image(systemName: "rectangle.stack.fill")
                    .font(.system(size: 22)).foregroundStyle(.blue)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if !state.items.isEmpty {
                    Text("\(state.items.count)")
                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(.blue, in: Capsule())
                        .padding(2)
                }
            }
            .padding(3)
            .accessibilityHidden(true)
            .overlay(CollapsedBarHandle(count: state.items.count, onExpand: onExpand))
        }
    }
}

private final class ScreenshotPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class ScreenshotHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var needsPanelToBecomeKey: Bool { false }
}

struct ScreenshotBarView: View {
    @ObservedObject var state: CaptureState
    let onCollapse: () -> Void

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
                .help("区域截图 ⌃⇧S")
                Button("全部粘贴") { state.pasteAll() }
                    .buttonStyle(.borderedProminent)
                    .disabled(state.items.isEmpty || state.isBusy)
                    .help("按当前顺序逐张粘贴，每张等待 400ms")
                Button("清空") { state.clear() }
                    .disabled(state.items.isEmpty || state.isBusy)
                Button("退出") { NSApplication.shared.terminate(nil) }
                    .disabled(state.isBusy)
                    .help("退出 SnapStack")
                Button(action: onCollapse) {
                    Image(systemName: "chevron.down")
                }
                .help("收起为小悬浮按钮，截图队列保留")
                .accessibilityLabel("收起截图栏")
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

private struct CollapsedBarHandle: NSViewRepresentable {
    let count: Int
    let onExpand: () -> Void

    func makeNSView(context: Context) -> CollapsedBarDragView {
        let view = CollapsedBarDragView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: CollapsedBarDragView, context: Context) {
        view.onExpand = onExpand
        view.setAccessibilityLabel("展开连截截图栏，\(count) 张截图")
        view.toolTip = "点击展开截图栏，拖动可移动；区域截图 ⌃⇧S"
    }
}

private final class CollapsedBarDragView: NSView {
    var onExpand: (() -> Void)?
    private var startPoint: NSPoint?
    private var startOrigin: NSPoint?
    private var didDrag = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var needsPanelToBecomeKey: Bool { false }
    override func accessibilityPerformPress() -> Bool {
        onExpand?()
        return true
    }

    override func mouseDown(with event: NSEvent) {
        startPoint = window?.convertPoint(toScreen: event.locationInWindow)
        startOrigin = window?.frame.origin
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window, let startPoint, let startOrigin else { return }
        let point = window.convertPoint(toScreen: event.locationInWindow)
        let dx = point.x - startPoint.x
        let dy = point.y - startPoint.y
        guard didDrag || hypot(dx, dy) > 4 else { return }
        didDrag = true
        var origin = NSPoint(x: startOrigin.x + dx, y: startOrigin.y + dy)
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? window.screen
        if let visible = screen?.visibleFrame {
            origin.x = min(max(origin.x, visible.minX), max(visible.minX, visible.maxX - window.frame.width))
            origin.y = min(max(origin.y, visible.minY), max(visible.minY, visible.maxY - window.frame.height))
        }
        window.setFrameOrigin(origin)
    }

    override func mouseUp(with event: NSEvent) {
        let shouldExpand = startPoint != nil && !didDrag
        startPoint = nil
        startOrigin = nil
        didDrag = false
        if shouldExpand { onExpand?() }
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
