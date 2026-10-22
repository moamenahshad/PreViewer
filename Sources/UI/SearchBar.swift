import SwiftUI

struct SearchBar: View {
    @ObservedObject var session: DocumentSession
    @ObservedObject var search: PDFSearchController
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search this PDF", text: $search.query)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onChange(of: search.query) { _, _ in search.scheduleSearch() }
                .onSubmit { session.revealMatch() }
                .accessibilityLabel("Search this PDF")
            if search.isSearching { ProgressView().controlSize(.small) }
            Text(status).font(.caption).foregroundStyle(.secondary).fixedSize()
            Button { session.revealMatch(backward: true) } label: { Image(systemName: "chevron.up") }
                .help("Previous Match (⇧⌘G)").disabled(search.matches.isEmpty)
            Button { session.revealMatch() } label: { Image(systemName: "chevron.down") }
                .help("Next Match (⌘G)").disabled(search.matches.isEmpty)
            Button("Done") {
                search.clear()
                session.pdfView?.setCurrentSelection(nil, animate: false)
                session.searchVisible = false
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding(10)
        .background(.bar)
        .onAppear { focused = true }
        .environment(\.layoutDirection, L10n.isArabic ? .rightToLeft : .leftToRight)
        .onChange(of: session.searchFocusRequest) { _, _ in focused = true }
    }

    private var status: String {
        if search.query.isEmpty { return "" }
        let count = "\(search.matches.count)\(search.isTruncated ? "+" : "")"
        if let index = search.selectedIndex { return "\(index + 1) of \(count)" }
        return "\(count) matches"
    }
}
