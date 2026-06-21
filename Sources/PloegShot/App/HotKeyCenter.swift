import AppKit
import Carbon

/// Carbon hot keys work while PloegShot is in the background and do not require
/// Accessibility permission. Screen capture permission is requested separately.
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private var hotKeys: [EventHotKeyRef] = []
    private var eventHandler: EventHandlerRef?
    private var actions: [UInt32: () -> Void] = [:]

    private init() {}

    func registerCaptureShortcuts(
        area: @escaping () -> Void,
        repeatArea: @escaping () -> Void,
        screen: @escaping () -> Void
    ) {
        unregister()
        actions = [1: area, 2: repeatArea, 3: screen]

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            guard let event else { return noErr }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            if status == noErr, hotKeyID.signature == HotKeyCenter.signature {
                DispatchQueue.main.async { HotKeyCenter.shared.actions[hotKeyID.id]?() }
            }
            return noErr
        }, 1, &eventType, nil, &eventHandler)

        register(id: 1, keyCode: UInt32(kVK_ANSI_2))
        register(id: 2, keyCode: UInt32(kVK_ANSI_R))
        register(id: 3, keyCode: UInt32(kVK_ANSI_F))
    }

    private func register(id: UInt32, keyCode: UInt32) {
        var reference: EventHotKeyRef?
        let identifier = EventHotKeyID(signature: Self.signature, id: id)
        RegisterEventHotKey(keyCode, UInt32(cmdKey | shiftKey), identifier, GetApplicationEventTarget(), 0, &reference)
        if let reference { hotKeys.append(reference) }
    }

    func unregister() {
        hotKeys.forEach { UnregisterEventHotKey($0) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
        hotKeys.removeAll()
        eventHandler = nil
        actions.removeAll()
    }

    private static let signature: OSType = 0x504C5348 // "PLSH"
}
