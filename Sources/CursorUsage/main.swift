import AppKit

if CommandLine.arguments.contains("--check") {
    let exitCode = CheckMode.run()
    exit(exitCode)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let statusController = StatusItemController()
let poller = UsagePoller(statusController: statusController)
poller.start()

app.run()
