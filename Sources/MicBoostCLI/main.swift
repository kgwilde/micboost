import Foundation
import MicBoostIPC
#if canImport(Darwin)
import Darwin
#endif

func fail(_ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(1)
}

/// `micboostctl` and `MicBoost.app` are built side by side by build.sh, so
/// the app can be found relative to wherever this binary actually lives
/// (following symlinks, since the README has you symlink this into PATH).
func siblingAppURL() -> URL? {
    let cliURL = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
    let appURL = cliURL.deletingLastPathComponent().appendingPathComponent("MicBoost.app")
    return FileManager.default.fileExists(atPath: appURL.path) ? appURL : nil
}

func launchApp() -> Bool {
    guard let appURL = siblingAppURL() else { return false }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = ["-a", appURL.path]
    do {
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
    } catch {
        return false
    }
}

func connectOrFail() -> LineChannel {
    if let fd = IPC.connectSocket() {
        return LineChannel(fd: fd)
    }

    guard launchApp() else {
        fail("MicBoost is not running and MicBoost.app wasn't found next to micboostctl. Launch it manually first.")
    }

    for _ in 0..<50 {
        Thread.sleep(forTimeInterval: 0.1)
        if let fd = IPC.connectSocket() {
            return LineChannel(fd: fd)
        }
    }
    fail("MicBoost didn't start in time.")
}

/// Settings chosen interactively by `micboostctl run`, persisted so a later
/// plain `micboostctl start` can reapply them without prompting again.
struct SavedSettings {
    let device: String
    let boostPercent: Int
    let bassDB: Int

    private static let path = NSHomeDirectory() + "/Library/Application Support/MicBoost/last-run-settings.txt"

    static func load() -> SavedSettings? {
        guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        let parts = contents.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3, let boost = Int(parts[1]), let bass = Int(parts[2]) else { return nil }
        return SavedSettings(device: parts[0], boostPercent: boost, bassDB: bass)
    }

    func save() {
        let dir = (SavedSettings.path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? "\(device)|\(boostPercent)|\(bassDB)".write(toFile: SavedSettings.path, atomically: true, encoding: .utf8)
    }
}

struct Status {
    let running: Bool
    let device: String
    let boostPercent: Int
    let bassDB: Int
    let level: Float

    init?(line: String) {
        let parts = line.split(separator: "|", maxSplits: 4, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 5,
              let runningFlag = Int(parts[0]),
              let boostPercent = Int(parts[2]),
              let bassDB = Int(parts[3]),
              let level = Float(parts[4]) else { return nil }
        running = runningFlag == 1
        device = parts[1]
        self.boostPercent = boostPercent
        self.bassDB = bassDB
        self.level = level
    }

    var summary: String {
        running
            ? "Running: \(device) (boost \(boostPercent)%, bass +\(bassDB)dB)"
            : "Stopped"
    }
}

func runOneShot(_ command: String) {
    let channel = connectOrFail()
    channel.writeLine(command)
    guard let line = channel.readLine(), let status = Status(line: line) else {
        fail("No response from MicBoost.")
    }
    print(status.summary)
    channel.close()
}

/// Plain `start`: reapplies settings saved by a previous `run`, if any.
func runStart() {
    let channel = connectOrFail()
    if let saved = SavedSettings.load() {
        channel.writeLine("START|\(saved.device)|\(saved.boostPercent)|\(saved.bassDB)")
    } else {
        channel.writeLine("START")
    }
    guard let line = channel.readLine(), let status = Status(line: line) else {
        fail("No response from MicBoost.")
    }
    print(status.summary)
    channel.close()
}

func fetchDevices(_ channel: LineChannel) -> [String] {
    channel.writeLine("DEVICES")
    guard let countLine = channel.readLine(), let count = Int(countLine) else { return [] }
    return (0..<count).compactMap { _ in channel.readLine() }
}

func promptDevice(_ names: [String], default defaultName: String) -> String {
    for (index, name) in names.enumerated() {
        let marker = name == defaultName ? "  (default)" : ""
        print("  \(index + 1)) \(name)\(marker)")
    }
    let defaultIndex = (names.firstIndex(of: defaultName) ?? 0) + 1
    print("Device [\(defaultIndex)]: ", terminator: "")
    guard let line = Swift.readLine(), let index = Int(line.trimmingCharacters(in: .whitespaces)),
          index >= 1, index <= names.count else {
        return defaultName
    }
    return names[index - 1]
}

func promptInt(_ label: String, default defaultValue: Int) -> Int {
    print("\(label) [\(defaultValue)]: ", terminator: "")
    guard let line = Swift.readLine(), let value = Int(line.trimmingCharacters(in: .whitespaces)) else {
        return defaultValue
    }
    return value
}

/// `run`'s interactive setup: pick a device, boost %, and bass boost dB
/// (defaulting to whatever was chosen last time), persist the choice, and
/// start with it.
func runInteractiveSetup() {
    let deviceChannel = connectOrFail()
    let devices = fetchDevices(deviceChannel)
    deviceChannel.close()

    guard !devices.isEmpty else {
        fail("No input devices available.")
    }

    let previous = SavedSettings.load()
    print("MicBoost setup: press Enter to accept the default shown.\n")
    let device = promptDevice(devices, default: previous?.device ?? devices[0])
    let boost = promptInt("Boost %", default: previous?.boostPercent ?? 100)
    let bass = promptInt("Bass boost (dB)", default: previous?.bassDB ?? 6)
    print()

    SavedSettings(device: device, boostPercent: boost, bassDB: bass).save()

    let startChannel = connectOrFail()
    startChannel.writeLine("START|\(device)|\(boost)|\(bass)")
    _ = startChannel.readLine()
    startChannel.close()
}

// MARK: - Raw terminal mode

var originalTermios = termios()

func enableRawMode() {
    tcgetattr(STDIN_FILENO, &originalTermios)
    var raw = originalTermios
    raw.c_lflag &= ~tcflag_t(ICANON | ECHO | ISIG)
    tcsetattr(STDIN_FILENO, TCSANOW, &raw)
}

func disableRawMode() {
    tcsetattr(STDIN_FILENO, TCSANOW, &originalTermios)
}

// MARK: - Watch dashboard

func renderBar(level: Float, width: Int = 30) -> String {
    let filled = max(0, min(width, Int(level * Float(width))))
    return String(repeating: "█", count: filled) + String(repeating: "░", count: width - filled)
}

func padded(_ s: String, _ width: Int = 60) -> String {
    s.count >= width ? s : s + String(repeating: " ", count: width - s.count)
}

func render(_ status: Status) {
    var out = "\u{1B}[H"
    out += padded("MicBoost: \(status.running ? "Running" : "Stopped")") + "\n"
    out += padded("Device: \(status.device)") + "\n"
    out += padded("Level:  [\(renderBar(level: status.level))] \(Int(status.level * 100))%") + "\n"
    out += padded("Boost:  \(status.boostPercent)%   Bass: +\(status.bassDB) dB") + "\n\n"
    out += padded("[s] start/stop    [q] or ctrl-c: stop and quit", 76)
    print(out, terminator: "")
    fflush(stdout)
}

/// Shows the live dashboard until the user quits, then sends STOP.
func runDashboard() {
    let channel = connectOrFail()
    channel.writeLine("WATCH")

    enableRawMode()
    print("\u{1B}[2J", terminator: "")

    let shouldExit = AtomicFlag()

    let keyThread = Thread {
        var byte: UInt8 = 0
        while true {
            let n = read(STDIN_FILENO, &byte, 1)
            if n <= 0 { break }
            if byte == 3 || byte == UInt8(ascii: "q") || byte == UInt8(ascii: "Q") {
                shouldExit.set(true)
                break
            } else if byte == UInt8(ascii: "s") || byte == UInt8(ascii: "S") {
                channel.writeLine("TOGGLE")
            }
        }
    }
    keyThread.start()

    while !shouldExit.get() {
        guard let line = channel.readLine(), let status = Status(line: line) else { break }
        render(status)
    }

    channel.writeLine("STOP")
    disableRawMode()
    channel.close()
    print("\u{1B}[2J\u{1B}[H", terminator: "")
}

/// Small lock-protected flag shared between the key-reading thread and the
/// status-rendering loop.
final class AtomicFlag {
    private var value = false
    private let lock = NSLock()

    func set(_ newValue: Bool) {
        lock.lock(); defer { lock.unlock() }
        value = newValue
    }

    func get() -> Bool {
        lock.lock(); defer { lock.unlock() }
        return value
    }
}

// MARK: - Entry point

let arguments = CommandLine.arguments
guard arguments.count > 1 else {
    fail("Usage: micboostctl <run|start|stop>")
}

switch arguments[1] {
case "run":
    runInteractiveSetup()
    runDashboard()
case "start": runStart()
case "stop": runOneShot("STOP")
default: fail("Usage: micboostctl <run|start|stop>")
}
