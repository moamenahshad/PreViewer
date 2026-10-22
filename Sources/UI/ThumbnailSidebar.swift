import SwiftUI

struct ThumbnailSidebar: View {
    @ObservedObject var session: DocumentSession
    @State private var showOutline = false
    private var selection: Binding<Int?> {
        Binding(get: { session.hasDocument ? session.currentPageIndex : nil },
                set: { if let index = $0 { session.go(to: index) } })
    }
    private func flatten(_ nodes: [DjVuBookmark], depth: Int = 0) -> [(DjVuBookmark, Int)] {
        nodes.flatMap { [($0, depth)] + flatten($0.children, depth: depth+1) }
    }
    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                List(selection: selection) {
                    if let summary = session.djvuSummary, !summary.outline.isEmpty {
                        Picker("Sidebar", selection: $showOutline) {
                            Text("Thumbnails").tag(false)
                            Text("Contents").tag(true)
                        }.pickerStyle(.segmented).labelsHidden()
                    }
                    if showOutline, let summary = session.djvuSummary {
                        ForEach(flatten(summary.outline), id: \.0.id) { bookmark, depth in
                            Button { if let page = bookmark.page { session.go(to: page) } } label: {
                                Label(bookmark.title, systemImage: "bookmark").padding(.leading, CGFloat(depth)*12)
                            }.buttonStyle(.plain).disabled(bookmark.page == nil)
                        }
                    } else {
                        ForEach(0..<session.pageCount, id: \.self) { index in
                            ThumbnailCell(store: session.thumbnails, index: index,
                                          width: min(144, max(96, geometry.size.width - 64)))
                                .frame(maxWidth: .infinity).padding(.vertical, 8).tag(index).id(index)
                        }
                    }
                }
                .listStyle(.sidebar).scrollContentBackground(.hidden)
                .onChange(of: session.currentPageIndex) { _, index in
                    if !showOutline { proxy.scrollTo(index, anchor: .center) }
                }
            }
        }
        .accessibilityLabel("Page thumbnails")
        .environment(\.layoutDirection, L10n.isArabic ? .rightToLeft : .leftToRight)
        .dropDestination(for: URL.self) { urls, _ in
            let pdfs = urls.filter { $0.isFileURL && ["pdf", "djvu", "djv"].contains($0.pathExtension.lowercased()) }
            for url in pdfs {
                NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
                    if let error { NSApplication.shared.presentError(error) }
                }
            }
            return !pdfs.isEmpty
        }
    }
}

private struct ThumbnailCell: View {
    let store: ThumbnailStore
    let index: Int
    let width: CGFloat
    @State private var image: NSImage?
    var body: some View {
        VStack(spacing: 8) {
            Group {
                if let image {
                    Image(nsImage: image).resizable().scaledToFit()
                } else {
                    Rectangle().fill(.background)
                        .aspectRatio(0.773, contentMode: .fit)
                        .overlay { Image(systemName: "doc").foregroundStyle(.secondary) }
                }
            }
            .frame(width: width)
            .shadow(color: .black.opacity(0.16), radius: 2, y: 1)
            Text(String(index + 1)).font(.caption).monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(index + 1)")
        .task { image = await store.image(for: index) }
        .onDisappear { image = nil }
    }
}
