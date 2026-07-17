import Cocoa
import CoreAudio

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private let engine = MicBoostEngine()

    private var devicePopup: NSPopUpButton!
    private var boostSlider: NSSlider!
    private var boostLabel: NSTextField!
    private var levelMeter: NSLevelIndicator!
    private var statusLabel: NSTextField!
    private var toggleButton: NSButton!

    private var levelTimer: Timer?
    private var devices: [(id: AudioDeviceID, name: String)] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        buildWindow()

        engine.onStatusChange = { [weak self] message in
            DispatchQueue.main.async { self?.statusLabel.stringValue = message }
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self else { return }
            levelMeter.doubleValue = Double(engine.peakLevel.current)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    // MARK: - UI

    private func buildWindow() {
        let rect = NSRect(x: 0, y: 0, width: 420, height: 270)
        window = NSWindow(contentRect: rect, styleMask: [.titled, .closable, .miniaturizable],
                           backing: .buffered, defer: false)
        window.title = "Mic Boost"
        window.center()
        window.isReleasedWhenClosed = false

        let content = NSView(frame: rect)
        window.contentView = content

        content.addSubview(label("Level (post-boost):", frame: NSRect(x: 20, y: 236, width: 140, height: 20)))

        levelMeter = NSLevelIndicator(frame: NSRect(x: 170, y: 232, width: 230, height: 20))
        levelMeter.levelIndicatorStyle = .continuousCapacity
        levelMeter.minValue = 0
        levelMeter.maxValue = 1
        levelMeter.warningValue = 0.7
        levelMeter.criticalValue = 0.95
        content.addSubview(levelMeter)

        content.addSubview(label("Microphone:", frame: NSRect(x: 20, y: 180, width: 100, height: 20)))

        devicePopup = NSPopUpButton(frame: NSRect(x: 120, y: 176, width: 280, height: 26))
        devices = engine.availableInputDevices()
        let defaultID = AudioDevice.defaultInputID()
        for device in devices {
            devicePopup.addItem(withTitle: device.name)
            if device.id == defaultID {
                devicePopup.selectItem(withTitle: device.name)
            }
        }
        content.addSubview(devicePopup)

        content.addSubview(label("Boost:", frame: NSRect(x: 20, y: 130, width: 100, height: 20)))

        boostSlider = NSSlider(frame: NSRect(x: 120, y: 125, width: 220, height: 26))
        boostSlider.minValue = 0
        boostSlider.maxValue = 1000
        boostSlider.doubleValue = 100
        boostSlider.target = self
        boostSlider.action = #selector(boostChanged)
        content.addSubview(boostSlider)

        boostLabel = label("100%", frame: NSRect(x: 350, y: 130, width: 60, height: 20))
        content.addSubview(boostLabel)

        toggleButton = NSButton(frame: NSRect(x: 20, y: 80, width: 120, height: 32))
        toggleButton.title = "Start"
        toggleButton.bezelStyle = .rounded
        toggleButton.target = self
        toggleButton.action = #selector(toggleEngine)
        content.addSubview(toggleButton)

        statusLabel = NSTextField(wrappingLabelWithString:
            "Not running. Pick your mic, set a boost level, then hit Start. In Voice Memos / Zoom, select \"BlackHole 2ch\" as the input.")
        statusLabel.frame = NSRect(x: 20, y: 20, width: 380, height: 50)
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        content.addSubview(statusLabel)
    }

    private func label(_ text: String, frame: NSRect) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.frame = frame
        return field
    }

    // MARK: - Actions

    @objc private func boostChanged() {
        let percent = boostSlider.doubleValue
        boostLabel.stringValue = "\(Int(percent))%"
        engine.gain.current = Float(percent / 100.0)
    }

    @objc private func toggleEngine() {
        if engine.isRunning {
            engine.stop()
            toggleButton.title = "Start"
            return
        }

        guard devicePopup.indexOfSelectedItem >= 0, devicePopup.indexOfSelectedItem < devices.count else { return }
        engine.start(micID: devices[devicePopup.indexOfSelectedItem].id)
        if engine.isRunning {
            toggleButton.title = "Stop"
        }
    }
}
