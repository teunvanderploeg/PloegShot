import AppKit
import CoreGraphics
import ScreenCaptureKit

@MainActor
final class CaptureCoordinator {
    private var selectionWindows: [SelectionWindow] = []
    private var escapeMonitor: Any?
    private var previewStacks: [CGDirectDisplayID: [PreviewPanelController]] = [:]
    private var previewOffsets: [CGDirectDisplayID: Int] = [:]
    private var editorController: EditorWindowController?
    private var hiddenEditorWindows: [NSWindow] = []
    private var previouslyActiveApplication: NSRunningApplication?
    private var lastAreaSelection: ScreenSelection?
    private var activeCaptureMode: CaptureMode = .area
    private var didLoadSavedArea = false
    private var activeCaptureSession: UUID?
    private var cursorWasPushed = false
    private var screenObserver: NSObjectProtocol?

    init() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.activeCaptureSession == nil else { return }
                self.layoutAllPreviews()
            }
        }
    }

    deinit {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    }

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
            var result: (image: NSImage, screen: NSScreen)?
            var captureError: Error?
            do { result = try await ScreenCapturer.capture(selection) }
            catch { captureError = error }
            guard self.activeCaptureSession == sessionID else { return }
            self.restoreEditorWindows()
            self.setPreviewsVisible(true)
            self.activeCaptureSession = nil
            guard let result else {
                self.showCaptureError(captureError ?? ScreenCaptureError.captureFailed, mode: self.activeCaptureMode)
                return
            }
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
            onNewer: { [weak self] controller in self?.changePreviewPage(for: controller, direction: -1) },
            onOlder: { [weak self] controller in self?.changePreviewPage(for: controller, direction: 1) },
            onClose: { [weak self] controller in
                self?.removePreview(controller)
            }
        )
        previewStacks[displayID, default: []].insert(controller, at: 0)
        previewOffsets[displayID] = 0
        layoutPreviews(on: displayID)
    }

    private func removePreview(_ controller: PreviewPanelController) {
        guard let displayID = previewStacks.first(where: { $0.value.contains { $0 === controller } })?.key else { return }
        previewStacks[displayID]?.removeAll { $0 === controller }
        if previewStacks[displayID]?.isEmpty == true {
            previewStacks.removeValue(forKey: displayID)
            previewOffsets.removeValue(forKey: displayID)
        } else {
            layoutPreviews(on: displayID)
        }
    }

    private func layoutPreviews(on displayID: CGDirectDisplayID) {
        guard let stack = previewStacks[displayID],
              let screen = NSScreen.screens.first(where: { $0.displayID == displayID }) ?? NSScreen.main else { return }
        let page = PreviewStackPage(total: stack.count, offset: previewOffsets[displayID] ?? 0, visibleHeight: screen.visibleFrame.height)
        previewOffsets[displayID] = page.range.lowerBound
        for (index, controller) in stack.enumerated() {
            if page.range.contains(index) {
                controller.setStackIndex(index - page.range.lowerBound, page: page, on: screen)
                controller.show()
            } else {
                controller.window?.orderOut(nil)
            }
        }
    }

    private func layoutAllPreviews() {
        let connected = Set(NSScreen.screens.compactMap(\.displayID))
        if let destination = NSScreen.main?.displayID {
            for displayID in Array(previewStacks.keys) where !connected.contains(displayID) {
                let moved = previewStacks.removeValue(forKey: displayID) ?? []
                previewStacks[destination, default: []].append(contentsOf: moved)
                previewOffsets.removeValue(forKey: displayID)
            }
        }
        for displayID in previewStacks.keys { layoutPreviews(on: displayID) }
    }

    private func changePreviewPage(for controller: PreviewPanelController, direction: Int) {
        guard let displayID = previewStacks.first(where: { $0.value.contains { $0 === controller } })?.key,
              let stack = previewStacks[displayID],
              let screen = NSScreen.screens.first(where: { $0.displayID == displayID }) ?? NSScreen.main else { return }
        let page = PreviewStackPage(total: stack.count, offset: previewOffsets[displayID] ?? 0, visibleHeight: screen.visibleFrame.height)
        previewOffsets[displayID] = page.range.lowerBound + direction * page.capacity
        layoutPreviews(on: displayID)
    }

    private func setPreviewsVisible(_ visible: Bool) {
        if visible {
            layoutAllPreviews()
        } else {
            previewStacks.values.joined().forEach { $0.window?.orderOut(nil) }
        }
    }

    private func showCaptureError(_ error: Error, mode: CaptureMode) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Couldn't capture screenshot"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "Try Again")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { startCapture(mode) }
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
    static func capture(_ selection: CaptureSelection) async throws -> (image: NSImage, screen: NSScreen) {
        if #available(macOS 14.0, *) {
            do { return try await captureWithScreenCaptureKit(selection) }
            catch ScreenCaptureError.invalidSelection { throw ScreenCaptureError.invalidSelection }
            catch { return try captureLegacy(selection) }
        }
        return try captureLegacy(selection)
    }

    @available(macOS 14.0, *)
    private static func captureWithScreenCaptureKit(_ selection: CaptureSelection) async throws -> (image: NSImage, screen: NSScreen) {
        let screen: NSScreen
        switch selection {
        case let .area(area): screen = area.screen
        case let .screen(selectedScreen): screen = selectedScreen
        }
        guard let displayID = screen.displayID else { throw ScreenCaptureError.displayUnavailable }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else { throw ScreenCaptureError.displayUnavailable }

        let configuration = SCStreamConfiguration()
        configuration.width = display.width
        configuration.height = display.height
        configuration.showsCursor = false
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let fullImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        let image = try crop(fullImage, for: selection, screen: screen)
        return (NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)), screen)
    }

    private static func captureLegacy(_ selection: CaptureSelection) throws -> (image: NSImage, screen: NSScreen) {
        switch selection {
        case let .area(area):
            guard let displayID = area.screen.displayID, let fullImage = CGDisplayCreateImage(displayID) else { throw ScreenCaptureError.captureFailed }
            let cropped = try crop(fullImage, for: selection, screen: area.screen)
            return (NSImage(cgImage: cropped, size: NSSize(width: cropped.width, height: cropped.height)), area.screen)
        case let .screen(screen):
            guard let displayID = screen.displayID, let cgImage = CGDisplayCreateImage(displayID) else { throw ScreenCaptureError.captureFailed }
            return (NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height)), screen)
        }
    }

    private static func crop(_ fullDisplayImage: CGImage, for selection: CaptureSelection, screen: NSScreen) throws -> CGImage {
        guard case let .area(area) = selection else { return fullDisplayImage }
        return try crop(fullDisplayImage, area: area.rect, screenSize: screen.frame.size)
    }

    static func crop(_ fullDisplayImage: CGImage, area: CGRect, screenSize: CGSize) throws -> CGImage {
        guard [area.origin.x, area.origin.y, area.width, area.height, screenSize.width, screenSize.height].allSatisfy({ $0.isFinite }),
              screenSize.width > 0, screenSize.height > 0 else { throw ScreenCaptureError.invalidSelection }
        let local = area.standardized
        guard local.width > 0, local.height > 0,
              CGRect(origin: .zero, size: screenSize).contains(local) else { throw ScreenCaptureError.invalidSelection }

        // Crop from a full display image so each monitor's independent scale and
        // global desktop origin cannot affect the selected rectangle.
        let scaleX = CGFloat(fullDisplayImage.width) / screenSize.width
        let scaleY = CGFloat(fullDisplayImage.height) / screenSize.height
        let pixelRect = CGRect(
            x: local.minX * scaleX,
            y: (screenSize.height - local.maxY) * scaleY,
            width: local.width * scaleX,
            height: local.height * scaleY
        ).integral

        let imageBounds = CGRect(x: 0, y: 0, width: fullDisplayImage.width, height: fullDisplayImage.height)
        guard let cropped = fullDisplayImage.cropping(to: pixelRect.intersection(imageBounds)) else {
            throw ScreenCaptureError.invalidSelection
        }
        return cropped
    }
}

enum ScreenCaptureError: LocalizedError {
    case invalidSelection, displayUnavailable, captureFailed

    var errorDescription: String? {
        switch self {
        case .invalidSelection: "The selected area couldn't be captured. Select an area inside one display and try again."
        case .displayUnavailable: "The selected display is no longer available. Choose a connected display and try again."
        case .captureFailed: "Check Screen Recording permission in System Settings, then try again."
        }
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
