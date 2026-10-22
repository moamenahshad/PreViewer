import AppKit
import Combine
import PDFKit

/// Per-window state routes PDF and DjVu actions to independent rendering backends.
/// Conversion services will consume source URLs independently of viewer state.
@MainActor
final class DocumentSession: ObservableObject {
    @Published private(set) var pdf: PDFDocument?
    @Published private(set) var sourceURL: URL?
    @Published private(set) var currentPageIndex = 0
    @Published private(set) var scale: CGFloat = 1
    @Published var sidebarVisible = true
    @Published var searchVisible = false
    @Published private(set) var searchFocusRequest = UUID()
    @Published var pageNumberText = "1"
    let search = PDFSearchController()
    let thumbnails = ThumbnailStore()
    weak var pdfView: PDFView?

    enum DjVuFit { case width, page, manual }
    @Published private(set) var djvuSummary: DjVuSummary?
    @Published var openingError: String?
    @Published var isLoading = false
    @Published var djvuQuery = ""
    @Published private(set) var djvuMatches: [Int] = []
    @Published private(set) var djvuSearching = false
    @Published private(set) var djvuSearchError: String?
    @Published private(set) var djvuSearchIncomplete = false
    var djvuBackend: DjVuDocumentBackend?
    weak var djvuView: DjVuCanvasView?
    var djvuScale: CGFloat = 1
    // Start with a sheet-like page preview; users can switch to width or manual zoom.
    var djvuFit: DjVuFit = .page
    private var openingTask: Task<Void, Never>?
    private var djvuSearchTask: Task<Void, Never>?
    private var djvuMatchIndex = -1
    private var djvuSearchRequestID = UUID()
    var isDjVu: Bool { djvuBackend != nil }
    var hasSearchMatches: Bool { isDjVu ? !djvuMatches.isEmpty : !search.matches.isEmpty }

    func openDjVu(_ url: URL) {
        sourceURL = url
        let backend = DjVuDocumentBackend(url: url)
        djvuBackend = backend
        thumbnails.attach(djvu: backend)
        isLoading = true
        openingTask = Task {
            do {
                let summary = try await backend.prepare()
                try Task.checkCancellation()
                djvuSummary = summary
            } catch is CancellationError { }
            catch { openingError = error.localizedDescription }
            isLoading = false
        }
    }
    func cancelDjVuWork() { openingTask?.cancel(); djvuSearchTask?.cancel(); djvuBackend?.cancel() }
    func setDjVuPage(_ index: Int) {
        guard currentPageIndex != index else { return }
        currentPageIndex = index
        pageNumberText = String(index+1)
    }
    func searchDjVu() {
        djvuSearchTask?.cancel(); djvuSearchRequestID = UUID()
        let requestID = djvuSearchRequestID
        djvuMatches = []; djvuMatchIndex = -1
        djvuSearchError = nil; djvuSearchIncomplete = false
        let query = djvuQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, let backend = djvuBackend else { djvuSearching = false; return }
        djvuSearching = true
        djvuSearchTask = Task(priority: .utility) {
            do {
                try await Task.sleep(for: .milliseconds(250))
                for index in 0..<pageCount {
                    try Task.checkCancellation()
                    let text = try await backend.words(index).map(\.text).joined(separator: " ")
                    try Task.checkCancellation()
                    guard djvuSearchRequestID == requestID else { return }
                    if text.localizedCaseInsensitiveContains(query) { djvuMatches.append(index) }
                    if djvuMatches.count >= 500 {
                        djvuSearchIncomplete = true
                        break
                    }
                }
                guard djvuSearchRequestID == requestID else { return }
                djvuSearching = false
            } catch is CancellationError { }
            catch {
                guard !Task.isCancelled, djvuSearchRequestID == requestID else { return }
                djvuSearchError = error.localizedDescription
                djvuSearchIncomplete = true
                djvuSearching = false
            }
        }
    }

    var pageCount: Int { djvuSummary?.pages.count ?? pdf?.pageCount ?? 0 }
    var hasDocument: Bool { pageCount > 0 }
    var canGoBack: Bool { hasDocument && currentPageIndex > 0 }
    var canGoForward: Bool { hasDocument && currentPageIndex < pageCount - 1 }

    func attach(_ document: PDFDocument, url: URL) {
        pdf = document
        sourceURL = url
        currentPageIndex = 0
        pageNumberText = "1"
        search.attach(document)
        thumbnails.attach(url: url)
    }

    func go(to index: Int) {
        if isDjVu { djvuView?.go(to: PageNavigation.clampedIndex(index, pageCount: pageCount)); return }
        guard let pdf, let page = pdf.page(at: PageNavigation.clampedIndex(index, pageCount: pageCount)) else { return }
        pdfView?.go(to: page)
        synchronizePage()
    }

    func submitPageNumber() {
        if let index = PageNavigation.index(forPageNumber: pageNumberText, pageCount: pageCount) { go(to: index) }
        pageNumberText = String(currentPageIndex + 1)
    }

    func synchronizePage() {
        guard let view = pdfView, let pdf, let page = view.currentPage else { return }
        let index = pdf.index(for: page)
        guard index != NSNotFound else { return }
        currentPageIndex = index
        pageNumberText = String(index + 1)
    }

    func synchronizeScale() { scale = pdfView?.scaleFactor ?? 1 }
    func zoomIn() {
        if isDjVu { djvuFit = .manual; djvuScale = min(8, djvuScale*1.2); djvuView?.layoutPages(); return }; pdfView?.autoScales = false; pdfView?.zoomIn(nil); synchronizeScale() }
    func zoomOut() {
        if isDjVu { djvuFit = .manual; djvuScale = max(0.1, djvuScale/1.2); djvuView?.layoutPages(); return }; pdfView?.autoScales = false; pdfView?.zoomOut(nil); synchronizeScale() }
    func actualSize() {
        if isDjVu { djvuFit = .manual; djvuScale = 1; djvuView?.layoutPages(); return }; pdfView?.autoScales = false; pdfView?.scaleFactor = 1; synchronizeScale() }
    func fitToWindow() {
        if isDjVu { djvuFit = .page; djvuView?.layoutPages(); return }; pdfView?.autoScales = true; synchronizeScale() }

    func requestSearch() {
        searchVisible = true
        searchFocusRequest = UUID()
    }

    func fitToWidth() {
        if isDjVu { djvuFit = .width; djvuView?.layoutPages() }
        else { fitToWindow() }
    }
    func revealMatch(backward: Bool = false) {
        if isDjVu {
            guard !djvuMatches.isEmpty else { return }
            djvuMatchIndex = Self.nextDjVuMatchIndex(current: djvuMatchIndex, count: djvuMatches.count, backward: backward)
            go(to: djvuMatches[djvuMatchIndex]); return
        }
        guard let selection = search.advance(backward: backward) else { return }
        pdfView?.setCurrentSelection(selection, animate: true)
        pdfView?.go(to: selection)
    }

    static func nextDjVuMatchIndex(current: Int, count: Int, backward: Bool) -> Int {
        guard count > 0 else { return -1 }
        if current < 0 { return backward ? count - 1 : 0 }
        return (current + (backward ? count - 1 : 1)) % count
    }
}
