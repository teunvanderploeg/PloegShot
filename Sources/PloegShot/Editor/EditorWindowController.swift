import AppKit
import PloegKit
import SwiftUI

final class EditorWindowController: NSWindowController {
    convenience init(image: NSImage) {
        self.init(document: EditorDocument(image: image))
    }

    init(document: EditorDocument) {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 1120, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "PloegShot Editor"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.acceptsMouseMovedEvents = true
        window.minSize = CGSize(width: 900, height: 580)
        window.center()
        window.contentViewController = NSHostingController(rootView: EditorView(document: document))
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

private struct EditorView: View {
    @ObservedObject var document: EditorDocument
    @State private var zoomScale: CGFloat?
    @State private var actualZoom: CGFloat = 1
    @State private var feedback: String?

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider().overlay(PloegTheme.line)
            HStack(spacing: 0) {
                toolSidebar
                Divider().overlay(PloegTheme.line)
                canvas
                Divider().overlay(PloegTheme.line)
                inspector
            }
            Divider().overlay(PloegTheme.line)
            bottomBar
        }
        .background(PloegTheme.surface)
        .foregroundStyle(PloegTheme.ink)
        .tint(PloegTheme.accent)
        .task(id: feedback) {
            guard feedback != nil else { return }
            do { try await Task.sleep(nanoseconds: 2_000_000_000) } catch { return }
            feedback = nil
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            PloegAppIcon(.shot, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text("PloegShot").font(.system(size: 15, weight: .semibold))
                Text("\(Int(document.image.size.width)) × \(Int(document.image.size.height)) pixels")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(PloegTheme.muted)
            }

            Spacer(minLength: 12)

            if let feedback {
                Label(feedback, systemImage: feedback.contains("failed") ? "exclamationmark.circle" : "checkmark.circle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(feedback.contains("failed") ? PloegTheme.danger : PloegTheme.success)
            }

            HStack(spacing: 4) {
                iconButton("arrow.uturn.backward", "Undo") { document.undo() }
                    .disabled(!document.canUndo)
                    .keyboardShortcut("z", modifiers: .command)
                iconButton("arrow.uturn.forward", "Redo") { document.redo() }
                    .disabled(!document.canRedo)
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                iconButton("trash", "Clear all annotations") { document.clear() }
                    .disabled(!document.canUndo)
            }

            Divider().frame(height: 24).padding(.horizontal, 4)

            Button { exportImage(save: true) } label: {
                Label("Save", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(PloegSecondaryButtonStyle())
            .keyboardShortcut("s", modifiers: .command)

            Button { exportImage(save: false) } label: {
                Label("Copy image", systemImage: "doc.on.doc")
            }
            .buttonStyle(PloegPrimaryButtonStyle())
            .keyboardShortcut("c", modifiers: [.command, .shift])
        }
        .padding(.leading, 76)
        .padding(.trailing, 20)
        .frame(height: 66)
        .background(PloegTheme.surface)
    }

    private var toolSidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 5) {
                Text("Tools")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(PloegTheme.muted)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 9)

                ForEach(EditorTool.allCases) { tool in
                    Button { document.selectedTool = tool } label: {
                        HStack(spacing: 10) {
                            Image(systemName: tool.systemImage)
                                .font(.system(size: 16, weight: .medium))
                                .frame(width: 20)
                            Text(tool.title)
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(document.selectedTool == tool ? PloegTheme.accent : PloegTheme.ink)
                        .padding(.horizontal, 10)
                        .frame(height: 40)
                        .background(
                            document.selectedTool == tool ? PloegTheme.accentSoft : Color.clear,
                            in: RoundedRectangle(cornerRadius: PloegTheme.controlRadius, style: .continuous)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: PloegTheme.controlRadius))
                    }
                    .buttonStyle(.plain)
                    .help(tool.title)
                    .accessibilityLabel(tool.title)
                    .accessibilityValue(document.selectedTool == tool ? "Selected" : "")
                }
            }
            .padding(.vertical, 20)
            .padding(.horizontal, 10)
        }
        .frame(width: 152)
        .background(PloegTheme.sidebar)
    }

    private var canvas: some View {
        AnnotationCanvas(document: document, zoomScale: $zoomScale, actualZoom: $actualZoom)
            .background(Color(red: 0.075, green: 0.106, blue: 0.165))
            .overlay(alignment: .bottomLeading) {
                Label(instruction, systemImage: document.selectedTool.systemImage)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.9))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(red: 0.098, green: 0.157, blue: 0.247).opacity(0.94), in: RoundedRectangle(cornerRadius: 8))
                    .padding(16)
                    .allowsHitTesting(false)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Annotation").font(.system(size: 16, weight: .semibold))
                    Text(document.selectedTool == .select ? "Select and adjust an existing mark." : document.selectedTool.title)
                        .font(.system(size: 12))
                        .foregroundStyle(PloegTheme.muted)
                }

                if document.selectedTool == .select {
                    PloegCard(padding: 14) {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Selection", systemImage: "cursorarrow")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Drag to move. Use the handles to resize. Double-click text to edit it.")
                                .font(.system(size: 12))
                                .foregroundStyle(PloegTheme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                            Button(role: .destructive) { document.deleteSelectedAnnotation() } label: {
                                Label("Delete selection", systemImage: "trash")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .disabled(document.selectedAnnotationIndex == nil)
                            .keyboardShortcut(.delete, modifiers: [])
                        }
                    }
                } else if document.selectedTool == .redact {
                    PloegCard(padding: 14) {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Permanent on export", systemImage: "lock.fill")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Cover sensitive content. Redactions stay editable here and become permanent in copied or saved images.")
                                .font(.system(size: 12))
                                .foregroundStyle(PloegTheme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } else {
                    PloegCard(padding: 14) {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Color").font(.system(size: 13, weight: .semibold))
                            LazyVGrid(columns: Array(repeating: GridItem(.fixed(32), spacing: 10), count: 4), spacing: 10) {
                                ForEach(AnnotationColor.allCases) { color in
                                    Button { document.selectedColor = color } label: {
                                        Circle()
                                            .fill(Color(nsColor: color.color))
                                            .frame(width: 23, height: 23)
                                            .overlay(Circle().stroke(PloegTheme.line, lineWidth: 1))
                                            .padding(4)
                                            .overlay(Circle().stroke(document.selectedColor == color ? PloegTheme.accent : Color.clear, lineWidth: 2))
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(color.rawValue.capitalized)
                                    .accessibilityValue(document.selectedColor == color ? "Selected" : "")
                                }
                            }

                            Divider().overlay(PloegTheme.line)
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text(document.selectedTool == .highlight ? "Marker size" : "Stroke width")
                                    Spacer()
                                    Text("\(Int(document.strokeWidth)) px").monospacedDigit().foregroundStyle(PloegTheme.muted)
                                }
                                .font(.system(size: 12, weight: .medium))
                                Slider(value: $document.strokeWidth, in: 2...18, step: 1)
                                    .accessibilityLabel("Stroke width")
                            }

                            if document.selectedTool == .text {
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        Text("Text size")
                                        Spacer()
                                        Text("\(Int(document.fontSize)) px").monospacedDigit().foregroundStyle(PloegTheme.muted)
                                    }
                                    .font(.system(size: 12, weight: .medium))
                                    Slider(value: $document.fontSize, in: 14...72, step: 1)
                                        .accessibilityLabel("Text size")
                                }
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Keyboard shortcuts")
                        .font(.system(size: 12, weight: .semibold))
                    shortcut("⌘ Z", "Undo")
                    shortcut("⇧ ⌘ Z", "Redo")
                    shortcut("⌘ S", "Save")
                    shortcut("⇧ ⌘ C", "Copy")
                }
                .foregroundStyle(PloegTheme.muted)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 236)
        .background(PloegTheme.sidebar)
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Label("Original resolution on export", systemImage: "photo")
                .font(.system(size: 11))
                .foregroundStyle(PloegTheme.muted)
            Spacer()
            Text("\(Int((actualZoom * 100).rounded()))%")
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(PloegTheme.muted)
                .frame(width: 44, alignment: .trailing)
            iconButton("minus.magnifyingglass", "Zoom out") { zoomScale = max(0.01, actualZoom / 1.25) }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(actualZoom <= 0.01)
            iconButton("plus.magnifyingglass", "Zoom in") { zoomScale = min(8, actualZoom * 1.25) }
                .keyboardShortcut("=", modifiers: .command)
                .disabled(actualZoom >= 8)
            Button("Fit") { zoomScale = nil }
                .keyboardShortcut("0", modifiers: .command)
            Button("100%") { zoomScale = 1 }
                .help("One image pixel per canvas point")
            Divider().frame(height: 16)
            Text("Scroll to pan · pinch to zoom")
                .font(.system(size: 11))
                .foregroundStyle(PloegTheme.muted)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 18)
        .frame(height: 44)
        .background(PloegTheme.surface)
    }

    private var instruction: String {
        switch document.selectedTool {
        case .select: "Click to select · drag to move · double-click text to edit"
        case .text: "Click to place text"
        case .pen, .highlight: "Drag to draw"
        case .redact: "Drag over sensitive content"
        default: "Drag to create"
        }
    }

    private func iconButton(_ icon: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 30, height: 30)
                .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.borderless)
        .help(help)
        .accessibilityLabel(help)
    }

    private func exportImage(save: Bool) {
        do {
            let image = try document.renderedImage()
            if save {
                if ImageExporter.save(image) { feedback = "Saved" }
            } else {
                feedback = ImageExporter.copyToClipboard(image) ? "Copied" : "Copy failed"
            }
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    private func shortcut(_ keys: String, _ label: String) -> some View {
        HStack {
            Text(label).font(.system(size: 12))
            Spacer()
            Text(keys).font(.system(size: 11).monospaced())
        }
    }
}
