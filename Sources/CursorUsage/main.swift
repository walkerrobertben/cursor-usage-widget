import Foundation
import CursorUsageCore

#if canImport(AppKit)
import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let statusController = StatusItemController()
let poller = UsagePoller(statusController: statusController)
poller.start()

app.run()
#else
fputs("Cursor Usage is a macOS menu bar app.\n", stderr)
exit(1)
#endif
