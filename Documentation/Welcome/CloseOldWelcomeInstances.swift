import AppKit
import ApplicationServices

for argument in CommandLine.arguments.dropFirst() {
    guard let pid = pid_t(argument), let running = NSRunningApplication(processIdentifier: pid),
          running.bundleIdentifier == "com.independent.djvupreview" else { continue }
    let app = AXUIElementCreateApplication(pid)
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
          let windows = value as? [AXUIElement] else { continue }
    let titles = windows.compactMap { window -> String? in
        var title: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &title)
        return title as? String
    }
    guard titles.allSatisfy({ $0.isEmpty || $0 == "Welcome to DjVu Preview" }) else { continue }
    print("Close old welcome-only study instance \(pid):", running.terminate())
}
