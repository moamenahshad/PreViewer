import SwiftUI
struct DjVuSearchBar: View {
    @ObservedObject var session: DocumentSession
    @FocusState private var focused: Bool
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
            TextField("Search source text", text: $session.djvuQuery)
                .textFieldStyle(.roundedBorder).focused($focused)
                .onChange(of: session.djvuQuery) { _, _ in session.searchDjVu() }
                .onSubmit { session.revealMatch() }
            if session.djvuSearching { ProgressView().controlSize(.small) }
            Text("\(session.djvuMatches.count)\(session.djvuMatches.count >= 500 ? "+" : "") matching pages").font(.caption)
            if let error = session.djvuSearchError {
                Text("Search incomplete: \(error)").font(.caption).foregroundStyle(.orange).lineLimit(1)
            } else if session.djvuSearchIncomplete {
                Text("Search incomplete").font(.caption).foregroundStyle(.secondary)
            }
            Button { session.revealMatch(backward: true) } label: { Image(systemName: "chevron.up") }.disabled(!session.hasSearchMatches)
            Button { session.revealMatch() } label: { Image(systemName: "chevron.down") }.disabled(!session.hasSearchMatches)
            Button("Done") { session.djvuQuery = ""; session.searchDjVu(); session.searchVisible = false }.keyboardShortcut(.cancelAction)
        }.padding(10).background(.bar).onAppear { focused = true }
    }
}
