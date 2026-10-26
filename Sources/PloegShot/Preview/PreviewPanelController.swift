import AppKit
import SwiftUI
import PloegKit

/// A page is sized to the display so every retained preview remains reachable.
struct PreviewStackPage {
    let capacity: Int
    let range: Range<Int>
    let total: Int

    init(total: Int, offset: Int, visibleHeight: CGFloat) {
        self.total = max(0, total)
        capacity = max(1, Int((max(0, visibleHeight - 36) + PreviewPanelController.stackSpacing)
            / (PreviewPanelController.panelSize.height + PreviewPanelController.stackSpacing)))
        let lastPage = self.total == 0 ? 0 : ((self.total - 1) / capacity) * capacity
        let start = min(max(0, offset / capacity * capacity), lastPage)
        range = start..<min(start + capacity, self.total)
    }

    var hasNewer: Bool { range.lowerBound > 0 }
    var hasOlder: Bool { range.upperBound < total }
    var label: String { "\(range.lowerBound + 1)–\(range.upperBound) of \(total)" }
}

private final class PreviewState: ObservableObject {
    weak var controller: PreviewPanelController?
    @Published var page = PreviewStackPage(total: 1, offset: 0, visibleHeight: 200)
    @Published var showsNavigation = false
}

final class PreviewPanelController: NSWindowController, NSWindowDelegate {
    static let panelSize = CGSize(width: 320, height: 200)
    static let stackSpacing: CGFloat = 12

    private let onClose: (PreviewPanelController) -> Void
    private let state = PreviewState()

    init(
        image: NSImage,
        screen: NSScreen,
        onCopy: @escaping () -> Bool,
        onSave: @escaping () -> Bool,
        onEdit: @escaping () -> Void,
        onNewer: @escaping (PreviewPanelController) -> Void,
        onOlder: @escaping (PreviewPanelController) -> Void,
        onClose: @escaping (PreviewPanelController) -> Void
    ) {
        self.onClose = onClose
        let visible = screen.visibleFrame
        let panelFrame = CGRect(
            x: visible.minX + 18,
            y: visible.minY + 18,
            width: Self.panelSize.width,
            height: Self.panelSize.height
        )
        let panel = NSPanel(
            contentRect: panelFrame,
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.minSize = Self.panelSize
        panel.maxSize = Self.panelSize
        panel.contentMinSize = Self.panelSize
        panel.contentMaxSize = Self.panelSize

        let previewState = state
        let root = PreviewView(
            image: image,
            state: state,
            onCopy: onCopy,
            onSave: onSave,
            onEdit: { [weak panel] in
                panel?.close()
                onEdit()
            },
            onClose: { [weak panel] in panel?.close() },
            onNewer: { [weak previewState] in
                if let controller = previewState?.controller { onNewer(controller) }
            },
            onOlder: { [weak previewState] in
                if let controller = previewState?.controller { onOlder(controller) }
            }
        )
        .frame(width: Self.panelSize.width, height: Self.panelSize.height)
        let hostingController = NSHostingController(rootView: root)
        hostingController.sizingOptions = []
        panel.contentViewController = hostingController
        // Setting the frame again after installing the hosting view prevents its
        // intrinsic size from moving the panel back onto the primary display.
        panel.setFrame(panelFrame, display: false)
        super.init(window: panel)
        state.controller = self
        panel.delegate = self
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show() { window?.orderFrontRegardless() }
    func windowWillClose(_ notification: Notification) { onClose(self) }

    func setStackIndex(_ index: Int, page: PreviewStackPage, on screen: NSScreen) {
        state.page = page
        state.showsNavigation = index == 0 && page.total > page.capacity
        let visible = screen.visibleFrame
        let origin = CGPoint(
            x: visible.minX + 18,
            y: visible.minY + 18 + CGFloat(index) * (Self.panelSize.height + Self.stackSpacing)
        )
        window?.setFrame(CGRect(origin: origin, size: Self.panelSize), display: true)
    }
}

private struct PreviewView: View {
    let image: NSImage
    @ObservedObject var state: PreviewState
    let onCopy: () -> Bool
    let onSave: () -> Bool
    let onEdit: () -> Void
    let onClose: () -> Void
    let onNewer: () -> Void
    let onOlder: () -> Void
    @State private var feedback: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                PloegAppIcon(.shot, size: 20)
                if state.showsNavigation {
                    stackNavigation
                } else {
                    Text("Screenshot").font(.system(size: 12, weight: .semibold))
                }
                Spacer(minLength: 0)
                HoverIconButton(icon: "xmark", label: "Close preview", action: onClose)
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(PloegTheme.surface)

            Divider().overlay(PloegTheme.line)
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(PloegTheme.canvas)
                .contentShape(Rectangle())
                .help("Drag this screenshot into another app")
                .accessibilityLabel("Screenshot. Drag to copy into another app.")
                .onDrag {
                    do {
                        return try ImageExporter.dragItemProvider(for: image)
                    } catch {
                        feedback = "Could not prepare PNG file"
                        return NSItemProvider(object: image)
                    }
                } preview: {
                    Image(nsImage: image).resizable().scaledToFit().frame(width: 240, height: 150)
                }
                .overlay(alignment: .bottomLeading) {
                    if let feedback {
                        Text(feedback)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(PloegTheme.ink)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(PloegTheme.surface, in: RoundedRectangle(cornerRadius: 6))
                            .padding(7)
                            .accessibilityLabel(feedback)
                    }
                }
            Divider().overlay(PloegTheme.line)
            HStack(spacing: 6) {
                actionButton("Edit", symbol: "pencil.tip", primary: true, action: onEdit)
                actionButton("Copy", symbol: "doc.on.doc") { feedback = onCopy() ? "Copied" : "Copy failed" }
                actionButton("Save", symbol: "square.and.arrow.down") { if onSave() { feedback = "Saved" } }
            }
            .padding(.horizontal, 8)
            .frame(height: 48)
            .background(PloegTheme.surface)
        }
        .frame(width: PreviewPanelController.panelSize.width, height: PreviewPanelController.panelSize.height)
        .foregroundStyle(PloegTheme.ink)
        .tint(PloegTheme.accent)
        .clipShape(RoundedRectangle(cornerRadius: PloegTheme.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: PloegTheme.cardRadius).stroke(PloegTheme.line))
        .task(id: feedback) {
            guard feedback != nil else { return }
            do { try await Task.sleep(nanoseconds: 2_000_000_000) } catch { return }
            feedback = nil
        }
    }

    private var stackNavigation: some View {
        HStack(spacing: 4) {
            HoverIconButton(icon: "chevron.left", label: "Newer screenshots", action: onNewer)
                .disabled(!state.page.hasNewer)
            Text(state.page.label)
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(PloegTheme.muted)
            HoverIconButton(icon: "chevron.right", label: "Older screenshots", action: onOlder)
                .disabled(!state.page.hasOlder)
        }
    }

    private func actionButton(_ title: String, symbol: String, primary: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 12, weight: .medium))
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .foregroundStyle(primary ? PloegTheme.onAccent : PloegTheme.ink)
                .background(primary ? PloegTheme.accent : PloegTheme.canvas, in: RoundedRectangle(cornerRadius: PloegTheme.controlRadius))
                .overlay(RoundedRectangle(cornerRadius: PloegTheme.controlRadius).stroke(primary ? Color.clear : PloegTheme.line))
                .contentShape(RoundedRectangle(cornerRadius: PloegTheme.controlRadius))
        }
        .buttonStyle(.plain)
        .help(title)
    }
}

private struct HoverIconButton: View {
    let icon: String
    let label: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(PloegTheme.muted)
                .frame(width: 24, height: 24)
                .background(isHovered ? PloegTheme.canvas : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
        .onHover { hovering in
            isHovered = hovering
            (hovering ? NSCursor.pointingHand : NSCursor.arrow).set()
        }
    }
}
