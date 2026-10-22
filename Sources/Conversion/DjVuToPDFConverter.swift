import AppKit
import CoreText
import ImageIO
import UniformTypeIdentifiers

struct DjVuToPDFOptions: Sendable, Equatable {
    enum Quality: String, CaseIterable, Sendable { case smaller = "Smaller File", balanced = "Balanced", maximum = "Maximum Quality" }
    enum Resolution: String, CaseIterable, Sendable { case original = "Preserve Original", dpi300 = "300 DPI", dpi150 = "150 DPI" }
    var quality: Quality = .balanced
    var resolution: Resolution = .original
    var text = true
    var outline = true
    var metadata = true
    func dimension(_ page: DjVuPageInfo) -> Int {
        let source = max(page.width,page.height)
        guard page.reliableDPI, resolution != .original else { return source }
        let target = resolution == .dpi300 ? 300 : 150
        return max(1, Int(ceil(Double(source) * min(1, Double(target)/Double(page.dpi)))))
    }
}
struct DjVuConversionResult: Sendable {
    let url: URL
    let bytes: Int64
    let duration: TimeInterval
}

/// One page is decoded, encoded and released at a time. The reader has its own decoder/cache.
actor DjVuToPDFConverter {
    let backend: DjVuDocumentBackend
    init(source: URL) { backend = DjVuDocumentBackend(url: source) }
    nonisolated func cancel() { backend.cancel() }
    func convert(to destination: URL, options: DjVuToPDFOptions,
                 pages requested: [Int]? = nil, progress: @Sendable (Int, Int) async -> Void = { _,_ in }) async throws -> DjVuConversionResult {
        guard destination.standardizedFileURL.resolvingSymlinksInPath() != backend.url.standardizedFileURL.resolvingSymlinksInPath() else {
            throw NSError(domain: "DjVuPreview.Export", code: 1, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("Choose a PDF destination different from the original DjVu document.", comment: "")])
        }
        let started = Date()
        let summary = try await backend.prepare()
        let indices = requested ?? Array(summary.pages.indices)
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".djvu-preview-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: temporary) }
        var attributes: [CFString: Any] = [kCGPDFContextCreator: "PreViewer"]
        if options.metadata {
            let keys: [(String, CFString)] = [("title",kCGPDFContextTitle),("author",kCGPDFContextAuthor),("subject",kCGPDFContextSubject),("keywords",kCGPDFContextKeywords)]
            for (name,key) in keys {
                if let value = summary.metadata.first(where: { $0.key.lowercased() == name })?.value { attributes[key] = value }
            }
        }
        guard let context = CGContext(temporary as CFURL, mediaBox: nil, attributes as CFDictionary) else { throw CocoaError(.fileWriteUnknown) }
        var closed = false
        defer { if !closed { context.closePDF() } }
        for (completed,index) in indices.enumerated() {
            try Task.checkCancellation()
            guard !backend.cancellation.cancelled else { throw CancellationError() }
            let info = summary.pages[index]
            let raster = try await backend.render(index, maximumDimension: options.dimension(info), cached: false)
            let text = options.text ? try await backend.words(index) : []
            try Task.checkCancellation()
            try autoreleasepool {
                guard let image = try Self.encodedImage(raster, quality: options.quality) else { throw CocoaError(.fileWriteUnknown) }
                var box = CGRect(origin: .zero, size: info.displayPoints)
                let boxData = Data(bytes: &box, count: MemoryLayout<CGRect>.size)
                context.beginPDFPage([kCGPDFContextMediaBox: boxData] as CFDictionary)
                context.saveGState()
                // DjVu rotation is counter-clockwise; keep source text coordinates aligned with the pixels.
                switch info.rotation % 4 {
                case 1: context.translateBy(x: info.points.height, y: 0); context.rotate(by: .pi/2)
                case 2: context.translateBy(x: info.points.width, y: info.points.height); context.rotate(by: .pi)
                case 3: context.translateBy(x: 0, y: info.points.width); context.rotate(by: -.pi/2)
                default: break
                }
                context.draw(image, in: CGRect(origin: .zero, size: info.points))
                let sx = info.points.width/CGFloat(info.width), sy = info.points.height/CGFloat(info.height)
                context.setTextDrawingMode(.invisible)
                for word in text where !word.text.isEmpty && word.rect.width > 0 && word.rect.height > 0 {
                    let rect = CGRect(x: word.rect.minX*sx,y: word.rect.minY*sy,width: word.rect.width*sx,height: word.rect.height*sy)
                    let font = CTFontCreateWithName("Helvetica" as CFString, rect.height, nil)
                    let line = CTLineCreateWithAttributedString(NSAttributedString(string: word.text + " ", attributes: [NSAttributedString.Key(kCTFontAttributeName as String):font]))
                    let bounds = CTLineGetBoundsWithOptions(line, [])
                    context.saveGState()
                    context.translateBy(x: rect.minX, y: rect.minY + CTFontGetDescent(font))
                    context.scaleBy(x: rect.width/max(1,bounds.width), y: 1)
                    context.textMatrix = .identity; context.textPosition = .zero
                    CTLineDraw(line,context)
                    context.restoreGState()
                }
                context.restoreGState()
                context.endPDFPage()
            }
            await progress(completed+1, indices.count)
        }
        if options.outline && requested == nil {
            func node(_ bookmark: DjVuBookmark) -> [CFString: Any]? {
                guard let page = bookmark.page else { return nil }
                var result: [CFString: Any] = [kCGPDFOutlineTitle: bookmark.title,kCGPDFOutlineDestination:page+1]
                let children = bookmark.children.compactMap(node)
                if !children.isEmpty { result[kCGPDFOutlineChildren] = children }
                return result
            }
            CGPDFContextSetOutline(context, [kCGPDFOutlineChildren: summary.outline.compactMap(node)] as CFDictionary)
        }
        context.closePDF(); closed = true
        guard let verified = CGPDFDocument(temporary as CFURL), verified.numberOfPages == indices.count else {
            throw NSError(domain: "DjVuPreview.Export", code: 2, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("The PDF could not be finalized. Check available disk space and destination permissions.", comment: "")])
        }
        try Task.checkCancellation()
        guard !backend.cancellation.cancelled else { throw CancellationError() }
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
        } else { try FileManager.default.moveItem(at: temporary, to: destination) }
        let size = (try destination.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return .init(url: destination, bytes: Int64(size), duration: Date().timeIntervalSince(started))
    }
    private static func encodedImage(_ raster: DjVuRaster, quality: DjVuToPDFOptions.Quality) throws -> CGImage? {
        // Preserve bilevel scans as one-bit gray rather than three-channel RGB/JPEG.
        var bilevel = true
        raster.data.withUnsafeBytes { raw in
            let pixels = raw.bindMemory(to: UInt8.self)
            for i in stride(from: 0, to: pixels.count, by: 3) {
                let value = pixels[i]
                if (value != 0 && value != 255) || pixels[i+1] != value || pixels[i+2] != value { bilevel = false; break }
            }
        }
        if bilevel {
            let stride = (raster.width+7)/8
            var bits = Data(repeating: 0, count: stride*raster.height)
            raster.data.withUnsafeBytes { source in
                bits.withUnsafeMutableBytes { target in
                    let src = source.bindMemory(to: UInt8.self), dst = target.bindMemory(to: UInt8.self)
                    for y in 0..<raster.height { for x in 0..<raster.width where src[(y*raster.width+x)*3] > 0 { dst[y*stride+x/8] |= UInt8(0x80 >> (x%8)) } }
                }
            }
            return CGImage(width: raster.width,height: raster.height,bitsPerComponent:1,bitsPerPixel:1,bytesPerRow:stride,space:CGColorSpaceCreateDeviceGray(),bitmapInfo:[],provider:CGDataProvider(data:bits as CFData)!,decode:nil,shouldInterpolate:false,intent:.defaultIntent)
        }
        guard let image = raster.image else { return nil }
        if quality == .maximum { return image }
        let data = NSMutableData()
        guard let encoder = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString,1,nil) else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(encoder,image,[kCGImageDestinationLossyCompressionQuality: quality == .smaller ? 0.55 : 0.82] as CFDictionary)
        guard CGImageDestinationFinalize(encoder), let source = CGImageSourceCreateWithData(data,nil) else { throw CocoaError(.fileWriteUnknown) }
        return CGImageSourceCreateImageAtIndex(source,0,[kCGImageSourceShouldCache:false] as CFDictionary)
    }
}

struct DjVuSizeEstimate: Sendable {
    let lower: Int64
    let upper: Int64
    let sampleCount: Int
}
actor DjVuToPDFSizeEstimator {
    let converter: DjVuToPDFConverter
    init(source: URL) { converter = DjVuToPDFConverter(source: source) }
    nonisolated func cancel() { converter.cancel() }
    func estimate(summary: DjVuSummary, options: DjVuToPDFOptions) async throws -> DjVuSizeEstimate? {
        let count = summary.pages.count
        guard count > 0 else { return nil }
        let samples = Array(Set([0,count/4,count/2,3*count/4,count-1])).sorted()
        var ratios: [Double] = []
        var separateBytes: Int64 = 0
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for page in samples {
            try Task.checkCancellation()
            let url = directory.appendingPathComponent("sample.pdf")
            let result = try await converter.convert(to:url, options:options,pages:[page])
            separateBytes += result.bytes
            let info = summary.pages[page]
            let dimension = Double(options.dimension(info))
            let area = dimension*dimension*Double(min(info.width,info.height))/Double(max(info.width,info.height))
            ratios.append(Double(result.bytes)/max(1,area))
        }
        let area = summary.pages.reduce(0.0) { sum,info in
            let dimension = Double(options.dimension(info))
            return sum+dimension*dimension*Double(min(info.width,info.height))/Double(max(info.width,info.height))
        }
        // A combined trial measures shared font/catalog overhead instead of counting it once per sample.
        let combined = try await converter.convert(to:directory.appendingPathComponent("combined.pdf"),options:options,pages:samples)
        let sampledArea = samples.reduce(0.0) { sum,index in
            let info = summary.pages[index], dimension = Double(options.dimension(info))
            return sum+dimension*dimension*Double(min(info.width,info.height))/Double(max(info.width,info.height))
        }
        let calibratedMean = Double(combined.bytes)/max(1,sampledArea)
        let mean = ratios.reduce(0,+)/Double(ratios.count)
        let variance = ratios.reduce(0) { $0+pow($1-mean,2) }/Double(ratios.count)
        // The range comes from measured page variability and observed shared-resource overhead.
        // It is a sampling range, not a statistical guarantee for unseen page types.
        let sharingCorrection = Double(combined.bytes)/max(1,Double(separateBytes))
        let variation = sqrt(variance)*sharingCorrection*area
        let overhead = Double(max(0,separateBytes-combined.bytes))
        let predicted = area*calibratedMean
        let margin = variation+overhead
        return .init(lower:Int64(max(0,predicted-margin)),upper:Int64(predicted+margin),sampleCount:samples.count)
    }
}
