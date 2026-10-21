import AppKit

@main
@MainActor
enum DjVuPreviewApp {
    static func main() {
        let documents = ViewerDocumentController()
        let app = NSApplication.shared
        let delegate = AppDelegate(documents: documents)
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let documents: ViewerDocumentController
    init(documents: ViewerDocumentController) { self.documents = documents; super.init() }

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApplication.shared.mainMenu = makeMenu()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            documents.openDocument(withContentsOf: url, display: true) { _, _, error in
                if let error { NSApplication.shared.presentError(error) }
            }
        }
    }

    // AppKit invokes this handler for a bare launch, but not for a Finder document-open launch.
    // Returning true means the request was handled by our welcome UI; no NSDocument is created.
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { true }
    func applicationOpenUntitledFile(_ sender: NSApplication) -> Bool {
        documents.scheduleWelcomeUpdate()
        return true
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if documents.documents.isEmpty { documents.showWelcomeAfterReopen() }
        else if !flag { documents.documents.forEach { $0.showWindows() } }
        return false
    }
    func applicationWillTerminate(_ notification: Notification) {
        documents.isTerminating = true
    }
    @objc func showWelcome(_ sender: Any?) {
        documents.showWelcomeIfNeeded()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        func submenu(_ title: String) -> NSMenu {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let child = NSMenu(title: title)
            item.submenu = child
            menu.addItem(item)
            return child
        }
        func item(_ menu: NSMenu, _ title: String, _ action: Selector, _ key: String = "",
                  _ modifiers: NSEvent.ModifierFlags = .command) {
            let entry = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
            entry.keyEquivalentModifierMask = modifiers
        }
        let app = submenu("PreViewer")
        item(app, "About PreViewer", #selector(NSApplication.orderFrontStandardAboutPanel(_:)))
        app.addItem(.separator())
        let services = NSMenu(title: "Services")
        let servicesItem = app.addItem(withTitle: "Services", action: nil, keyEquivalent: "")
        servicesItem.submenu = services
        NSApplication.shared.servicesMenu = services
        app.addItem(.separator())
        item(app, "Hide PreViewer", #selector(NSApplication.hide(_:)), "h")
        item(app, "Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option])
        item(app, "Show All", #selector(NSApplication.unhideAllApplications(_:)))
        app.addItem(.separator())
        item(app, "Quit PreViewer", #selector(NSApplication.terminate(_:)), "q")
        let file = submenu("File")
        let welcomeItem = file.addItem(withTitle: "Welcome", action: #selector(ViewerDocumentController.welcomeShortcut(_:)), keyEquivalent: "n")
        welcomeItem.keyEquivalentModifierMask = [.command]
        welcomeItem.target = documents
        item(file, "Open…", #selector(NSDocumentController.openDocument(_:)), "o")
        item(file, "Export…", #selector(ViewerWindowController.exportDjVu(_:)), "e", [.command, .shift])
        file.addItem(.separator())
        item(file, "Close Window", #selector(NSWindow.performClose(_:)), "w")
        let edit = submenu("Edit")
        item(edit, "Cut", #selector(NSText.cut(_:)), "x")
        item(edit, "Paste", #selector(NSText.paste(_:)), "v")
        item(edit, "Copy", #selector(NSText.copy(_:)), "c")
        item(edit, "Select All", #selector(NSText.selectAll(_:)), "a")
        edit.addItem(.separator())
        item(edit, "Find…", #selector(ViewerWindowController.showSearch(_:)), "f")
        item(edit, "Find Next", #selector(ViewerWindowController.findNext(_:)), "g")
        item(edit, "Find Previous", #selector(ViewerWindowController.findPrevious(_:)), "g", [.command, .shift])
        let view = submenu("View")
        item(view, "Toggle Thumbnails", #selector(ViewerWindowController.toggleSidebar(_:)), "1", [.command, .option])
        view.addItem(.separator())
        item(view, "Zoom In", #selector(ViewerWindowController.zoomIn(_:)), "+")
        item(view, "Zoom Out", #selector(ViewerWindowController.zoomOut(_:)), "-")
        item(view, "Actual Size", #selector(ViewerWindowController.actualSize(_:)), "0")
        item(view, "Fit to Window", #selector(ViewerWindowController.fitToWindow(_:)), "9")
        item(view, "Fit to Width", #selector(ViewerWindowController.fitToWidth(_:)))
        let go = submenu("Go")
        item(go, "Previous Page", #selector(ViewerWindowController.previousPage(_:)), "\u{f700}", [.command])
        item(go, "Next Page", #selector(ViewerWindowController.nextPage(_:)), "\u{f701}", [.command])
        item(go, "First Page", #selector(ViewerWindowController.firstPage(_:)))
        item(go, "Last Page", #selector(ViewerWindowController.lastPage(_:)))
        let window = submenu("Window")
        item(window, "Minimize", #selector(NSWindow.performMiniaturize(_:)), "m")
        item(window, "Zoom", #selector(NSWindow.performZoom(_:)))
        item(window, "Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control])
        window.addItem(.separator())
        item(window, "Bring All to Front", #selector(NSApplication.arrangeInFront(_:)))
        NSApplication.shared.windowsMenu = window
        return menu
    }
}
