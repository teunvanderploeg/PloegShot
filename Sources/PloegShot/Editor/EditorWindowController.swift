import AppKit
import SwiftUI

final class EditorWindowController: NSWindowController {
    init(image: NSImage) {
        let document = EditorDocument(image: image)
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 1040, height: 660),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "PloegShot Editor"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.acceptsMouseMovedEvents = true
        window.minSize = CGSize(width: 780, height: 500)
        window.center()
        window.contentViewController = NSHostingController(rootView: EditorView(document: document))
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

private struct EditorView: View {
    @ObservedObject var document: EditorDocument

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            HStack(spacing: 0) {
                toolSidebar
                Divider()
                canvas
                Divider()
                inspector
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            Text("PloegShot Editor").font(.system(size: 13, weight: .semibold))
            Text("\(Int(document.image.size.width)) × \(Int(document.image.size.height))")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)

            Spacer()

            HStack(spacing: 2) {
                iconButton("arrow.uturn.backward", "Undo") { document.undo() }
                    .disabled(!document.canUndo)
                    .keyboardShortcut("z", modifiers: .command)
                iconButton("arrow.uturn.forward", "Redo") { document.redo() }
                    .disabled(!document.canRedo)
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                iconButton("trash", "Clear all") { document.clear() }
                    .disabled(!document.canUndo)
            }

            Divider().frame(height: 20).padding(.horizontal, 2)

            Button {
                ImageExporter.copyToClipboard(document.renderedImage())
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])

            Button {
                ImageExporter.save(document.renderedImage())
            } label: {
                Label("Save", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("s", modifiers: .command)
        }
        .controlSize(.small)
        .padding(.leading, 72)
        .padding(.trailing, 10)
        .frame(height: 46)
        .background(.bar)
    }

    private var toolSidebar: some View {
        ScrollView {
            VStack(spacing: 4) {
                Text("TOOLS")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 2)

                ForEach(EditorTool.allCases) { tool in
                    Button {
                        document.selectedTool = tool
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: tool.systemImage)
                                .font(.system(size: 15, weight: .medium))
                                .frame(height: 16)
                            Text(tool.title).font(.system(size: 9, weight: .medium))
                        }
                        .foregroundStyle(document.selectedTool == tool ? Color.white : Color.primary)
                        .frame(width: 52, height: 41)
                        .background(
                            document.selectedTool == tool ? Color.accentColor : Color.clear,
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .help(tool.title)
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 6)
        }
        .frame(width: 66)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var canvas: some View {
        AnnotationCanvas(document: document)
            .padding(18)
            .background(Color(nsColor: NSColor(calibratedWhite: 0.105, alpha: 1)))
            .overlay(alignment: .bottomLeading) {
                Label(instruction, systemImage: document.selectedTool.systemImage)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.72))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(.black.opacity(0.55), in: Capsule())
                    .padding(9)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("STYLE")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            if document.selectedTool == .select {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Select an annotation", systemImage: "cursorarrow")
                        .font(.caption.weight(.medium))
                    Text("Drag to move. Use the handles to resize. Double-click text to edit it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(role: .destructive) {
                        document.deleteSelectedAnnotation()
                    } label: {
                        Label("Delete Selection", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(document.selectedAnnotationIndex == nil)
                    .keyboardShortcut(.delete, modifiers: [])
                }
            } else if document.selectedTool == .redact {
                Label("Draw over sensitive content to permanently hide it.", systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Color").font(.caption.weight(.medium))
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(25), spacing: 7), count: 4), spacing: 7) {
                        ForEach(AnnotationColor.allCases) { color in
                            Button {
                                document.selectedColor = color
                            } label: {
                                Circle()
                                    .fill(Color(nsColor: color.color))
                                    .frame(width: 21, height: 21)
                                    .overlay(Circle().stroke(.white.opacity(0.35)))
                                    .overlay {
                                        if document.selectedColor == color {
                                            Circle().stroke(Color.accentColor, lineWidth: 3).padding(-3)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(document.selectedTool == .highlight ? "Marker size" : "Stroke")
                        Spacer()
                        Text("\(Int(document.strokeWidth)) px").monospacedDigit().foregroundStyle(.secondary)
                    }
                    .font(.caption.weight(.medium))
                    Slider(value: $document.strokeWidth, in: 2...18, step: 1)
                }

                if document.selectedTool == .text {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Text size")
                            Spacer()
                            Text("\(Int(document.fontSize)) px").monospacedDigit().foregroundStyle(.secondary)
                        }
                        .font(.caption.weight(.medium))
                        Slider(value: $document.fontSize, in: 14...72, step: 1)
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 5) {
                shortcut("⌘ Z", "Undo")
                shortcut("⇧ ⌘ Z", "Redo")
                shortcut("⌘ S", "Save")
                shortcut("⇧ ⌘ C", "Copy")
            }

            Spacer()
        }
        .padding(12)
        .frame(width: 170)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var instruction: String {
        switch document.selectedTool {
        case .select: "Click to select • drag to move • double-click text to edit"
        case .text: "Click to place text"
        case .pen, .highlight: "Drag to draw"
        case .redact: "Drag over sensitive content"
        default: "Drag to create"
        }
    }

    private func iconButton(_ icon: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func shortcut(_ keys: String, _ label: String) -> some View {
        HStack {
            Text(keys).font(.caption.monospaced()).foregroundStyle(.secondary)
            Spacer()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}
