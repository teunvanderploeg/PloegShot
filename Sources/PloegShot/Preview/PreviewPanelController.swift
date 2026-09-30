import AppKit
import SwiftUI

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
        GeometryReader { geometry in
            ZStack {
                Color(nsColor: NSColor(calibratedWhite: 0.08, alpha: 1))

                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: geometry.size.width, height: geometry.size.height)
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

                VStack {
                    HStack {
                        if state.showsNavigation { stackNavigation }
                        Spacer()
                        closeButton
                    }
                    Spacer()
                    HStack {
                        if let feedback {
                            Text(feedback)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.white)
                                .padding(6)
                                .background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 4))
                                .accessibilityLabel(feedback)
                        }
                        Spacer()
                        actionToolbar
                    }
                }
                .padding(8)
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .task(id: feedback) {
            guard feedback != nil else { return }
            do { try await Task.sleep(nanoseconds: 2_000_000_000) } catch { return }
            feedback = nil
        }
    }

    private var stackNavigation: some View {
        HStack(spacing: 5) {
            toolbarButton("chevron.left", "Newer screenshots", onNewer).disabled(!state.page.hasNewer)
            Text(state.page.label).font(.caption.monospacedDigit()).foregroundStyle(.white)
            toolbarButton("chevron.right", "Older screenshots", onOlder).disabled(!state.page.hasOlder)
        }
        .background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 4))
    }

    private var actionToolbar: some View {
        HStack(spacing: 0) {
            toolbarButton("pencil.tip", "Edit", onEdit)
            separator
            toolbarButton("doc.on.doc", "Copy") { feedback = onCopy() ? "Copied" : "Copy failed" }
            separator
            toolbarButton("square.and.arrow.down", "Save") { if onSave() { feedback = "Saved" } }
        }
        .padding(.horizontal, 3)
        .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 4))
    }

    private var closeButton: some View {
        HoverIconButton(
            icon: "xmark",
            label: "Close",
            size: CGSize(width: 25, height: 25),
            hasPersistentBackground: true,
            action: onClose
        )
    }

    private var separator: some View {
        Rectangle()
            .fill(.white.opacity(0.18))
            .frame(width: 1, height: 15)
    }

    private func toolbarButton(_ icon: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        HoverIconButton(
            icon: icon,
            label: label,
            size: CGSize(width: 30, height: 27),
            hasPersistentBackground: false,
            action: action
        )
    }
}

private struct HoverIconButton: View {
    let icon: String
    let label: String
    let size: CGSize
    let hasPersistentBackground: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(isHovered ? 1 : 0.82))
                .frame(width: size.width, height: size.height)
                .background(backgroundColor, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
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

    private var backgroundColor: Color {
        if hasPersistentBackground {
            return isHovered ? .white.opacity(0.12) : .black.opacity(0.68)
        }
        return isHovered ? .white.opacity(0.09) : .clear
    }
}
