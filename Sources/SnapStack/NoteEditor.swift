import AppKit
import SwiftUI

struct NoteEditor: NSViewRepresentable {
    @Binding var text: String
    let label: String
    var isEditable = true
    var onSubmit: () -> Void = {}

    // Match the editor's native glyph layout, including soft wrapping.
    @MainActor static func height(for text: String) -> CGFloat {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        let storage = NSTextStorage(string: text.isEmpty ? " " : text + (text.hasSuffix("\n") ? " " : ""),
                                    attributes: [.font: NSFont.systemFont(ofSize: 13), .paragraphStyle: paragraph])
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 474, height: CGFloat.greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)
        layout.ensureLayout(for: container)
        return min(76, max(36, ceil(layout.usedRect(for: container).height) + 16))
    }

    @MainActor static func commitCurrentInput() {
        guard let editor = NSApp.keyWindow?.firstResponder as? PlaceholderTextView else { return }
        if editor.hasMarkedText() { editor.unmarkText() }
        editor.delegate?.textDidChange?(Notification(name: NSText.didChangeNotification, object: editor))
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        let editor = PlaceholderTextView(frame: .zero)
        editor.isRichText = false
        editor.isEditable = isEditable
        editor.drawsBackground = false
        editor.font = .systemFont(ofSize: 13)
        editor.textColor = NSColor(red: 48/255, green: 58/255, blue: 73/255, alpha: 1)
        editor.insertionPointColor = editor.textColor!
        editor.textContainerInset = NSSize(width: 5, height: 8)
        editor.textContainer?.lineFragmentPadding = 0
        editor.textContainer?.widthTracksTextView = true
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.minSize = .zero
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        editor.defaultParagraphStyle = paragraph
        editor.typingAttributes = [.font: editor.font!, .paragraphStyle: paragraph, .foregroundColor: editor.textColor!]
        editor.allowsUndo = true
        editor.string = text
        editor.setAccessibilityLabel(label)
        editor.delegate = context.coordinator
        editor.onSubmit = { context.coordinator.submit($0) }
        scroll.documentView = editor
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scroll.documentView as? PlaceholderTextView else { return }
        editor.isEditable = isEditable
        // Never overwrite the input method's in-progress composition.
        if !editor.hasMarkedText(), editor.string != text { editor.string = text }
        editor.needsDisplay = true
    }
    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NoteEditor
        init(_ parent: NoteEditor) { self.parent = parent }
        func submit(_ editor: NSTextView) {
            guard !editor.hasMarkedText() else { return }
            parent.text = editor.string
            parent.onSubmit()
        }
        func textDidEndEditing(_ notification: Notification) { textDidChange(notification) }
        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            editor.needsDisplay = true
            if !editor.hasMarkedText() { parent.text = editor.string }
        }
    }
}

final class PlaceholderTextView: NSTextView {
    var onSubmit: ((NSTextView) -> Void)?
    override func keyDown(with event: NSEvent) {
        if (event.keyCode == 36 || event.keyCode == 76), !hasMarkedText(),
           event.modifierFlags.intersection([.shift, .control, .option, .command]) == .shift {
            insertNewline(nil)
            return
        }
        // The IME must consume Return to choose a candidate before submission.
        if (event.keyCode == 36 || event.keyCode == 76), !hasMarkedText(),
           event.modifierFlags.intersection([.shift, .control, .option, .command]).isEmpty {
            onSubmit?(self)
            return
        }
        super.keyDown(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !hasMarkedText(), let textContainer, let font else { return }
        // Use the same native glyph layout and origin as the actual text.
        let storage = NSTextStorage(string: "添加备注…", attributes: [
            .font: font,
            .paragraphStyle: defaultParagraphStyle ?? NSParagraphStyle.default,
            .foregroundColor: NSColor(red: 102/255, green: 116/255, blue: 135/255, alpha: 0.55)
        ])
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: textContainer.size)
        container.lineFragmentPadding = textContainer.lineFragmentPadding
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)
        layout.drawGlyphs(forGlyphRange: layout.glyphRange(for: container), at: textContainerOrigin)
    }
    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        needsDisplay = true
    }
    override func unmarkText() {
        super.unmarkText()
        needsDisplay = true
        delegate?.textDidChange?(Notification(name: NSText.didChangeNotification, object: self))
    }
}
