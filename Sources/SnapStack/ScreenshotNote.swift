import Foundation

enum ScreenshotNote {
    static func pasteText(_ note: String, imageNumber: Int, followsNote: Bool = false) -> String? {
        let content = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return nil }
        return (followsNote ? "\n" : "") + "图片 \(imageNumber)：\(content)"
    }
}
