import AppKit
import SwiftUI

@main
struct NotesChecks {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let wrapped = String(repeating: "自动换行备注", count: 5)
        precondition(NoteEditor.height(for: wrapped, width: 210, maximum: 126) > NoteEditor.height(for: wrapped))
        precondition(NoteEditor.height(for: String(repeating: "很长的备注", count: 100), width: 210, maximum: 126) == 126)
        precondition(NoteEditor.height(for: "") == 36)
        precondition(NoteEditor.height(for: "一行备注") == 36)
        precondition(NoteEditor.height(for: "第一行\n第二行") > 36)
        precondition(NoteEditor.height(for: String(repeating: "长备注自动换行", count: 100)) == 76)
        precondition(NoteEditor.height(for: "缩回一行") == 36)
        precondition(ScreenshotNote.pasteText(" \n \t", imageNumber: 1) == nil)
        precondition(ScreenshotNote.pasteText("  保存没反应\n第二行🙂  ", imageNumber: 3) == "图片 3：保存没反应\n第二行🙂")
        precondition(ScreenshotNote.pasteText("123", imageNumber: 1) == "图片 1：123")
        precondition(ScreenshotNote.pasteText("456", imageNumber: 3, followsNote: true) == "\n图片 3：456")
        precondition(ScreenshotNote.pasteText(" ", imageNumber: 2, followsNote: true) == nil)
        let editor = PlaceholderTextView(frame: NSRect(x: 0, y: 0, width: 480, height: 76))
        var submits = 0
        editor.onSubmit = { _ in submits += 1 }
        func enter(_ modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
                             timestamp: 0, windowNumber: 0, context: nil,
                             characters: "\r", charactersIgnoringModifiers: "\r",
                             isARepeat: false, keyCode: 36)!
        }
        editor.string = "123"
        editor.keyDown(with: enter())
        precondition(submits == 1 && editor.string == "123")
        editor.setSelectedRange(NSRange(location: 3, length: 0))
        editor.keyDown(with: enter(.shift))
        precondition(submits == 1 && editor.string.contains("\n"))
        editor.setMarkedText("zhong", selectedRange: NSRange(location: 5, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        editor.keyDown(with: enter())
        precondition(submits == 1)
        print("PASS: Return submits, Shift-Return adds newline, marked input does not submit")
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 16, pixelsHigh: 16, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let image = NSImage(size: NSSize(width: 16, height: 16))
        image.addRepresentation(bitmap)
        let firstURL = temporary.appendingPathComponent("first.png")
        let secondURL = temporary.appendingPathComponent("second.png")
        try bitmap.representation(using: .png, properties: [:])!.write(to: firstURL)
        try FileManager.default.copyItem(at: firstURL, to: secondURL)
        let first = ScreenshotItem(id: UUID(), fileURL: firstURL, thumbnail: image)
        let second = ScreenshotItem(id: UUID(), fileURL: secondURL, thumbnail: image)
        let state = CaptureState(items: [first, second])
        let mark = ImageMark(tool: .arrow, points: [CGPoint(x: 0.1, y: 0.2), CGPoint(x: 0.8, y: 0.7)], color: 0, width: 0.01)
        let sourceBytes = try Data(contentsOf: firstURL)
        state.addMark(mark, for: first.id)
        state.undoMark(for: first.id)
        precondition(state.items[0].marks.isEmpty && state.items[0].redoMarks.count == 1)
        state.redoMark(for: first.id)
        precondition(state.items[0].marks.count == 1)
        let rendered = MarkRenderer.export(url: firstURL, marks: state.items[0].marks)!
        precondition(rendered.representations[0].pixelsWide == 16)
        let unchangedBytes = try Data(contentsOf: firstURL)
        precondition(unchangedBytes == sourceBytes)
        for tool in MarkTool.allCases {
            var sample = mark; sample.tool = tool; sample.text = "Test"
            precondition(MarkRenderer.export(url: firstURL, marks: [sample]) != nil)
        }
        state.setNote("只备注第一张\n第二行🙂", for: first.id)
        state.editingNoteID = first.id
        state.move(first.id, beforeOrAfter: second.id)
        precondition(state.items[1].marks.count == 1 && state.items[0].marks.isEmpty)
        precondition(state.items[1].id == first.id && state.items[1].note == "只备注第一张\n第二行🙂")
        precondition(state.items[0].note.isEmpty && state.editingNoteID == first.id)
        precondition(ScreenshotNote.pasteText(state.items[1].note, imageNumber: 2)!.hasPrefix("图片 2："))
        print("PASS: optional notes, Unicode, reordered identity and numbering")

        // Receive actual image/text pasteboard formats into a native rich-text editor,
        // without touching the user's general clipboard or sending keystrokes.
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let receiver = NSTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 300))
        receiver.isRichText = true
        receiver.importsGraphics = true
        for (index, item) in state.items.enumerated() {
            board.clearContents()
            precondition(board.writeObjects([image]))
            receiver.setSelectedRange(NSRange(location: receiver.string.utf16.count, length: 0))
            precondition(receiver.readSelection(from: board))
            if let note = ScreenshotNote.pasteText(item.note, imageNumber: index + 1) {
                board.clearContents()
                precondition(board.setString(note, forType: .string))
                receiver.setSelectedRange(NSRange(location: receiver.string.utf16.count, length: 0))
                precondition(receiver.readSelection(from: board))
            }
        }
        var attachments = 0
        receiver.textStorage!.enumerateAttribute(.attachment, in: NSRange(location: 0, length: receiver.textStorage!.length)) { value, _, _ in
            if value is NSTextAttachment { attachments += 1 }
        }
        precondition(attachments == 2)
        precondition(receiver.string == "\u{fffc}\u{fffc}图片 2：只备注第一张\n第二行🙂")
        print("PASS: native receiver preserves two images and only the selected note")
        state.setNote("另一张独立备注", for: second.id)
        for _ in 0..<4 {
            state.move(first.id, beforeOrAfter: second.id)
            precondition(state.items.first(where: { $0.id == first.id })!.note == "只备注第一张\n第二行🙂")
            precondition(state.items.first(where: { $0.id == second.id })!.note == "另一张独立备注")
            precondition(state.editingNoteID == first.id)
        }
        state.setNote("", for: second.id)
        print("PASS: repeated reordering keeps both notes and the editor bound to image UUIDs")
        state.remove(first.id)
        precondition(state.editingNoteID == nil && state.items.count == 1 && state.items[0].note.isEmpty)
        state.setNote("temporary", for: second.id)
        state.clear()
        precondition(state.items.isEmpty && state.editingNoteID == nil)
        state.cleanup()
        print("PASS: delete/clear remove the matching notes")
    }
}
