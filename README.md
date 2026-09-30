# PloegShot

PloegShot is a native macOS screenshot utility built with SwiftUI and AppKit.

## MVP features

- Configurable global shortcuts for area, reusable previous-area, and full-display capture
- Multi-display selection overlays and Retina-resolution capture
- Floating bottom-left preview with Copy, Save, and Edit actions
- Drag previews into other apps as images or PNG files, with Copy and Save feedback
- On-screen preview pages with access to older captures
- Non-destructive arrows, lines, text, shapes, freehand drawing, and highlights
- Editor zoom, fit-to-window, and scrolling to pan
- Complete rectangular redaction in exports, configurable colors and stroke sizes, undo, and redo
- Flattened copy and PNG export at the original screenshot resolution
- Menu-bar-only app with a Screen Recording permission flow

## Run locally

Open `Package.swift` in Xcode and run the `PloegShot` executable, or run:

```sh
swift run PloegShot
```

macOS will request Screen Recording permission on first capture. For a stable
permission identity and distribution, build the included Xcode app target.

## Using previews and zoom

Drag the screenshot thumbnail into another app to insert a copy. The preview
stays available. When captures fill a display, use the newer/older arrows on
the bottom card to browse the remaining previews. Previews last for the current
app session.

The editor opens with the image fitted to the window. Use the Zoom controls,
pinch to zoom, or scroll to pan. Command-minus and Command-equals adjust zoom;
Command-0 fits the image again. Zoom changes the view, not the exported image.
Redactions remain editable in the editor and become permanent in copied or
saved images.

## Tests

Run `swift test` to check annotation history, crop coordinates and failure
handling, exported pixel dimensions, redaction coverage, drag representations,
preview paging, and drawing coordinates after zoom and pan.

## Architecture

- `App`: lifecycle, status item, and global hot key
- `Capture`: selection overlays and display-coordinate capture
- `Preview`: floating post-capture actions
- `Editor`: tool model, canvas interaction, and annotation rendering
- `Shared`: clipboard and PNG export

New editor tools can be added by extending `EditorTool`, `Annotation`, and
`AnnotationRenderer`, without changing capture or export code.
