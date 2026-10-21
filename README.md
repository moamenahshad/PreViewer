# PreViewer

PreViewer is an independent native macOS document viewer using Swift 6, AppKit, SwiftUI and PDFKit, with a separate DjVuLibre backend for DjVu reading and DjVu-to-PDF export. No proprietary converter or Apple Preview resources or code are included.

## Requirements and build

Intel x86_64, macOS 26 or later, Xcode 26.5. The bundled native libraries require macOS 26, so the project deployment target is 26.0. No Homebrew, MacPorts or command-line utility is needed by end users. Dependencies are already vendored; building the app installs nothing.

```sh
xcodebuild -project 'DjVu Preview.xcodeproj' -scheme 'DjVu Preview' \
  -configuration Debug -destination 'platform=macOS,arch=x86_64' \
  -derivedDataPath Build -jobs 1 CODE_SIGNING_ALLOWED=NO build

xcodebuild -project 'DjVu Preview.xcodeproj' -scheme 'DjVu Preview' \
  -configuration Debug -destination 'platform=macOS,arch=x86_64' \
  -derivedDataPath Build -jobs 1 -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO test
```

The built product is `Build/Build/Products/Debug/PreViewer.app`. The Xcode project and scheme retain the historical name `DjVu Preview`; this is an internal project label, while the product and bundle display name are `PreViewer`.

## Reader

File > Open, Finder document events, welcome/recent documents and drops accept PDF, .djvu and .djv. AppKit owns window/document lifetime and native toolbar/sidebar materials. PDF rendering/search remain with PDFKit. DjVu uses direct lazy raster rendering into an AppKit scroll view; no intermediate PDF is created. Existing source word zones enable rectangular text selection and copying. Search returns matching pages, with a 500-page limit. The Contents sidebar supports numeric internal page bookmarks; unsupported destinations are disabled.

DjVu work is confined to an actor with a 24 MiB DjVuLibre cache and a separate 40 MiB raster cache. Thumbnails have a 16 MiB/80-entry cache. Only visible page images are retained by the canvas. Offscreen tasks are cancelled and visible pages are requested in viewport order. Rendered previews are capped at 4096 pixels on the long edge; export has a 40 megapixel output-page safety limit. Decoder wait loops poll cancellation with finite timeouts. A single native raster operation completes before its cancellation can be observed.

## Export

With a DjVu document active, choose File > Export (Shift-Command-E). The dedicated **DjVu to PDF** window displays source properties, real quality/resolution/preservation settings, a sampled output-size range, native Save Panel destination selection, progress/cancellation and completion statistics. Source files are read-only. Conversion uses a separate decoder, writes a sibling temporary file, verifies PDF page count and finalizes by move or replacement. Cancelled/failed temporary output is removed.

JPEG scalar quality is 0.55 for Smaller File and 0.82 for Balanced. Maximum Quality preserves the decoded raster losslessly. Bilevel rasters use one-bit grayscale/Flate at every quality. Layers are composited, not exported as MRC. Original/300/150 DPI settings cap resolution at source DPI without upscaling. Existing word-zone text is emitted as an invisible CoreText PDF text layer; no OCR is performed. Numeric page outlines and supported metadata fields are preserved where available.

See the [architecture](Documentation/architecture.md), [testing guide](Documentation/testing.md), [DjVu notes](Documentation/djvu.md), [limitations](Documentation/limitations.md), and [dependency notices](Vendor/DjVuLibre/NOTICE.md). DjVuLibre is GPL-2.0-or-later: distribution requires a GPL-compatible combined application and compliance with corresponding-source obligations. The application has no selected root license yet; see [licensing](Documentation/licensing.md). Production signing, notarization, and source distribution remain release work.

## Shortcuts

| Action | Shortcut |
| --- | --- |
| Open / Welcome / Close | Command-O / Command-N / Command-W |
| Find / Next / Previous Match | Command-F / Command-G / Shift-Command-G |
| Previous / Next Page | Command-Up / Command-Down |
| Thumbnails | Option-Command-1 |
| Zoom In / Out | Command-Plus / Command-Minus |
| Actual Size / Fit to Window | Command-0 / Command-9 |
| DjVu Export | Shift-Command-E |
| Full Screen | Control-Command-F |

Password-protected PDFs requiring unlock remain unsupported. PDF-to-DjVu, OCR, annotations, editing, and MRC encoding are not implemented. Earlier UI, welcome, and toolbar studies are retained under Documentation as research history; current behavior is described by the documents linked above.
