import AppKit
import Combine
import UniformTypeIdentifiers

struct RecentDocument: Identifiable {
    let url: URL
    let lastOpened: Date?
    let isAvailable: Bool
    var id: String { Self.fileKey(url) }
    static func fileKey(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().absoluteString
    }

    static func entries(for urls: [URL], dates: [String: Date]) -> [RecentDocument] {
        urls.map { url in
            RecentDocument(url: url, lastOpened: dates[url.standardizedFileURL.absoluteString],
                           isAvailable: FileManager.default.fileExists(atPath: url.path))
        }
    }
}

/// Uses AppKit recents where available, with a bounded app-local history for API/Finder opens.
@MainActor
final class ViewerDocumentController: NSDocumentController, ObservableObject {
    @Published private(set) var recentDocuments: [RecentDocument] = []
    private(set) var pendingOpenCount = 0
    private(set) var welcomeController: WelcomeWindowController?
    var isTerminating = false
    var historyDefaults: UserDefaults
    private let historyKey = "RecentDocumentLastOpenedDates"
    private let recordsKey = "RecentDocumentHistory"
    private let recentLimit = 20

    private struct StoredRecentDocument: Codable {
        let url: URL
        let lastOpened: Date
        let bookmark: Data?

        var resolvedURL: URL {
            guard let bookmark else { return url }
            var stale = false
            return (try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting],
                             relativeTo: nil, bookmarkDataIsStale: &stale)) ?? url
        }
    }
    private var welcomeUpdate: Task<Void, Never>?
    private var returningToWelcome = false

    override init() {
        historyDefaults = .standard
        super.init()
        refreshRecentDocuments()
    }

    required init?(coder: NSCoder) {
        historyDefaults = .standard
        super.init(coder: coder)
        refreshRecentDocuments()
    }

    /// DjVu associations from other installed apps need not conform to our declared UTI.
    /// Include their registered extension types in AppKit's native Open panel filter.
    func openPanelTypeIdentifiers(including types: [String]?) -> [String] {
        var identifiers = types ?? []
        for identifier in [UTType.pdf.identifier, "com.lizardtech.djvu", "org.djvu.djvu"] {
            if !identifiers.contains(identifier) { identifiers.append(identifier) }
        }
        for extensionName in ["djvu", "djv"] {
            for type in UTType.types(tag: extensionName, tagClass: .filenameExtension, conformingTo: nil) {
                if !identifiers.contains(type.identifier) { identifiers.append(type.identifier) }
            }
        }
        return identifiers
    }

    override func beginOpenPanel(_ openPanel: NSOpenPanel, forTypes inTypes: [String]?,
                                 completionHandler: @escaping (Int) -> Void) {
        // Keep the native panel predictable and large enough for long filenames and the sidebar.
        openPanel.setContentSize(NSSize(width: 900, height: 600))
        openPanel.minSize = NSSize(width: 700, height: 460)
        openPanel.center()
        super.beginOpenPanel(openPanel, forTypes: openPanelTypeIdentifiers(including: inTypes),
                             completionHandler: completionHandler)
    }

    override func newDocument(_ sender: Any?) {
        // Cmd-N returns to the welcome surface; this viewer never manufactures
        // an empty NSDocument.
        if documents.isEmpty {
            showWelcomeIfNeeded()
        } else {
            returnToWelcome()
        }
    }

    @objc func welcomeShortcut(_ sender: Any?) {
        if documents.isEmpty {
            showWelcomeIfNeeded()
        } else {
            returnToWelcome()
        }
    }

    func returnToWelcome() {
        returningToWelcome = true
        let openDocuments = documents
        openDocuments.forEach { $0.close() }
        Task { @MainActor [weak self] in
            guard let self, !self.isTerminating else { return }
            // NSDocument.close can finish its controller bookkeeping on the next
            // main-actor turn. Give it a bounded opportunity before the fallback.
            for _ in 0..<10 {
                if self.documents.isEmpty { break }
                await Task.yield()
            }
            if self.documents.isEmpty {
                self.returningToWelcome = false
                self.showWelcomeIfNeeded()
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
        }
    }

    override func addDocument(_ document: NSDocument) {
        super.addDocument(document)
        welcomeController?.close()
    }

    override func removeDocument(_ document: NSDocument) {
        super.removeDocument(document)
        guard documents.isEmpty else { return }
        if returningToWelcome {
            returningToWelcome = false
            showWelcomeIfNeeded()
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }
        // Closing a document returns the app to the Dock. The welcome window is shown
        // when the user clicks the app again, matching the native document-app flow.
        welcomeController?.close()
        NSApplication.shared.hide(nil)
    }

    override func openDocument(withContentsOf url: URL, display displayDocument: Bool,
                               completionHandler: @escaping (NSDocument?, Bool, (any Error)?) -> Void) {
        pendingOpenCount += 1
        welcomeUpdate?.cancel()
        // A Finder/open-panel request must not briefly reveal the welcome window.
        welcomeController?.close()
        super.openDocument(withContentsOf: url, display: displayDocument) { [weak self] document, alreadyOpen, error in
            guard let self else { completionHandler(document, alreadyOpen, error); return }
            self.pendingOpenCount -= 1
            if document != nil, error == nil { self.recordSuccessfulOpen(url) }
            completionHandler(document, alreadyOpen, error)
            self.scheduleWelcomeUpdate()
        }
    }

    func scheduleWelcomeUpdate() {
        welcomeUpdate?.cancel()
        welcomeUpdate = Task { @MainActor [weak self] in
            // Allow NSDocument.close and queued open requests to finish their lifecycle changes.
            await Task.yield()
            guard !Task.isCancelled else { return }
            self?.showWelcomeIfNeeded()
        }
    }

    func showWelcomeIfNeeded() {
        guard !isTerminating, documents.isEmpty, pendingOpenCount == 0 else {
            welcomeController?.close()
            return
        }
        refreshRecentDocuments()
        if welcomeController == nil { welcomeController = WelcomeWindowController(documents: self) }
        welcomeController?.showWindow(nil)
        welcomeController?.window?.makeKeyAndOrderFront(nil)
    }

    func showWelcomeAfterReopen() {
        guard documents.isEmpty else { return }
        showWelcomeIfNeeded()
    }

    private func storedRecentDocuments() -> [StoredRecentDocument] {
        if let data = historyDefaults.data(forKey: recordsKey),
           let records = try? JSONDecoder().decode([StoredRecentDocument].self, from: data) {
            return records
        }
        // Migrate dates recorded by the first welcome build; these keys are already file URLs.
        let dates = historyDefaults.dictionary(forKey: historyKey) as? [String: Date] ?? [:]
        return dates.compactMap { key, date in
            guard let url = URL(string: key), url.isFileURL else { return nil }
            return StoredRecentDocument(url: url, lastOpened: date, bookmark: nil)
        }.sorted { $0.lastOpened > $1.lastOpened }
    }

    func refreshRecentDocuments() {
        let dates = historyDefaults.dictionary(forKey: historyKey) as? [String: Date] ?? [:]
        let stored = storedRecentDocuments().sorted { $0.lastOpened > $1.lastOpened }
        var orderedURLs: [URL] = []
        var knownDates: [String: Date] = [:]
        var seen = Set<String>()
        let resolved = stored.map { (originalKey: RecentDocument.fileKey($0.url), url: $0.resolvedURL, date: $0.lastOpened) }
        // Preserve AppKit's order and resolve native paths using our bookmarks when files move.
        for nativeURL in recentDocumentURLs where nativeURL.isFileURL {
            let nativeKey = RecentDocument.fileKey(nativeURL)
            let record = resolved.first { $0.originalKey == nativeKey || RecentDocument.fileKey($0.url) == nativeKey }
            let url = record?.url ?? nativeURL
            let key = RecentDocument.fileKey(url)
            guard seen.insert(key).inserted else { continue }
            let date = record?.date ?? dates[key] ?? dates[url.standardizedFileURL.absoluteString]
            orderedURLs.append(url)
            if let date { knownDates[url.standardizedFileURL.absoluteString] = date }
        }
        for record in resolved where record.url.isFileURL {
            guard seen.insert(RecentDocument.fileKey(record.url)).inserted else { continue }
            orderedURLs.append(record.url)
            knownDates[record.url.standardizedFileURL.absoluteString] = record.date
        }
        recentDocuments = RecentDocument.entries(for: Array(orderedURLs.prefix(recentLimit)), dates: knownDates)
    }

    func lastOpenedDate(for url: URL) -> Date? {
        let key = RecentDocument.fileKey(url)
        if let record = storedRecentDocuments().first(where: { RecentDocument.fileKey($0.resolvedURL) == key }) {
            return record.lastOpened
        }
        let dates = historyDefaults.dictionary(forKey: historyKey) as? [String: Date] ?? [:]
        return dates[key] ?? dates[url.standardizedFileURL.absoluteString]
    }

    private func recordSuccessfulOpen(_ url: URL) {
        // API/Finder opens do not necessarily pass through AppKit's Open-panel action.
        // Explicitly register every successful open using the public recent-document API.
        noteNewRecentDocumentURL(url)
        var dates = historyDefaults.dictionary(forKey: historyKey) as? [String: Date] ?? [:]
        let openedAt = Date()
        dates[RecentDocument.fileKey(url)] = openedAt
        dates = Dictionary(uniqueKeysWithValues: dates.sorted { $0.value > $1.value }.prefix(recentLimit).map { ($0.key, $0.value) })
        historyDefaults.set(dates, forKey: historyKey)
        var records = storedRecentDocuments().filter { RecentDocument.fileKey($0.resolvedURL) != RecentDocument.fileKey(url) }
        let bookmark = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        records.insert(StoredRecentDocument(url: url, lastOpened: openedAt, bookmark: bookmark), at: 0)
        if let data = try? JSONEncoder().encode(Array(records.prefix(recentLimit))) {
            historyDefaults.set(data, forKey: recordsKey)
        }
        refreshRecentDocuments()
    }

    override func clearRecentDocuments(_ sender: Any?) {
        super.clearRecentDocuments(sender)
        historyDefaults.removeObject(forKey: historyKey)
        historyDefaults.removeObject(forKey: recordsKey)
        refreshRecentDocuments()
    }

    func openFromWelcome(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            presentMissingFile(url)
            return
        }
        openDocument(withContentsOf: url, display: true) { [weak self] _, _, error in
            if let error { self?.presentOpenError(error) }
        }
    }

    override func typeForContents(of url: URL) throws -> String {
        if ["djvu", "djv"].contains(url.pathExtension.lowercased()) { return "com.lizardtech.djvu" }
        return try super.typeForContents(of: url)
    }

    func openDroppedURLs(_ urls: [URL]) -> Bool {
        let pdfs = urls.filter { $0.isFileURL && ["pdf", "djvu", "djv"].contains($0.pathExtension.lowercased()) }
        for url in pdfs { openFromWelcome(url) }
        return !pdfs.isEmpty
    }

    private func presentOpenError(_ error: any Error) {
        showWelcomeIfNeeded()
        let alert = NSAlert(error: error)
        if let window = welcomeController?.window, window.isVisible {
            alert.beginSheetModal(for: window)
        } else { NSApplication.shared.presentError(error) }
    }

    private func presentMissingFile(_ url: URL) {
        let alert = NSAlert()
        alert.messageText = L10n.string("Document Not Found")
        alert.informativeText = L10n.string("Document %@ may have been moved, renamed, or deleted. You can locate it and open it again.", url.lastPathComponent)
        alert.addButton(withTitle: L10n.string("Locate…"))
        alert.addButton(withTitle: L10n.string("Cancel"))
        guard let window = welcomeController?.window else { return }
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.openDocument(nil)
        }
    }
}
