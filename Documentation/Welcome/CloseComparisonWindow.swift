import AppKit
import ApplicationServices

let pid = pid_t(CommandLine.arguments[1])!
let app = AXUIElementCreateApplication(pid)
var value: CFTypeRef?
guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
      let windows = value as? [AXUIElement] else { fatalError("Cannot read application windows") }
for window in windows {
    var title: CFTypeRef?
    AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &title)
    guard (title as? String)?.contains("Comparison.pdf") == true else { continue }
    var button: CFTypeRef?
    guard AXUIElementCopyAttributeValue(window, kAXCloseButtonAttribute as CFString, &button) == .success,
          let button else { continue }
    print("Close generated comparison PDF:", AXUIElementPerformAction(button as! AXUIElement, kAXPressAction as CFString).rawValue)
}
