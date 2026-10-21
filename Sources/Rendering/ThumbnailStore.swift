import AppKit
import Combine
import PDFKit

/// Owns a separate PDFDocument confined to this actor, never sharing PDFKit objects across threads.
actor ThumbnailRenderer {
    private let url: URL
    private var document: PDFDocument?
    init(url: URL) { self.url = url }

    func imageData(for index: Int) -> Data? {
        guard !Task.isCancelled else { return nil }
        return autoreleasepool {
            if document == nil { document = PDFDocument(url: url) }
            guard let page = document?.page(at: index) else { return nil }
            let image = page.thumbnail(of: NSSize(width: 112, height: 148), for: .cropBox)
            return image.tiffRepresentation
        }
    }
}

@MainActor
final class ThumbnailStore: ObservableObject {
    private let cache = NSCache<NSNumber, NSImage>()
    private var renderer: ThumbnailRenderer?
    private var djvu: DjVuDocumentBackend?
    private var generation = UUID()

    init() {
        cache.countLimit = 80
        cache.totalCostLimit = 16 * 1024 * 1024
    }

    func attach(url: URL) {
        djvu = nil
        generation = UUID()
        cache.removeAllObjects()
        renderer = ThumbnailRenderer(url: url)
    }

    func attach(djvu: DjVuDocumentBackend) {
        generation = UUID(); cache.removeAllObjects(); renderer = nil; self.djvu = djvu
    }
    func image(for index: Int) async -> NSImage? {
        if let djvu {
            let key = NSNumber(value: index)
            if let image = cache.object(forKey: key) { return image }
            guard let raster = try? await djvu.render(index, maximumDimension: 192), !Task.isCancelled,
                  let cg = raster.orientedImage else { return nil }
            let image = NSImage(cgImage: cg, size: .zero)
            cache.setObject(image, forKey: key, cost: raster.width * raster.height * 4)
            return image
        }
        let key = NSNumber(value: index)
        if let image = cache.object(forKey: key) { return image }
        let expectedGeneration = generation
        guard let renderer, let data = await renderer.imageData(for: index),
              !Task.isCancelled, expectedGeneration == generation,
              let image = NSImage(data: data) else { return nil }
        // Account conservatively for decoded backing pixels, not only compressed TIFF bytes.
        let cost = max(data.count, 224 * 296 * 4)
        cache.setObject(image, forKey: key, cost: cost)
        return image
    }
}
