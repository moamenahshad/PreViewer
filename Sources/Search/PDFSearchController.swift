import AppKit
import Combine
import PDFKit

/// PDFKit searches asynchronously. Results are bounded to avoid retaining every hit in large files.
@MainActor
final class PDFSearchController: NSObject, ObservableObject, @MainActor PDFDocumentDelegate {
    static let resultLimit = 500
    @Published var query = ""
    @Published private(set) var matches: [PDFSelection] = []
    @Published private(set) var isSearching = false
    @Published private(set) var isTruncated = false
    @Published private(set) var selectedIndex: Int?
    private weak var document: PDFDocument?
    private var acceptingResults = false
    private var pendingSearch: Task<Void, Never>?

    func attach(_ document: PDFDocument) {
        self.document?.cancelFindString()
        self.document?.delegate = nil
        self.document = document
        document.delegate = self
        clear()
    }

    func scheduleSearch() {
        pendingSearch?.cancel()
        acceptingResults = false
        document?.cancelFindString()
        matches = []
        selectedIndex = nil
        isTruncated = false
        isSearching = false
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return }
        pendingSearch = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self else { return }
            self.acceptingResults = true
            self.isSearching = true
            self.document?.beginFindString(term, withOptions: [.caseInsensitive])
        }
    }

    func clear() {
        pendingSearch?.cancel()
        acceptingResults = false
        document?.cancelFindString()
        query = ""
        matches = []
        selectedIndex = nil
        isSearching = false
        isTruncated = false
    }

    func didMatchString(_ instance: PDFSelection) {
        guard acceptingResults else { return }
        guard matches.count < Self.resultLimit else {
            isTruncated = true
            acceptingResults = false
            isSearching = false
            document?.cancelFindString()
            return
        }
        matches.append(instance)
    }

    func documentDidEndDocumentFind(_ notification: Notification) {
        guard acceptingResults else { return }
        isSearching = false
    }

    func advance(backward: Bool) -> PDFSelection? {
        guard !matches.isEmpty else { return nil }
        if let index = selectedIndex {
            selectedIndex = (index + (backward ? matches.count - 1 : 1)) % matches.count
        } else {
            selectedIndex = backward ? matches.count - 1 : 0
        }
        return matches[selectedIndex!]
    }
}
