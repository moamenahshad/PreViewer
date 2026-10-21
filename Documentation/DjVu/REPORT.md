# Direct DjVu reading and DjVu-to-PDF export

> Historical investigation report. Current supported behavior and test results are maintained in [`Documentation/djvu.md`](../djvu.md) and [`Documentation/testing.md`](../testing.md).

## Implementation

The app now opens `.djvu` and `.djv` through NSDocument, File > Open, Finder events, the welcome/recent-document UI and URL drops. A small signature check precedes asynchronous DjVu header loading. The reader does not convert DjVu to PDF. DjVuLibre decodes visible pages into a dedicated AppKit scroll canvas. Source word zones support rectangular selection/copying and a search that navigates matching pages. A Contents/Thumbnails sidebar exposes supported source outlines. PDF rendering/search continue using the existing PDFKit path.

File > Export (Shift-Command-E), enabled for loaded DjVu documents, opens a separate window titled exactly **DjVu to PDF**. Export semantics keep the source unchanged. The window contains source properties, real quality and resolution controls, preservation options with explicit limitations, destination selection through NSSavePanel, a size estimate, page-based progress/cancellation, and a completion section with actual sizes, signed size difference/percentage, duration, location, Open PDF and Show in Finder.

AppKit owns the conversion window's initial 620×760-point content size and its 520×560-point minimum frame. SwiftUI hosting sizing is disabled for this window to prevent an unsolicited shrink to the fitting minimum. The estimated-size label stays in the footer at every supported size. The form scrolls when necessary; no custom glass/blur overlay or toolbar replacement is used.

## Pipeline and real settings

Reading, estimation and conversion use independent decoder instances. Swift actors confine non-thread-safe decoder state. The decoder uses public `ddjvu_document_create_by_filename_utf8`, `ddjvu_document_get_pageinfo`, `ddjvu_page_create_by_pageno`, `ddjvu_page_render`, text/outline/annotation APIs. It never invokes an external converter process.

Conversion processes one page at a time into a CoreGraphics PDF context. DjVuLibre's source image layers are decoded and composited, then the output image is encoded. Source compression streams are not transplanted into PDF. This implementation does not claim MRC layer preservation.

| Setting | Actual behavior |
| --- | --- |
| Smaller File | ImageIO JPEG quality scalar 0.55 for continuous-tone images |
| Balanced | ImageIO JPEG quality scalar 0.82 for continuous-tone images |
| Maximum Quality | Lossless encoding of decoded raster pixels through Quartz/Flate |
| Bilevel raster | Packed to one-bit grayscale, losslessly encoded at every preset |
| Preserve Original | Preserve source raster dimensions, subject to the export safety limit |
| 300 / 150 DPI | Downsample to at most the requested DPI; never upscale |
| Source text | Existing word-zone text becomes invisible CoreText PDF text, with source coordinates and orientation |
| Outlines | Numeric internal page destinations and supported hierarchy |
| Metadata | Title, Author, Subject, Keywords from document/shared annotations, with first-page fallback |

The source DPI is taken from the DjVu header. Values outside 25–6000 are treated as unknown: retain original pixels and use 300 DPI for physical page dimensions, explicitly disclosed in the UI. DjVuLibre page-info dimensions already include orientation, so the bridge normalizes them before applying orientation once to image/text/export dimensions. A rotation regression test covers a quarter-turn page and all resolution settings.

Temporary output is created beside the destination. After closing the PDF context, page count is verified using CGPDFDocument. Only then is output moved or replaced. Failure/cancellation removes incomplete temporary output and leaves an existing destination untouched until finalization. The converter rejects a destination resolving to the source URL. NSSavePanel supplies the user's output/replacement choice.

## Size estimation

Estimation is asynchronous and debounced. Setting changes and window closure cancel the prior estimate and its decoder. Up to five stratified source pages are selected: first, quarter, middle, three-quarter and last, deduplicated for short documents. These pages are actually encoded with the selected image quality, resolution and text/metadata options. Separate single-page trials measure variability; a combined sample trial measures shared font/catalog overhead. The combined sample's bytes per rendered pixel are extrapolated over all page dimensions at the selected resolution. The range derives from measured page variability and observed shared-resource overhead, not a multiplier on the DjVu file size.

A failed or unavailable estimate displays **Estimate unavailable**. The UI distinguishes estimated and actual sizes. The range is a sampling range, not a confidence guarantee: rare photographs, different layer composition or unusual text outside the sample can change the result. Original DjVu size is measured and shown, but it is not used as a false predictor of PDF compression. Trials reproduce the composited layer content of sampled pages; the estimator does not classify every source page's layers or decode every page of a large document.

Latest recorded measurements are in `measurements.json` and `tests-final.log`:

| Source/settings | Estimated bytes | Actual bytes |
| --- | ---: | ---: |
| Generated 3-page color fixture, Smaller File | 22,782–46,591 | 35,006 |
| Same, Balanced | 32,678–56,123 | 44,720 |
| Same, Maximum Quality | 524,620–543,919 | 534,589 |
| 57-page DjVuLibre book, Balanced, 150 DPI | 14,300,505–30,558,676 | 18,547,777 |

PDF is not guaranteed to be smaller than DjVu. The 57-page source is approximately 429 KB and expands substantially when represented as PDF images/text.

## Performance and cancellation

- DjVuLibre cache: 24 MiB per active decoder.
- Viewer raster cache: 40 MiB; thumbnail image cache: 16 MiB and at most 80 entries.
- Canvas retains visible images only. Binary search locates visible page frames without scanning every page on each scroll event. Viewport order prioritizes the nearest pages.
- Layout changes replace requests; ordinary session updates reuse unchanged layout/images. Request identities prevent late cancelled jobs from clearing a newer request or becoming permanent page errors.
- Actor decoding and trial/conversion work run off the main thread. Cancellation tokens are atomic and checked by finite decoder wait loops. A synchronous native raster/codec operation completes before cancellation is observed.
- Visible preview rasters are capped at 4096 pixels on the long edge. Export rejects output pages above 40 megapixels with a resolution recommendation rather than allocating an unbounded bitmap.
- Autorelease pools release Objective-C raster intermediates after each page. In the latest 57-page run, per-page resident-memory samples peaked at 141,185,024 bytes (about 134.6 MiB), with 5,637,600 bytes in the exercised viewer cache. This is sampled process residency, not an instantaneous peak or a universal memory guarantee. Conversion took approximately 7.3 seconds on this fixture.

## Validation

Intel x86_64 build succeeded on macOS 26.7.1 / Xcode 26.5. The final full suite passed **20 tests with zero failures**: eight DjVu tests and twelve existing PDF, toolbar, welcome, lifecycle and search tests.

Coverage includes direct decoding without an intermediate PDF, source text, numeric outlines and metadata, cache bounds, every quality preset, every resolution option, rotated page/thumbnail dimensions, PDF page count, searchable-text presence/absence, actual DCT/Flate PDF filters, one-bit bilevel preservation without JPEG at Smaller File, lossless raster pixel comparison, estimated versus actual size on fixtures, a complete 57-page conversion, cancellation/temporary cleanup, corrupt input, source-overwrite rejection, conversion-model completion/settings replacement, rapid viewer navigation, and both appearances/window sizes.

Native smoke validation additionally opened the bundled Lizard document using a Finder-style application open event, activated the actual File > Export menu, and opened/cancelled its native save sheet. Accessibility inspection verified the named controls, source properties and estimated range. The application's own system frameworks use their normal public APIs; no security settings or system applications were modified.

The final selected-window screenshots are retained in this directory: `reader-light.png`, `reader-dark.png`, `conversion-light.png`, `conversion-dark.png`, `conversion-minimum.png`, and the real-document captures. Light/dark standard layouts and the light minimum-size layout were visually inspected; both minimum sizes also run in the automated UI test. They verify settled light/dark layouts, not frame-by-frame animation timing. Keyboard menus retain their existing bindings. A complete manual VoiceOver audit, Finder drag interaction, real-world thousand-page documents, damaged indirect documents, disk-full fault injection and broad multilingual text fidelity remain untested. Open PDF/Show in Finder use native APIs but their final external-app interaction was not automated. No pixel-perfect equivalence with Apple Preview is claimed.

## Known limits

- No PDF-to-DjVu conversion, OCR, annotation editing, MRC export, CCITT Group 4 encoder, source vector reconstruction or compressed-layer reuse.
- The canvas uses word rectangles for selection. Selection/Select All covers loaded visible pages; it is not PDFKit-style character selection across an entire DjVu document.
- DjVu search reports matching pages (up to 500), rather than every occurrence with per-glyph highlighting.
- Named/file-ID/external bookmark destinations, unsupported outline subtrees, hyperlinks, custom/XMP metadata and page-specific metadata beyond the first-page fallback are not preserved. Supported options are described explicitly in the UI.
- Unsupported/malformed source text raises an error instead of being silently reported as preserved. Disable text preservation for an image-only export if needed.
- DPI is nominal header data, not a physical-size calibration. Unknown-DPI fallback and the 40-megapixel export limit are disclosed.
- Production signing/notarization, a license decision for the combined app and release/source packaging are still release tasks.

## Changed files

New runtime modules:

- `Sources/DjVu/DjVuBridge.h` / `.m`: independent public-C-API bridge, atomic cancellation and source expression parsing.
- `Sources/DjVu/DjVuDocumentBackend.swift`: decoder confinement, metadata/outline/text types, bounded raster cache and orientation.
- `Sources/DjVu/DjVuCanvas.swift`: native lazy continuous canvas, navigation/zoom, text selection and viewport request management.
- `Sources/DjVu/DjVuSearchBar.swift`: source-text search UI.
- `Sources/Conversion/DjVuToPDFConverter.swift`: options, PDF writing and sampled estimator.
- `Sources/Conversion/DjVuToPDFWindowController.swift`: utility window, model, progress/completion UI and native Save Panel.

Integration changes:

- `Sources/Documents/DocumentSession.swift`, `ViewerDocument.swift`, `ViewerDocumentController.swift`.
- `Sources/Rendering/ThumbnailStore.swift`.
- `Sources/UI/ViewerContentView.swift`, `ThumbnailSidebar.swift`, `ViewerWindowController.swift`, `WelcomeWindow.swift`.
- `Sources/App/DjVuPreviewApp.swift`, `Info.plist`, Xcode project and README.
- `Tests/DjVuTests.swift`, project-owned/generated/upstream fixtures, dependency notices/source archives and this validation directory.

## Dependencies and licensing

DjVuLibre 3.5.30 and libjpeg-turbo 3.2.0 were already installed locally. Copies are bundled with project-local loader paths; no package/dependency was installed and the original installed files were not modified. End users need neither Homebrew nor MacPorts. Vendored binaries require macOS 26 and x86_64; the deployment target now reflects that requirement.

DjVuLibre is GPL-2.0-or-later. Distribution of the linked application requires a GPL-compatible combined application, notices/license texts and a compliant complete-corresponding-source arrangement. The project includes upstream source archives, the MacPorts Portfiles/patch and JPEG license notices. It does not choose the user's application license or claim release readiness. See `Vendor/DjVuLibre/NOTICE.md`, [GNU GPL v2](https://www.gnu.org/licenses/old-licenses/gpl-2.0.html), [DjVuLibre upstream](https://sourceforge.net/projects/djvu/) and [libjpeg-turbo licensing](https://github.com/libjpeg-turbo/libjpeg-turbo/blob/3.2.0/LICENSE.md).

Built app: `Build/Build/Products/Debug/DjVu Preview.app`.
