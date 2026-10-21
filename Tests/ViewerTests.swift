import XCTest
import PDFKit
import CoreText
@testable import DjVuPreview

@MainActor
final class ViewerTests: XCTestCase {
    func testPageNavigationBounds() {
        XCTAssertEqual(PageNavigation.clampedIndex(-1, pageCount: 20), 0)
        XCTAssertEqual(PageNavigation.clampedIndex(20, pageCount: 20), 19)
        XCTAssertEqual(PageNavigation.clampedIndex(9, pageCount: 0), 0)
        XCTAssertEqual(PageNavigation.index(forPageNumber: "20", pageCount: 20), 19)
        XCTAssertNil(PageNavigation.index(forPageNumber: "0", pageCount: 20))
        XCTAssertNil(PageNavigation.index(forPageNumber: "21", pageCount: 20))
        XCTAssertNil(PageNavigation.index(forPageNumber: "abc", pageCount: 20))
    }

    func testPDFSessionAndPageNavigation() throws {
        let pdf = try fixture(pages: 3)
        let session = DocumentSession()
        session.attach(pdf, url: URL(fileURLWithPath: "/unused-fixture.pdf"))
        let view = PDFView()
        view.document = pdf
        session.pdfView = view
        XCTAssertEqual(session.pageCount, 3)
        session.go(to: 2)
        XCTAssertEqual(session.currentPageIndex, 2)
        XCTAssertFalse(session.canGoForward)
        session.go(to: -5)
        XCTAssertEqual(session.currentPageIndex, 0)
        XCTAssertFalse(session.canGoBack)
    }

    func testSearchFindsSelectableTextAndWraps() async throws {
        let pdf = try fixture(pages: 3)
        let search = PDFSearchController()
        search.attach(pdf)
        search.query = "needle"
        search.scheduleSearch()
        try await waitForSearch(search)
        XCTAssertEqual(search.matches.count, 3)
        XCTAssertEqual(search.advance(backward: false)?.string?.lowercased(), "needle")
        XCTAssertEqual(search.selectedIndex, 0)
        _ = search.advance(backward: true)
        XCTAssertEqual(search.selectedIndex, 2)
        search.clear()
        XCTAssertTrue(search.matches.isEmpty)
        XCTAssertNil(search.advance(backward: false))
    }

    func testReplacingSearchCancelsOldQuery() async throws {
        let pdf = try fixture(pages: 2)
        let search = PDFSearchController()
        search.attach(pdf)
        search.query = "needle"
        search.scheduleSearch()
        search.query = "absent"
        search.scheduleSearch()
        try await waitForSearch(search)
        XCTAssertTrue(search.matches.isEmpty)
        XCTAssertFalse(search.isSearching)
    }

    func testDocumentLoadingAndNativeToolbar() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("fixture.pdf")
        XCTAssertTrue(try fixture(pages: 2).write(to: url))
        let document = try ViewerDocument(contentsOf: url, ofType: "com.adobe.pdf")
        XCTAssertEqual(document.session.pageCount, 2)
        document.makeWindowControllers()
        let window = try XCTUnwrap(document.windowControllers.first?.window)
        XCTAssertNotNil(window.contentViewController)
        let toolbar = try XCTUnwrap(window.toolbar)
        XCTAssertTrue(window.styleMask.contains(.fullSizeContentView))
        XCTAssertFalse(window.titlebarAppearsTransparent)
        let controller = try XCTUnwrap(document.windowControllers.first as? ViewerWindowController)
        let split = try XCTUnwrap(window.contentViewController as? ViewerSplitViewController)
        XCTAssertEqual(split.splitViewItems.count, 2)
        XCTAssertEqual(split.thumbnailItem.behavior, .sidebar)
        XCTAssertFalse(split.thumbnailItem.isCollapsed)
        controller.toggleSidebar(nil)
        XCTAssertTrue(split.thumbnailItem.isCollapsed)
        controller.toggleSidebar(nil)
        XCTAssertFalse(split.thumbnailItem.isCollapsed)
        XCTAssertTrue(toolbar.items.contains { $0.itemIdentifier == .sidebarTrackingSeparator })
        let zoom = try XCTUnwrap(toolbar.items.first { $0.itemIdentifier.rawValue == "zoom" } as? NSToolbarItemGroup)
        XCTAssertEqual(zoom.subitems.count, 3)
        XCTAssertEqual(zoom.selectionMode, .momentary)
        XCTAssertTrue(zoom.isBordered)
        XCTAssertEqual(zoom.visibilityPriority, .low)
        XCTAssertFalse(zoom.title.isEmpty)
        XCTAssertEqual(zoom.menuFormRepresentation?.submenu?.items.map(\.action),
                       [#selector(controller.zoomOut(_:)), #selector(controller.actualSize(_:)), #selector(controller.zoomIn(_:))])
        XCTAssertFalse(toolbar.items.contains { $0.itemIdentifier.rawValue == "page" })
        XCTAssertFalse(controller.toolbarAllowedItemIdentifiers(toolbar).contains(.init("page")))
        XCTAssertEqual(window.subtitle, "Page 1 of 2")
        let sidebar = try XCTUnwrap(toolbar.items.first { $0.itemIdentifier.rawValue == "sidebar" } as? NSMenuToolbarItem)
        XCTAssertTrue(sidebar.isBordered)
        XCTAssertNil(sidebar.action) // One menu affordance, matching the observed View menu.
        XCTAssertNil(sidebar.view) // AppKit generates the system view rather than an NSHostingView.
        document.close()
    }

    func testToolbarAtSupportedWidthsAndAppearances() async throws {
        let session = DocumentSession()
        session.attach(try fixture(pages: 4), url: FileManager.default.temporaryDirectory.appendingPathComponent("toolbar-validation.pdf"))
        let controller = ViewerWindowController(session: session)
        let window = try XCTUnwrap(controller.window)
        defer { window.close() }
        window.setFrameAutosaveName("")
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            window.appearance = NSAppearance(named: appearance)
            for width in [1280, 960, 760, 640] {
                window.setFrame(NSRect(x: 40, y: 100, width: width, height: 700), display: true)
                window.makeKeyAndOrderFront(nil)
                try await Task.sleep(for: .milliseconds(700))
                window.title = "Toolbar Validation \(appearance.rawValue) \(width)"
                try await Task.sleep(for: .seconds(3))
                XCTAssertEqual(Int(window.frame.width), width)
                XCTAssertEqual(window.subtitle, "Page 1 of 4")
                let toolbar = try XCTUnwrap(window.toolbar)
                XCTAssertFalse(toolbar.items.contains { $0.itemIdentifier.rawValue == "page" })
                for group in toolbar.items.compactMap({ $0 as? NSToolbarItemGroup }) {
                    XCTAssertFalse(group.title.isEmpty)
                    XCTAssertFalse(try XCTUnwrap(group.menuFormRepresentation?.submenu).items.isEmpty)
                }
            }
        }
        controller.nextPage(nil)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(window.subtitle, "Page 2 of 4")
        controller.previousPage(nil)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(window.subtitle, "Page 1 of 4")
    }

    func testSearchResultRetentionIsBounded() async throws {
        let pdf = try fixture(pages: 1)
        let search = PDFSearchController()
        search.attach(pdf)
        search.query = "needle"
        search.scheduleSearch()
        try await waitForSearch(search)
        let selection = try XCTUnwrap(search.matches.first)
        // Exercise the callback boundary without building a huge PDF fixture.
        for _ in 0...PDFSearchController.resultLimit { search.didMatchString(selection) }
        XCTAssertEqual(search.matches.count, PDFSearchController.resultLimit)
        XCTAssertTrue(search.isTruncated)
        XCTAssertFalse(search.isSearching)
    }

    func testWelcomeDoesNotCreateDocumentsAndReusesItsWindow() throws {
        XCTAssertTrue(NSDocumentController.shared is ViewerDocumentController)
        let controller = try XCTUnwrap(NSDocumentController.shared as? ViewerDocumentController)
        controller.isTerminating = false
        defer { controller.isTerminating = true; controller.welcomeController?.close() }
        controller.newDocument(nil)
        let first = try XCTUnwrap(controller.welcomeController)
        XCTAssertTrue(controller.documents.isEmpty)
        XCTAssertTrue(first.window?.isVisible == true)
        controller.showWelcomeIfNeeded()
        XCTAssertTrue(controller.welcomeController === first)
        XCTAssertTrue(controller.documents.isEmpty)
    }

    func testWelcomeFollowsLastDocumentRemoval() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("lifecycle.pdf")
        XCTAssertTrue(try fixture(pages: 1).write(to: url))
        let controller = try XCTUnwrap(NSDocumentController.shared as? ViewerDocumentController)
        controller.isTerminating = false
        defer { controller.isTerminating = true; controller.welcomeController?.close() }
        controller.showWelcomeIfNeeded()
        let document = try ViewerDocument(contentsOf: url, ofType: "com.adobe.pdf")
        controller.addDocument(document)
        XCTAssertFalse(controller.welcomeController?.window?.isVisible == true)
        controller.showWelcomeIfNeeded()
        XCTAssertFalse(controller.welcomeController?.window?.isVisible == true)
        controller.removeDocument(document)
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertFalse(controller.welcomeController?.window?.isVisible == true)
        controller.showWelcomeAfterReopen()
        XCTAssertTrue(controller.welcomeController?.window?.isVisible == true)
        document.close()
    }

    func testWelcomeShortcutClosesDocumentAndShowsWelcome() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("shortcut.pdf")
        XCTAssertTrue(try fixture(pages: 1).write(to: url))
        let controller = try XCTUnwrap(NSDocumentController.shared as? ViewerDocumentController)
        controller.isTerminating = false
        controller.welcomeController?.close()
        let document = try ViewerDocument(contentsOf: url, ofType: "com.adobe.pdf")
        controller.addDocument(document)
        XCTAssertEqual(controller.documents.count, 1)
        controller.welcomeShortcut(nil)
        try await Task.sleep(for: .milliseconds(120))
        XCTAssertTrue(controller.documents.isEmpty)
        XCTAssertTrue(controller.welcomeController?.window?.isVisible == true)
        controller.welcomeController?.close()
        controller.isTerminating = true
        document.close()
    }

    func testFileLaunchOpensDirectlyAndRecordsRecentDate() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("direct.pdf")
        XCTAssertTrue(try fixture(pages: 1).write(to: url))
        let suite = "DjVuPreviewTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = try XCTUnwrap(NSDocumentController.shared as? ViewerDocumentController)
        controller.isTerminating = false
        let previousDefaults = controller.historyDefaults
        controller.historyDefaults = defaults
        defer { controller.historyDefaults = previousDefaults }
        controller.welcomeController?.close()
        defer {
            controller.isTerminating = true
            for document in controller.documents { controller.removeDocument(document); document.close() }
            controller.welcomeController?.close()
        }
        let success = await withCheckedContinuation { continuation in
            controller.openDocument(withContentsOf: url, display: true) { document, _, error in
                continuation.resume(returning: document != nil && error == nil)
            }
        }
        XCTAssertTrue(success)
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertFalse(controller.welcomeController?.window?.isVisible == true)
        XCTAssertEqual(controller.pendingOpenCount, 0)
        XCTAssertEqual(controller.documents.count, 1)
        XCTAssertNotNil(controller.lastOpenedDate(for: url))
        controller.refreshRecentDocuments()
        let recent = try XCTUnwrap(controller.recentDocuments.first { RecentDocument.fileKey($0.url) == RecentDocument.fileKey(url) })
        XCTAssertNotNil(recent.lastOpened)
        XCTAssertTrue(recent.isAvailable)
        XCTAssertNotNil(defaults.data(forKey: "RecentDocumentHistory"))
        let moved = directory.appendingPathComponent("renamed.pdf")
        try FileManager.default.moveItem(at: url, to: moved)
        controller.refreshRecentDocuments()
        let movedRecent = try XCTUnwrap(controller.recentDocuments.first { RecentDocument.fileKey($0.url) == RecentDocument.fileKey(moved) })
        XCTAssertTrue(movedRecent.isAvailable)
        XCTAssertEqual(movedRecent.lastOpened, recent.lastOpened)
        XCTAssertEqual(controller.lastOpenedDate(for: moved), recent.lastOpened)

    }

    func testFailedOpenRestoresWelcomeWithoutRecordingDate() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        let controller = try XCTUnwrap(NSDocumentController.shared as? ViewerDocumentController)
        controller.isTerminating = false
        defer { controller.isTerminating = true; controller.welcomeController?.close() }
        controller.showWelcomeIfNeeded()
        let failed = await withCheckedContinuation { continuation in
            controller.openDocument(withContentsOf: url, display: true) { document, _, error in
                continuation.resume(returning: document == nil && error != nil)
            }
        }
        XCTAssertTrue(failed)
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(controller.pendingOpenCount, 0)
        XCTAssertTrue(controller.documents.isEmpty)
        XCTAssertNil(controller.lastOpenedDate(for: url))
        XCTAssertTrue(controller.welcomeController?.window?.isVisible == true)
    }

    func testMissingRecentDocumentHasNoInventedLastOpenedDate() throws {
        let missing = URL(fileURLWithPath: "/nonexistent/" + UUID().uuidString + ".pdf")
        let entries = RecentDocument.entries(for: [missing], dates: [:])
        let entry = try XCTUnwrap(entries.first)
        XCTAssertEqual(entries.count, 1)
        XCTAssertFalse(entry.isAvailable)
        XCTAssertNil(entry.lastOpened)
    }

    private func waitForSearch(_ search: PDFSearchController) async throws {
        // Allow the debounce to elapse, then yield the main thread to PDFKit's notifications.
        try await Task.sleep(for: .milliseconds(400))
        for _ in 0..<100 {
            if !search.isSearching { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("PDF search did not finish")
    }

    private func fixture(pages: Int) throws -> PDFDocument {
        let data = NSMutableData()
        let consumer = try XCTUnwrap(CGDataConsumer(data: data))
        var box = CGRect(x: 0, y: 0, width: 300, height: 400)
        let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &box, nil))
        for _ in 0..<pages {
            context.beginPDFPage(nil)
            let text = NSAttributedString(string: "Needle in a PDF", attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, 18, nil)
            ])
            context.textPosition = CGPoint(x: 20, y: 300)
            CTLineDraw(CTLineCreateWithAttributedString(text), context)
            context.endPDFPage()
        }
        context.closePDF()
        return try XCTUnwrap(PDFDocument(data: data as Data))
    }
}

