# Red Pen

iOS photo markup, but better. Built for one thing: marking up screenshots as fast as possible, straight from the share sheet.

The whole editor runs **inside the share extension** — take a screenshot, tap share, tap Red Pen, and you're drawing. No app switch, no handoff delay.

## Setup

The Xcode project is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
brew install xcodegen
cd red-pen
xcodegen generate
open RedPen.xcodeproj
```

Then in Xcode:

1. Select the **RedPen** and **RedPenShare** targets and set your development team.
2. Change `bundleIdPrefix` in `project.yml` (and the two `PRODUCT_BUNDLE_IDENTIFIER`s) to your own identifier, then re-run `xcodegen generate`. The extension's bundle id must stay prefixed by the app's.
3. Build and run the **RedPen** scheme on a device (share extensions are much easier to test on hardware).

Requires iOS 26+.

## Make Red Pen show up front in the share sheet

iOS decides share sheet order, but favorites always appear first (where Mail sits by default):

1. Open any share sheet and scroll the row of app icons to the end.
2. Tap **More → Edit**.
3. Add **Red Pen** to Favorites and drag it to the front.

## The zero-original workflow

The originals never have to touch your photo library:

1. Take a screenshot.
2. Tap the screenshot thumbnail, then the **share** icon.
3. Pick **Red Pen**, mark it up, hit **Save** — the edited copy is saved to your library.
4. Close the screenshot preview and choose **Delete Screenshot**.

If screenshots already landed in your library, use the main app instead: **Pick Screenshots → edit → Save**, and Red Pen offers to delete the originals (iOS shows a single system confirmation per batch — silent deletion isn't possible, by design).

## Features

- **Share extension editor** — full editor inside the share sheet, up to 10 images at once
- **Filmstrip** — edit many screenshots in one session, tap thumbnails to switch, one Save for all
- **Pen** — four detented sizes, with a **90° toggle** for straight horizontal/vertical lines only
- **Eraser** — four detented sizes; erases ink, never the screenshot
- **Crop** — drag corners or move the window, apply per screenshot
- **Shapes** — rectangle and rounded rectangle, with text inside (left/center aligned; 12/18/24/40pt font styles plus ±4pt nudging)
- **Colors** — red, blue, green, yellow. That's it, on purpose.
- **Fill styles** — opaque, 50% transparent, or no fill (color becomes a 2pt stroke)
- **Auto-contrast text** — text inside shapes is black or white, chosen by the app for contrast; not editable
- **Undo / redo** — gesture-driven: two-finger tap the canvas to undo, three-finger tap to redo. Per screenshot, covers everything including crop
- **Native UI** — system navigation and toolbars (Liquid Glass on iOS 26), segmented tool picker, native menus for tool options
- **Dark mode only**

## TestFlight

CI is Xcode Cloud: every push to `main` archives the app and uploads it to
TestFlight internal testing. The `.xcodeproj` is not committed, so
`ci_scripts/ci_post_clone.sh` regenerates it with XcodeGen on the build
runner before Xcode Cloud builds.

## Architecture

| Path | What it is |
| --- | --- |
| `project.yml` | XcodeGen spec: app target + share extension target |
| `App/` | Main app: home screen, photo picker, delete-originals flow |
| `ShareExtension/` | Share extension entry point; hosts the editor in the sheet |
| `Shared/` | The editor itself, compiled into both targets |
| `Shared/Models.swift` | Tools, colors, fills, shapes, document + undo snapshots |
| `Shared/EditorSession.swift` | Observable session state: documents, tool state, undo/redo |
| `Shared/CanvasView.swift` | Drawing canvas, shape overlays, image↔view coordinate transform |
| `Shared/CropOverlay.swift` | Crop window with draggable corners |
| `Shared/EditorView.swift` | Editor chrome: top bar, filmstrip, toolbar |
| `Shared/ShapeTextSheet.swift` | Shape text, alignment, and font size editing |
| `Shared/Renderer.swift` | CoreGraphics export renderer (matches on-screen output) |
| `Shared/SaveService.swift` | Photo library save + delete-originals |

Annotations are stored in image space, so exports are pixel-faithful regardless of display size. Stroke widths and font sizes are normalized to the source device's point scale, so a "6pt" pen looks like 6pt on the original screenshot.
