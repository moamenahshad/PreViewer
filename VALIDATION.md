# Validation — 2026-10-22

## Environment

- Intel x86_64, macOS 26.7.1.
- Xcode 26.5 (17F42), Swift 6.3.2, macOS 26.5 SDK.
- No third-party packages or build tools were installed.
- The original converter and user documents were not modified or launched.

## Executed checks

- `xcodebuild ... build`: passed for the Intel Debug application.
- `xcodebuild ... test`: 22 XCTest tests passed, zero failures (13 viewer tests and 9 DjVu tests).
- Tests compile and link the final application as their host.
- Tests initially could not reach `com.apple.testmanagerd.control` from the execution sandbox. The authorized run outside the sandbox completed successfully.
- The reproducible commands and current coverage are maintained in `Documentation/testing.md`. Historical logs remain under `Documentation/`.

### Test coverage

1. PDF page bounds, opening, navigation, search, result wrapping, and bounded result retention.
2. Native toolbar/sidebar sizing, appearances, and document-window creation.
3. Welcome, recent-document, direct-launch, failed-open, and missing-file behavior.
4. DjVu validation, metadata, page information, word zones, outlines, rendering, cancellation, rotation, and corrupt input.
5. DjVu-to-PDF export page counts, searchable text, quality/resolution settings, cleanup, and bilevel output.

Fixtures are generated from CoreGraphics/CoreText. The document-loading test creates and removes only its own UUID-named temporary directory.

## Manual verification still required

- Visual comparison with Preview in light and dark appearances, at different window sizes and display scale factors.
- File > Open interaction, Finder file associations, drag-and-drop from Finder, and multiple dropped files.
- Keyboard routing while the PDF canvas, page field, or search field has focus.
- Scrolling, trackpad gestures, fit-to-window behavior during resize, and thumbnail selection/scroll synchronization.
- Large documents with thousands of pages: opening latency, scroll responsiveness, peak memory, thumbnail task cancellation, and long searches.
- Rotated pages, mixed page sizes, unusual fonts, Arabic/RTL selection/search, malformed files, and permissions-restricted documents.
- Accessibility with VoiceOver and keyboard-only navigation.

PDFKit and SwiftUI emit known system graphics and AttributeGraph diagnostics during the tests; all 22 assertions-based tests pass. These tests do not constitute large-document performance validation.

## Deliberate milestone limitations

Password-protected PDFs requiring unlock are rejected. PDF-to-DjVu, OCR, annotations, editing, and PDF page manipulation are not implemented. Code signing, notarization, release packaging, and non-Intel builds are not validated.

## Preview UI follow-up

See `Documentation/UIStudy/REPORT.md` for the subsequent native toolbar/sidebar changes and rendered validation. The updated Intel build and 22 tests pass after the current changes. Selected-window screenshots and UI studies remain historical evidence; precise animation timing, accessibility, and large-document performance checks remain outstanding. The latest historical logs are in `Documentation/UIStudy/tests.log`.

## Welcome startup follow-up

The standalone welcome lifecycle and bounded recent-file history are documented in `Documentation/Welcome/README.md`. The current suite contains 22 tests, including real PDF and DjVu opening, persistence, export, bookmark behavior, and the explicit Command-N Welcome action. No empty NSDocument is requested. See `Documentation/testing.md` for the current build/test result.
