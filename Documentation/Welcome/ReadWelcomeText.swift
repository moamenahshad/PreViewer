import AppKit
import ApplicationServices
let app = AXUIElementCreateApplication(pid_t(CommandLine.arguments[1])!)
func attr(_ e: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    AXUIElementCopyAttributeValue(e, name as CFString, &value)
    return value
}
func visit(_ e: AXUIElement, depth: Int = 0) {
    guard depth < 12 else { return }
    let role = attr(e, kAXRoleAttribute) as? String ?? ""
    let title = attr(e, kAXTitleAttribute) as? String ?? ""
    let value = attr(e, kAXValueAttribute) as? String ?? ""
    if !title.isEmpty || !value.isEmpty { print(role, title, value) }
    for child in attr(e, kAXChildrenAttribute) as? [AXUIElement] ?? [] { visit(child, depth: depth + 1) }
}
for window in attr(app, kAXWindowsAttribute) as? [AXUIElement] ?? [] {
    if (attr(window, kAXTitleAttribute) as? String)?.contains("Welcome to DjVu Preview") == true { visit(window) }
}
