import AppKit

if case let .finished(code) = CLI.dispatch(arguments: CommandLine.arguments) {
    exit(code)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let statusController = StatusItemController()
let poller = UsagePoller(statusController: statusController)
poller.start()

app.run()
