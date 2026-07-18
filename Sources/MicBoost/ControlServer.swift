import Foundation
import MicBoostIPC
#if canImport(Darwin)
import Darwin
#endif

/// Listens on the local control socket so `micboostctl` can start/stop/watch
/// the engine that's already running in this app. All engine access is
/// funneled through the main thread via `DispatchQueue.main.sync`, since
/// `MicBoostEngine` (like the popover UI) assumes single-threaded use.
final class ControlServer {
    private let engine: MicBoostEngine

    init(engine: MicBoostEngine) {
        self.engine = engine
    }

    func start() {
        guard let listenFD = IPC.listenSocket() else { return }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.acceptLoop(listenFD)
        }
    }

    private func acceptLoop(_ listenFD: Int32) {
        while true {
            let clientFD = accept(listenFD, nil, nil)
            guard clientFD >= 0 else { continue }
            DispatchQueue.global(qos: .utility).async { [weak self] in
                self?.handle(LineChannel(fd: clientFD))
            }
        }
    }

    private func handle(_ channel: LineChannel) {
        guard let command = channel.readLine() else {
            channel.close()
            return
        }

        if command == "START" || command.hasPrefix("START|") {
            DispatchQueue.main.sync { performStart(command) }
            channel.writeLine(statusLine())
            channel.close()
        } else if command == "STOP" {
            DispatchQueue.main.sync { engine.stop() }
            channel.writeLine(statusLine())
            channel.close()
        } else if command == "WATCH" {
            watchLoop(channel)
        } else if command == "DEVICES" {
            sendDevices(channel)
            channel.close()
        } else {
            channel.writeLine("ERR unknown command")
            channel.close()
        }
    }

    /// Plain "START" reuses whatever device/boost/bass are already set.
    /// "START|device|boostPercent|bassDB" (from `micboostctl run`) applies
    /// those first. An empty device field falls back the same way plain
    /// START does.
    private func performStart(_ command: String) {
        guard command != "START" else {
            engine.startWithLastOrDefaultDevice()
            return
        }
        let parts = command.split(separator: "|", maxSplits: 3, omittingEmptySubsequences: false).map(String.init)
        let deviceName = parts.count > 1 && !parts[1].isEmpty ? parts[1] : nil
        let boostPercent = parts.count > 2 ? Int(parts[2]) : nil
        let bassDB = parts.count > 3 ? Int(parts[3]) : nil
        engine.configureAndStart(deviceName: deviceName, boostPercent: boostPercent, bassDB: bassDB)
    }

    private func sendDevices(_ channel: LineChannel) {
        let names = DispatchQueue.main.sync { engine.availableInputDevices().map(\.name) }
        channel.writeLine("\(names.count)")
        for name in names {
            channel.writeLine(name)
        }
    }

    /// Streams a status line every 100ms while also listening for "TOGGLE"
    /// or "STOP" commands from the client, until the client disconnects.
    private func watchLoop(_ channel: LineChannel) {
        let stopped = AtomicValue<Bool>(false)
        let writerDone = DispatchSemaphore(value: 0)

        DispatchQueue.global(qos: .utility).async { [weak self] in
            while !stopped.current {
                guard let self, channel.writeLine(self.statusLine()) else {
                    stopped.current = true
                    break
                }
                Thread.sleep(forTimeInterval: 0.1)
            }
            writerDone.signal()
        }

        while !stopped.current {
            guard let line = channel.readLine() else { break }
            if line == "TOGGLE" {
                DispatchQueue.main.sync {
                    if engine.isRunning {
                        engine.stop()
                    } else {
                        engine.startWithLastOrDefaultDevice()
                    }
                }
            } else if line == "STOP" {
                DispatchQueue.main.sync { engine.stop() }
            }
        }

        stopped.current = true
        writerDone.wait()
        channel.close()
    }

    /// `running|device|boostPercent|bassDB|level`, `|`-delimited so a
    /// device name with spaces doesn't break parsing.
    private func statusLine() -> String {
        DispatchQueue.main.sync {
            let running = engine.isRunning ? "1" : "0"
            let device = engine.currentDeviceName ?? "-"
            let boost = Int(engine.gain.current * 100)
            let bass = Int(engine.bassBoostDB.current)
            let level = engine.peakLevel.current
            return "\(running)|\(device)|\(boost)|\(bass)|\(String(format: "%.3f", level))"
        }
    }
}
