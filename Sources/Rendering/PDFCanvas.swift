import PDFKit
import SwiftUI

struct PDFCanvas: NSViewRepresentable {
    @ObservedObject var session: DocumentSession

    func makeNSView(context: Context) -> PDFView {
        let view = InsetAwarePDFView()
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.displaysPageBreaks = true
        view.displaysAsBook = false
        view.minScaleFactor = 0.1
        view.maxScaleFactor = 8
        view.backgroundColor = .underPageBackgroundColor
        view.document = session.pdf
        view.autoScales = true
        session.pdfView = view
        context.coordinator.observe(view)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        if view.document !== session.pdf {
            view.document = session.pdf
            view.autoScales = true
        }
    }

    static func dismantleNSView(_ view: PDFView, coordinator: Coordinator) {
        coordinator.stopObserving()
        view.document = nil
    }

    func makeCoordinator() -> Coordinator { Coordinator(session: session) }

    @MainActor
    final class Coordinator: NSObject {
        let session: DocumentSession
        init(session: DocumentSession) { self.session = session }
        func observe(_ view: PDFView) {
            NotificationCenter.default.addObserver(self, selector: #selector(pageChanged), name: .PDFViewPageChanged, object: view)
            NotificationCenter.default.addObserver(self, selector: #selector(scaleChanged), name: .PDFViewScaleChanged, object: view)
        }
        func stopObserving() { NotificationCenter.default.removeObserver(self) }
        @objc private func pageChanged(_ notification: Notification) { session.synchronizePage() }
        @objc private func scaleChanged(_ notification: Notification) { session.synchronizeScale() }
    }
}

/// PDFKit's public documentView gives access to its enclosing NSScrollView.
/// Let AppKit inset the first page below an overlapping toolbar while preserving edge-to-edge scrolling.
@MainActor
final class InsetAwarePDFView: PDFView {
    private weak var initiallyPositionedDocument: PDFDocument?

    override func layout() {
        super.layout()
        guard let scrollView = documentView?.enclosingScrollView else { return }
        if !scrollView.automaticallyAdjustsContentInsets { scrollView.automaticallyAdjustsContentInsets = true }
        guard window != nil, bounds.height > 100, let document,
              document !== initiallyPositionedDocument, scrollView.contentInsets.top > 0,
              let scrollingDocument = scrollView.documentView else { return }
        initiallyPositionedDocument = document
        // Insets can become known only after PDFKit has positioned a newly opened document.
        // Start above the first page by the system-provided inset; subsequent scrolling stays untouched.
        let clip = scrollView.contentView
        var origin = clip.bounds.origin
        origin.y = scrollingDocument.isFlipped
            ? scrollingDocument.frame.minY - scrollView.contentInsets.top
            : scrollingDocument.frame.maxY - clip.bounds.height + scrollView.contentInsets.top
        clip.scroll(to: origin)
        scrollView.reflectScrolledClipView(clip)
    }
}
