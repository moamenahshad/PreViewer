# Preview UI Architecture Study — macOS 26.7.1

## Scope and target identity

Read-only static inspection of `/System/Applications/Preview.app`, version 11.0, build 1113.5.3. The application declares macOS 26.7 as its minimum and was built against Apple's internal macOS 26.7 SDK. The inspected universal executable has SHA-256 `db13f63838230a80bbdcee98913df71731cbc8417a625438c68be54943108c3c`; analysis selected x86_64.

No debugger attachment, code injection, modification of Preview, private framework reuse, security setting changes, or third-party installations were performed. UI observation attempts use normal OS permissions only. A four-page comparison PDF was generated specifically for this study; no user documents were used.

## Confirmed static findings

REA Evidence `ev_a35fde01a0cf3d7ded5a65409f11751ebdea382239e34d3514ad3e1f37b188b8` exposes these class relationships:

| Preview class | Superclass | Implication |
| --- | --- | --- |
| PVToolbar | NSToolbar | Native AppKit toolbar foundation |
| PVToolbarItem | NSToolbarItem | App-specific configuration of native items |
| PVSegmentedToolbarItem | NSToolbarItemGroup | Semantic toolbar groups, not an arbitrary horizontal custom view |
| PVPopupMenuToolbarItem | NSToolbarItem | Specialized view/menu item |
| PVSplitViewController | NSSplitViewController | Native split item lifecycle and sidebar management |
| PVSidebarCollectionView | NSCollectionView | Collection-based sidebar |
| PVThumbnailSidebarController | NSViewController | Independent thumbnail controller |
| PVWindowController | NSWindowController | AppKit document window orchestration |

Relevant methods include:

- `PVSegmentedToolbarItem initWithIdentifier:tag:itemProperties:` at `0x10005e826`.
- `PVPopupMenuToolbarItem initWithIdentifier:tag:itemProperties:` at `0x10006226c`.
- `PVSplitViewController _openOrCloseSidebarAnimated:maintainingSidebarContentWidth:withCompletionHandler:` at `0x100070091`.
- `PVThumbnailSidebarController _thumbnailSizeToFitSidebarWidth:` at `0x100129343`.
- `PVThumbnailSidebarController _thumbnailAspectWithCachingForElement:` at `0x100129632`.
- `PVThumbnailSidebarController willAnimateToWidth:` at `0x100127c47` and `didAnimateToWidth:` at `0x100127cf1`.

`Contents/Resources/CommonToolbar.proplist` was read in place, not incorporated into our application. It declares a view-menu item using `sidebar.leading`, a sidebar tracking separator, grouped zoom-out/actual-size/zoom-in controls, optional previous/next page controls, fixed and flexible spaces, and search. Its default list is a packaged configuration, not proof of the user's active customized toolbar.

Metadata decoding is partial: some ivar pointers and Swift metadata could not be decoded. Methods establish available structure, not runtime invocation, animation timing, or exact property values. Focused assembly was inspected, but this toolchain did not resolve enough Objective-C message selectors to establish exact NSWindow configuration values. No such values are claimed as observed.

## Public API corroboration

Apple's WWDC25 session documents native floating toolbar glass, grouping of related items, separation with spaces, system sidebar materials, safe-area adjustments, and edge-to-edge document content. It also explains that control geometry depends on system control size. The circular/capsule appearance is framework rendering, not an asset that should be copied.

- https://developer.apple.com/videos/play/wwdc2025/310/
- https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass
- https://developer.apple.com/documentation/appkit/nstoolbaritem/isbordered

The installed public SDK confirms `NSToolbarItem.isBordered`, `NSToolbarItemGroup`, `NSMenuToolbarItem`, `NSToolbarItem.Identifier.sidebarTrackingSeparator`, `NSSplitViewItem(sidebarWithViewController:)`, `allowsFullHeightLayout`, `automaticallyAdjustsSafeAreaInsets` (macOS 26), and animator-based `isCollapsed` changes.

## Comparison and changes

| Previous implementation | Cause of difference | Implemented public API change |
| --- | --- | --- |
| Borderless SwiftUI buttons in custom NSHostingView toolbar items | Custom controls bypass system-generated toolbar button presentation | Native bordered NSToolbarItem actions and NSMenuToolbarItem sidebar menu |
| Zoom functions grouped only by SwiftUI HStack | No native toolbar group semantics | Momentary NSToolbarItemGroup with out/actual/in actions |
| Sidebar built with conditional HSplitView | No AppKit sidebar split-item behavior or toolbar divider tracking | NSSplitViewController, NSSplitViewItem.sidebar, sidebar tracking separator |
| No full-size content mask | Content layout stopped at title/toolbar boundary | fullSizeContentView, system-rendered titlebar backdrop, unified toolbar, full-height sidebar |
| Opaque sidebar fill and custom selection outline | Covers native material and hard-codes selection appearance | Transparent List with sidebar style and native selection |
| Fixed thumbnail width and height | Poor adaptation to sidebar width and mixed page aspect ratios | Width derived from available sidebar space, aspect-preserving thumbnails |
| Sidebar appeared/disappeared immediately | Conditional view insertion rather than split-item collapse | AppKit animator proxy, with Reduce Motion respected |
| Custom fixed toolbar height and borderless style | Overrides system geometry decisions | System toolbar sizing for buttons; only page entry remains a custom view |

The new window title uses the native document title and a page-count subtitle. These are public API choices, not verified copies of Preview's exact title policy. Current sidebar bounds (190–300 points) and thumbnail widths (96–144 points) are design choices informed by the screenshots, not exact recovered constants. In the initial Preview screenshot the sidebar is approximately 197 points wide and its PDF thumbnail approximately 130 points wide. Preview uses its own NSCollectionView-based sidebar, while our simpler sidebar uses native SwiftUI List selection. Exact selection geometry may differ.

No manually drawn blur or NSGlassEffectView overlay is used. NSToolbar and NSSplitViewController supply their system materials. PDFCanvas extends to the top safe-area edge when the search bar is absent; search remains in the unobscured region. The public PDFView.documentView.enclosingScrollView exposes NSScrollView.automaticallyAdjustsContentInsets. The canvas enables that system adjustment and positions a newly opened document once using the computed inset; no fixed toolbar height is used. The document split item opts into macOS 26 safe-area adjustment for overlaid sidebars. The system titlebar backdrop remains enabled. These settings were revised after rendered screenshots exposed a page overlapping the title and an incorrect initial viewport.

PDF rendering, navigation, text search, keyboard shortcuts, lazy thumbnail production, and the bounded cache remain in their existing modules. File drop handling is present in both the document canvas region and the sidebar.

## Rendered validation and remaining differences

The Intel Debug build succeeded. All six XCTest tests passed after the final inset initialization change. The window test verifies the native split sidebar, collapse/expand synchronization, full-size content mask, native menu-only sidebar item, bordered zoom group, and sidebar tracking separator. Existing PDF navigation and text-search tests still pass. The final successful test/build output is in `tests.log`.

### Captures actually inspected

| Capture | REA Evidence | Window pixels | Scope |
| --- | --- | --- | --- |
| `preview-0.png` | `ev_2f6f67bdc29a93fff8e044e2de76cfce7c06b757db87010e7749d3bb31692d0c` | 1035 × 925 | Preview, first page, dark appearance |
| `preview-scrolled.png` | `ev_79d816a81e9029b580c2e18a8e77711751a1380dc89e728e1c7773a6d5bfb5db` | 960 × 972 | Preview, same PDF scrolled; adaptive glass over colored content |
| `djvu-final.png` | `ev_e1c05ec808b807b727ce3378773f3db8797ec1870dfcefee1fb6b2ec90e6340d` | 960 × 972 | Final DjVu Preview, first page, dark appearance |

Both applications opened the generated `Comparison.pdf`. Successful AX/screenshot captures followed the user's permission change. Earlier attempts were blocked by unavailable permissions or window matching; no security setting was changed by the agent. AX JSON snapshots retain the exact selected process/window, node paths, capture dimensions, and Evidence identity.

Confirmed visually:

- Preview exposes a menu-only View/sidebar control and a three-button zoom group. Our final toolbar now uses the same public control categories and system capsule rendering.
- Both applications expose native AXToolbar and AXSplitGroup structures. Preview's thumbnail region is an AXList backed by NSCollectionView; ours is an AXOutline backed by SwiftUI List.
- The final title and page-count subtitle are readable, and the initial page begins below the toolbar rather than being covered by it.
- System sidebar surfaces have rounded inset edges; no synthetic blur layer is present in our implementation.
- Preview's scrolled capture visibly changes glass color with the blue PDF beneath it. Our full-size canvas and system scroll-edge/inset configuration also produced adaptive toolbar coloration in an intermediate capture (`ev_161fdc84f44064ef78abc86df3ac2f934acedb84e310d3d42601a3e618519c0f`). The final initialization change corrects the initial viewport without adding a custom material.

Remaining observed differences:

- Preview uses a narrower blue thumbnail-selection surround, including the page label. Our native List uses its system row selection and inactive gray emphasis. This is a component/design difference, not evidence that public APIs cannot reproduce Preview's selection. A future NSCollectionView implementation could provide closer behavior.
- Our sidebar menu sits farther left, and our toolbar includes page navigation, page entry, and fit controls absent from Preview's displayed default configuration. Preview includes annotation/editing controls outside this milestone.
- Thumbnail row padding and selection bounds remain different. The final sidebar is around 198 points wide, close to the observed Preview sidebar; exact pixel equality is not claimed.
- The initial and scrolled Preview captures have different scroll positions. Page-position comparison uses the first-page baseline; the 960 × 972 scrolled capture supports geometry and adaptive material observations, not identical page content alignment.

### Interactions and limits

The Preview View menu was opened through AXPress and its options were read: Hide Sidebar, Thumbnails, Table of Contents, Highlights and Notes, Bookmarks, Contact Sheet, Continuous Scroll, Single Page, and Two Pages. A subsequent AXPress on Hide Sidebar returned completion but did not establish a collapsed state; no claim of a successfully measured Preview collapse is made. Public scroll actions also returned unsupported errors, so they are not treated as successful scrolling observations. A later screenshot independently records the scrolled viewport.

The implementation uses AppKit's animator-based collapsed property, respecting Reduce Motion. Unit tests confirm the collapsed state stays synchronized, but screenshots are not frame-timed recordings. Exact duration, easing, morphing, and interaction parity remain unmeasured. Light appearance, Reduce Transparency, different glass preferences, VoiceOver behavior, and large-document performance need further manual validation.

**The rendered interfaces were inspected; visual equivalence is not claimed.** No private APIs, Apple resources, or proprietary implementation code were added to the application. All native REA sessions opened for this study were closed.
