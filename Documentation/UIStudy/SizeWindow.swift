import AppKit
import ApplicationServices

let pid = pid_t(CommandLine.arguments[1])!
let app = AXUIElementCreateApplication(pid)
var value: CFTypeRef?
guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
      let windows = value as? [AXUIElement] else { fatalError("Window access unavailable") }
for window in windows {
    var title: CFTypeRef?
    AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &title)
    guard (title as? String)?.contains("Comparison.pdf") == true else { continue }
    var position = CGPoint(x: 960, y: 30)
    AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, AXValueCreate(.cgPoint, &position)!)
    var size = CGSize(width: 960, height: 972)
    let sizeValue = AXValueCreate(.cgSize, &size)!
    print("Resize:", AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue).rawValue)
    AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    NSRunningApplication(processIdentifier: pid)?.activate(options: [])
}
