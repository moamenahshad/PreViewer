# Native Open panel DjVu filter fix

## Confirmed cause

On this Mac, both `.djvu` and `.djv` resolve preferentially to `com.lizardtech.djvu`. Other installed apps register sibling types, including `com.firmshell.djvu` and `org.djvuzone.djvulibre.djvu`. The application declared only `org.djvu.djvu`. Sibling types do not automatically conform to that identifier, so the native Open panel excluded otherwise valid DjVu files. Direct/Finder opening worked because the document controller routed extensions independently of the panel filter.

## Changes

- Info.plist now imports the established `com.lizardtech.djvu` identifier and retains the previous identifier for compatibility, with both extensions and MIME declaration.
- ViewerDocumentController augments AppKit's Open-panel type identifiers with every currently registered type for the two DjVu extensions, and keeps PDF enabled. It does not allow all data/items or replace the native panel.
- Extension-based document dispatch uses `com.lizardtech.djvu`.
- The decoder, PDF renderer and conversion pipeline are unchanged.

## Verification

Historical snapshot: the Intel build succeeded and 21 tests passed at that milestone. The current suite is documented in `Documentation/testing.md`. The added regression test presents the real NSOpenPanel, checks the resulting allowedContentTypes against actual resource types for `.djvu` and a copied `.djv`, verifies all installed DjVu associations, and ensures PDF remains allowed without broadly admitting public.data/public.item.

A fresh application instance was also exercised through File > Open and the system Go to Folder/File field. Selecting the project-owned `generated.djvu` fixture enabled Open; pressing it opened a three-page DjVu document. See open-panel-smoke.log. The file-selection validation helper is outside the application target and changes no clipboard contents or source documents.

Changed runtime files: Info.plist and Sources/Documents/ViewerDocumentController.swift. Added regression coverage in Tests/DjVuTests.swift; validation helpers/records are in this directory.

Previously running instances retain old code until restarted. For the current product, use `Build/Build/Products/Debug/PreViewer.app` after restarting the previous instance. The surrounding log is retained as historical investigation material.
