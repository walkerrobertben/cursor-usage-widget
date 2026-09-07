import Foundation
import CursorUsageCore

#if canImport(AppKit)
import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let statusController = MainActor.assumeIsolated { StatusItemController() }
let poller = MainActor.assumeIsolated {
    let poller = UsagePoller(statusController: statusController)
    poller.start()
    return poller
}

app.run()
#else
fputs("Cursor Usage is a macOS menu bar app.\n", stderr)
exit(1)
#endif
