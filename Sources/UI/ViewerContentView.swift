import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ViewerContentView: View {
    @ObservedObject var session: DocumentSession
    @State private var dropTargeted = false
    @State private var openError: String?

    var body: some View {
        VStack(spacing: 0) {
            if session.searchVisible {
                if session.isDjVu { DjVuSearchBar(session: session) }
                else { SearchBar(session: session, search: session.search) }
                Divider()
            }
            Group {
                if session.isLoading { ProgressView("Opening DjVu…") }
                else if session.isDjVu, session.djvuSummary != nil { DjVuCanvas(session: session) }
                else if session.pdf != nil {
                    PDFCanvas(session: session)
                        .ignoresSafeArea(.container, edges: session.searchVisible ? [] : .top)
                } else { welcome }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 400, minHeight: 400)
        .environment(\.layoutDirection, L10n.isArabic ? .rightToLeft : .leftToRight)
        .onAppear { openError = session.openingError }
        .onChange(of: session.openingError) { _, error in openError = error }
        .overlay { if dropTargeted { RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor, lineWidth: 3).allowsHitTesting(false) } }
        .dropDestination(for: URL.self) { urls, _ in
            let pdfs = urls.filter { $0.isFileURL && ["pdf", "djvu", "djv"].contains($0.pathExtension.lowercased()) }
            guard !pdfs.isEmpty else { return false }
            for url in pdfs { open(url) }
            return true
        } isTargeted: { dropTargeted = $0 }
        .alert("Unable to Open Document", isPresented: Binding(get: { openError != nil }, set: { if !$0 { openError = nil } })) {
            Button("OK") { openError = nil }
        } message: { Text(openError ?? "") }
    }

    private var welcome: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.richtext").font(.system(size: 64)).foregroundStyle(.secondary)
            Text("PreViewer").font(.title)
            Text("Open a PDF or DjVu document, or drop one here.").foregroundStyle(.secondary)
            Button("Open Document…") { NSDocumentController.shared.openDocument(nil) }
                .buttonStyle(.borderedProminent)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(.background)
    }

    private func open(_ url: URL) {
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
            if let error { Task { @MainActor in openError = error.localizedDescription } }
        }
    }
}
