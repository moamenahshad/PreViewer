import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 360),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = L10n.string("Settings")
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: SettingsView())
        window.center()
        super.init(window: window)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var showRestartAlert = false

    var body: some View {
        Form {
            Section {
                Picker("Language", selection: Binding(get: { settings.language }, set: { newValue in
                    settings.language = newValue
                    showRestartAlert = true
                })) {
                    Text("Follow System").tag(AppSettings.Language.system)
                    Text("English").tag(AppSettings.Language.english)
                    Text("Arabic").tag(AppSettings.Language.arabic)
                }
                Text("Restart PreViewer after changing the language.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: {
                Text("Language")
            }

            Section {
                Picker("Theme", selection: $settings.theme) {
                    Text("System").tag(AppSettings.Theme.system)
                    Text("Light").tag(AppSettings.Theme.light)
                    Text("Dark").tag(AppSettings.Theme.dark)
                }
            } header: {
                Text("Appearance")
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(minWidth: 460, minHeight: 300)
        .environment(\.layoutDirection, settings.language == .arabic ? .rightToLeft : .leftToRight)
        .alert("Restart Required", isPresented: $showRestartAlert) {
            Button("Later", role: .cancel) { }
            Button("Quit PreViewer") { NSApp.terminate(nil) }
        } message: {
            Text("The language change will take effect the next time PreViewer opens.")
        }
    }
}
