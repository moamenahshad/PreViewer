import AppKit
import ApplicationServices

let pid = pid_t(CommandLine.arguments[1])!
let app = AXUIElementCreateApplication(pid)
func attr(_ e: AXUIElement, _ key: String) -> CFTypeRef? {
    var value: CFTypeRef?
    AXUIElementCopyAttributeValue(e, key as CFString, &value)
    return value
}
func children(_ e: AXUIElement) -> [AXUIElement] { attr(e, kAXChildrenAttribute) as? [AXUIElement] ?? [] }
func hasPage(_ e: AXUIElement, depth: Int = 0) -> Bool {
    if attr(e, kAXRoleAttribute) as? String == "AXPage" { return true }
    return depth < 5 && children(e).contains { hasPage($0, depth: depth + 1) }
}
func visit(_ e: AXUIElement, depth: Int = 0) {
    guard depth < 10 else { return }
    let role = attr(e, kAXRoleAttribute) as? String
    if role == "AXMenu" { AXUIElementPerformAction(e, "AXCancel" as CFString); return }
    if role == "AXScrollArea" && hasPage(e) {
        for _ in 0..<5 { print("Scroll up status:", AXUIElementPerformAction(e, "AXScrollUpByPage" as CFString).rawValue) }
        return
    }
    for child in children(e) { visit(child, depth: depth + 1) }
}
if let windows = attr(app, kAXWindowsAttribute) as? [AXUIElement] {
    for window in windows where (attr(window, kAXTitleAttribute) as? String)?.contains("Comparison.pdf") == true { visit(window) }
}
NSRunningApplication(processIdentifier: pid)?.activate(options: [])
