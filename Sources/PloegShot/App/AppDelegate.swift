import AppKit
import SwiftUI
import PloegKit

enum PloegShotLaunchRequest: Equatable {
    case menuBarOnly
    case showSettings
    case designPreview

    init(arguments: [String], bundleDesignPreview: Bool = false) {
        if bundleDesignPreview || arguments.contains(where: { $0.hasPrefix("--design-preview") }) {
            self = .designPreview
        } else if arguments.contains("--show-settings") {
            self = .showSettings
        } else {
            self = .menuBarOnly
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let captureCoordinator = CaptureCoordinator()
    private var statusItem: NSStatusItem?
    private var hotKeyObserver: NSObjectProtocol?
    private var settingsWindowController: NSWindowController?
    private var designPreviewEditor: EditorWindowController?
    private let launchRequest = PloegShotLaunchRequest(
        arguments: CommandLine.arguments,
        bundleDesignPreview: Bundle.main.object(forInfoDictionaryKey: "PloegDesignPreview") as? Bool == true
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.applicationIconImage = AppResources.logo
        if launchRequest == .designPreview {
            showDesignPreview()
            return
        }
        configureStatusItem()
        registerHotKeys()
        hotKeyObserver = NotificationCenter.default.addObserver(
            forName: .captureHotKeysDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.registerHotKeys()
                self?.configureMenu()
            }
        }
        if launchRequest == .showSettings {
            presentPrimaryWindow()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        presentPrimaryWindow()
        return false
    }

    /// Opening the app reveals its workspace without requesting a screenshot.
    private func presentPrimaryWindow() {
        let editorWindows = NSApp.orderedWindows + NSApp.windows
        if let editor = editorWindows.first(where: {
            $0.windowController is EditorWindowController && ($0.isVisible || $0.isMiniaturized)
        }) {
            NSApp.activate(ignoringOtherApps: true)
            if editor.isMiniaturized { editor.deminiaturize(nil) }
            editor.makeKeyAndOrderFront(nil)
        } else if launchRequest == .designPreview {
            showDesignPreview()
        } else {
            presentSettings(isDesignPreview: false)
        }
    }

    private func registerHotKeys() {
        HotKeyCenter.shared.registerCaptureShortcuts(
            settings: .shared,
            area: { [weak self] in self?.captureCoordinator.startCapture(.area) },
            repeatArea: { [weak self] in self?.captureCoordinator.startCapture(.repeatArea) },
            screen: { [weak self] in self?.captureCoordinator.startCapture(.screen) }
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let hotKeyObserver { NotificationCenter.default.removeObserver(hotKeyObserver) }
        HotKeyCenter.shared.unregister()
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "PloegShot")
        statusItem = item
        configureMenu()
    }

    private func configureMenu() {
        guard let item = statusItem else { return }
        let settings = HotKeySettings.shared
        let menu = NSMenu()
        let heading = NSMenuItem(title: "PloegShot", action: nil, keyEquivalent: "")
        heading.image = PloegAssets.image(for: .shot)
        heading.image?.size = NSSize(width: 24, height: 24)
        menu.addItem(heading)
        menu.addItem(.separator())
        let capture = menuItem(title: "Capture area", action: #selector(captureArea), hotKey: settings.area)
        capture.target = self
        menu.addItem(capture)
        let repeatArea = menuItem(title: "Capture previous area", action: #selector(capturePreviousArea), hotKey: settings.repeatArea)
        repeatArea.target = self
        menu.addItem(repeatArea)
        let captureScreen = menuItem(title: "Capture full screen", action: #selector(captureScreen), hotKey: settings.screen)
        captureScreen.target = self
        menu.addItem(captureScreen)
        menu.addItem(.separator())
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit PloegShot", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        item.menu = menu
    }

    private func menuItem(title: String, action: Selector, hotKey: CaptureHotKey) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: hotKey.menuKeyEquivalent ?? "")
        item.keyEquivalentModifierMask = hotKey.modifierFlags
        return item
    }

    @objc private func captureArea() { captureCoordinator.startCapture(.area) }
    @objc private func capturePreviousArea() { captureCoordinator.startCapture(.repeatArea) }
    @objc private func captureScreen() { captureCoordinator.startCapture(.screen) }
    @objc private func openSettings() {
        presentSettings(isDesignPreview: false)
    }

    private func presentSettings(isDesignPreview: Bool) {
        if settingsWindowController == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: PloegShotSettingsView(isDesignPreview: isDesignPreview)))
            window.title = "PloegShot Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindowController = NSWindowController(window: window)
        }
        NSApp.activate(ignoringOtherApps: true)
        if settingsWindowController?.window?.isMiniaturized == true {
            settingsWindowController?.window?.deminiaturize(nil)
        }
        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
    }

    private func showDesignPreview() {
        NSApp.setActivationPolicy(.regular)
        if CommandLine.arguments.contains("--design-preview-dark") {
            NSApp.appearance = NSAppearance(named: .darkAqua)
        } else {
            NSApp.appearance = NSAppearance(named: .aqua)
        }
        let bundleMode = Bundle.main.object(forInfoDictionaryKey: "PloegDesignPreviewMode") as? String
        if bundleMode == "settings" || CommandLine.arguments.contains("--design-preview-settings") {
            presentSettings(isDesignPreview: true)
            return
        }
        let document = EditorDocument(image: DesignPreviewImage.make())
        let style = AnnotationStyle(color: NSColor(srgbRed: 36 / 255, green: 91 / 255, blue: 212 / 255, alpha: 1), lineWidth: 6, fontSize: 26)
        document.add(.arrow(start: CGPoint(x: 740, y: 435), end: CGPoint(x: 585, y: 395), style: style))
        document.add(.text("Review this section", at: CGPoint(x: 670, y: 460), style: style))
        document.add(.redact(CGRect(x: 95, y: 176, width: 300, height: 29)))
        document.selectedTool = .arrow
        document.selectedColor = .blue
        let editor = EditorWindowController(document: document)
        designPreviewEditor = editor
        NSApp.activate(ignoringOtherApps: true)
        editor.showWindow(nil)
        editor.window?.makeKeyAndOrderFront(nil)
    }

    @objc private func quitApp() { NSApp.terminate(nil) }
}

/// A local fixture for visual review. It never captures a screen or reads the clipboard.
@MainActor
private enum DesignPreviewImage {
    static func make() -> NSImage {
        let image = NSImage(size: NSSize(width: 960, height: 620))
        image.lockFocus()
        defer { image.unlockFocus() }
        let ink = NSColor(srgbRed: 25 / 255, green: 40 / 255, blue: 63 / 255, alpha: 1)
        let muted = NSColor(srgbRed: 88 / 255, green: 103 / 255, blue: 124 / 255, alpha: 1)
        NSColor(srgbRed: 237 / 255, green: 242 / 255, blue: 248 / 255, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: 960, height: 620).fill()
        NSColor.white.setFill()
        NSBezierPath(roundedRect: NSRect(x: 40, y: 38, width: 880, height: 544), xRadius: 12, yRadius: 12).fill()
        func text(_ value: String, x: CGFloat, y: CGFloat, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = ink) {
            (value as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color])
        }
        text("Project notes", x: 90, y: 510, size: 34, weight: .semibold)
        text("Website refresh · review draft", x: 92, y: 475, size: 18, color: muted)
        text("Design review", x: 92, y: 410, size: 24, weight: .semibold)
        text("Keep navigation clear and actions easy to find.", x: 92, y: 370, size: 19)
        text("Use one type scale and a consistent blue accent.", x: 92, y: 335, size: 19)
        text("Make the smallest controls comfortable to read.", x: 92, y: 300, size: 19)
        text("Internal reference", x: 92, y: 225, size: 21, weight: .semibold)
        text("DRAFT-EXAMPLE-REFERENCE", x: 95, y: 178, size: 20, color: muted)
        text("Next step", x: 92, y: 112, size: 22, weight: .semibold)
        text("Capture, annotate, then copy the result.", x: 92, y: 75, size: 19, color: muted)
        return image
    }
}
