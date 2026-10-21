import AppKit
import PDFKit
import SwiftUI

/// NSDocument owns URLs, recent documents, open panels, and native window lifetime.
/// This milestone is a read-only viewer: no save or autosave path writes input files.
@MainActor
@objc(ViewerDocument)
final class ViewerDocument: NSDocument {
    let session = DocumentSession()
    override class var autosavesInPlace: Bool { false }

    override class func canConcurrentlyReadDocuments(ofType typeName: String) -> Bool { false }

    nonisolated override func read(from url: URL, ofType typeName: String) throws {
        // Concurrent NSDocument reads are disabled above; AppKit calls this path on the main thread.
        try MainActor.assumeIsolated {
            if ["djvu", "djv"].contains(url.pathExtension.lowercased()) {
                let file = try FileHandle(forReadingFrom: url)
                defer { try? file.close() }
                let prefix = try file.read(upToCount: 16) ?? Data()
                guard prefix.starts(with: Data("AT&TFORM".utf8)) else { throw CocoaError(.fileReadCorruptFile) }
                session.openDjVu(url)
            }
            else { try loadPDF(from: url) }
        }
    }

    private func loadPDF(from url: URL) throws {
        guard let pdf = PDFDocument(url: url) else {
            throw NSError(domain: "DjVuPreview", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "The PDF could not be opened. It may be damaged or inaccessible."
            ])
        }
        guard !pdf.isLocked else {
            throw NSError(domain: "DjVuPreview", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "This PDF requires a password. Password-protected documents are not supported in this milestone."
            ])
        }
        session.attach(pdf, url: url)
    }

    override func close() {
        session.cancelDjVuWork()
        windowControllers.compactMap { $0 as? ViewerWindowController }.forEach { $0.closeConversion() }
        super.close()
    }

    override func makeWindowControllers() {
        let controller = ViewerWindowController(session: session)
        addWindowController(controller)
    }
}
