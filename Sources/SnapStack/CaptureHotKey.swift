import Carbon
import Foundation

@MainActor
final class CaptureHotKey {
    enum Action: UInt32, CaseIterable {
        case capture = 1, pasteAll = 2

        var keyCode: UInt32 { UInt32(self == .capture ? kVK_ANSI_A : kVK_ANSI_S) }
        var label: String { self == .capture ? "截图 ⌃⇧A" : "粘贴全部 ⌃⇧S" }
    }

    private let action: Action
    private let onPressed: () -> Void
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    init(action: Action, onPressed: @escaping () -> Void) {
        self.action = action
        self.onPressed = onPressed
    }

    func register() throws {
        guard hotKeyRef == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard result == noErr, id.signature == 0x534E4150 else {
                return OSStatus(eventNotHandledErr)
            }
            let service = Unmanaged<CaptureHotKey>.fromOpaque(context).takeUnretainedValue()
            return MainActor.assumeIsolated {
                guard id.id == service.action.rawValue else { return OSStatus(eventNotHandledErr) }
                service.onPressed()
                return noErr
            }
        }, 1, &eventType, context, &handlerRef)
        guard installed == noErr else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(installed)) }
        let status = RegisterEventHotKey(action.keyCode, UInt32(controlKey | shiftKey),
            EventHotKeyID(signature: 0x534E4150, id: action.rawValue), GetApplicationEventTarget(),
            OptionBits(kEventHotKeyExclusive), &hotKeyRef)
        guard status == noErr else {
            unregister()
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        hotKeyRef = nil
        handlerRef = nil
    }
}
