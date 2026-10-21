// Select a project-owned fixture through the native Open panel, without clipboard changes.
import AppKit
import ApplicationServices
let pid = Int32(CommandLine.arguments[1])!
let path = CommandLine.arguments[2]
precondition(path.contains("/DjVu Preview/Tests/Fixtures/"))
func attribute(_ e: AXUIElement,_ key: String) -> CFTypeRef? { var value: CFTypeRef?; AXUIElementCopyAttributeValue(e,key as CFString,&value); return value }
func children(_ e: AXUIElement) -> [AXUIElement] { attribute(e,kAXChildrenAttribute) as? [AXUIElement] ?? [] }
let app = AXUIElementCreateApplication(pid)
guard let window = (attribute(app,kAXWindowsAttribute) as? [AXUIElement])?.first(where:{ attribute($0,kAXTitleAttribute) as? String == "Open" }) else { fatalError("Native Open panel unavailable") }
NSRunningApplication(processIdentifier:pid)?.activate()
AXUIElementPerformAction(window,kAXRaiseAction as CFString)
Thread.sleep(forTimeInterval:0.3)
guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { exit(2) }
func key(_ code: CGKeyCode,_ flags: CGEventFlags = []) {
    for down in [true,false] { let event = CGEvent(keyboardEventSource:nil,virtualKey:code,keyDown:down)!; event.flags = flags; event.post(tap:.cghidEventTap) }
}
key(5,[.maskCommand,.maskShift]) // Native Go to Folder/File.
Thread.sleep(forTimeInterval:0.4)
guard let focused = attribute(app,kAXFocusedUIElementAttribute) else { fatalError("No path field") }
let field = focused as! AXUIElement
let role = attribute(field,kAXRoleAttribute) as? String ?? ""
guard [kAXTextFieldRole,kAXComboBoxRole].contains(role) else { fatalError("Unexpected path field role: \(role)") }
let status = AXUIElementSetAttributeValue(field,kAXValueAttribute as CFString,path as CFString)
guard status == .success else { fatalError("Cannot enter fixture path: \(status.rawValue)") }
key(36)
Thread.sleep(forTimeInterval:0.6)
func openButton(_ e: AXUIElement,_ depth: Int = 0) -> AXUIElement? {
    guard depth < 20 else { return nil }
    if attribute(e,kAXRoleAttribute) as? String == kAXButtonRole && attribute(e,kAXTitleAttribute) as? String == "Open" { return e }
    for child in children(e) { if let button = openButton(child,depth+1) { return button } }
    return nil
}
guard let button = openButton(window) else { fatalError("No Open button") }
let enabled = attribute(button,kAXEnabledAttribute) as? Bool ?? false
print("Selected fixture:",URL(fileURLWithPath:path).lastPathComponent,"Open enabled:",enabled)
guard enabled else { fatalError("DjVu file is still rejected by the native panel") }
print("Open action:",AXUIElementPerformAction(button,kAXPressAction as CFString).rawValue)
