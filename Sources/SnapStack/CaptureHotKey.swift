import Carbon
import Foundation

@MainActor
final class CaptureHotKey {
    private let onPressed: () -> Void
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    init(onPressed: @escaping () -> Void) { self.onPressed = onPressed }

    func register() throws {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard result == noErr, id.signature == 0x534E4150, id.id == 1 else {
                return OSStatus(eventNotHandledErr)
            }
            let service = Unmanaged<CaptureHotKey>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { service.onPressed() }
            return noErr
        }, 1, &eventType, context, &handlerRef)
        guard installed == noErr else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(installed)) }
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_S), UInt32(controlKey | shiftKey),
            EventHotKeyID(signature: 0x534E4150, id: 1), GetApplicationEventTarget(),
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
