import AppKit
import ApplicationServices
import CoreGraphics
import CoreText

let root = URL(fileURLWithPath: "/Users/moamen/Documents/REA APPS/DjVu Preview/Documentation/UIStudy")
if CommandLine.arguments.contains("--fixture") {
    let url = root.appendingPathComponent("Comparison.pdf")
    if !FileManager.default.fileExists(atPath: url.path) {
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        let context = CGContext(url as CFURL, mediaBox: &box, nil)!
        for index in 1...4 {
            context.beginPDFPage(nil)
            context.setFillColor(CGColor(red: 0.12, green: 0.35, blue: 0.65, alpha: 1))
            context.fill(CGRect(x: 0, y: 650, width: 612, height: 142))
            let title = NSAttributedString(string: "Document interface study — \(index)", attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica-Bold" as CFString, 23, nil),
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): NSColor.white.cgColor
            ])
            context.textPosition = CGPoint(x: 40, y: 710)
            CTLineDraw(CTLineCreateWithAttributedString(title), context)
            let body = NSAttributedString(string: "The same PDF is used in both viewers.\nPage \(index) of 4", attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, 16, nil)
            ])
            let framesetter = CTFramesetterCreateWithAttributedString(body)
            let path = CGPath(rect: CGRect(x: 40, y: 120, width: 532, height: 480), transform: nil)
            CTFrameDraw(CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil), context)
            context.endPDFPage()
        }
        context.closePDF()
    }
    print("Fixture: \(url.path)")
}
print("AX trusted: \(AXIsProcessTrusted()); screen capture: \(CGPreflightScreenCaptureAccess())")
let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
for window in windows {
    let owner = window[kCGWindowOwnerName as String] as? String ?? ""
    if owner == "Preview" || owner == "DjVu Preview" { print(window) }
}
