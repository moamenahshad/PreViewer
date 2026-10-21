import AppKit
import ScreenCaptureKit
import ImageIO
import UniformTypeIdentifiers

_ = NSApplication.shared

let id = UInt32(CommandLine.arguments[1])!
let output = URL(fileURLWithPath: CommandLine.arguments[2])
let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
guard let window = content.windows.first(where: { $0.windowID == id }) else { fatalError("Selected window is unavailable") }
let filter = SCContentFilter(desktopIndependentWindow: window)
let configuration = SCStreamConfiguration()
configuration.width = Int(window.frame.width)
configuration.height = Int(window.frame.height)
configuration.showsCursor = false
configuration.ignoreShadowsSingleWindow = true
let image: CGImage = try await withCheckedThrowingContinuation { continuation in
    SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) { image, error in
        if let image { continuation.resume(returning: image) }
        else { continuation.resume(throwing: error ?? NSError(domain: "Capture", code: 1)) }
    }
}
guard let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    fatalError("Cannot create screenshot output")
}
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("Cannot save screenshot") }
print("Captured selected window \(id): \(image.width)×\(image.height)")
