import AppKit
import Carbon

let pid = pid_t(CommandLine.arguments[1])!
let target = NSAppleEventDescriptor(processIdentifier: pid)
let event = NSAppleEventDescriptor(eventClass: AEEventClass(kCoreEventClass), eventID: AEEventID(kAEOpenDocuments),
                                  targetDescriptor: target, returnID: AEReturnID(kAutoGenerateReturnID),
                                  transactionID: AETransactionID(kAnyTransactionID))
let files = NSAppleEventDescriptor.list()
files.insert(NSAppleEventDescriptor(fileURL: URL(fileURLWithPath: "/Users/moamen/Documents/REA APPS/DjVu Preview/Documentation/UIStudy/Comparison.pdf")), at: 1)
event.setParam(files, forKeyword: AEKeyword(keyDirectObject))
_ = try event.sendEvent(options: .noReply, timeout: 5)
print("Sent standard open-documents event to \(pid)")
