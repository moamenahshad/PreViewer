// Captures only the test host windows identified by the DjVu UI test document title.
import AppKit
import ScreenCaptureKit
import ImageIO
import UniformTypeIdentifiers
_ = NSApplication.shared
let directory = URL(fileURLWithPath: CommandLine.arguments[1],isDirectory:true)
try FileManager.default.createDirectory(at: directory,withIntermediateDirectories:true)
let deadline = Date().addingTimeInterval(90)
var sequence = 0
while Date() < deadline && sequence < 28 {
    let content = try await SCShareableContent.excludingDesktopWindows(true,onScreenWindowsOnly:true)
    if let reader = content.windows.first(where:{ ($0.title ?? "").hasPrefix("DjVu Validation ") }),
       let pid = reader.owningApplication?.processID {
        for window in content.windows where window.owningApplication?.processID == pid && ((window.title ?? "").hasPrefix("DjVu Validation ") || window.title == "DjVu to PDF") {
            let filter = SCContentFilter(desktopIndependentWindow:window)
            let config = SCStreamConfiguration()
            config.width = Int(window.frame.width); config.height = Int(window.frame.height)
            config.showsCursor = false; config.ignoreShadowsSingleWindow = true
            let image: CGImage = try await withCheckedThrowingContinuation { continuation in
                SCScreenshotManager.captureImage(contentFilter:filter,configuration:config) { image,error in
                    if let image { continuation.resume(returning:image) }
                    else { continuation.resume(throwing:error ?? NSError(domain:"Capture",code:1)) }
                }
            }
            let file = directory.appendingPathComponent("\(sequence)-\(window.title ?? "window").png")
            if let destination = CGImageDestinationCreateWithURL(file as CFURL,UTType.png.identifier as CFString,1,nil) {
                CGImageDestinationAddImage(destination,image,nil); CGImageDestinationFinalize(destination)
            }
            print(file.path); sequence += 1
        }
    }
    try await Task.sleep(for:.milliseconds(750))
}
