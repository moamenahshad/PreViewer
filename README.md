# DjVu Preview

Independent native macOS document viewer using Swift 6, AppKit, SwiftUI and PDFKit, with a separate DjVuLibre backend for DjVu reading and DjVu-to-PDF export. No proprietary converter or Apple Preview resources/code are included.

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

Open `Build/Build/Products/Debug/DjVu Preview.app`, or run the DjVu Preview scheme in Xcode. Tests must be allowed to contact macOS testmanagerd.

## Reader

File > Open, Finder document events, welcome/recent documents and drops accept PDF, .djvu and .djv. AppKit owns window/document lifetime and native toolbar/sidebar materials. PDF rendering/search remain with PDFKit. DjVu uses direct lazy raster rendering into an AppKit scroll view; no intermediate PDF is created. Existing source word zones enable rectangular text selection and copying. Search returns matching pages, with a 500-page limit. The Contents sidebar supports numeric internal page bookmarks; unsupported destinations are disabled.

DjVu work is confined to an actor with a 24 MiB DjVuLibre cache and a separate 40 MiB raster cache. Thumbnails have a 16 MiB/80-entry cache. Only visible page images are retained by the canvas. Offscreen tasks are cancelled and visible pages are requested in viewport order. Rendered previews are capped at 4096 pixels on the long edge; export has a 40 megapixel output-page safety limit. Decoder wait loops poll cancellation with finite timeouts. A single native raster operation completes before its cancellation can be observed.

## Export

With a DjVu document active, choose File > Export (Shift-Command-E). The dedicated **DjVu to PDF** window displays source properties, real quality/resolution/preservation settings, a sampled output-size range, native Save Panel destination selection, progress/cancellation and completion statistics. Source files are read-only. Conversion uses a separate decoder, writes a sibling temporary file, verifies PDF page count and finalizes by move or replacement. Cancelled/failed temporary output is removed.

JPEG scalar quality is 0.55 for Smaller File and 0.82 for Balanced. Maximum Quality preserves the decoded raster losslessly. Bilevel rasters use one-bit grayscale/Flate at every quality. Layers are composited, not exported as MRC. Original/300/150 DPI settings cap resolution at source DPI without upscaling. Existing word-zone text is emitted as an invisible CoreText PDF text layer; no OCR is performed. Numeric page outlines and supported metadata fields are preserved where available.

See [DjVu validation and limitations](Documentation/DjVu/REPORT.md) and [dependency notices](Vendor/DjVuLibre/NOTICE.md). DjVuLibre is GPL-2.0-or-later: distribution requires a GPL-compatible combined application and compliance with corresponding-source obligations. This milestone does not select the application's license or prepare a signed public release. Production signing/notarization and source distribution remain release work.

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

Password-protected PDFs requiring unlock remain unsupported. PDF-to-DjVu, OCR and MRC encoding are not implemented. Earlier UI/welcome/toolbar studies are under Documentation; their milestone-specific limitations may have been superseded by this implementation.
