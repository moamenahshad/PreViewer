// Read and exercise only the most recently launched DjVu Preview instance.
// Used with project-owned fixtures; never selects or overwrites user documents.
import AppKit
import ApplicationServices
import CoreGraphics

func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    AXUIElementCopyAttributeValue(element, name as CFString, &value)
    return value
}
func children(_ element: AXUIElement) -> [AXUIElement] {
    attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
}
func string(_ element: AXUIElement, _ name: String) -> String {
    attribute(element, name) as? String ?? ""
}
let running = NSRunningApplication.runningApplications(withBundleIdentifier: "com.independent.djvupreview")
    .sorted { ($0.launchDate ?? .distantPast) > ($1.launchDate ?? .distantPast) }
let requestedPID = ProcessInfo.processInfo.environment["DJVU_VALIDATION_PID"].flatMap(Int32.init)
guard let running = running.first(where: { requestedPID == nil || $0.processIdentifier == requestedPID }) else { fatalError("DjVu Preview is not running") }
let app = AXUIElementCreateApplication(running.processIdentifier)
let command = CommandLine.arguments.dropFirst().first ?? "inspect"
if command == "close-validation-instance" {
    guard requestedPID != nil else { fatalError("An explicit DJVU_VALIDATION_PID is required for closing an instance") }
    let windows = attribute(app,kAXWindowsAttribute) as? [AXUIElement] ?? []
    let titles = windows.map { string($0,kAXTitleAttribute) }
    guard !titles.isEmpty, titles.allSatisfy({ $0.hasPrefix("lizard2002.djvu") || $0 == "DjVu to PDF" }) else { fatalError("Instance contains windows outside the validation fixture") }
    print("Terminate fixture-only instance:", running.terminate())
} else if command == "export" || command == "open" {
    guard let raw = attribute(app, kAXMenuBarAttribute) else { fatalError("Menu bar unavailable") }
    let bar = raw as! AXUIElement
    guard let file = children(bar).first(where: { string($0,kAXTitleAttribute) == "File" }) else { fatalError("File menu unavailable") }
    print("File menu:", AXUIElementPerformAction(file,kAXPressAction as CFString).rawValue)
    let menuTitle = command == "open" ? "Open…" : "Export…"
    for menu in children(file) {
        for item in children(menu) where string(item,kAXTitleAttribute) == menuTitle {
            print(menuTitle,AXUIElementPerformAction(item,kAXPressAction as CFString).rawValue)
        }
    }
 } else if command == "cancel-save-panel" {
    var found = false
    func visit(_ element: AXUIElement, _ depth: Int, insideSheet: Bool) {
        guard depth < 22 else { return }
        let sheet = insideSheet || string(element,kAXRoleAttribute) == kAXSheetRole
        if sheet && !found && string(element,kAXRoleAttribute) == kAXButtonRole && string(element,kAXTitleAttribute) == "Cancel" {
            print("Native save sheet found; Cancel:",AXUIElementPerformAction(element,kAXPressAction as CFString).rawValue)
            found = true; return
        }
        if !found { for child in children(element) { visit(child,depth+1,insideSheet:sheet) } }
    }
    for window in attribute(app,kAXWindowsAttribute) as? [AXUIElement] ?? [] where string(window,kAXTitleAttribute) == "DjVu to PDF" { visit(window,0,insideSheet:false) }
    if !found { print("No save sheet found") }
} else if command == "resize", CommandLine.arguments.count == 4 {
    let windows = attribute(app,kAXWindowsAttribute) as? [AXUIElement] ?? []
    guard let window = windows.first(where: { string($0,kAXTitleAttribute) == "DjVu to PDF" }) else { fatalError("Conversion window unavailable") }
    var size = CGSize(width: Double(CommandLine.arguments[2])!,height: Double(CommandLine.arguments[3])!)
    print("Resize:",AXUIElementSetAttributeValue(window,kAXSizeAttribute as CFString,AXValueCreate(.cgSize,&size)!).rawValue)
} else if command == "press", CommandLine.arguments.count == 3 {
    let label = CommandLine.arguments[2]
    var pressed = false
    func visit(_ element: AXUIElement, _ depth: Int) {
        guard depth < 20, !pressed else { return }
        if string(element,kAXRoleAttribute) == kAXButtonRole && (string(element,kAXTitleAttribute) == label || string(element,kAXDescriptionAttribute) == label) {
            print("Press \(label):",AXUIElementPerformAction(element,kAXPressAction as CFString).rawValue); pressed = true; return
        }
        for child in children(element) { visit(child,depth+1) }
    }
    for window in attribute(app,kAXWindowsAttribute) as? [AXUIElement] ?? [] where string(window,kAXTitleAttribute) == "DjVu to PDF" { visit(window,0) }
    if !pressed { print("Button unavailable:", label) }
} else {
    print("PID:",running.processIdentifier)
    var nodes = 0
    func visit(_ element: AXUIElement, _ depth: Int) {
        guard depth < 18, nodes < 220 else { return }; nodes += 1
        print(String(repeating:" ",count:depth),string(element,kAXRoleAttribute),string(element,kAXTitleAttribute),string(element,kAXDescriptionAttribute),string(element,kAXValueAttribute))
        for child in children(element) { visit(child,depth+1) }
    }
    for window in attribute(app,kAXWindowsAttribute) as? [AXUIElement] ?? [] { visit(window,0) }
    if let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly,.excludeDesktopElements],kCGNullWindowID) as? [[String:Any]] {
        for window in windows where window[kCGWindowOwnerPID as String] as? Int32 == running.processIdentifier {
            print("WINDOW:",window[kCGWindowNumber as String] ?? "",window[kCGWindowName as String] ?? "",window[kCGWindowBounds as String] ?? "")
        }
    }
}
