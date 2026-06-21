import AppKit
import CoreGraphics
import ScreenCaptureKit

@MainActor
final class CaptureCoordinator {
    private var selectionWindows: [SelectionWindow] = []
    private var escapeMonitor: Any?
    private var previewStacks: [CGDirectDisplayID: [PreviewPanelController]] = [:]
    private var editorController: EditorWindowController?
    private var hiddenEditorWindows: [NSWindow] = []
    private var previouslyActiveApplication: NSRunningApplication?
    private var lastAreaSelection: ScreenSelection?
    private var activeCaptureMode: CaptureMode = .area
    private var didLoadSavedArea = false
    private var activeCaptureSession: UUID?
    private var cursorWasPushed = false

    func startCapture(_ mode: CaptureMode = .area) {
        guard activeCaptureSession == nil else { return }
        loadSavedAreaIfNeeded()
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            showPermissionAlert()
            return
        }

        let sessionID = UUID()
        activeCaptureSession = sessionID
        activeCaptureMode = mode
        previouslyActiveApplication = NSWorkspace.shared.frontmostApplication
        hideEditorWindows()
        setPreviewsVisible(false)
        let reusableState = makeReusableAreaState(for: mode)
        selectionWindows = NSScreen.screens.map { screen in
            SelectionWindow(mode: mode, screen: screen, reusableState: reusableState) { [weak self] selection in
                self?.finishSelection(selection, sessionID: sessionID)
            } onCancel: { [weak self] in
                self?.cancelSelection(sessionID: sessionID)
            }
        }
        selectionWindows.forEach { $0.orderFrontRegardless() }
        selectionWindows.forEach { $0.ignoresMouseEvents = false }

        // Screenshot mode owns input until capture or cancellation. Keeping one
        // overlay key also ensures drag and Escape events do not reach the app
        // underneath, while the remaining overlays block the other displays.
        NSApp.activate(ignoringOtherApps: true)
        let pointerScreen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
        let keyWindow = selectionWindows.first(where: { $0.canConfirmSelection })
            ?? selectionWindows.first(where: { $0.captureScreen == pointerScreen })
            ?? selectionWindows.first
        keyWindow?.makeKeyAndOrderFront(nil)

        NSCursor.crosshair.push()
        cursorWasPushed = true
        NSCursor.crosshair.set()
        selectionWindows.forEach { window in
            if let contentView = window.contentView {
                window.invalidateCursorRects(for: contentView)
            }
        }

        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.cancelSelection(sessionID: sessionID)
                return nil
            }
            if event.keyCode == 36 || event.keyCode == 76 {
                guard let self, case .repeatArea = self.activeCaptureMode else { return event }
                let target = self.selectionWindows.first(where: { $0.isKeyWindow && $0.canConfirmSelection })
                    ?? self.selectionWindows.first(where: { $0.canConfirmSelection })
                target?.confirmSelection()
                return nil
            }
            return event
        }
    }

    private func finishSelection(_ selection: CaptureSelection, sessionID: UUID) {
        guard activeCaptureSession == sessionID, !selectionWindows.isEmpty else { return }
        if case let .area(area) = selection {
            lastAreaSelection = area
            saveArea(area)
        }
        dismissSelectionWindows()

        // Give WindowServer one frame to remove the dimming overlays before capture.
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard let self, self.activeCaptureSession == sessionID else { return }
            let result = await ScreenCapturer.capture(selection)
            guard self.activeCaptureSession == sessionID else { return }
            self.restoreEditorWindows()
            self.setPreviewsVisible(true)
            self.activeCaptureSession = nil
            guard let result else { return }
            self.showPreview(result.image, on: result.screen)
        }
    }

    private func cancelSelection(sessionID: UUID) {
        guard activeCaptureSession == sessionID else { return }
        dismissSelectionWindows()
        restoreEditorWindows()
        setPreviewsVisible(true)
        activeCaptureSession = nil
    }

    private func dismissSelectionWindows() {
        selectionWindows.forEach { $0.orderOut(nil) }
        selectionWindows.removeAll()
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        escapeMonitor = nil
        if cursorWasPushed {
            NSCursor.pop()
            cursorWasPushed = false
        }
    }

    private func makeReusableAreaState(for mode: CaptureMode) -> ReusableAreaState? {
        guard case .repeatArea = mode else { return nil }
        let pointerScreen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main
        let savedDisplayID = lastAreaSelection?.screen.displayID
        guard let targetScreen = NSScreen.screens.first(where: { $0.displayID == savedDisplayID }) ?? pointerScreen else { return nil }
        let proposed = lastAreaSelection?.rect ?? CGRect(
            x: targetScreen.frame.width * 0.2,
            y: targetScreen.frame.height * 0.25,
            width: targetScreen.frame.width * 0.6,
            height: targetScreen.frame.height * 0.5
        )
        let width = min(proposed.width, targetScreen.frame.width)
        let height = min(proposed.height, targetScreen.frame.height)
        let rect = CGRect(
            x: min(max(0, proposed.minX), targetScreen.frame.width - width),
            y: min(max(0, proposed.minY), targetScreen.frame.height - height),
            width: width,
            height: height
        )
        return ReusableAreaState(screen: targetScreen, rect: rect)
    }

    private func saveArea(_ selection: ScreenSelection) {
        let defaults = UserDefaults.standard
        defaults.set(selection.screen.displayID, forKey: "captureArea.displayID")
        defaults.set(selection.rect.minX, forKey: "captureArea.x")
        defaults.set(selection.rect.minY, forKey: "captureArea.y")
        defaults.set(selection.rect.width, forKey: "captureArea.width")
        defaults.set(selection.rect.height, forKey: "captureArea.height")
    }

    private func loadSavedAreaIfNeeded() {
        guard !didLoadSavedArea else { return }
        didLoadSavedArea = true
        let defaults = UserDefaults.standard
        let displayID = CGDirectDisplayID(defaults.integer(forKey: "captureArea.displayID"))
        guard let screen = NSScreen.screens.first(where: { $0.displayID == displayID }) ?? NSScreen.main else { return }
        let rect = CGRect(
            x: defaults.double(forKey: "captureArea.x"),
            y: defaults.double(forKey: "captureArea.y"),
            width: defaults.double(forKey: "captureArea.width"),
            height: defaults.double(forKey: "captureArea.height")
        )
        if rect.width >= 2, rect.height >= 2 { lastAreaSelection = ScreenSelection(screen: screen, rect: rect) }
    }

    private func showPreview(_ image: NSImage, on screen: NSScreen) {
        guard let displayID = screen.displayID else { return }
        let controller = PreviewPanelController(
            image: image,
            screen: screen,
            onCopy: { ImageExporter.copyToClipboard(image) },
            onSave: { ImageExporter.save(image) },
            onEdit: { [weak self] in self?.openEditor(image) },
            onClose: { [weak self] controller in
                self?.removePreview(controller, from: displayID)
            }
        )
        previewStacks[displayID, default: []].insert(controller, at: 0)
        layoutPreviews(on: displayID)
        controller.show()
    }

    private func removePreview(_ controller: PreviewPanelController, from displayID: CGDirectDisplayID) {
        previewStacks[displayID]?.removeAll { $0 === controller }
        if previewStacks[displayID]?.isEmpty == true {
            previewStacks.removeValue(forKey: displayID)
        } else {
            layoutPreviews(on: displayID)
        }
    }

    private func layoutPreviews(on displayID: CGDirectDisplayID) {
        previewStacks[displayID]?.enumerated().forEach { index, controller in
            controller.setStackIndex(index)
        }
    }

    private func setPreviewsVisible(_ visible: Bool) {
        previewStacks.values.joined().forEach { controller in
            if visible {
                controller.show()
            } else {
                controller.window?.orderOut(nil)
            }
        }
    }

    private func hideEditorWindows() {
        hiddenEditorWindows = NSApp.windows.filter { window in
            window.isVisible && window.windowController is EditorWindowController
        }
        hiddenEditorWindows.forEach { $0.orderOut(nil) }
    }

    private func restoreEditorWindows() {
        let previousApp = previouslyActiveApplication
        let wasPloegShotActive = previousApp?.processIdentifier == ProcessInfo.processInfo.processIdentifier

        hiddenEditorWindows.forEach { window in
            if wasPloegShotActive {
                window.orderFront(nil)
            } else {
                // Preserve the editor and its unsaved annotations without placing
                // it over the application the user intended to capture.
                window.orderBack(nil)
            }
        }

        if wasPloegShotActive {
            NSApp.activate(ignoringOtherApps: true)
        } else {
            previousApp?.activate(options: [.activateIgnoringOtherApps])
        }

        hiddenEditorWindows.removeAll()
        previouslyActiveApplication = nil
    }

    private func openEditor(_ image: NSImage) {
        let editor = EditorWindowController(image: image)
        editorController = editor
        editor.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Screen Recording Permission Required"
        alert.informativeText = "Enable PloegShot in System Settings → Privacy & Security → Screen & System Audio Recording, then relaunch the app."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}

struct ScreenSelection {
    let screen: NSScreen
    let rect: CGRect // Screen-local AppKit points, origin at bottom-left.
}

enum ScreenCapturer {
    static func capture(_ selection: CaptureSelection) async -> (image: NSImage, screen: NSScreen)? {
        if #available(macOS 14.0, *), let result = try? await captureWithScreenCaptureKit(selection) {
            return result
        }
        return captureLegacy(selection)
    }

    @available(macOS 14.0, *)
    private static func captureWithScreenCaptureKit(_ selection: CaptureSelection) async throws -> (image: NSImage, screen: NSScreen)? {
        let screen: NSScreen
        switch selection {
        case let .area(area): screen = area.screen
        case let .screen(selectedScreen): screen = selectedScreen
        }
        guard let displayID = screen.displayID else { return nil }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else { return nil }

        let configuration = SCStreamConfiguration()
        configuration.width = display.width
        configuration.height = display.height
        configuration.showsCursor = false
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let fullImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        let image = crop(fullImage, for: selection, screen: screen) ?? fullImage
        return (NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)), screen)
    }

    private static func captureLegacy(_ selection: CaptureSelection) -> (image: NSImage, screen: NSScreen)? {
        switch selection {
        case let .area(area):
            guard let displayID = area.screen.displayID, let fullImage = CGDisplayCreateImage(displayID),
                  let cropped = crop(fullImage, for: selection, screen: area.screen) else { return nil }
            return (NSImage(cgImage: cropped, size: NSSize(width: cropped.width, height: cropped.height)), area.screen)
        case let .screen(screen):
            guard let displayID = screen.displayID, let cgImage = CGDisplayCreateImage(displayID) else { return nil }
            return (NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height)), screen)
        }
    }

    private static func crop(_ fullDisplayImage: CGImage, for selection: CaptureSelection, screen: NSScreen) -> CGImage? {
        guard case let .area(area) = selection else { return fullDisplayImage }
        let local = area.rect.standardized

        // Crop from a full display image so each monitor's independent scale and
        // global desktop origin cannot affect the selected rectangle.
        let scaleX = CGFloat(fullDisplayImage.width) / screen.frame.width
        let scaleY = CGFloat(fullDisplayImage.height) / screen.frame.height
        let pixelRect = CGRect(
            x: local.minX * scaleX,
            y: (screen.frame.height - local.maxY) * scaleY,
            width: local.width * scaleX,
            height: local.height * scaleY
        ).integral

        return fullDisplayImage.cropping(to: pixelRect)
    }
}

private extension NSScreen {
    var displayID: CGDirectDisplayID? {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return CGDirectDisplayID(number.uint32Value)
    }
}
