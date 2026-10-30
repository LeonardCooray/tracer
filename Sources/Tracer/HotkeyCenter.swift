import Carbon.HIToolbox
import TracerCore

@MainActor
final class HotkeyCenter {
    nonisolated(unsafe) private static var handlers: [UInt32: () -> Void] = [:]
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var sessionIDs: [UInt32] = []
    private static let signature = OSType(0x5452_4352) // "TRCR"
    private static let sessionBase: UInt32 = 1000

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            let handler = HotkeyCenter.handlers[id.id]
            MainActor.assumeIsolated { handler?() }
            return noErr
        }, 1, &spec, nil, nil)
    }

    @discardableResult
    func register(_ hotkey: Hotkey, id: UInt32, handler: @escaping () -> Void) -> Bool {
        unregister(id: id)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(hotkey.keyCode, hotkey.modifiers, EventHotKeyID(signature: Self.signature, id: id),
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return false }
        refs[id] = ref
        Self.handlers[id] = handler
        return true
    }

    func unregister(id: UInt32) {
        if let ref = refs.removeValue(forKey: id) { UnregisterEventHotKey(ref) }
        Self.handlers[id] = nil
    }

    func registerSessionKeys(capture: Bool, handler: @escaping (SessionKey) -> Void) {
        unregisterSessionKeys()
        var keys: [(Hotkey, SessionKey)] = [
            (Hotkey(keyCode: KeyCode.one, modifiers: 0), .digit(1)),
            (Hotkey(keyCode: KeyCode.two, modifiers: 0), .digit(2)),
            (Hotkey(keyCode: KeyCode.three, modifiers: 0), .digit(3)),
            (Hotkey(keyCode: KeyCode.four, modifiers: 0), .digit(4)),
            (Hotkey(keyCode: KeyCode.five, modifiers: 0), .digit(5)),
            (Hotkey(keyCode: KeyCode.six, modifiers: 0), .digit(6)),
            (Hotkey(keyCode: KeyCode.escape, modifiers: 0), .escape),
            (Hotkey(keyCode: KeyCode.delete, modifiers: 0), .delete),
            (Hotkey(keyCode: KeyCode.forwardDelete, modifiers: 0), .delete),
            (Hotkey(keyCode: KeyCode.z, modifiers: Hotkey.command), .undo),
        ]
        if capture {
            keys += [
                (Hotkey(keyCode: KeyCode.returnKey, modifiers: 0), .returnKey),
                (Hotkey(keyCode: KeyCode.c, modifiers: Hotkey.command), .copy),
                (Hotkey(keyCode: KeyCode.s, modifiers: Hotkey.command), .save),
            ]
        }
        for (i, (hotkey, key)) in keys.enumerated() {
            let id = Self.sessionBase + UInt32(i)
            if register(hotkey, id: id, handler: { handler(key) }) { sessionIDs.append(id) }
        }
    }

    func unregisterSessionKeys() {
        sessionIDs.forEach(unregister(id:))
        sessionIDs.removeAll()
    }
}
