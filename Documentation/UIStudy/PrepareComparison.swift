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
    var size = CGSize(width: 1035, height: 925)
    print("Resize status:", AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, AXValueCreate(.cgSize, &size)!).rawValue)
    AXUIElementPerformAction(window, kAXRaiseAction as CFString)
}
NSRunningApplication(processIdentifier: pid)?.activate(options: [])
// Public accessibility menu actions only. Reset to the first page to compare the same viewport.
var menuBar: CFTypeRef?
if AXUIElementCopyAttributeValue(app, kAXMenuBarAttribute as CFString, &menuBar) == .success {
    func children(_ item: AXUIElement) -> [AXUIElement] {
        var result: CFTypeRef?
        AXUIElementCopyAttributeValue(item, kAXChildrenAttribute as CFString, &result)
        return result as? [AXUIElement] ?? []
    }
    func title(_ item: AXUIElement) -> String {
        var result: CFTypeRef?
        AXUIElementCopyAttributeValue(item, kAXTitleAttribute as CFString, &result)
        return result as? String ?? ""
    }
    let bar = menuBar as! AXUIElement
    if let go = children(bar).first(where: { title($0) == "Go" }) {
        for menu in children(go) {
            if let first = children(menu).first(where: { ["First Page", "First Item"].contains(title($0)) }) {
                print("First page status:", AXUIElementPerformAction(first, kAXPressAction as CFString).rawValue)
            }
        }
    }
}
