import AppKit
import Carbon
import SwiftUI
import PloegKit

struct CaptureHotKey: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt

    static let defaultArea = CaptureHotKey(keyCode: UInt32(kVK_ANSI_2), modifiers: defaultModifiers)
    static let defaultRepeatArea = CaptureHotKey(keyCode: UInt32(kVK_ANSI_R), modifiers: defaultModifiers)
    static let defaultScreen = CaptureHotKey(keyCode: UInt32(kVK_ANSI_F), modifiers: defaultModifiers)

    private static let defaultModifiers = NSEvent.ModifierFlags([.command, .shift]).rawValue

    var modifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifiers).intersection([.command, .option, .control, .shift])
    }

    var carbonModifiers: UInt32 {
        var result: UInt32 = 0
        if modifierFlags.contains(.command) { result |= UInt32(cmdKey) }
        if modifierFlags.contains(.option) { result |= UInt32(optionKey) }
        if modifierFlags.contains(.control) { result |= UInt32(controlKey) }
        if modifierFlags.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }

    var displayName: String {
        var value = ""
        if modifierFlags.contains(.control) { value += "⌃" }
        if modifierFlags.contains(.option) { value += "⌥" }
        if modifierFlags.contains(.shift) { value += "⇧" }
        if modifierFlags.contains(.command) { value += "⌘" }
        return value + Self.keyName(for: keyCode)
    }

    var menuKeyEquivalent: String? {
        Self.menuKeyEquivalents[keyCode]
    }

    static func from(event: NSEvent) -> CaptureHotKey? {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard !event.isARepeat,
              flags.contains(.command) || flags.contains(.option) || flags.contains(.control),
              keyNames[UInt32(event.keyCode)] != nil else { return nil }
        return CaptureHotKey(keyCode: UInt32(event.keyCode), modifiers: flags.rawValue)
    }

    private static func keyName(for keyCode: UInt32) -> String {
        keyNames[keyCode] ?? "Key (keyCode)"
    }

    private static let keyNames: [UInt32: String] = [
        UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_B): "B", UInt32(kVK_ANSI_C): "C",
        UInt32(kVK_ANSI_D): "D", UInt32(kVK_ANSI_E): "E", UInt32(kVK_ANSI_F): "F",
        UInt32(kVK_ANSI_G): "G", UInt32(kVK_ANSI_H): "H", UInt32(kVK_ANSI_I): "I",
        UInt32(kVK_ANSI_J): "J", UInt32(kVK_ANSI_K): "K", UInt32(kVK_ANSI_L): "L",
        UInt32(kVK_ANSI_M): "M", UInt32(kVK_ANSI_N): "N", UInt32(kVK_ANSI_O): "O",
        UInt32(kVK_ANSI_P): "P", UInt32(kVK_ANSI_Q): "Q", UInt32(kVK_ANSI_R): "R",
        UInt32(kVK_ANSI_S): "S", UInt32(kVK_ANSI_T): "T", UInt32(kVK_ANSI_U): "U",
        UInt32(kVK_ANSI_V): "V", UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_X): "X",
        UInt32(kVK_ANSI_Y): "Y", UInt32(kVK_ANSI_Z): "Z",
        UInt32(kVK_ANSI_0): "0", UInt32(kVK_ANSI_1): "1", UInt32(kVK_ANSI_2): "2",
        UInt32(kVK_ANSI_3): "3", UInt32(kVK_ANSI_4): "4", UInt32(kVK_ANSI_5): "5",
        UInt32(kVK_ANSI_6): "6", UInt32(kVK_ANSI_7): "7", UInt32(kVK_ANSI_8): "8",
        UInt32(kVK_ANSI_9): "9", UInt32(kVK_Space): "Space", UInt32(kVK_Return): "Return",
        UInt32(kVK_Tab): "Tab", UInt32(kVK_LeftArrow): "←", UInt32(kVK_RightArrow): "→",
        UInt32(kVK_UpArrow): "↑", UInt32(kVK_DownArrow): "↓",
        UInt32(kVK_F1): "F1", UInt32(kVK_F2): "F2", UInt32(kVK_F3): "F3",
        UInt32(kVK_F4): "F4", UInt32(kVK_F5): "F5", UInt32(kVK_F6): "F6",
        UInt32(kVK_F7): "F7", UInt32(kVK_F8): "F8", UInt32(kVK_F9): "F9",
        UInt32(kVK_F10): "F10", UInt32(kVK_F11): "F11", UInt32(kVK_F12): "F12"
    ]

    private static let menuKeyEquivalents: [UInt32: String] = [
        UInt32(kVK_ANSI_A): "a", UInt32(kVK_ANSI_B): "b", UInt32(kVK_ANSI_C): "c",
        UInt32(kVK_ANSI_D): "d", UInt32(kVK_ANSI_E): "e", UInt32(kVK_ANSI_F): "f",
        UInt32(kVK_ANSI_G): "g", UInt32(kVK_ANSI_H): "h", UInt32(kVK_ANSI_I): "i",
        UInt32(kVK_ANSI_J): "j", UInt32(kVK_ANSI_K): "k", UInt32(kVK_ANSI_L): "l",
        UInt32(kVK_ANSI_M): "m", UInt32(kVK_ANSI_N): "n", UInt32(kVK_ANSI_O): "o",
        UInt32(kVK_ANSI_P): "p", UInt32(kVK_ANSI_Q): "q", UInt32(kVK_ANSI_R): "r",
        UInt32(kVK_ANSI_S): "s", UInt32(kVK_ANSI_T): "t", UInt32(kVK_ANSI_U): "u",
        UInt32(kVK_ANSI_V): "v", UInt32(kVK_ANSI_W): "w", UInt32(kVK_ANSI_X): "x",
        UInt32(kVK_ANSI_Y): "y", UInt32(kVK_ANSI_Z): "z",
        UInt32(kVK_ANSI_0): "0", UInt32(kVK_ANSI_1): "1", UInt32(kVK_ANSI_2): "2",
        UInt32(kVK_ANSI_3): "3", UInt32(kVK_ANSI_4): "4", UInt32(kVK_ANSI_5): "5",
        UInt32(kVK_ANSI_6): "6", UInt32(kVK_ANSI_7): "7", UInt32(kVK_ANSI_8): "8",
        UInt32(kVK_ANSI_9): "9", UInt32(kVK_Space): " ", UInt32(kVK_Return): "\r",
        UInt32(kVK_Tab): "\t", UInt32(kVK_LeftArrow): String(Character(UnicodeScalar(NSLeftArrowFunctionKey)!)),
        UInt32(kVK_RightArrow): String(Character(UnicodeScalar(NSRightArrowFunctionKey)!)),
        UInt32(kVK_UpArrow): String(Character(UnicodeScalar(NSUpArrowFunctionKey)!)),
        UInt32(kVK_DownArrow): String(Character(UnicodeScalar(NSDownArrowFunctionKey)!))
    ]
}

extension Notification.Name {
    static let captureHotKeysDidChange = Notification.Name("captureHotKeysDidChange")
}

enum CaptureHotKeyAction {
    case area
    case repeatArea
    case screen
}

@MainActor
final class HotKeySettings: ObservableObject {
    static let shared = HotKeySettings()

    @Published var area: CaptureHotKey { didSet { save() } }
    @Published var repeatArea: CaptureHotKey { didSet { save() } }
    @Published var screen: CaptureHotKey { didSet { save() } }

    private let defaults = UserDefaults.standard
    private var isLoading = true

    private init() {
        area = Self.load("areaHotKey") ?? .defaultArea
        repeatArea = Self.load("repeatAreaHotKey") ?? .defaultRepeatArea
        screen = Self.load("screenHotKey") ?? .defaultScreen
        isLoading = false
    }

    func reset() {
        area = .defaultArea
        repeatArea = .defaultRepeatArea
        screen = .defaultScreen
    }

    func conflictDescription(for candidate: CaptureHotKey, excluding action: CaptureHotKeyAction) -> String? {
        let shortcuts: [(CaptureHotKeyAction, String, CaptureHotKey)] = [
            (.area, "Capture area", area),
            (.repeatArea, "Previous area", repeatArea),
            (.screen, "Full screen", screen)
        ]
        guard let conflict = shortcuts.first(where: { $0.0 != action && $0.2 == candidate }) else { return nil }
        return "\(candidate.displayName) is already assigned to \(conflict.1)."
    }

    private static func load(_ key: String) -> CaptureHotKey? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(CaptureHotKey.self, from: data)
    }

    private func save() {
        guard !isLoading else { return }
        let encoder = JSONEncoder()
        defaults.set(try? encoder.encode(area), forKey: "areaHotKey")
        defaults.set(try? encoder.encode(repeatArea), forKey: "repeatAreaHotKey")
        defaults.set(try? encoder.encode(screen), forKey: "screenHotKey")
        NotificationCenter.default.post(name: .captureHotKeysDidChange, object: nil)
    }
}

struct HotKeyRecorder: NSViewRepresentable {
    @Binding var hotKey: CaptureHotKey
    let validationMessage: (CaptureHotKey) -> String?
    let onFeedback: (String?) -> Void

    func makeNSView(context: Context) -> RecorderView {
        let view = RecorderView()
        view.onShortcut = { shortcut in
            if let message = validationMessage(shortcut) {
                NSSound.beep()
                onFeedback(message)
                return
            }
            hotKey = shortcut
            onFeedback(nil)
        }
        view.onInvalidShortcut = { onFeedback("Shortcuts must include Command, Option, or Control and a supported key.") }
        view.hotKey = hotKey
        return view
    }

    func updateNSView(_ view: RecorderView, context: Context) {
        view.hotKey = hotKey
        view.onShortcut = { shortcut in
            if let message = validationMessage(shortcut) {
                NSSound.beep()
                onFeedback(message)
                return
            }
            hotKey = shortcut
            onFeedback(nil)
        }
        view.onInvalidShortcut = { onFeedback("Shortcuts must include Command, Option, or Control and a supported key.") }
        view.needsDisplay = true
    }

    final class RecorderView: NSView {
        var hotKey = CaptureHotKey.defaultArea
        var onShortcut: ((CaptureHotKey) -> Void)?
        var onInvalidShortcut: (() -> Void)?
        private var isRecording = false

        override var acceptsFirstResponder: Bool { true }
        override var intrinsicContentSize: NSSize { NSSize(width: 136, height: 36) }

        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
            isRecording = true
            needsDisplay = true
        }

        override func resignFirstResponder() -> Bool {
            isRecording = false
            needsDisplay = true
            return super.resignFirstResponder()
        }

        override func keyDown(with event: NSEvent) {
            if event.keyCode == UInt16(kVK_Escape) {
                isRecording = false
                window?.makeFirstResponder(nil)
            } else if let shortcut = CaptureHotKey.from(event: event) {
                onShortcut?(shortcut)
                isRecording = false
                window?.makeFirstResponder(nil)
            } else {
                NSSound.beep()
                onInvalidShortcut?()
            }
            needsDisplay = true
        }

        override func draw(_ dirtyRect: NSRect) {
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
            (isRecording ? PloegTheme.accentSoftNS : PloegTheme.surfaceNS).setFill()
            path.fill()
            (isRecording ? PloegTheme.accentNS : PloegTheme.lineNS).setStroke()
            path.stroke()

            let text = isRecording ? "Type shortcut" : hotKey.displayName
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13, weight: .medium),
                .foregroundColor: PloegTheme.inkNS
            ]
            let size = text.size(withAttributes: attributes)
            text.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2), withAttributes: attributes)
        }
    }
}
