import Cocoa
import CoreAudio

final class MicBoostViewController: NSViewController {
    private let engine: MicBoostEngine
    var onRunningChanged: ((Bool) -> Void)?

    private var devicePopup: NSPopUpButton!
    private var boostSlider: NSSlider!
    private var boostLabel: NSTextField!
    private var levelMeter: NSLevelIndicator!
    private var statusLabel: NSTextField!
    private var toggleButton: NSButton!

    private var levelTimer: Timer?
    private var devices: [(id: AudioDeviceID, name: String)] = []

    init(engine: MicBoostEngine) {
        self.engine = engine
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let rect = NSRect(x: 0, y: 0, width: 320, height: 250)
        let content = NSView(frame: rect)
        buildUI(in: content)
        view = content
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        refreshDevices()
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self else { return }
            levelMeter.doubleValue = Double(engine.peakLevel.current)
        }
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        levelTimer?.invalidate()
        levelTimer = nil
    }

    func updateStatus(_ message: String) {
        statusLabel.stringValue = message
    }

    func refreshDevices() {
        let defaultID = AudioDevice.defaultInputID()
        let previouslySelected = devicePopup.titleOfSelectedItem
        devices = engine.availableInputDevices()

        devicePopup.removeAllItems()
        for device in devices {
            devicePopup.addItem(withTitle: device.name)
        }

        if let previouslySelected, devices.contains(where: { $0.name == previouslySelected }) {
            devicePopup.selectItem(withTitle: previouslySelected)
        } else if let defaultDevice = devices.first(where: { $0.id == defaultID }) {
            devicePopup.selectItem(withTitle: defaultDevice.name)
        }
    }

    // MARK: - UI

    private func buildUI(in content: NSView) {
        content.addSubview(label("Level (post-boost):", frame: NSRect(x: 16, y: 216, width: 140, height: 20)))

        levelMeter = NSLevelIndicator(frame: NSRect(x: 150, y: 212, width: 154, height: 20))
        levelMeter.levelIndicatorStyle = .continuousCapacity
        levelMeter.minValue = 0
        levelMeter.maxValue = 1
        levelMeter.warningValue = 0.7
        levelMeter.criticalValue = 0.95
        content.addSubview(levelMeter)

        content.addSubview(label("Microphone:", frame: NSRect(x: 16, y: 172, width: 90, height: 20)))

        devicePopup = NSPopUpButton(frame: NSRect(x: 16, y: 148, width: 288, height: 26))
        content.addSubview(devicePopup)

        content.addSubview(label("Boost:", frame: NSRect(x: 16, y: 108, width: 90, height: 20)))

        boostSlider = NSSlider(frame: NSRect(x: 16, y: 84, width: 220, height: 26))
        boostSlider.minValue = 0
        boostSlider.maxValue = 1000
        boostSlider.doubleValue = Double(engine.gain.current * 100)
        boostSlider.target = self
        boostSlider.action = #selector(boostChanged)
        content.addSubview(boostSlider)

        boostLabel = label("\(Int(boostSlider.doubleValue))%", frame: NSRect(x: 244, y: 88, width: 60, height: 20))
        content.addSubview(boostLabel)

        toggleButton = NSButton(frame: NSRect(x: 16, y: 44, width: 100, height: 32))
        toggleButton.title = engine.isRunning ? "Stop" : "Start"
        toggleButton.bezelStyle = .rounded
        toggleButton.target = self
        toggleButton.action = #selector(toggleEngine)
        content.addSubview(toggleButton)

        let quitButton = NSButton(frame: NSRect(x: 204, y: 44, width: 100, height: 32))
        quitButton.title = "Quit"
        quitButton.bezelStyle = .rounded
        quitButton.target = NSApp
        quitButton.action = #selector(NSApplication.terminate(_:))
        content.addSubview(quitButton)

        statusLabel = NSTextField(wrappingLabelWithString:
            "Not running. Pick your mic, set a boost level, then hit Start. In Voice Memos / Zoom, select \"BlackHole 2ch\" as the input.")
        statusLabel.frame = NSRect(x: 16, y: 4, width: 288, height: 36)
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
            onRunningChanged?(false)
            return
        }

        guard devicePopup.indexOfSelectedItem >= 0, devicePopup.indexOfSelectedItem < devices.count else { return }
        engine.start(micID: devices[devicePopup.indexOfSelectedItem].id)
        if engine.isRunning {
            toggleButton.title = "Stop"
            onRunningChanged?(true)
        }
    }
}
