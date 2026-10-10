import AppKit
import Combine
import QuartzCore
import SwiftUI

@MainActor
final class FloatingBarController {
    private let panel: ScreenshotPanel
    private let presentation = BarPresentation()
    private var expanded = true
    private var expandedHost: NSView!
    private var collapsedHost: NSView!
    private var expandedImage: CGImage?
    private var collapsedImage: CGImage?
    private var prewarmTask: Task<Void, Never>?
    private var observations = Set<AnyCancellable>()
    private var expandedBeforeCapture: Bool?
    private let surfaceTransition = BarSurfaceTransition()
    private static let expandedSize = NSSize(width: 520, height: 72)
    private static let collapsedSize = NSSize(width: 56, height: 48)

    var isExpanded: Bool { expanded }

    init(state: CaptureState) {
        let size = Self.expandedSize
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
        panel.appearance = NSAppearance(named: .aqua)
        let host = ScreenshotHostingView(rootView: FloatingBarRootView(
            state: state, presentation: presentation,
            onExpand: { [weak self] in self?.show() },
            onCollapse: { [weak self] in self?.collapse() }))
        host.frame = NSRect(origin: .zero, size: size)
        host.autoresizingMask = [.width, .height]
        // The panel controls its size; outgoing content must not constrain the animation.
        host.sizingOptions = []
        panel.contentView = host
        expandedHost = host
        let compactPresentation = BarPresentation()
        compactPresentation.isExpanded = false
        let compact = ScreenshotHostingView(rootView: FloatingBarRootView(
            state: state, presentation: compactPresentation,
            onExpand: { [weak self] in self?.show() },
            onCollapse: { [weak self] in self?.collapse() }))
        compact.frame = NSRect(origin: .zero, size: Self.collapsedSize)
        compact.autoresizingMask = [.width, .height]
        compact.sizingOptions = []
        collapsedHost = compact
        state.$items.map { $0.map(\.id) }.removeDuplicates().dropFirst().sink { [weak self] _ in self?.invalidateSnapshots() }
            .store(in: &observations)
        state.$isPasting.dropFirst().sink { [weak self] _ in self?.invalidateSnapshots() }
            .store(in: &observations)
        invalidateSnapshots()
    }

    func show() { setExpanded(true) }
    func collapse() { presentation.showsQueue = false; setExpanded(false) }
    func toggle() { setExpanded(!isExpanded) }
    func present() { panel.orderFrontRegardless() }

    private func invalidateSnapshots() {
        expandedImage = nil
        collapsedImage = nil
        prewarmTask?.cancel()
        prewarmTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            guard let self else { return }
            self.expandedImage = BarSurfaceTransition.snapshot(self.expandedHost)
            self.collapsedImage = BarSurfaceTransition.snapshot(self.collapsedHost)
        }
    }

    func beginCapture() {
        surfaceTransition.finish()
        presentation.contentOpacity = 1
        presentation.showsQueue = false
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
        surfaceTransition.finish()
        guard isExpanded != expanded else { panel.orderFrontRegardless(); return }
        let started = CACurrentMediaTime()
        let oldImage = isExpanded ? expandedImage : collapsedImage
        let newImage = expanded ? expandedImage : collapsedImage
        let destination = expanded ? expandedHost! : collapsedHost!
        let size = expanded ? Self.expandedSize : Self.collapsedSize
        let frame = panel.frame
        var next = NSRect(x: frame.maxX - size.width, y: frame.minY,
                          width: size.width, height: size.height)
        let screen = panel.screen ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            next.origin.x = min(max(next.minX, visible.minX), max(visible.minX, visible.maxX - size.width))
            next.origin.y = min(max(next.minY, visible.minY), max(visible.minY, visible.maxY - size.height))
        }
        let animate = panel.isVisible && isExpanded != expanded
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        self.expanded = expanded
        if animate,
           let oldImage = oldImage ?? BarSurfaceTransition.snapshot(panel.contentView),
           let newImage = newImage ?? BarSurfaceTransition.snapshot(destination) {
            surfaceTransition.start(panel: panel, content: destination, from: frame, to: next,
                                    oldImage: oldImage, newImage: newImage)
            #if DEBUG
            print("Bar morph preparation: \(String(format: "%.2f", (CACurrentMediaTime() - started) * 1000)) ms; animation: 260 ms")
            #endif
        } else {
            panel.contentView = destination
            panel.setFrame(next, display: false)
            destination.frame = NSRect(origin: .zero, size: next.size)
        }
        panel.orderFrontRegardless()
    }
}

@MainActor
private final class BarPresentation: ObservableObject {
    @Published var isExpanded = true
    @Published var showsQueue = false
    @Published var contentOpacity: Double = 1
}

private struct FloatingBarRootView: View {
    @ObservedObject var state: CaptureState
    @ObservedObject var presentation: BarPresentation
    let onExpand: () -> Void
    let onCollapse: () -> Void

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if presentation.isExpanded {
                ScreenshotBarView(state: state, showsQueue: $presentation.showsQueue, onCollapse: onCollapse)
                    .frame(width: 520, height: 72)
                    .transition(.identity)
            } else {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "rectangle.stack.fill")
                        .font(.system(size: 22)).foregroundStyle(InterfaceStyle.accent)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if !state.items.isEmpty {
                        Text("\(state.items.count)")
                            .font(.system(size: 10, weight: .semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(InterfaceStyle.accent, in: Capsule())
                            .padding(2)
                    }
                }
                .padding(3)
                .accessibilityHidden(true)
                .overlay(CollapsedBarHandle(count: state.items.count, onExpand: onExpand))
                .frame(width: 56, height: 48)
                .transition(.identity)
            }
        }
        .opacity(presentation.contentOpacity)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(InterfaceStyle.line))
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
    @Binding var showsQueue: Bool
    @StateObject private var more = BooleanViewState()
    let onCollapse: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 4) {
                ForEach(0..<3) { _ in
                    HStack(spacing: 4) {
                        Circle().frame(width: 2.5, height: 2.5)
                        Circle().frame(width: 2.5, height: 2.5)
                    }
                }
            }
                .foregroundStyle(InterfaceStyle.muted.opacity(0.55))
                .frame(width: 18, height: 44)
                .overlay(PanelDragHandle().accessibilityHidden(true))
                .offset(x: -4)
                .help("拖动移动截图栏")
            Button { state.capture() } label: {
                HStack(spacing: 8) {
                    CaptureOutline()
                        .stroke(style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                        .frame(width: 22, height: 18)
                    Text("截图").font(.system(size: 13, weight: .medium))
                }.frame(width: 80, height: 44)
                    .contentShape(Rectangle())
                    .foregroundStyle(InterfaceStyle.ink.opacity(0.85))
            }
            .buttonStyle(ToolbarHoverStyle()).disabled(state.isBusy).help("区域截图 ⌃⇧A")
            divider
            Button { more.value = false; showsQueue.toggle() } label: {
                HStack(spacing: 6) {
                    if state.items.isEmpty {
                        Image(systemName: "rectangle.stack").font(.system(size: 17, weight: .regular))
                        Text("暂无截图").font(.system(size: 12))
                    } else {
                        ForEach(Array(state.items.prefix(3).enumerated()), id: \.element.id) { index, item in
                            Image(nsImage: item.thumbnail).resizable().scaledToFit()
                                .frame(maxWidth: 46).frame(height: 36)
                                .background(InterfaceStyle.background, in: RoundedRectangle(cornerRadius: 5))
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                                .overlay(RoundedRectangle(cornerRadius: 5).stroke(InterfaceStyle.line))
                                .accessibilityLabel("截图 \(index + 1)")
                        }
                        if state.items.count > 3 {
                            Text("+\(state.items.count - 3)").font(.system(size: 11, weight: .medium))
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up").font(.system(size: 9, weight: .medium))
                }.animation(.easeInOut(duration: 0.24), value: state.items.map(\.id))
                .padding(.horizontal, 10)
                .frame(width: 172, height: 48)
                .contentShape(Rectangle())
            }
            .buttonStyle(ToolbarHoverStyle()).foregroundStyle(InterfaceStyle.muted)
            .accessibilityLabel("查看与整理截图，\(state.items.count) 张")
            .help(state.message)
            .stablePopover(isPresented: $showsQueue, size: ScreenshotQueueView.size(for: state)) {
                ScreenshotQueueView(state: state)
            }
            divider
            Button { state.pasteAll() } label: {
                Text(state.isPasting ? "粘贴中…" : "粘贴")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 84, height: 44)
                    .foregroundStyle(state.items.isEmpty ? InterfaceStyle.muted : InterfaceStyle.primaryButton)
                    .background(state.items.isEmpty ? InterfaceStyle.background : InterfaceStyle.accentBackground,
                                in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(ToolbarHoverStyle()).disabled(state.items.isEmpty || state.isBusy)
            .accessibilityLabel("粘贴全部 \(state.items.count) 张截图到 \(state.targetName)")
            .help("粘贴全部 ⌃⇧S\n\(state.message)\n粘贴目标：\(state.targetName)")
            Button { showsQueue = false; more.value.toggle() } label: {
                Image(systemName: "ellipsis").font(.system(size: 15, weight: .regular))
                    .foregroundStyle(InterfaceStyle.accent)
                    .frame(width: 40, height: 40)
                    .background(more.value ? InterfaceStyle.accentBackground : InterfaceStyle.background.opacity(0.6),
                                in: RoundedRectangle(cornerRadius: 11))
                    .overlay(RoundedRectangle(cornerRadius: 11).stroke(InterfaceStyle.line.opacity(0.7)))
            }
            .buttonStyle(ToolbarHoverStyle()).accessibilityLabel("更多操作").disabled(state.isBusy)
            .stablePopover(isPresented: $more.value, size: CGSize(width: 220, height: 199)) {
                VStack(spacing: 4) {
                    MoreActionRow(title: "收起为悬浮按钮", symbol: "rectangle.compress.vertical") {
                        more.value = false; onCollapse()
                    }
                    MoreActionRow(title: "权限与使用引导", symbol: "checkmark.shield") {
                        more.value = false; state.onShowPermissions?()
                    }
                    Rectangle().fill(InterfaceStyle.line).frame(height: 1).padding(.vertical, 5)
                    MoreActionRow(title: "清空截图", symbol: "trash") {
                        more.value = false; state.clear()
                    }.disabled(state.items.isEmpty)
                    MoreActionRow(title: "退出连截", symbol: "power") {
                        NSApplication.shared.terminate(nil)
                    }
                }
                .padding(10).frame(width: 220, height: 199, alignment: .topLeading)
                .background(Color.white)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(InterfaceStyle.line))
            }
        }
        .padding(.horizontal, 16)
        .foregroundStyle(InterfaceStyle.ink)
        .onReceive(state.$isCapturing) { capturing in
            if capturing { showsQueue = false; more.value = false }
        }
        .onReceive(state.$message) { message in
            // Surface failures without reserving a permanent status row.
            if message.contains("失败") || message.contains("无法") || message.contains("未能")
                || message.hasPrefix("请先点击") { showsQueue = true }
        }
    }

    private var divider: some View {
        Rectangle().fill(InterfaceStyle.line).frame(width: 1, height: 32)
    }
}

private struct CaptureOutline: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r: CGFloat = 3.5
        let arm: CGFloat = 8
        // Draw each corner at the intended aspect ratio, with one consistent
        // stroke width instead of stretching a square SF Symbol.
        for (x, y, dx, dy) in [(rect.minX, rect.minY, CGFloat(1), CGFloat(1)),
                               (rect.maxX, rect.minY, -1, 1),
                               (rect.maxX, rect.maxY, -1, -1),
                               (rect.minX, rect.maxY, 1, -1)] {
            path.move(to: CGPoint(x: x + dx * arm, y: y))
            path.addLine(to: CGPoint(x: x + dx * r, y: y))
            path.addQuadCurve(to: CGPoint(x: x, y: y + dy * r), control: CGPoint(x: x, y: y))
            path.addLine(to: CGPoint(x: x, y: y + dy * arm))
        }
        return path
    }
}

private final class BooleanViewState: ObservableObject {
    @Published var value = false
}

private struct MoreActionRow: View {
    let title: String
    let symbol: String
    let action: () -> Void
    @StateObject private var hover = BooleanViewState()
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.system(size: 15, weight: .regular))
                    .foregroundStyle(InterfaceStyle.accent).frame(width: 20)
                Text(title).font(.system(size: 13, weight: .regular))
                Spacer(minLength: 0)
            }
            .foregroundStyle(InterfaceStyle.ink)
            .padding(.horizontal, 11).frame(height: 38)
            .background(hover.value && enabled ? InterfaceStyle.accentBackground : Color.clear,
                        in: RoundedRectangle(cornerRadius: 8))
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .opacity(enabled ? 1 : 0.35)
        }
        .buttonStyle(.plain).onHover { hover.value = $0 }
    }
}

private struct ScreenshotQueueView: View {
    @ObservedObject var state: CaptureState
    static func size(for state: CaptureState) -> CGSize {
        let hasNote = state.editingNoteID.map { id in state.items.contains { $0.id == id } } ?? false
        let note = state.items.first { $0.id == state.editingNoteID }?.note ?? ""
        return ScreenshotQueueLayout.size(isEmpty: state.items.isEmpty, showsNote: hasNote,
                                          noteHeight: NoteEditor.height(for: note), showsError: state.transientError != nil)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("截图 \(state.items.count) 张").font(.system(size: 14, weight: .medium))
                Spacer()
                Text("拖动图片调整顺序").font(.system(size: 11)).foregroundStyle(InterfaceStyle.muted)
            }
            .frame(height: 18)
            if state.items.isEmpty {
                Text("按 ⌃⇧A 截图，图片会收集在这里。")
                    .font(.system(size: 13)).foregroundStyle(InterfaceStyle.muted)
                    .frame(maxWidth: .infinity, minHeight: 100, maxHeight: 100)
            } else {
            ScrollView(.horizontal) {
                HStack(spacing: 14) {
                    ForEach(Array(state.items.enumerated()), id: \.element.id) { index, item in
                        VStack(alignment: .leading, spacing: 8) {
                            ZStack(alignment: .topTrailing) {
                            Image(nsImage: item.thumbnail).resizable().scaledToFit()
                                .frame(width: 150, height: 88)
                                .background(InterfaceStyle.background, in: RoundedRectangle(cornerRadius: 8))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(state.editingNoteID == item.id ? InterfaceStyle.accent : InterfaceStyle.line, lineWidth: state.editingNoteID == item.id ? 1.5 : 1))
                                .overlay(ThumbnailDragHandle(itemID: item.id, state: state).accessibilityHidden(true))
                                Button { state.remove(item.id) } label: {
                                    Image(systemName: "xmark").font(.system(size: 8, weight: .semibold))
                                        .foregroundStyle(InterfaceStyle.ink).frame(width: 19, height: 19)
                                        .background(.white.opacity(0.95), in: Circle())
                                }.buttonStyle(.plain).padding(4).disabled(state.isBusy)
                                    .accessibilityLabel("删除截图 \(index + 1)")
                            }
                            HStack(spacing: 0) {
                                Text("\(index + 1)").foregroundStyle(InterfaceStyle.muted)
                                Spacer()
                                Button {
                                    NoteEditor.commitCurrentInput()
                                    state.editingNoteID = state.editingNoteID == item.id ? nil : item.id
                                } label: {
                                    Label((item.note).isEmpty ? "添加备注" : "编辑备注", systemImage: "square.and.pencil")
                                }
                                .buttonStyle(.plain).foregroundStyle(InterfaceStyle.primaryButton).disabled(state.isBusy)
                            }.font(.system(size: 11))
                        }.frame(width: 150)
                            .overlay(RoundedRectangle(cornerRadius: 9)
                                .stroke(InterfaceStyle.accent.opacity(state.reorderedID == item.id ? 0.8 : 0), lineWidth: 2)
                                .padding(-3).allowsHitTesting(false))
                            .animation(.easeOut(duration: 0.2), value: state.reorderedID)

                    }
                }.animation(.easeInOut(duration: 0.24), value: state.items.map(\.id)).padding(4)
            }.scrollIndicators(.hidden).frame(height: 118)
            }
            if let id = state.editingNoteID, let selected = state.items.firstIndex(where: { $0.id == id }) {
                Rectangle().fill(InterfaceStyle.line).frame(height: 1)
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("图片 \(selected + 1) 的备注").font(.system(size: 12, weight: .medium))
                        Spacer()
                        Button("收起") { NoteEditor.commitCurrentInput(); state.editingNoteID = nil }
                            .buttonStyle(.plain).font(.system(size: 11))
                            .foregroundStyle(InterfaceStyle.muted)
                    }
                    .frame(height: 16)
                    NoteEditor(text: Binding(get: { state.items.first(where: { $0.id == id })?.note ?? "" }, set: { state.setNote($0, for: id) }), label: "图片 \(selected + 1) 的备注", isEditable: !state.isBusy, onSubmit: { state.editingNoteID = nil })
                        .id(id)
                        .frame(height: NoteEditor.height(for: state.items[selected].note)).padding(.horizontal, 6)
                        .background(InterfaceStyle.background.opacity(0.65), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(InterfaceStyle.line))
                }
            }
            if let error = state.transientError {
                Text(error).font(.system(size: 11)).foregroundStyle(InterfaceStyle.muted)
                    .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading).frame(height: 28, alignment: .topLeading)
            }
        }
        .padding(22).frame(width: 540, height: Self.size(for: state).height, alignment: .topLeading)
        .foregroundStyle(InterfaceStyle.ink).background(Color.white)
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
        view.toolTip = "点击展开截图栏，拖动可移动；区域截图 ⌃⇧A"
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
    private var lastReorderTime = -Double.infinity

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
        NoteEditor.commitCurrentInput()
        lastReorderTime = -Double.infinity
        startPoint = event.locationInWindow
    }

    override func mouseDragged(with event: NSEvent) {
        guard !state.isBusy, let startPoint, let root = window?.contentView else { return }
        let point = event.locationInWindow
        guard hypot(point.x - startPoint.x, point.y - startPoint.y) >= 4 else { return }
        state.draggingID = itemID
        if event.timestamp - lastReorderTime >= 0.26,
           let destination = thumbnail(in: root, at: point), destination.itemID != itemID {
            lastReorderTime = event.timestamp
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
