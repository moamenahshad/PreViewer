import AppKit
import SwiftUI

struct DjVuCanvas: NSViewRepresentable {
    @ObservedObject var session: DocumentSession
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.drawsBackground = true
        scroll.backgroundColor = .underPageBackgroundColor
        scroll.automaticallyAdjustsContentInsets = true
        let canvas = DjVuCanvasView(session: session)
        scroll.documentView = canvas
        session.djvuView = canvas
        canvas.startObserving(scroll)
        return scroll
    }
    func updateNSView(_ view: NSScrollView, context: Context) { session.djvuView?.layoutPages() }
}

@MainActor
final class DjVuCanvasView: NSView {
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    weak var session: DocumentSession?
    private var frames: [CGRect] = []
    private var images: [Int: CGImage] = [:]
    private var words: [Int: [DjVuWord]] = [:]
    private var tasks: [Int: Task<Void, Never>] = [:]
    private var requestIDs: [Int: UUID] = [:]
    private var lastLayout: (CGFloat, CGFloat, CGFloat, Int)?
    private var observer: NSObjectProtocol?
    private var resizeObserver: NSObjectProtocol?
    private var dragStart: CGPoint?
    private var selected: [(Int, Int)] = []
    private var failures: [Int: String] = [:]
    private var layingOut = false
    private var revision = UUID()
    init(session: DocumentSession) {
        self.session = session; super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("DjVu document")
    }
    required init?(coder: NSCoder) { fatalError() }
    func startObserving(_ scroll: NSScrollView) {
        scroll.contentView.postsBoundsChangedNotifications = true
        observer = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateVisiblePages() }
        }
        scroll.contentView.postsFrameChangedNotifications = true
        resizeObserver = NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: scroll.contentView, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.layoutPages() }
        }
        layoutPages()
    }
    func layoutPages() {
        guard !layingOut, let session, let summary = session.djvuSummary, let clip = enclosingScrollView?.contentView else { return }
        layingOut = true
        defer { layingOut = false }
        let width = max(1, clip.bounds.width)
        let available = max(1, width-32)
        let maxPage = summary.pages.map(\.displayPoints.width).max() ?? 612
        if session.djvuFit == .width { session.djvuScale = min(8, available/maxPage) }
        if session.djvuFit == .page {
            let page = summary.pages[min(session.currentPageIndex, summary.pages.count-1)].displayPoints
            session.djvuScale = min(available/page.width, max(1,clip.bounds.height-40)/page.height)
        }
        let scale = session.djvuScale
        let signature = (width, clip.bounds.height, scale, summary.pages.count)
        if let lastLayout, lastLayout == signature {
            layingOut = false
            updateVisiblePages()
            return
        }
        lastLayout = signature
        let canvasWidth = max(width, maxPage * scale + 32)
        var y: CGFloat = 16
        frames = summary.pages.map { page in
            let size = page.displayPoints
            let rect = CGRect(x: (canvasWidth-size.width*scale)/2, y: y, width: size.width*scale, height: size.height*scale)
            y += rect.height+16
            return rect
        }
        setFrameSize(CGSize(width: canvasWidth, height: max(clip.bounds.height, y)))
        revision = UUID()
        images.removeAll()
        tasks.values.forEach { $0.cancel() }; tasks.removeAll(); requestIDs.removeAll()
        layingOut = false
        updateVisiblePages()
        needsDisplay = true
    }
    func go(to index: Int) {
        guard frames.indices.contains(index) else { return }
        scrollToVisible(frames[index].intersection(CGRect(x: 0, y: frames[index].minY, width: frame.width, height: enclosingScrollView?.contentView.bounds.height ?? 1)))
        session?.setDjVuPage(index)
    }
    private func pageIndices(intersecting rect: CGRect) -> Range<Int> {
        // Page frames are ordered vertically; scroll events should inspect visible pages only.
        var lower = 0, upper = frames.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if frames[middle].maxY < rect.minY { lower = middle + 1 } else { upper = middle }
        }
        let first = lower
        upper = frames.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if frames[middle].minY <= rect.maxY { lower = middle + 1 } else { upper = middle }
        }
        return first..<lower
    }
    func updateVisiblePages() {
        guard !layingOut, let session, let backend = session.djvuBackend else { return }
        let visible = visibleRect
        let active = Set(pageIndices(intersecting: visible))
        for index in Array(tasks.keys) where !active.contains(index) {
            requestIDs[index] = nil
            tasks.removeValue(forKey: index)?.cancel()
        }
        images = images.filter { active.contains($0.key) }
        words = words.filter { active.contains($0.key) }
        if let index = active.min(by: { abs(frames[$0].midY-visible.midY) < abs(frames[$1].midY-visible.midY) }) { session.setDjVuPage(index) }
        for index in active.sorted(by: { abs(frames[$0].midY-visible.midY) < abs(frames[$1].midY-visible.midY) }) where images[index] == nil && tasks[index] == nil && failures[index] == nil {
            let pixels = min(4096, max(128, Int(max(frames[index].width,frames[index].height) * (window?.backingScaleFactor ?? 1))))
            let expectedRevision = revision
            let requestID = UUID()
            requestIDs[index] = requestID
            tasks[index] = Task(priority: .userInitiated) { [weak self] in
                do {
                    let raster = try await backend.render(index, maximumDimension: pixels)
                    try Task.checkCancellation()
                    guard self?.revision == expectedRevision, self?.requestIDs[index] == requestID else { return }
                    guard let image = raster.image else {
                        throw CocoaError(.fileReadCorruptFile)
                    }
                    // Rendering is useful even when the optional text layer cannot be read.
                    self?.images[index] = image
                    self?.failures[index] = nil
                    self?.needsDisplay = true

                    do {
                        let text = try await backend.words(index)
                        try Task.checkCancellation()
                        guard self?.revision == expectedRevision, self?.requestIDs[index] == requestID else { return }
                        self?.words[index] = text
                        self?.setAccessibilityValue(text.map(\.text).joined(separator: " "))
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        // Keep the rendered page visible; text is an enhancement for
                        // selection and accessibility, not a rendering prerequisite.
                        if !Task.isCancelled, self?.revision == expectedRevision, self?.requestIDs[index] == requestID {
                            self?.words[index] = []
                            self?.setAccessibilityValue(nil)
                        }
                    }
                } catch is CancellationError { }
                catch {
                    if !Task.isCancelled, self?.revision == expectedRevision, self?.requestIDs[index] == requestID {
                        self?.failures[index] = error.localizedDescription
                    }
                }
                guard self?.revision == expectedRevision, self?.requestIDs[index] == requestID else { return }
                self?.requestIDs[index] = nil
                self?.tasks[index] = nil
                self?.needsDisplay = true
            }
        }
        needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        guard let summary = session?.djvuSummary, let context = NSGraphicsContext.current?.cgContext else { return }
        for index in pageIndices(intersecting: dirtyRect) {
            let rect = frames[index]
            NSColor.white.setFill(); rect.fill()
            if let image = images[index] {
                context.saveGState()
                context.translateBy(x: rect.midX, y: rect.midY)
                context.rotate(by: -CGFloat(summary.pages[index].rotation) * .pi/2)
                let size = summary.pages[index].rotation % 2 == 0 ? rect.size : CGSize(width: rect.height, height: rect.width)
                context.scaleBy(x: 1, y: -1)
                context.draw(image, in: CGRect(x: -size.width/2, y: -size.height/2, width: size.width, height: size.height))
                context.restoreGState()
            } else {
                let message = failures[index] ?? "Loading page \(index+1)…"
                (message as NSString).draw(in: rect.insetBy(dx: 24, dy: 24), withAttributes: [.foregroundColor: NSColor.darkGray])
            }
        }
        NSColor.selectedTextBackgroundColor.withAlphaComponent(0.35).setFill()
        for (page, word) in selected { if let list = words[page], list.indices.contains(word) { wordRect(list[word], page: page).fill() } }
    }
    private func wordRect(_ word: DjVuWord, page: Int) -> CGRect {
        guard let info = session?.djvuSummary?.pages[page] else { return .zero }
        let source = CGRect(x: word.rect.minX/CGFloat(info.width), y: 1-word.rect.maxY/CGFloat(info.height), width: word.rect.width/CGFloat(info.width), height: word.rect.height/CGFloat(info.height))
        let transformed: CGRect
        switch info.rotation % 4 {
        case 1: transformed = CGRect(x: source.minY, y: 1-source.maxX, width: source.height, height: source.width)
        case 2: transformed = CGRect(x: 1-source.maxX, y: 1-source.maxY, width: source.width, height: source.height)
        case 3: transformed = CGRect(x: 1-source.maxY, y: source.minX, width: source.height, height: source.width)
        default: transformed = source
        }
        let frame = frames[page]
        return CGRect(x: frame.minX+transformed.minX*frame.width, y: frame.minY+transformed.minY*frame.height, width: transformed.width*frame.width, height: transformed.height*frame.height)
    }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        dragStart = convert(event.locationInWindow, from: nil); selected = []; needsDisplay = true
    }
    override func magnify(with event: NSEvent) {
        guard let session else { return }
        session.djvuFit = .manual
        session.djvuScale = min(8,max(0.1,session.djvuScale*(1+event.magnification)))
        layoutPages()
    }
    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else { return }
        let end = convert(event.locationInWindow, from: nil)
        let rect = CGRect(x: min(start.x,end.x), y: min(start.y,end.y), width: max(1,abs(start.x-end.x)), height: max(1,abs(start.y-end.y)))
        selected = words.keys.sorted().flatMap { page in words[page]!.indices.compactMap { word in wordRect(words[page]![word],page: page).intersects(rect) ? (page,word) : nil } }
        needsDisplay = true
    }
    @objc func copy(_ sender: Any?) {
        let text = selected.compactMap { page, word in words[page]?[word].text }.joined(separator: " ")
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
    }
    @objc override func selectAll(_ sender: Any?) {
        selected = words.keys.sorted().flatMap { page in words[page]!.indices.map { (page,$0) } }; needsDisplay = true
    }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            tasks.values.forEach { $0.cancel() }; tasks.removeAll(); requestIDs.removeAll(); images.removeAll()
            if let observer { NotificationCenter.default.removeObserver(observer) }
            if let resizeObserver { NotificationCenter.default.removeObserver(resizeObserver) }
            observer = nil; resizeObserver = nil
        }
        super.viewWillMove(toWindow: newWindow)
    }
}
