import CoreGraphics

// Header, thumbnail/empty content and outer padding; optional editor and errors
// share these exact dimensions with the hosting panel.
enum ScreenshotQueueLayout {
    static func size(isEmpty: Bool, showsNote: Bool, noteHeight: CGFloat = 36, showsError: Bool = false) -> CGSize {
        CGSize(width: 540, height: (isEmpty ? 180 : 198)
               + (!isEmpty && showsNote ? 63 + noteHeight : 0)
               + (showsError ? 46 : 0))
    }
}
