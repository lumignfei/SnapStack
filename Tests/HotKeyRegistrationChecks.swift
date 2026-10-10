import AppKit
import Foundation

@main
struct HotKeyRegistrationChecks {
    @MainActor static func main() throws {
        let capture = CaptureHotKey(action: .capture) {}
        let paste = CaptureHotKey(action: .pasteAll) {}
        defer { capture.unregister(); paste.unregister() }
        try capture.register()
        try paste.register()
        try capture.register() // Repeat registration is harmless.
        print("PASS: A and S registered together")
        for action in CaptureHotKey.Action.allCases {
            let duplicate = CaptureHotKey(action: action) {}
            var rejected = false
            do { try duplicate.register() } catch { rejected = true }
            duplicate.unregister()
            precondition(rejected, "Duplicate registration must fail")
        }
        print("PASS: duplicate conflicts rejected independently")
        capture.unregister()
        try capture.register()
        paste.unregister()
        try paste.register()
        print("PASS: release and re-registration work independently")
    }
}
