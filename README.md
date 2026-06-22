# PloegShot

PloegShot is a native macOS screenshot utility built with SwiftUI and AppKit.

## MVP features

- Configurable global shortcuts for area, reusable previous-area, and full-display capture
- Multi-display selection overlays and Retina-resolution capture
- Floating bottom-left preview with Copy, Save, and Edit actions
- Non-destructive arrows, lines, text, shapes, freehand drawing, and highlights
- Permanent redaction, configurable colors and stroke sizes, undo, and redo
- Flattened copy and PNG export at the original screenshot resolution
- Menu-bar-only app with a Screen Recording permission flow

## Run locally

Open `Package.swift` in Xcode and run the `PloegShot` executable, or run:

```sh
swift run PloegShot
```

macOS will request Screen Recording permission on first capture. For a stable
permission identity and distribution, build the included Xcode app target.

## Architecture

- `App`: lifecycle, status item, and global hot key
- `Capture`: selection overlays and display-coordinate capture
- `Preview`: floating post-capture actions
- `Editor`: tool model, canvas interaction, and annotation rendering
- `Shared`: clipboard and PNG export

New editor tools can be added by extending `EditorTool`, `Annotation`, and
`AnnotationRenderer`, without changing capture or export code.
