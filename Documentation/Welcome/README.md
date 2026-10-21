# Welcome Window and Startup Lifecycle

## Root cause

The previous launch handler and File > New Window action called `NSDocumentController.newDocument`. The registered PDF type has the Viewer role, so AppKit has no default editable document type to create. This produced “No document could be created.”

## Implementation

- AppKit's bare-launch `applicationOpenUntitledFile` callback is handled by welcome UI and returns success without constructing an NSDocument. Launch completion never requests an empty document.
- `ViewerDocumentController` is installed as the first/shared NSDocumentController. Its defensive `newDocument` override also routes to welcome UI.
- Finder URL events and File > Open still use AppKit document loading. A pending-open count suppresses welcome presentation while asynchronous opens finish.
- `addDocument` dismisses welcome; `removeDocument` schedules a coalesced reconciliation after document closing completes. The single retained WelcomeWindowController is reused.
- File > Welcome (Command-N) replaces New Window. File > Open (Command-O) is preserved. Dock reopen shows welcome only if no documents are open; otherwise it restores document windows.
- No changes were made to PDF rendering, conversion support, or the original converter.

## Welcome UI

Native SwiftUI/AppKit views show the application icon, requested title/subtitle, prominent Open Document button, PDF file-drop support, recent file icons/names/dates, empty state, and a small capability footer. The capability footer accurately states that PDF is implemented and DjVu/conversion are future work.

## Recent files

Successful opens explicitly call `noteNewRecentDocumentURL`. AppKit's recent URL ordering is used when available. During development verification, the system list remained empty despite successful opens, so a bounded local history is also maintained. This makes the welcome list usable even when the system recent-document service supplies no entries.

The local history contains at most 20 file URLs, last-opened dates, and ordinary Foundation file bookmarks in application UserDefaults. It does not copy document contents. Bookmarks are resolved without showing UI or mounting volumes. They can follow same-volume moves/renames; a missing or unresolvable file retains its saved URL and presents a friendly Locate/Cancel sheet when selected. Symlink-equivalent paths are deduplicated. Clear Recent Documents clears AppKit's list and the local history.

Native recent entries predating our own timestamp tracking display “Previously opened.” No file-modification date is invented as a last-opened date. Existing timestamp-only history migrates to the new model.

Only PDF opens are supported in this milestone. DjVu support and conversion remain deferred.

## Verification

The Intel Debug build and all 11 XCTest tests passed. See `tests.log` for the final run and `welcome.png` for the actual selected-window screenshot. Tests exercise:

- Existing PDF navigation, search, toolbar, and sidebar behavior.
- Reusing one welcome window without creating empty documents.
- Dismissing welcome while a document is registered and restoring it after the last removal.
- Opening a PDF directly, recording its date, and persisting local history.
- Following a renamed generated test PDF via bookmark while preserving its last-opened date.
- Restoring welcome after a failed open without recording a false date.
- Missing file availability and unknown-date presentation data.

The live checks use only the generated `Documentation/UIStudy/Comparison.pdf`. A bare launch was observed with one welcome window and no document-creation error. A standard open-documents event addressed to that instance dismissed welcome and displayed the PDF. Closing its native document window restored the same welcome window. A fresh launch with a PDF argument displayed a document window directly.

Manual checks still needed include Finder drag-and-drop interaction, the missing-file Locate panel, light appearance, and startup while macOS restores multiple documents. Automated tests use the actual shared NSDocumentController: on this host, attempting to allocate a second instance returned the same object, so tests do not rely on a fictitious isolated controller subclass. Timestamp/history preferences are isolated in a temporary defaults suite for successful-open persistence tests.

The final rendered welcome window was inspected with a populated recent list: the generated Comparison.pdf shows its icon and actual last-opened date, and an unavailable generated test document shows “File unavailable.” The empty-state screenshot was also inspected earlier. No document-creation error appeared during the live bare-launch check.
