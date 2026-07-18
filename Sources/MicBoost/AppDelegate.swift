import Cocoa
import CoreAudio

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let engine = MicBoostEngine()
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var popoverVC: MicBoostViewController!
    private var eventMonitor: Any?
    private var controlServer: ControlServer!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        controlServer = ControlServer(engine: engine)
        controlServer.start()

        popoverVC = MicBoostViewController(engine: engine)
        // Load eagerly: the CLI can trigger engine.onStatusChange (which
        // touches popoverVC's outlets) before the popover is ever shown.
        _ = popoverVC.view

        popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 300)
        popover.behavior = .transient
        popover.contentViewController = popoverVC

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = statusIcon(isRunning: false)
            button.target = self
            button.action = #selector(togglePopover)
        }

        engine.onStatusChange = { [weak self] message in
            DispatchQueue.main.async {
                guard let self else { return }
                self.popoverVC.updateStatus(message)
                self.updateIcon(isRunning: self.engine.isRunning)
            }
        }
    }

    // MARK: - Status item

    private func statusIcon(isRunning: Bool) -> NSImage? {
        let symbolName = isRunning ? "mic.fill" : "mic.slash.fill"
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Mic Boost")
        image?.isTemplate = true
        return image
    }

    private func updateIcon(isRunning: Bool) {
        statusItem.button?.image = statusIcon(isRunning: isRunning)
    }

    @objc private func togglePopover() {
        if popover.isShown {
            closePopover()
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePopover()
        }
    }

    private func closePopover() {
        popover.performClose(nil)
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
        eventMonitor = nil
    }
}
