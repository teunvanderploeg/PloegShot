import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let captureCoordinator = CaptureCoordinator()
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.applicationIconImage = AppResources.logo
        configureStatusItem()
        HotKeyCenter.shared.registerCaptureShortcuts(
            area: { [weak self] in self?.captureCoordinator.startCapture(.area) },
            repeatArea: { [weak self] in self?.captureCoordinator.startCapture(.repeatArea) },
            screen: { [weak self] in self?.captureCoordinator.startCapture(.screen) }
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotKeyCenter.shared.unregister()
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "PloegShot")

        let menu = NSMenu()
        let capture = NSMenuItem(title: "Capture Area", action: #selector(captureArea), keyEquivalent: "2")
        capture.keyEquivalentModifierMask = [.command, .shift]
        capture.target = self
        menu.addItem(capture)
        let repeatArea = NSMenuItem(title: "Capture Previous Area", action: #selector(capturePreviousArea), keyEquivalent: "r")
        repeatArea.keyEquivalentModifierMask = [.command, .shift]
        repeatArea.target = self
        menu.addItem(repeatArea)
        let captureScreen = NSMenuItem(title: "Capture Full Screen", action: #selector(captureScreen), keyEquivalent: "f")
        captureScreen.keyEquivalentModifierMask = [.command, .shift]
        captureScreen.target = self
        menu.addItem(captureScreen)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit PloegShot", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        item.menu = menu
        statusItem = item
    }

    @objc private func captureArea() { captureCoordinator.startCapture(.area) }
    @objc private func capturePreviousArea() { captureCoordinator.startCapture(.repeatArea) }
    @objc private func captureScreen() { captureCoordinator.startCapture(.screen) }
    @objc private func quitApp() { NSApp.terminate(nil) }
}
