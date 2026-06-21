import AppKit
import SwiftUI

final class PreviewPanelController: NSWindowController, NSWindowDelegate {
    static let panelSize = CGSize(width: 320, height: 200)
    static let stackSpacing: CGFloat = 12

    private let targetScreen: NSScreen
    private let onClose: (PreviewPanelController) -> Void

    init(
        image: NSImage,
        screen: NSScreen,
        onCopy: @escaping () -> Void,
        onSave: @escaping () -> Void,
        onEdit: @escaping () -> Void,
        onClose: @escaping (PreviewPanelController) -> Void
    ) {
        self.targetScreen = screen
        self.onClose = onClose
        let visible = screen.visibleFrame
        let panelFrame = CGRect(
            x: visible.minX + 18,
            y: visible.minY + 18,
            width: Self.panelSize.width,
            height: Self.panelSize.height
        )
        let panel = UnconstrainedPreviewPanel(
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

        let root = PreviewView(
            image: image,
            onCopy: onCopy,
            onSave: onSave,
            onEdit: { [weak panel] in
                panel?.close()
                onEdit()
            },
            onClose: { [weak panel] in panel?.close() }
        )
        .frame(width: Self.panelSize.width, height: Self.panelSize.height)
        let hostingController = NSHostingController(rootView: root)
        hostingController.sizingOptions = []
        panel.contentViewController = hostingController
        // Setting the frame again after installing the hosting view prevents its
        // intrinsic size from moving the panel back onto the primary display.
        panel.setFrame(panelFrame, display: false)
        super.init(window: panel)
        panel.delegate = self
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show() { window?.orderFrontRegardless() }
    func windowWillClose(_ notification: Notification) { onClose(self) }

    /// New captures use index zero at the bottom. Older captures move upward,
    /// so every additional screenshot appears below the previous one.
    func setStackIndex(_ index: Int) {
        let visible = targetScreen.visibleFrame
        let origin = CGPoint(
            x: visible.minX + 18,
            y: visible.minY + 18 + CGFloat(index) * (Self.panelSize.height + Self.stackSpacing)
        )
        window?.setFrame(CGRect(origin: origin, size: Self.panelSize), display: true)
    }
}

/// AppKit normally keeps windows inside the visible screen, which causes every
/// item past the top edge to collapse onto the same position. Preview stacks are
/// intentionally allowed to continue off-screen and return as lower cards close.
private final class UnconstrainedPreviewPanel: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

private struct PreviewView: View {
    let image: NSImage
    let onCopy: () -> Void
    let onSave: () -> Void
    let onEdit: () -> Void
    let onClose: () -> Void

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(nsColor: NSColor(calibratedWhite: 0.08, alpha: 1))

                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: geometry.size.width, height: geometry.size.height)

                VStack {
                    HStack {
                        Spacer()
                        closeButton
                    }
                    Spacer()
                    HStack {
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
    }

    private var actionToolbar: some View {
        HStack(spacing: 0) {
            toolbarButton("pencil.tip", "Edit", onEdit)
            separator
            toolbarButton("doc.on.doc", "Copy", onCopy)
            separator
            toolbarButton("square.and.arrow.down", "Save", onSave)
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
