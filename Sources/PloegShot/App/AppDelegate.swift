import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let captureCoordinator = CaptureCoordinator()
    private var statusItem: NSStatusItem?
    private var hotKeyObserver: NSObjectProtocol?
    private var settingsWindowController: NSWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.applicationIconImage = AppResources.logo
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
        let capture = menuItem(title: "Capture Area", action: #selector(captureArea), hotKey: settings.area)
        capture.target = self
        menu.addItem(capture)
        let repeatArea = menuItem(title: "Capture Previous Area", action: #selector(capturePreviousArea), hotKey: settings.repeatArea)
        repeatArea.target = self
        menu.addItem(repeatArea)
        let captureScreen = menuItem(title: "Capture Full Screen", action: #selector(captureScreen), hotKey: settings.screen)
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
        if settingsWindowController == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: PloegShotSettingsView()))
            window.title = "PloegShot Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindowController = NSWindowController(window: window)
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
    }
    @objc private func quitApp() { NSApp.terminate(nil) }
}
