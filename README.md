# PloegShot

[**Download PloegShot for Mac**](https://github.com/teunvanderploeg/PloegShot/releases/latest/download/PloegShot-macOS-AppleSilicon.dmg)

Apple silicon. macOS 13.0 or later.
Open the disk image and drag PloegShot to Applications.
[ZIP download and checksums](https://github.com/teunvanderploeg/PloegShot/releases/latest).

PloegShot is a native macOS screenshot utility built with SwiftUI and AppKit.

The redesigned PloegShot interface is in beta. More updates will follow.

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

Keep the shared `PloegKit` package beside this checkout:

```text
Code/
  PloegKit/
  PloegShot/
```

Clone [PloegKit](https://github.com/teunvanderploeg/PloegKit) at the shared beta tag
from the directory containing your PloegShot checkout:

```sh
git clone --branch v0.1.0-beta.1 https://github.com/teunvanderploeg/PloegKit.git PloegKit
```

Open `Package.swift` in Xcode and run the `PloegShot` executable, or run:

```sh
swift run PloegShot
```

macOS will request Screen Recording permission on first capture. For a stable
permission identity and distribution, build the included Xcode app target.

PloegToolbox launches the app with `--show-settings` to show Settings without
starting a capture. Opening an already running PloegShot brings its current
editor forward, including a minimized editor, or shows Settings when no editor
is open. A normal background launch still starts only the menu-bar app.
`PloegToolboxOpenVersion` in the app's Info.plist declares this launch behavior.

## Ploeg design foundation

The editor, screenshot previews and Settings use the shared PloegKit colors,
controls, spacing and centered generated PloegShot icon. Appearance follows macOS.
The editor retains its image canvas, tool rail and annotation inspector. Image
coordinates, capture behavior, redaction and export remain in the existing Swift
implementation.

The Xcode app target includes the local PloegKit package and its resource bundle.
Keep the existing bundle identifier when packaging an update so Screen Recording
permission and user preferences retain their identity.

For visual review without capturing a screen, registering hotkeys or reading the
clipboard, launch the built executable with one of these flags:

```sh
swift run PloegShot --design-preview
swift run PloegShot --design-preview-settings
swift run PloegShot --design-preview-dark
```

Preview mode uses a synthetic project-notes image. Settings preview prevents
shortcut writes and does not open system permissions. Add `--design-preview-dark`
to the settings flag to inspect dark appearance. Preview mode does not replace
an installed application.

A copied review bundle can instead set `PloegDesignPreview` to `true` in its
Info.plist, with `PloegDesignPreviewMode` set to `editor` or `settings`. This
allows visual-review tools to launch the safe fixture without command-line
arguments. Those keys are absent from the production Info.plist.

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
preview paging, drawing coordinates after zoom and pan, and launch requests.

## Architecture

- `App`: lifecycle, status item, and global hot key
- `Capture`: selection overlays and display-coordinate capture
- `Preview`: floating post-capture actions
- `Editor`: tool model, canvas interaction, and annotation rendering
- `Shared`: clipboard and PNG export

New editor tools can be added by extending `EditorTool`, `Annotation`, and
`AnnotationRenderer`, without changing capture or export code.
