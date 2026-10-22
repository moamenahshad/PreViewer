import AppKit
import ImageIO

struct DjVuPageInfo: Sendable {
    let width: Int
    let height: Int
    let dpi: Int
    let rotation: Int
    var reliableDPI: Bool { (25...6000).contains(dpi) }
    var points: CGSize { CGSize(width: Double(width) * 72 / Double(reliableDPI ? dpi : 300), height: Double(height) * 72 / Double(reliableDPI ? dpi : 300)) }
    var displayPoints: CGSize { rotation % 2 == 0 ? points : CGSize(width: points.height, height: points.width) }
}
struct DjVuWord: Sendable {
    let text: String
    let rect: CGRect // Source pixels, bottom-left origin.
}
struct DjVuBookmark: Sendable, Identifiable {
    let id = UUID()
    let title: String
    let page: Int?
    let children: [DjVuBookmark]
}
struct DjVuSummary: Sendable {
    let pages: [DjVuPageInfo]
    let outline: [DjVuBookmark]
    let metadata: [String: String]
    let version: String
}
struct DjVuRaster: Sendable {
    let data: Data
    let width: Int
    let height: Int
    let rotation: Int
    init(data: Data, width: Int, height: Int, rotation: Int = 0) {
        self.data = data; self.width = width; self.height = height; self.rotation = rotation
    }
    var orientedImage: CGImage? {
        guard let image else { return nil }
        guard rotation != 0 else { return image }
        let size = rotation % 2 == 0 ? CGSize(width: width, height: height) : CGSize(width: height, height: width)
        guard let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: Int(size.width)*4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        switch rotation % 4 {
        case 1: context.translateBy(x: CGFloat(height), y: 0); context.rotate(by: .pi/2)
        case 2: context.translateBy(x: CGFloat(width), y: CGFloat(height)); context.rotate(by: .pi)
        case 3: context.translateBy(x: 0, y: CGFloat(width)); context.rotate(by: -.pi/2)
        default: break
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
    var image: CGImage? {
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 24, bytesPerRow: width * 3,
                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: [], provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}

/// Every decoder is confined to one actor. Viewer and conversion use independent contexts.
extension DPCancellation: @unchecked Sendable {}

actor DjVuDocumentBackend {
    nonisolated let cancellation = DPCancellation()
    nonisolated func cancel() { cancellation.cancel() }
    let url: URL
    private var decoder: DPDecoder?
    private var prepared: DjVuSummary?
    private var cache: [String: DjVuRaster] = [:]
    private var order: [String] = []
    private var cacheBytes = 0
    static let cacheLimit = 40 * 1024 * 1024
    init(url: URL) { self.url = url }
    private func engine() throws -> DPDecoder {
        if let decoder { return decoder }
        guard !cancellation.cancelled else { throw CancellationError() }
        let created = try DPDecoder(url: url, cancellation: cancellation)
        guard !cancellation.cancelled else { throw CancellationError() }
        decoder = created
        return created
    }
    func prepare() throws -> DjVuSummary {
        guard !cancellation.cancelled else { throw CancellationError() }
        if let prepared { return prepared }
        let engine = try engine()
        guard engine.pageCount > 0, engine.pageCount <= 100000 else { throw CocoaError(.fileReadCorruptFile) }
        var pages: [DjVuPageInfo] = []
        for index in 0..<engine.pageCount {
            try Task.checkCancellation()
            guard !cancellation.cancelled else { throw CancellationError() }
            let raw = try engine.pageInfo(index)
            func number(_ key: String) -> Int { (raw[key] as? NSNumber)?.intValue ?? 0 }
            guard number("width") > 0, number("height") > 0 else { throw CocoaError(.fileReadCorruptFile) }
            pages.append(.init(width: number("width"), height: number("height"), dpi: number("dpi"), rotation: number("rotation")))
        }
        func bookmarks(_ raw: [Any]) -> [DjVuBookmark] {
            raw.compactMap { entry in
                guard let a = entry as? [Any], a.count >= 2, let title = a[0] as? String, let link = a[1] as? String else { return nil }
                let number = link.hasPrefix("#") ? Int(link.dropFirst()) : nil
                return DjVuBookmark(title: title, page: number.flatMap { (1...pages.count).contains($0) ? $0-1 : nil }, children: bookmarks(Array(a.dropFirst(2))))
            }
        }
        let result = DjVuSummary(pages: pages, outline: bookmarks(Array(engine.outline().dropFirst())), metadata: engine.metadata(), version: engine.version)
        prepared = result
        return result
    }
    func render(_ index: Int, maximumDimension: Int, cached: Bool = true) async throws -> DjVuRaster {
        let request = DPCancellation()
        return try await withTaskCancellationHandler {
            try renderSynchronously(index, maximumDimension: maximumDimension, cached: cached, request: request)
        } onCancel: { request.cancel() }
    }
    private func renderSynchronously(_ index: Int, maximumDimension: Int, cached: Bool, request: DPCancellation) throws -> DjVuRaster {
        try Task.checkCancellation()
        guard !cancellation.cancelled else { throw CancellationError() }
        let key = "\(index):\(maximumDimension)"
        if let raster = cache[key] { return raster }
        let raster: DjVuRaster = try autoreleasepool {
            let raw = try engine().render(index, maximumDimension: maximumDimension, cancellation: request)
            try Task.checkCancellation()
            guard let data = raw["data"] as? Data, let width = raw["width"] as? Int, let height = raw["height"] as? Int else { throw CocoaError(.fileReadCorruptFile) }
            let info = try engine().pageInfo(index)
            return DjVuRaster(data: data, width: width, height: height, rotation: (info["rotation"] as? Int) ?? 0)
        }
        let data = raster.data
        if cached && data.count <= Self.cacheLimit {
            while cacheBytes + data.count > Self.cacheLimit, !order.isEmpty {
                let oldest = order.removeFirst()
                cacheBytes -= cache.removeValue(forKey: oldest)?.data.count ?? 0
            }
            cache[key] = raster; order.append(key); cacheBytes += data.count
        }
        return raster
    }
    func words(_ page: Int) async throws -> [DjVuWord] {
        let request = DPCancellation()
        return try await withTaskCancellationHandler {
            try wordsSynchronously(page, request: request)
        } onCancel: { request.cancel() }
    }
    private func wordsSynchronously(_ page: Int, request: DPCancellation) throws -> [DjVuWord] {
        try Task.checkCancellation()
        var words: [DjVuWord] = []
        func visit(_ raw: [Any], depth: Int) {
            guard depth < 64, raw.count >= 6 else { return }
            if let text = raw[5] as? String, let x0 = raw[1] as? Double, let y0 = raw[2] as? Double,
               let x1 = raw[3] as? Double, let y1 = raw[4] as? Double {
                words.append(.init(text: text, rect: CGRect(x: x0, y: y0, width: x1-x0, height: y1-y0)))
            } else { for entry in raw.dropFirst(5) { if let entry = entry as? [Any] { visit(entry, depth: depth+1) } } }
        }
        visit(try engine().text(page, cancellation: request), depth: 0)
        return words
    }
    func cachedByteCount() -> Int { cacheBytes }
}
