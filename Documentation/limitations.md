# Current limitations

- Intel x86_64 is the only verified architecture. Apple Silicon is not claimed or tested.
- Deployment target is macOS 26.0 because the vendored native libraries and current toolchain are built for that target.
- PDF-to-DjVu conversion, OCR, annotations, editing, and PDF page manipulation are not implemented.
- Password-protected PDFs that require an unlock dialog are unsupported.
- PDF outlines and selection depend on PDFKit. DjVu outlines are numeric internal page bookmarks when the source provides them; unsupported destinations are disabled.
- DjVu export composites decoded layers into a raster PDF page. It preserves available word-zone text as an invisible searchable layer, but does not perform OCR or MRC encoding.
- Large-document behavior has bounded caches, but peak memory and responsiveness for thousands of pages still need dedicated profiling.
- Production signing, notarization, installer packaging, and a root application license are release tasks.
