# Architecture

PreViewer keeps document lifecycle separate from format-specific rendering.

- `ViewerDocumentController` owns native `NSDocumentController` lifecycle, recent documents, welcome-window transitions, file-open routing, and registered PDF/DjVu types.
- `ViewerDocument` and `DocumentSession` choose a PDFKit session or the DjVu actor-backed session.
- `PDFCanvas` hosts PDFKit rendering and selection. `DjVuCanvas` hosts lazy raster rendering from the vendored DjVuLibre bridge.
- `ThumbnailStore` provides bounded, lazy thumbnail caching. Search is implemented separately for PDFKit and DjVu word zones.
- `DjVuToPDFConverter` and its window controller are independent of the viewer and export through Core Graphics/Core Text.
- `WelcomeWindow` and the AppKit window controller provide the Preview-inspired native window and toolbar surface.

DjVu decoding is isolated behind `DjVuDocumentBackend` and an Objective-C bridge. The viewer keeps a 24 MiB decoder cache and a 40 MiB raster cache; thumbnails use a separate bounded cache. The product is currently compiled for Intel x86_64 and macOS 26.0 or later.
