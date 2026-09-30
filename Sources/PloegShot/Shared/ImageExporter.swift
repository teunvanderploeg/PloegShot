import AppKit
import UniformTypeIdentifiers

enum ImageExporter {
    @discardableResult
    static func copyToClipboard(_ image: NSImage) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.writeObjects([image])
    }

    @discardableResult
    static func save(_ image: NSImage, suggestedName: String = defaultFilename) -> Bool {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = suggestedName
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        do {
            guard let png = image.pngData else { throw CocoaError(.fileWriteUnknown) }
            try png.write(to: url, options: .atomic)
            return true
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
            return false
        }
    }

    /// File URLs support Finder and upload fields; image data supports editors
    /// and messaging apps. Keep the file alive after the preview is dismissed.
    static func dragItemProvider(for image: NSImage) throws -> NSItemProvider {
        guard let png = image.pngData else { throw CocoaError(.fileWriteUnknown) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PloegShot-Drags", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        removeExpiredDragFiles(in: directory)
        let url = directory.appendingPathComponent("PloegShot-\(UUID().uuidString).png")
        try png.write(to: url, options: .atomic)
        let provider = NSItemProvider(object: url as NSURL)
        provider.suggestedName = defaultFilename
        provider.registerFileRepresentation(forTypeIdentifier: UTType.png.identifier, fileOptions: [], visibility: .all) { completion in
            completion(url, false, nil)
            return nil
        }
        provider.registerDataRepresentation(forTypeIdentifier: UTType.png.identifier, visibility: .all) { completion in
            completion(png, nil)
            return nil
        }
        return provider
    }

    private static func removeExpiredDragFiles(in directory: URL) {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.creationDateKey]
        )) ?? []
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        for file in files {
            if let created = try? file.resourceValues(forKeys: [.creationDateKey]).creationDate,
               created < cutoff {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    private static var defaultFilename: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "PloegShot \(formatter.string(from: Date())).png"
    }
}

extension NSImage {
    var pngData: Data? {
        guard let tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffRepresentation) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}
