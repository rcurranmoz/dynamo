import AppKit

final class Dynamo: NSObject, NSApplicationDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var task: Process?

    private var isAwake: Bool { task?.isRunning ?? false }

    func applicationDidFinishLaunching(_ note: Notification) {
        let button = item.button!
        button.target = self
        button.action = #selector(clicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        render()
    }

    @objc private func clicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(withTitle: isAwake ? "Awake (click icon to stop)" : "Sleeping",
                         action: nil, keyEquivalent: "").isEnabled = false
            menu.addItem(.separator())
            menu.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "q").target = self
            item.menu = menu
            item.button?.performClick(nil)   // pop the menu
            item.menu = nil                  // detach so left-click keeps toggling
            return
        }
        isAwake ? stop() : start()
        render()
    }

    private func start() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        // -w <our pid>: caffeinate exits automatically if this app ever dies uncleanly.
        p.arguments = ["-dimsu", "-w", String(ProcessInfo.processInfo.processIdentifier)]
        p.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { self?.render() }
        }
        try? p.run()
        task = p
    }

    private func stop() {
        task?.terminate()
        task = nil
    }

    private func render() {
        let name = isAwake ? "bolt.fill" : "bolt"
        let label = isAwake ? "Keeping Mac awake" : "Sleep allowed"
        item.button?.image = NSImage(systemSymbolName: name, accessibilityDescription: label)
        item.button?.toolTip = label
    }

    @objc private func quit() { stop(); NSApp.terminate(nil) }

    func applicationWillTerminate(_ note: Notification) { stop() }
}

let app = NSApplication.shared
let delegate = Dynamo()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // no Dock icon, no menu bar
app.run()
