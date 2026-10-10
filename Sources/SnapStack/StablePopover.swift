import AppKit
import QuartzCore
import SwiftUI

extension View {
    func stablePopover<Content: View>(isPresented: Binding<Bool>, size: CGSize, @ViewBuilder content: () -> Content) -> some View {
        background(StablePopoverAnchor(isPresented: isPresented, requestedSize: size, content: content()))
    }
}

// One white shape paints both the body and arrow; no system material can
// show through the arrow during or after the layer animation.
private struct StablePopoverAnchor<Content: View>: NSViewRepresentable {
    @Binding var isPresented: Bool
    let requestedSize: CGSize
    let content: Content
    func makeCoordinator() -> Coordinator { Coordinator(binding: $isPresented, content: content) }
    func makeNSView(context: Context) -> NSView {
        let view = PopoverAnchorView()
        view.willDetach = { [weak coordinator = context.coordinator] in coordinator?.close(animated: false) }
        return view
    }
    func updateNSView(_ anchor: NSView, context: Context) {
        let c = context.coordinator
        c.binding = $isPresented
        c.updateContent(content, size: requestedSize)
        if isPresented, anchor.window != nil { c.show(from: anchor) }
        else if c.isPresented { c.close(animated: true) }

    }
    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) { coordinator.close(animated: false) }

    @MainActor final class Coordinator {
        var binding: Binding<Bool>
        let host: NSHostingController<Content>
        let panel = PopoverPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        let surface = NSView()
        let shape = CAShapeLayer()
        var isPresented = false
        var above = true
        weak var anchorView: NSView?
        var contentSize = CGSize.zero
        var requestedSize = CGSize.zero
        var closing: Task<Void, Never>?
        var localMonitor: Any?
        var globalMonitor: Any?

        init(binding: Binding<Bool>, content: Content) {
            self.binding = binding
            host = NSHostingController(rootView: content)
            host.sizingOptions = []
            if let view = host.view as? NSHostingView<Content> { view.sizingOptions = [] }
            host.view.autoresizingMask = []
            host.view.translatesAutoresizingMaskIntoConstraints = true
            panel.title = "连截浮窗"
            panel.level = .floating
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.appearance = NSAppearance(named: .aqua)
            surface.wantsLayer = true
            surface.layer?.addSublayer(shape)
            shape.fillColor = NSColor.white.cgColor
            shape.shadowColor = NSColor.black.cgColor
            shape.shadowOpacity = 0.16
            shape.shadowRadius = 8
            shape.shadowOffset = CGSize(width: 0, height: -2)
            surface.addSubview(host.view)
            panel.contentView = surface
            host.view.layoutSubtreeIfNeeded()
        }

        func updateContent(_ content: Content, size: CGSize) {
            requestedSize = size
            host.rootView = content
        }
        func show(from anchor: NSView) {
            guard let parent = anchor.window else { return }
            // The state that renders the content also supplies its dimensions.
            // Do not size the window from a delayed GeometryReader callback.
            host.view.layoutSubtreeIfNeeded()
            let size = requestedSize
            if isPresented {
                layout(from: anchor, size: size)
                return
            }
            closing?.cancel()
            anchorView = anchor
            isPresented = true
            layout(from: anchor, size: size)
            parent.addChildWindow(panel, ordered: .above)
            panel.makeKeyAndOrderFront(nil)
            animate(opening: true)
            installMonitors()
        }
        private func layout(from anchor: NSView, size: CGSize) {
            guard let parent = anchor.window, size.width > 0, size.height > 0 else { return }
            contentSize = size
            let visible = parent.screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
            let rect = parent.convertToScreen(anchor.convert(anchor.bounds, to: nil))
            let width = size.width + 24, height = size.height + 34
            above = rect.maxY + height <= visible.maxY
            let x = min(max(rect.midX - width / 2, visible.minX), visible.maxX - width)
            let y = above ? rect.maxY - 8 : rect.minY - height + 8
            panel.setFrame(NSRect(x: x, y: min(max(y, visible.minY), visible.maxY - height), width: width, height: height), display: false)
            surface.frame = NSRect(origin: .zero, size: panel.frame.size)
            let body = NSRect(x: 12, y: above ? 22 : 12, width: size.width, height: size.height)
            host.view.frame = body
            host.view.layoutSubtreeIfNeeded()
            let arrowX = min(max(rect.midX - x, body.minX + 24), body.maxX - 24)
            let path = CGMutablePath()
            path.addRoundedRect(in: body, cornerWidth: 20, cornerHeight: 20)
            let base = above ? body.minY + 1 : body.maxY - 1
            let tip = above ? body.minY - 10 : body.maxY + 10
            path.move(to: CGPoint(x: arrowX - 11, y: base))
            path.addLine(to: CGPoint(x: arrowX, y: tip))
            path.addLine(to: CGPoint(x: arrowX + 11, y: base))
            path.closeSubpath()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            shape.path = path
            shape.shadowPath = path
            host.view.wantsLayer = true
            host.view.layer?.cornerRadius = 20
            host.view.layer?.masksToBounds = true
            CATransaction.commit()
        }

        private func animate(opening: Bool) {
            guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, let layer = surface.layer else { return }
            let movement = CABasicAnimation(keyPath: "transform")
            let offset = CATransform3DTranslate(CATransform3DMakeScale(0.96, 0.96, 1), 0, above ? -6 : 6, 0)
            movement.fromValue = NSValue(caTransform3D: opening ? offset : CATransform3DIdentity)
            movement.toValue = NSValue(caTransform3D: opening ? CATransform3DIdentity : offset)
            let opacity = CABasicAnimation(keyPath: "opacity")
            opacity.fromValue = opening ? 0 : 1
            opacity.toValue = opening ? 1 : 0
            let group = CAAnimationGroup()
            group.animations = [movement, opacity]
            group.duration = opening ? 0.20 : 0.13
            group.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 0.8, 0.25, 1)
            group.fillMode = .forwards
            group.isRemovedOnCompletion = opening
            layer.add(group, forKey: "popoverMotion")
        }

        func close(animated: Bool) {
            NoteEditor.commitCurrentInput()
            guard isPresented || panel.isVisible else { return }
            isPresented = false
            removeMonitors()
            closing?.cancel()
            if animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                animate(opening: false)
                closing = Task { @MainActor [weak self] in
                    do { try await Task.sleep(for: .milliseconds(130)) } catch { return }
                    self?.hide()
                }
            } else { hide() }
        }
        private func hide() {
            panel.parent?.removeChildWindow(panel)
            panel.orderOut(nil)
            surface.layer?.removeAllAnimations()
        }
        private func dismiss() { binding.wrappedValue = false; close(animated: true) }
        private func installMonitors() {
            removeMonitors()
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
                let consumed = MainActor.assumeIsolated {
                    guard let self else { return false }
                    if event.type == .keyDown {
                        if event.keyCode == 53 {
                            if let editor = self.panel.firstResponder as? NSTextView, editor.hasMarkedText() { return false }
                            self.dismiss(); return true
                        }
                    } else if event.window !== self.panel && event.window !== self.panel.parent { self.dismiss() }
                    return false
                }
                return consumed ? nil : event
            }
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                Task { @MainActor in self?.dismiss() }
            }
        }
        private func removeMonitors() {
            if let localMonitor { NSEvent.removeMonitor(localMonitor) }
            if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
            localMonitor = nil; globalMonitor = nil
        }
    }
}
private final class PopoverAnchorView: NSView {
    var willDetach: (() -> Void)?
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { willDetach?() }
        super.viewWillMove(toWindow: newWindow)
    }
}

private final class PopoverPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
