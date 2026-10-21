# Testing

Run from the repository root:

```sh
xcodebuild -project 'DjVu Preview.xcodeproj' -scheme 'DjVu Preview' \
  -configuration Debug -destination 'platform=macOS,arch=x86_64' \
  -derivedDataPath Build -jobs 1 CODE_SIGNING_ALLOWED=NO build

xcodebuild -project 'DjVu Preview.xcodeproj' -scheme 'DjVu Preview' \
  -configuration Debug -destination 'platform=macOS,arch=x86_64' \
  -derivedDataPath Build -jobs 1 -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO test
```

The current suite contains 22 tests: 13 viewer tests and 9 DjVu tests. It covers page bounds, PDF opening/search, welcome and recent-document lifecycle, the Command-N Welcome shortcut, registered file types, DjVu validation, metadata, text zones, outlines, rendering, cancellation, rotation, quality/resolution settings, export page counts, searchable text, and corrupt input handling. Fixtures live in `Tests/Fixtures`; temporary outputs are created and removed by the tests.

The verified Intel run on 2026-10-22 passed all 22 tests. The run emits known macOS graphics, SwiftUI AttributeGraph, LaunchServices, and compiler-request diagnostics, but no test failures. A sandboxed invocation cannot contact `testmanagerd`; run XCTest from Xcode or an authorized host session.

Manual coverage still needed includes Finder association and drag-and-drop, very large documents, unusual fonts and RTL text, permissions errors, VoiceOver, and signed/notarized release builds.

Current local captures of the running Intel Debug app are [the welcome window](screenshots/welcome-current.png) and [the PDF reader](screenshots/pdf-reader-current.png). They were captured from the built product on 2026-10-22 using the repository's generated `Documentation/UIStudy/Comparison.pdf` fixture.
