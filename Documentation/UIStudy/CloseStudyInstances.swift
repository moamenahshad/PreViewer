import AppKit
import ApplicationServices

// Only instances launched during this study, and only if they contain no other titled document.
for pid: pid_t in [42408, 44539, 46464] {
    guard let running = NSRunningApplication(processIdentifier: pid),
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
    guard titles.allSatisfy({ $0.isEmpty || $0.contains("Comparison.pdf") }) else { continue }
    print("Terminate study instance \(pid): \(running.terminate())")
}
