import AppKit
import Combine
import SwiftUI

@MainActor
final class ViewerWindowController: NSWindowController, NSMenuItemValidation, NSToolbarDelegate, NSToolbarItemValidation {
    let session: DocumentSession
    let documentSplitViewController: ViewerSplitViewController
    private var conversionWindow: DjVuToPDFWindowController?
    private var subscriptions = Set<AnyCancellable>()

    init(session: DocumentSession) {
        self.session = session
        documentSplitViewController = ViewerSplitViewController(session: session)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 800),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.minSize = NSSize(width: 760, height: 560)
        window.title = "PreViewer"
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        window.titlebarSeparatorStyle = .none
        // Use a new autosave namespace so an older compact frame cannot override
        // the wider PreViewer default on first launch.
        window.setFrameAutosaveName("PreViewerDocumentWindowV2")
        window.center()
        window.contentViewController = documentSplitViewController
        window.toolbarStyle = .unified
        super.init(window: window)
        shouldCascadeWindows = true
        let toolbar = NSToolbar(identifier: "DocumentToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
        session.objectWillChange.sink { [weak self] in
            // ObservableObject emits before the state changes; validate on the following main-actor turn.
            Task { @MainActor [weak self] in self?.updateToolbarState() }
        }.store(in: &subscriptions)
        updateToolbarState()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.init("sidebar"), .sidebarTrackingSeparator, .flexibleSpace, .init("zoom"),
         .init("navigation"), .flexibleSpace, .init("fit"), .init("search")]
    }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarAllowedItemIdentifiers(toolbar)
    }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch identifier.rawValue {
        case "sidebar":
            let item = NSMenuToolbarItem(itemIdentifier: identifier)
            item.visibilityPriority = .high
            item.label = L10n.string("View")
            item.toolTip = L10n.string("Show or Hide Thumbnails (⌥⌘1)")
            item.image = NSImage(systemSymbolName: "sidebar.leading", accessibilityDescription: L10n.string("Sidebar"))
            item.isBordered = true
            let menu = NSMenu(title: L10n.string("View"))
            let toggle = menu.addItem(withTitle: L10n.string("Toggle Thumbnails"), action: #selector(toggleSidebar(_:)), keyEquivalent: "")
            toggle.target = self
            item.menu = menu
            return item
        case "zoom":
            return group(identifier, label: "Zoom", symbols: ["minus.magnifyingglass", "1.magnifyingglass", "plus.magnifyingglass"],
                         labels: ["Zoom Out", "Actual Size", "Zoom In"], actions: [#selector(zoomOut(_:)), #selector(actualSize(_:)), #selector(zoomIn(_:))], action: #selector(zoomSelected(_:)))
        case "navigation":
            return group(identifier, label: "Page Navigation", symbols: ["arrow.up.doc", "arrow.down.doc"],
                         labels: ["Previous Page", "Next Page"], actions: [#selector(previousPage(_:)), #selector(nextPage(_:))], action: #selector(pageSelected(_:)))
        case "fit":
            return button(identifier, label: "Fit to Window", symbol: "arrow.up.left.and.down.right.magnifyingglass", action: #selector(fitToWindow(_:)))
        case "search":
            return button(identifier, label: "Find", symbol: "magnifyingglass", action: #selector(showSearch(_:)))
        default: return nil // AppKit supplies standard spaces and the sidebar tracking separator.
        }
    }

    private func button(_ identifier: NSToolbarItem.Identifier, label: String, symbol: String, action: Selector) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.visibilityPriority = identifier.rawValue == "search" ? .high : .low
        item.label = L10n.string(label)
        item.toolTip = L10n.string(label)
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: L10n.string(label))
        item.target = self
        item.action = action
        item.isBordered = true
        return item
    }

    private func group(_ identifier: NSToolbarItem.Identifier, label: String, symbols: [String], labels: [String], actions: [Selector], action: Selector) -> NSToolbarItemGroup {
        let localizedLabels = labels.map { L10n.string($0) }
        let images = zip(symbols, localizedLabels).map { NSImage(systemSymbolName: $0.0, accessibilityDescription: $0.1)! }
        let item = NSToolbarItemGroup(itemIdentifier: identifier, images: images, selectionMode: .momentary,
                                      labels: localizedLabels, target: self, action: action)
        item.label = L10n.string(label)
        item.title = L10n.string(label)
        item.image = images[0]
        item.visibilityPriority = identifier.rawValue == "navigation" ? .high : .low
        item.isBordered = true
        item.controlRepresentation = .automatic
        // Explicit commands also work when AppKit moves the group into overflow.
        let menu = NSMenu(title: L10n.string(label))
        for (index, child) in item.subitems.enumerated() {
            child.toolTip = localizedLabels[index]
            let command = menu.addItem(withTitle: localizedLabels[index], action: actions[index], keyEquivalent: "")
            command.target = self
            command.image = images[index]
        }
        let representation = NSMenuItem(title: L10n.string(label), action: nil, keyEquivalent: "")
        representation.submenu = menu
        item.menuFormRepresentation = representation
        return item
    }

    private func updateToolbarState() {
        window?.subtitle = session.hasDocument ? L10n.string("Page %d of %d", session.currentPageIndex + 1, session.pageCount) : ""
        window?.toolbar?.validateVisibleItems()
        for item in window?.toolbar?.items ?? [] {
            guard let group = item as? NSToolbarItemGroup else { continue }
            let states = item.itemIdentifier.rawValue == "navigation"
                ? [session.canGoBack, session.canGoForward]
                : [session.hasDocument, session.hasDocument, session.hasDocument]
            for (index, enabled) in states.enumerated() where index < group.subitems.count {
                group.subitems[index].isEnabled = enabled
                (group.view as? NSSegmentedControl)?.setEnabled(enabled, forSegment: index)
            }
        }
    }

    @objc private func zoomSelected(_ sender: NSToolbarItemGroup) {
        switch sender.selectedIndex {
        case 0: session.zoomOut()
        case 1: session.actualSize()
        case 2: session.zoomIn()
        default: break
        }
    }
    @objc private func pageSelected(_ sender: NSToolbarItemGroup) {
        if sender.selectedIndex == 0 { previousPage(sender) }
        else if sender.selectedIndex == 1 { nextPage(sender) }
    }

    func closeConversion() { conversionWindow?.close(); conversionWindow = nil }
    @objc func exportDjVu(_ sender: Any?) {
        guard session.isDjVu, let url = session.sourceURL, let summary = session.djvuSummary else { return }
        if conversionWindow?.window?.isVisible != true { conversionWindow = DjVuToPDFWindowController(source: url, summary: summary) }
        conversionWindow?.showWindow(nil)
        conversionWindow?.window?.makeKeyAndOrderFront(nil)
    }
    @objc func toggleSidebar(_ sender: Any?) { session.sidebarVisible.toggle() }
    @objc func showSearch(_ sender: Any?) { session.requestSearch() }
    @objc func findNext(_ sender: Any?) { session.revealMatch() }
    @objc func findPrevious(_ sender: Any?) { session.revealMatch(backward: true) }
    @objc func nextPage(_ sender: Any?) { session.go(to: session.currentPageIndex + 1) }
    @objc func previousPage(_ sender: Any?) { session.go(to: session.currentPageIndex - 1) }
    @objc func firstPage(_ sender: Any?) { session.go(to: 0) }
    @objc func lastPage(_ sender: Any?) { session.go(to: session.pageCount - 1) }
    @objc func zoomIn(_ sender: Any?) { session.zoomIn() }
    @objc func zoomOut(_ sender: Any?) { session.zoomOut() }
    @objc func actualSize(_ sender: Any?) { session.actualSize() }
    @objc func fitToWidth(_ sender: Any?) { session.fitToWidth() }
    @objc func fitToWindow(_ sender: Any?) { session.fitToWindow() }

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        item.itemIdentifier.rawValue == "sidebar" || session.hasDocument
    }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(exportDjVu(_:)): return session.isDjVu && session.hasDocument
        case #selector(nextPage(_:)), #selector(lastPage(_:)): return session.canGoForward
        case #selector(previousPage(_:)), #selector(firstPage(_:)): return session.canGoBack
        case #selector(findNext(_:)), #selector(findPrevious(_:)): return session.hasSearchMatches
        case #selector(toggleSidebar(_:)):
            menuItem.state = session.sidebarVisible ? .on : .off
            return true
        default: return session.hasDocument
        }
    }
}

/// AppKit owns the sidebar material, divider tracking, safe areas, and collapse animation.
@MainActor
final class ViewerSplitViewController: NSSplitViewController {
    let session: DocumentSession
    let thumbnailItem: NSSplitViewItem
    private var subscriptions = Set<AnyCancellable>()
    private var collapsedObservation: NSKeyValueObservation?

    init(session: DocumentSession) {
        self.session = session
        thumbnailItem = NSSplitViewItem(sidebarWithViewController: NSHostingController(rootView: ThumbnailSidebar(session: session)))
        super.init(nibName: nil, bundle: nil)
        thumbnailItem.minimumThickness = 190
        thumbnailItem.maximumThickness = 300
        thumbnailItem.preferredThicknessFraction = 0.19
        thumbnailItem.canCollapse = true
        thumbnailItem.canCollapseFromWindowResize = false
        thumbnailItem.allowsFullHeightLayout = true
        thumbnailItem.isCollapsed = !session.sidebarVisible || !session.hasDocument
        let documentItem = NSSplitViewItem(viewController: NSHostingController(rootView: ViewerContentView(session: session)))
        documentItem.minimumThickness = 400
        if #available(macOS 26.0, *) { documentItem.automaticallyAdjustsSafeAreaInsets = true }
        addSplitViewItem(thumbnailItem)
        addSplitViewItem(documentItem)
        collapsedObservation = thumbnailItem.observe(\.isCollapsed, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self, self.session.hasDocument else { return }
                let visible = !self.thumbnailItem.isCollapsed
                if self.session.sidebarVisible != visible { self.session.sidebarVisible = visible }
            }
        }
        session.$djvuSummary.dropFirst().sink { [weak self] summary in
            guard summary != nil else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.setSidebarVisible(self.session.sidebarVisible, animated: false)
            }
        }.store(in: &subscriptions)
        session.$sidebarVisible.dropFirst().removeDuplicates().sink { [weak self] visible in
            self?.setSidebarVisible(visible, animated: true)
        }.store(in: &subscriptions)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func viewDidLoad() {
        super.viewDidLoad()
        splitView.autosaveName = "DocumentSidebar"
    }
    func setSidebarVisible(_ visible: Bool, animated: Bool) {
        let collapsed = !visible || !session.hasDocument
        guard thumbnailItem.isCollapsed != collapsed else { return }
        if animated && view.window?.isVisible == true && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            thumbnailItem.animator().isCollapsed = collapsed
        } else { thumbnailItem.isCollapsed = collapsed }
    }
}
