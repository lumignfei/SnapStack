import AppKit
import QuartzCore

/// Morph a cached surface, not a live SwiftUI layout. Only the two endpoints
/// are laid out; Core Animation interpolates the outline between them.
@MainActor
final class BarSurfaceTransition {
    private var completion: (() -> Void)?
    private var task: Task<Void, Never>?

    static func snapshot(_ view: NSView?) -> CGImage? {
        guard let view else { return nil }
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        return bitmap.cgImage
    }

    func finish() {
        task?.cancel()
        task = nil
        let action = completion
        completion = nil
        action?()
    }

    func start(panel: NSPanel, content: NSView, from: NSRect, to: NSRect,
               oldImage: CGImage, newImage: CGImage) {
        finish()
        let duration = 0.26
        let union = from.union(to).insetBy(dx: -16, dy: -16)
        let oldRect = from.offsetBy(dx: -union.minX, dy: -union.minY)
        let newRect = to.offsetBy(dx: -union.minX, dy: -union.minY)
        let surface = NSView(frame: NSRect(origin: .zero, size: union.size))
        surface.wantsLayer = true
        guard let root = surface.layer else { return }
        let oldRadius: CGFloat = from.width > 100 ? 28 : 18
        let newRadius: CGFloat = to.width > 100 ? 28 : 18
        let oldPath = CGPath(roundedRect: oldRect, cornerWidth: oldRadius, cornerHeight: oldRadius, transform: nil)
        let newPath = CGPath(roundedRect: newRect, cornerWidth: newRadius, cornerHeight: newRadius, transform: nil)
        let shell = CAShapeLayer()
        shell.path = newPath
        shell.fillColor = NSColor.white.cgColor
        shell.shadowColor = NSColor.black.cgColor
        shell.shadowOpacity = 0.15
        shell.shadowRadius = 8
        shell.shadowOffset = CGSize(width: 0, height: -2)
        shell.shadowPath = newPath
        root.addSublayer(shell)

        let images = CALayer()
        images.frame = surface.bounds
        let mask = CAShapeLayer()
        mask.path = newPath
        images.mask = mask
        root.addSublayer(images)
        let old = CALayer()
        old.frame = oldRect
        old.contents = oldImage
        old.opacity = 0
        images.addSublayer(old)
        let new = CALayer()
        new.frame = newRect
        new.contents = newImage
        images.addSublayer(new)

        let border = CAShapeLayer()
        border.path = newPath
        border.fillColor = nil
        border.strokeColor = NSColor(calibratedRed: 0.376, green: 0.486, blue: 0.608, alpha: 0.15).cgColor
        border.lineWidth = 1
        root.addSublayer(border)

        // No events reach a half-collapsed control. Global capture can still
        // interrupt, committing the endpoint and hiding this surface first.
        let hadShadow = panel.hasShadow
        panel.ignoresMouseEvents = true
        panel.hasShadow = false
        panel.contentView = surface
        panel.setFrame(union, display: false)
        completion = { [weak panel] in
            guard let panel else { return }
            panel.contentView = content
            panel.setFrame(to, display: false)
            content.frame = NSRect(origin: .zero, size: to.size)
            panel.hasShadow = hadShadow
            panel.ignoresMouseEvents = false
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (layer, key) in [(shell, "path"), (shell, "shadowPath"), (mask, "path"), (border, "path")] {
            let animation = CABasicAnimation(keyPath: key)
            animation.fromValue = oldPath
            animation.toValue = newPath
            animation.duration = duration
            animation.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 0.8, 0.25, 1)
            layer.add(animation, forKey: key)
        }
        // Stagger the content so old and new icons never overlap, while the
        // background keeps moving continuously for the full duration.
        let outgoing = CAKeyframeAnimation(keyPath: "opacity")
        outgoing.values = [1, 0, 0]
        outgoing.keyTimes = [0, 0.30, 1]
        outgoing.duration = duration
        old.add(outgoing, forKey: "outgoing")
        let incoming = CAKeyframeAnimation(keyPath: "opacity")
        incoming.values = [0, 0, 1]
        incoming.keyTimes = [0, 0.40, 1]
        incoming.duration = duration
        new.add(incoming, forKey: "incoming")
        CATransaction.commit()

        task = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(duration)) } catch { return }
            self?.finish()
        }
    }
}
