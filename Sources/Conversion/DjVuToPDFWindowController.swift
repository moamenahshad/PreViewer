import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class DjVuToPDFModel: ObservableObject {
    let source: URL
    let summary: DjVuSummary
    let sourceBytes: Int64
    @Published var options = DjVuToPDFOptions()
    @Published var destination: URL?
    @Published var estimate: DjVuSizeEstimate?
    @Published var estimating = false
    @Published var converting = false
    @Published var completed = 0
    @Published var started: Date?
    @Published var result: DjVuConversionResult?
    @Published var error: String?
    private var estimateTask: Task<Void,Never>?
    private var conversionTask: Task<Void,Never>?
    private var estimator: DjVuToPDFSizeEstimator?
    private var converter: DjVuToPDFConverter?
    init(source: URL, summary: DjVuSummary) {
        self.source = source; self.summary = summary
        sourceBytes = Int64((try? source.resourceValues(forKeys:[.fileSizeKey]).fileSize) ?? 0)
    }
    var proposedName: String { source.deletingPathExtension().lastPathComponent + ".pdf" }
    static func size(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount:bytes,countStyle:.file) }
    var estimateText: String {
        if estimating { return L10n.string("Estimating…") }
        guard let estimate else { return L10n.string("Estimate unavailable") }
        return L10n.string("Approximately %@–%@", Self.size(estimate.lower), Self.size(estimate.upper))
    }
    func chooseDestination(window: NSWindow?) {
        guard let window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = proposedName
            panel.prompt = L10n.string("Choose Destination")
        panel.beginSheetModal(for:window) { [weak self] response in
            if response == .OK { self?.destination = panel.url }
        }
    }
    func recalculate() {
        estimateTask?.cancel(); estimator?.cancel(); estimate = nil
        guard !converting else { return }
        estimating = true
        let options = options
        let worker = DjVuToPDFSizeEstimator(source:source)
        estimator = worker
        estimateTask = Task {
            do {
                try await Task.sleep(for:.milliseconds(400))
                let calculated = try await worker.estimate(summary:summary,options:options)
                try Task.checkCancellation()
                estimate = calculated
            } catch { }
            if !Task.isCancelled { estimating = false }
        }
    }
    func convert() {
        guard let destination, !converting else { return }
        estimateTask?.cancel(); estimator?.cancel(); estimating = false
        converting = true; completed = 0; result = nil; started = Date()
        let worker = DjVuToPDFConverter(source:source)
        converter = worker
        let options = options
        conversionTask = Task {
            do {
                result = try await worker.convert(to:destination,options:options) { [weak self] page,_ in
                    await MainActor.run { self?.completed = page }
                }
            } catch is CancellationError { }
            catch { if !Task.isCancelled { self.error = error.localizedDescription } }
            converting = false
        }
    }
    func cancel() { conversionTask?.cancel(); converter?.cancel() }
    func close() { estimateTask?.cancel(); estimator?.cancel(); cancel() }
}

@MainActor
final class DjVuToPDFWindowController: NSWindowController, NSWindowDelegate {
    let model: DjVuToPDFModel
    init(source: URL, summary: DjVuSummary) {
        model = DjVuToPDFModel(source:source,summary:summary)
        let window = NSWindow(contentRect:NSRect(x:0,y:0,width:620,height:760),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
        window.title = L10n.string("DjVu to PDF")
        window.minSize = NSSize(width:520,height:560)
        window.isReleasedWhenClosed = false
        super.init(window:window)
        window.delegate = self
        let hosting = NSHostingController(rootView:DjVuToPDFView(model:model,choose:{ [weak self] in self?.model.chooseDestination(window:self?.window) }))
        // AppKit owns the utility window size; SwiftUI must not shrink it to its fitting minimum.
        hosting.sizingOptions = []
        window.contentViewController = hosting
        window.setContentSize(NSSize(width:620,height:760))
        window.center()
        model.recalculate()
    }
    required init?(coder:NSCoder) { fatalError() }
    func windowWillClose(_ notification: Notification) { model.close() }
}

private struct DjVuToPDFView: View {
    @ObservedObject var model: DjVuToPDFModel
    let choose: () -> Void
    var body: some View {
        VStack(spacing:0) {
            Form {
                Section("Source") {
                    LabeledContent("Document",value:model.source.lastPathComponent)
                    LabeledContent("File size",value:DjVuToPDFModel.size(model.sourceBytes))
                    LabeledContent("Pages",value:"\(model.summary.pages.count)")
                    if let first = model.summary.pages.first {
                        LabeledContent("First page",value:"\(first.width) × \(first.height) pixels · \(first.reliableDPI ? String(first.dpi) + " DPI" : "DPI unknown")")
                    }
                }
                Section("Conversion") {
                    Picker("Quality",selection:$model.options.quality) {
                        ForEach(DjVuToPDFOptions.Quality.allCases,id:\.self) { Text(L10n.string($0.rawValue)).tag($0) }
                    }
                    Text("Smaller File: JPEG 55%. Balanced: JPEG 82%. Maximum Quality: lossless raster. Bilevel pages remain lossless at every quality.").font(.caption).foregroundStyle(.secondary)
                    Picker("Image resolution",selection:$model.options.resolution) {
                        ForEach(DjVuToPDFOptions.Resolution.allCases,id:\.self) { Text(L10n.string($0.rawValue)).tag($0) }
                    }
                    Text("Resolution is capped at the source DPI; pages are never upscaled. Unknown DPI retains original pixels and uses 300 DPI for page dimensions.").font(.caption).foregroundStyle(.secondary)
                }.disabled(model.converting)
                Section("Document preservation") {
                    Toggle("Preserve searchable source text",isOn:$model.options.text)
                    Toggle("Preserve supported bookmarks",isOn:$model.options.outline).disabled(model.summary.outline.isEmpty)
                    Toggle("Preserve supported metadata",isOn:$model.options.metadata).disabled(model.summary.metadata.isEmpty)
                    Text("No OCR is performed. Only existing text, numeric internal page bookmarks, and Title, Author, Subject and Keywords metadata are preserved. Other annotation types are not exported. DjVu layers are composited; source compression is not copied.")
                        .font(.caption).foregroundStyle(.secondary)
                }.disabled(model.converting)
                Section("Output") {
                    LabeledContent("Filename",value:model.destination?.lastPathComponent ?? model.proposedName)
                    HStack {
                        Text(model.destination?.deletingLastPathComponent().path ?? L10n.string("Choose a PDF destination")).font(.callout).textSelection(.enabled).lineLimit(2)
                        Spacer()
                        Button("Choose…",action:choose).disabled(model.converting)
                    }
                    if let estimate = model.estimate {
                        Text(L10n.string("Based on trial PDF encoding of %d representative pages. Mixed content and shared font overhead may change the final size.", estimate.sampleCount)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let result = model.result {
                    Section("Completed") {
                        LabeledContent("Actual PDF size",value:DjVuToPDFModel.size(result.bytes))
                        LabeledContent("Original DjVu",value:DjVuToPDFModel.size(model.sourceBytes))
                        LabeledContent("Size change",value:difference(result))
                        LabeledContent("Duration",value:L10n.string("%.1f seconds", result.duration))
                        Text(result.url.path).font(.caption).textSelection(.enabled)
                        HStack {
                            Button("Open PDF") { NSDocumentController.shared.openDocument(withContentsOf:result.url,display:true) { _,_,error in if let error { NSApp.presentError(error) } } }
                            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([result.url]) }
                        }
                    }
                }
            }.formStyle(.grouped)
            Divider()
            HStack {
                if !model.converting {
                    VStack(alignment:.leading,spacing:3) {
                        Text("Estimated PDF size").font(.caption).foregroundStyle(.secondary)
                        Text(model.estimateText).font(.callout).monospacedDigit()
                    }.accessibilityElement(children:.combine)
                }
                if model.converting {
                    VStack(alignment:.leading) {
                        ProgressView(value:Double(model.completed),total:Double(model.summary.pages.count)).frame(width:190)
                        TimelineView(.periodic(from:.now,by:1)) { context in
                            Text("Encoding page \(min(model.completed+1,model.summary.pages.count)) of \(model.summary.pages.count) · \(Int(context.date.timeIntervalSince(model.started ?? context.date)))s").font(.caption)
                        }
                    }
                }
                Spacer()
                if model.converting { Button("Cancel") { model.cancel() }.keyboardShortcut(.cancelAction) }
                else { Button("Convert") { model.convert() }.buttonStyle(.borderedProminent).disabled(model.destination == nil).keyboardShortcut(.defaultAction) }
            }.padding()
        }
        .onChange(of:model.options) { _,_ in model.recalculate() }
        .environment(\.layoutDirection, L10n.isArabic ? .rightToLeft : .leftToRight)
        .alert("Unable to Convert",isPresented:Binding(get:{model.error != nil},set:{if !$0 { model.error = nil }})) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
    }
    private func difference(_ result: DjVuConversionResult) -> String {
        let delta = result.bytes-model.sourceBytes
        let megabytes = Double(delta)/1_000_000
        guard model.sourceBytes > 0 else { return L10n.string("%+.2f MB", megabytes) }
        return L10n.string("%+.2f MB (%+.1f%%)", megabytes, Double(delta)/Double(model.sourceBytes)*100)
    }
}
