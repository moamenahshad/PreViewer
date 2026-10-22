import XCTest
import PDFKit
import Darwin
import UniformTypeIdentifiers
@testable import DjVuPreview

@MainActor
final class DjVuTests: XCTestCase {
    private var fixture: URL { URL(fileURLWithPath:#filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/generated.djvu") }
    func testNativeOpenPanelAcceptsRegisteredDjVuAndPDFTypes() async throws {
        let controller = try XCTUnwrap(NSDocumentController.shared as? ViewerDocumentController)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let shortExtension = directory.appendingPathComponent("sample.djv")
        try FileManager.default.copyItem(at: fixture, to: shortExtension)
        let panel = NSOpenPanel()
        panel.directoryURL = fixture.deletingLastPathComponent()
        controller.beginOpenPanel(panel, forTypes: ViewerDocument.readableTypes) { _ in }
        defer { panel.cancel(nil) }
        try await Task.sleep(for: .milliseconds(300))
        let allowed = panel.allowedContentTypes
        XCTAssertTrue(allowed.contains(.pdf))
        for url in [fixture, shortExtension] {
            let actualType = try XCTUnwrap(url.resourceValues(forKeys: [.contentTypeKey]).contentType)
            XCTAssertTrue(allowed.contains { actualType.conforms(to: $0) }, "Open panel excludes \(url.pathExtension): \(actualType.identifier)")
            XCTAssertEqual(try controller.typeForContents(of: url), "com.lizardtech.djvu")
        }
        for ext in ["djvu", "djv"] {
            for type in UTType.types(tag: ext, tagClass: .filenameExtension, conformingTo: nil) {
                XCTAssertTrue(allowed.contains(type), "Missing installed DjVu association: \(type.identifier)")
            }
        }
        XCTAssertFalse(allowed.contains(.data))
        XCTAssertFalse(allowed.contains(.item))
    }

    func testDirectDecoderTextOutlineAndBoundedCache() async throws {
        let backend = DjVuDocumentBackend(url:fixture)
        let summary = try await backend.prepare()
        XCTAssertEqual(summary.pages.count,3)
        XCTAssertEqual(summary.pages[0].dpi,300)
        XCTAssertEqual(summary.outline.count,2)
        XCTAssertEqual(summary.metadata["Title"],"DjVu integration fixture")
        let words = try await backend.words(0)
        XCTAssertEqual(words.map(\.text),["DjVu","needle"])
        let raster = try await backend.render(0,maximumDimension:300)
        XCTAssertEqual(raster.width,200)
        XCTAssertEqual(raster.height,300)
        XCTAssertNotNil(raster.image)
        let bytes = await backend.cachedByteCount()
        XCTAssertLessThanOrEqual(bytes,DjVuDocumentBackend.cacheLimit)
        let document = try ViewerDocument(contentsOf:fixture,ofType:"org.djvu.djvu")
        defer { document.close() }
        for _ in 0..<200 where document.session.isLoading { try await Task.sleep(for:.milliseconds(20)) }
        XCTAssertTrue(document.session.isDjVu)
        XCTAssertNil(document.session.pdf) // Direct decoding, no hidden PDF conversion.
        XCTAssertEqual(document.session.pageCount,3)
        document.session.djvuQuery = "needle"; document.session.searchDjVu()
        for _ in 0..<200 where document.session.djvuSearching { try await Task.sleep(for:.milliseconds(20)) }
        XCTAssertEqual(document.session.djvuMatches,[0])
    }
    func testDjVuMatchNavigationStartsAndWrapsCorrectly() {
        XCTAssertEqual(DocumentSession.nextDjVuMatchIndex(current: -1, count: 1, backward: false), 0)
        XCTAssertEqual(DocumentSession.nextDjVuMatchIndex(current: -1, count: 1, backward: true), 0)
        XCTAssertEqual(DocumentSession.nextDjVuMatchIndex(current: -1, count: 3, backward: false), 0)
        XCTAssertEqual(DocumentSession.nextDjVuMatchIndex(current: -1, count: 3, backward: true), 2)
        XCTAssertEqual(DocumentSession.nextDjVuMatchIndex(current: 0, count: 3, backward: true), 2)
        XCTAssertEqual(DocumentSession.nextDjVuMatchIndex(current: 2, count: 3, backward: false), 0)
        XCTAssertEqual(DocumentSession.nextDjVuMatchIndex(current: 0, count: 3, backward: false), 1)
        XCTAssertEqual(DocumentSession.nextDjVuMatchIndex(current: 2, count: 3, backward: true), 1)
    }
    func testDjVuCanvasContextMenuProvidesNativeReaderActions() {
        let session = DocumentSession()
        let canvas = DjVuCanvasView(session: session)
        let menu = canvas.contextMenu()
        let expectedTitles = [L10n.string("Copy"), L10n.string("Select All"), "", L10n.string("Find…")]
        XCTAssertEqual(menu.items.map(\.title), expectedTitles)
        XCTAssertFalse(menu.items.first?.isEnabled ?? true)
        XCTAssertFalse(menu.items.last?.isEnabled ?? true)
    }
    func testConversionPresetsResolutionTextAndEstimate() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:directory) }
        let summary = try await DjVuDocumentBackend(url:fixture).prepare()
        var sizes: [Int64] = []
        for quality in DjVuToPDFOptions.Quality.allCases {
            var options = DjVuToPDFOptions(); options.quality = quality
            let url = directory.appendingPathComponent(quality.rawValue+".pdf")
            let result = try await DjVuToPDFConverter(source:fixture).convert(to:url,options:options)
            sizes.append(result.bytes)
            let pdf = try XCTUnwrap(PDFDocument(url:url))
            XCTAssertEqual(pdf.pageCount,3)
            XCTAssertTrue(pdf.string?.contains("needle") == true)
            XCTAssertEqual(pdf.page(at:0)?.bounds(for:.mediaBox).width ?? 0,72,accuracy:0.1)
            XCTAssertEqual(pdf.outlineRoot?.numberOfChildren,2)
            XCTAssertEqual(pdf.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String,"DjVu integration fixture")
            let bytes = try Data(contentsOf:url)
            let raw = String(decoding:bytes,as:UTF8.self)
            XCTAssertTrue(raw.contains(quality == .maximum ? "/FlateDecode" : "/DCTDecode"))
            let measured = try await DjVuToPDFSizeEstimator(source:fixture).estimate(summary:summary,options:options)
            let estimate = try XCTUnwrap(measured)
            print("ESTIMATE \(quality.rawValue): \(estimate.lower)...\(estimate.upper); actual \(result.bytes)")
            XCTAssertGreaterThan(estimate.upper,estimate.lower)
            XCTAssertGreaterThanOrEqual(result.bytes,estimate.lower)
            XCTAssertLessThanOrEqual(result.bytes,estimate.upper)
        }
        XCTAssertGreaterThan(Set(sizes).count,1)
        var options = DjVuToPDFOptions(); options.resolution = .dpi150
        XCTAssertEqual(options.dimension(summary.pages[0]),225)
        options.resolution = .dpi300
        XCTAssertEqual(options.dimension(summary.pages[0]),450) // Never upscale.
        options.text = false; options.outline = false; options.metadata = false
        let output = directory.appendingPathComponent("without-text.pdf")
        _ = try await DjVuToPDFConverter(source:fixture).convert(to:output,options:options)
        XCTAssertFalse(PDFDocument(url:output)?.string?.contains("needle") == true)
    }
    func testMultipageBookAndRasterFidelity() async throws {
        let book = fixture.deletingLastPathComponent().appendingPathComponent("djvulibre-book-en.djvu")
        let backend = DjVuDocumentBackend(url:book)
        let summary = try await backend.prepare()
        XCTAssertEqual(summary.pages.count,57)
        for index in [0,28,56] {
            let raster = try await backend.render(index,maximumDimension:900)
            XCTAssertNotNil(raster.image)
        }
        let retained = await backend.cachedByteCount()
        XCTAssertLessThanOrEqual(retained,DjVuDocumentBackend.cacheLimit)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:directory) }
        var options = DjVuToPDFOptions(); options.resolution = .dpi150
        let output = directory.appendingPathComponent("book.pdf")
        let conversion = try await DjVuToPDFConverter(source:book).convert(to:output,options:options) { page,_ in
            print("MEMORY page \(page): \(residentBytes()) bytes resident")
        }
        XCTAssertEqual(PDFDocument(url:output)?.pageCount,57)
        print("BOOK 57 pages: \(conversion.bytes) bytes, \(conversion.duration) seconds; viewer cache \(retained) bytes")
        let measured = try await DjVuToPDFSizeEstimator(source:book).estimate(summary:summary,options:options)
        let estimate = try XCTUnwrap(measured)
        print("BOOK ESTIMATE: \(estimate.lower)...\(estimate.upper); actual \(conversion.bytes)")
        XCTAssertLessThan(estimate.sampleCount,summary.pages.count)
        let raster = try await DjVuDocumentBackend(url:fixture).render(0,maximumDimension:450)
        let faithful = directory.appendingPathComponent("faithful.pdf")
        options = .init(); options.quality = .maximum; options.text = false
        _ = try await DjVuToPDFConverter(source:fixture).convert(to:faithful,options:options,pages:[0])
        let pdf = try XCTUnwrap(CGPDFDocument(faithful as CFURL))
        let page = try XCTUnwrap(pdf.page(at:1))
        func pixels(pdfPage: CGPDFPage?) throws -> [UInt8] {
            let context = try XCTUnwrap(CGContext(data:nil,width:raster.width,height:raster.height,bitsPerComponent:8,bytesPerRow:raster.width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue))
            if let pdfPage {
                context.scaleBy(x:CGFloat(raster.width)/72,y:CGFloat(raster.height)/108)
                context.drawPDFPage(pdfPage)
            } else { context.draw(try XCTUnwrap(raster.image),in:CGRect(x:0,y:0,width:raster.width,height:raster.height)) }
            let data = try XCTUnwrap(context.data)
            return Array(UnsafeBufferPointer(start:data.assumingMemoryBound(to:UInt8.self),count:raster.width*raster.height*4))
        }
        let original = try pixels(pdfPage:nil), rendered = try pixels(pdfPage:page)
        let difference = zip(original,rendered).enumerated().filter { $0.offset % 4 != 3 }.reduce(0.0) { $0+Double(abs(Int($1.element.0)-Int($1.element.1))) } / Double(raster.width*raster.height*3)
        XCTAssertLessThan(difference,0.1,"Lossless PDF must preserve source raster pixels")
    }

    func testBilevelPageStaysOneBitWithoutJPEG() async throws {
        let source = fixture.deletingLastPathComponent().appendingPathComponent("djvulibre-book-en.djvu")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:directory) }
        var options = DjVuToPDFOptions()
        options.quality = .smaller
        options.text = false
        let output = directory.appendingPathComponent("bilevel.pdf")
        _ = try await DjVuToPDFConverter(source:source).convert(to:output,options:options,pages:[0])
        let pdf = try XCTUnwrap(PDFDocument(url:output))
        XCTAssertEqual(pdf.pageCount,1)
        XCTAssertEqual(pdf.page(at:0)?.bounds(for:.mediaBox).width ?? 0,612,accuracy:0.1)
        let bytes = String(decoding:try Data(contentsOf:output),as:UTF8.self)
        XCTAssertTrue(bytes.contains("/BitsPerComponent 1"))
        XCTAssertTrue(bytes.contains("/FlateDecode"))
        XCTAssertFalse(bytes.contains("/DCTDecode"),"Bilevel source must remain lossless even at Smaller File")
    }

    func testRotationAndResolutionOutput() async throws {
        let source = fixture.deletingLastPathComponent().appendingPathComponent("rotated.djvu")
        let summary = try await DjVuDocumentBackend(url:source).prepare()
        XCTAssertEqual(summary.pages[0].rotation,1)
        let thumbnail = try await DjVuDocumentBackend(url:source).render(0,maximumDimension:300)
        XCTAssertEqual(thumbnail.orientedImage?.width,300)
        XCTAssertEqual(thumbnail.orientedImage?.height,200)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:directory) }
        for resolution in DjVuToPDFOptions.Resolution.allCases {
            var options = DjVuToPDFOptions(); options.resolution = resolution
            let output = directory.appendingPathComponent(resolution.rawValue+".pdf")
            _ = try await DjVuToPDFConverter(source:source).convert(to:output,options:options)
            let pdf = try XCTUnwrap(PDFDocument(url:output))
            let page = try XCTUnwrap(pdf.page(at:0))
            XCTAssertEqual(page.bounds(for:.mediaBox).width,108,accuracy:0.1)
            XCTAssertEqual(page.bounds(for:.mediaBox).height,72,accuracy:0.1)
            XCTAssertTrue(page.string?.contains("needle") == true)
            let expected = resolution == .dpi150 ? 150 : 300
            XCTAssertTrue(String(decoding:try Data(contentsOf:output),as:UTF8.self).contains("/Width \(expected)"))
        }
    }

    func testCancellationAndCorruptInput() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:directory) }
        let output = directory.appendingPathComponent("cancelled.pdf")
        let originalBytes = try Data(contentsOf:fixture)
        do { _ = try await DjVuToPDFConverter(source:fixture).convert(to:fixture,options:.init()); XCTFail("Source overwrite accepted") } catch { }
        XCTAssertEqual(try Data(contentsOf:fixture), originalBytes)
        let converter = DjVuToPDFConverter(source:fixture)
        let task = Task { try await converter.convert(to:output,options:.init()) { page,_ in if page == 1 { converter.cancel() } } }
        do { _ = try await task.value; XCTFail("Cancelled conversion should not finish") } catch { }
        XCTAssertFalse(FileManager.default.fileExists(atPath:output.path))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath:directory.path).isEmpty)
        let estimator = DjVuToPDFSizeEstimator(source:fixture)
        estimator.cancel()
        let summary = try await DjVuDocumentBackend(url:fixture).prepare()
        do { _ = try await estimator.estimate(summary:summary,options:.init()); XCTFail("Cancelled estimate should fail") } catch { }
        let corrupt = directory.appendingPathComponent("bad.djvu")
        try Data("not a DjVu".utf8).write(to:corrupt)
        do { _ = try await DjVuDocumentBackend(url:corrupt).prepare(); XCTFail("Corrupt document accepted") } catch { }
    }
    func testConversionWindowModelCompletionAndSettingsReplacement() async throws {
        let summary = try await DjVuDocumentBackend(url:fixture).prepare()
        let model = DjVuToPDFModel(source:fixture,summary:summary)
        defer { model.close() }
        model.recalculate()
        model.options.quality = .maximum
        model.recalculate() // Cancels the previous estimate and its decoder.
        for _ in 0..<300 where model.estimating { try await Task.sleep(for:.milliseconds(20)) }
        XCTAssertNotNil(model.estimate)
        XCTAssertEqual(model.options.quality,.maximum)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:directory) }
        model.destination = directory.appendingPathComponent("model-output.pdf")
        model.convert()
        for _ in 0..<300 where model.converting { try await Task.sleep(for:.milliseconds(20)) }
        XCTAssertNil(model.error)
        let result = try XCTUnwrap(model.result)
        XCTAssertEqual(result.url,model.destination)
        XCTAssertGreaterThan(result.bytes,0)
        XCTAssertGreaterThan(result.duration,0)
        XCTAssertEqual(model.completed,3)
    }

    func testNativeDjVuWindowsLightDarkAndResize() async throws {
        let document = try ViewerDocument(contentsOf:fixture,ofType:"org.djvu.djvu")
        defer { document.close() }
        for _ in 0..<200 where document.session.isLoading { try await Task.sleep(for:.milliseconds(20)) }
        XCTAssertNil(document.session.openingError)
        document.makeWindowControllers()
        let viewer = try XCTUnwrap(document.windowControllers.first as? ViewerWindowController)
        let window = try XCTUnwrap(viewer.window)
        window.setFrameAutosaveName("")
        let summary = try XCTUnwrap(document.session.djvuSummary)
        let conversion = DjVuToPDFWindowController(source:fixture,summary:summary)
        defer { conversion.close() }
        XCTAssertEqual(conversion.window?.contentView?.frame.width ?? 0,620,accuracy:1)
        XCTAssertEqual(conversion.window?.contentView?.frame.height ?? 0,760,accuracy:1)
        for appearance in [NSAppearance.Name.aqua,.darkAqua] {
            window.appearance = NSAppearance(named:appearance)
            window.setFrame(NSRect(x:40,y:100,width:960,height:700),display:true)
            window.makeKeyAndOrderFront(nil)
            try await Task.sleep(for:.seconds(1))
            window.title = "DjVu Validation \(appearance.rawValue)"
            try await Task.sleep(for:.seconds(2))
            viewer.nextPage(nil)
            XCTAssertEqual(document.session.currentPageIndex,1)
            document.session.zoomIn(); document.session.zoomOut(); document.session.fitToWidth()
            viewer.firstPage(nil)
            // Rapid navigation replaces offscreen requests; returning to the page must still render.
            for page in [2, 0, 1, 0] {
                document.session.go(to:page)
                await Task.yield()
            }
            try await Task.sleep(for:.milliseconds(400))
            XCTAssertEqual(document.session.currentPageIndex,0)
            XCTAssertTrue((document.session.djvuView?.accessibilityValue() as? String)?.contains("needle") == true)
            conversion.window?.appearance = NSAppearance(named:appearance)
            conversion.window?.setFrame(NSRect(x:100,y:100,width:620,height:760),display:true)
            conversion.showWindow(nil)
            try await Task.sleep(for:.seconds(1))
            conversion.window?.title = "DjVu to PDF"
            try await Task.sleep(for:.seconds(2))
            conversion.window?.setFrame(NSRect(x:100,y:100,width:520,height:560),display:true)
            try await Task.sleep(for:.milliseconds(300))
        }
        XCTAssertNotNil(conversion.model.estimate)
    }
}

private func residentBytes() -> UInt64 {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
    let status = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
        }
    }
    return status == KERN_SUCCESS ? info.resident_size : 0
}
