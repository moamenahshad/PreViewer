import AppKit
import SwiftUI

@MainActor
final class WelcomeWindowController: NSWindowController {
    init(documents: ViewerDocumentController) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 680),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Welcome to PreViewer"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: WelcomeView(documents: documents))
        window.setContentSize(NSSize(width: 620, height: 680))
        window.minSize = NSSize(width: 520, height: 560)
        window.center()
        super.init(window: window)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

struct WelcomeView: View {
    @ObservedObject var documents: ViewerDocumentController
    @State private var dropTargeted = false

    private var preViewerIcon: NSImage {
        if let url = Bundle.main.url(forResource: "PreViewer", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        return NSApplication.shared.applicationIconImage
    }

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 10) {
                Image(nsImage: preViewerIcon)
                    .resizable().interpolation(.high).antialiased(true)
                    .scaledToFit().frame(width: 88, height: 88)
                    .accessibilityHidden(true)
                Text("PreViewer").font(.largeTitle.weight(.semibold))
                Text("View and convert PDF and DjVu documents in one place.")
                    .foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("Open Document…") { documents.openDocument(nil) }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .padding(.top, 8)
            }
            .padding(.top, 12)
            HStack {
                Text("Recent Documents").font(.headline)
                Spacer()
                if !documents.recentDocuments.isEmpty {
                    Button("Clear Recent Documents") { documents.clearRecentDocuments(nil) }
                        .buttonStyle(.link).font(.caption)
                }
            }
            if documents.recentDocuments.isEmpty {
                ContentUnavailableView("No Recent Documents", systemImage: "clock",
                                       description: Text("Open a PDF or DjVu document, or drop one onto this window."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(documents.recentDocuments) { recent in
                    Button { documents.openFromWelcome(recent.url) } label: {
                        HStack(spacing: 12) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: recent.url.path))
                                .resizable().scaledToFit().frame(width: 32, height: 32)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(recent.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                                HStack(spacing: 6) {
                                    if !recent.isAvailable { Text("File unavailable").foregroundStyle(.secondary) }
                                    if let date = recent.lastOpened {
                                        Text(date, format: .dateTime.month(.abbreviated).day().year().hour().minute())
                                    } else { Text("Previously opened") }
                                }
                                .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(recent.url.path)
                    .accessibilityLabel("Open \(recent.url.lastPathComponent)")
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
            Text("Native PDF and DjVu viewing, with DjVu to PDF export.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(minWidth: 460, minHeight: 480)
        .background(.background)
        .overlay {
            if dropTargeted { RoundedRectangle(cornerRadius: 12).stroke(Color.accentColor, lineWidth: 3).padding(8).allowsHitTesting(false) }
        }
        .dropDestination(for: URL.self) { urls, _ in documents.openDroppedURLs(urls) }
            isTargeted: { dropTargeted = $0 }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            documents.refreshRecentDocuments()
        }
    }
}
