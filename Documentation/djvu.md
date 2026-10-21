# DjVu support

DjVu files are opened through the vendored DjVuLibre 3.5.30 dynamic library and an Objective-C bridge. Pages are decoded lazily and rasterized only when visible or needed for a thumbnail. Existing DjVu word zones are exposed for search, rectangular selection, copying, and export to an invisible Core Text PDF layer.

DjVu-to-PDF export runs in a separate service. Quality presets select JPEG scalar quality for color/gray rasters; bilevel pages use one-bit grayscale with Flate. Resolution settings cap output at the source DPI, 300 DPI, or 150 DPI without upscaling. The exporter verifies the output page count, writes to a sibling temporary file, removes it on failure or cancellation, and then finalizes the destination. Metadata and numeric page outlines are preserved when available.

The export path is raster-based. It does not preserve DjVu compression layers as PDF objects and it does not run OCR. PDF-to-DjVu is not implemented.

The historical static-analysis material and visual logs remain under `Documentation/DjVu/`; those files are evidence for the investigation, not the public API contract.
