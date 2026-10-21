# Validation — 2026-10-21

## Environment

- Intel x86_64, macOS 26.7.1.
- Xcode 26.5 (17F42), Swift 6.3.2, macOS 26.5 SDK.
- No third-party packages or build tools were installed.
- The original converter and user documents were not modified or launched.

## Executed checks

- `xcodebuild ... build`: passed for the Intel Debug application.
- `xcodebuild ... test`: six XCTest tests passed, zero failures, including after the final search-focus and menu changes.
- Tests compile and link the final application as their host.
- Tests initially could not reach `com.apple.testmanagerd.control` from the execution sandbox. The authorized run outside the sandbox completed successfully.
- Build and test command output is retained in `Documentation/build.log` and `Documentation/tests.log`.

### Test coverage

1. Page input validation, first/last bounds, and empty page counts.
2. PDFKit canvas navigation and current-page synchronization.
3. Real asynchronous PDF text search and result navigation wrapping.
4. Replacing a pending query and canceling its old debounce.
5. Loading a generated PDF through NSDocument and creating its window and native toolbar.
6. Enforcing bounded search-result retention at the delegate boundary.

Fixtures are generated from CoreGraphics/CoreText. The document-loading test creates and removes only its own UUID-named temporary directory.

## Manual verification still required

- Visual comparison with Preview in light and dark appearances, at different window sizes and display scale factors.
- File > Open interaction, Finder file associations, drag-and-drop from Finder, and multiple dropped files.
- Keyboard routing while the PDF canvas, page field, or search field has focus.
- Scrolling, trackpad gestures, fit-to-window behavior during resize, and thumbnail selection/scroll synchronization.
- Large documents with thousands of pages: opening latency, scroll responsiveness, peak memory, thumbnail task cancellation, and long searches.
- Rotated pages, mixed page sizes, unusual fonts, Arabic/RTL selection/search, malformed files, and permissions-restricted documents.
- Accessibility with VoiceOver and keyboard-only navigation.

PDFKit emits system diagnostic messages during the tests, including graphics request compiler messages; the six assertions-based tests still pass. These tests do not constitute visual UI or large-document performance validation.

## Deliberate milestone limitations

Password-protected PDFs requiring unlock are rejected. No editing, saving, export, OCR, DjVu decoding, or document conversion is implemented. PDFKit's internal caches are not capped by the application's 16 MiB thumbnail cache limit. Initial document parsing is synchronous on the main actor and should be profiled against large/pathological PDFs before release. Code signing, notarization, release packaging, and non-Intel builds are not validated.

## Preview UI follow-up

See `Documentation/UIStudy/REPORT.md` for the subsequent native toolbar/sidebar changes and rendered validation. The updated Intel build and six tests passed after the final changes. Selected-window dark-mode screenshots were inspected for Preview and DjVu Preview using the same generated PDF. Manual light-mode, accessibility preference, precise animation timing, and performance checks remain outstanding. The latest logs are in `Documentation/UIStudy/tests.log`.

## Welcome startup follow-up

The standalone welcome lifecycle and bounded recent-file history are documented in `Documentation/Welcome/README.md`. The updated suite contains 11 tests, including real PDF opening, persistence, and bookmark resolution after renaming a generated fixture. Live bare launch, direct document launch, dismissal on open, return on native close, and the rendered recent list were checked. No empty NSDocument is requested. See `Documentation/Welcome/tests.log` for the latest build/test result.
