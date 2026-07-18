import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Local control channel between the MicBoost menu bar app (which owns the
/// one running audio engine) and the `micboostctl` CLI. The CLI never runs
/// its own engine, it just sends commands over this socket so both stay in
/// sync with whichever process is showing state at the time.
public enum IPC {
    public static let socketPath: String = {
        let dir = NSHomeDirectory() + "/Library/Application Support/MicBoost"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir + "/control.sock"
    }()

    private static func makeAddress() -> sockaddr_un {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(socketPath.utf8)
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            raw.copyBytes(from: bytes.prefix(raw.count - 1))
        }
        return addr
    }

    /// Creates a listening socket at `socketPath`. Only the app calls this.
    public static func listenSocket() -> Int32? {
        unlink(socketPath)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }

        var addr = makeAddress()
        let bindResult = withUnsafePointer(to: &addr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0, Darwin.listen(fd, 4) == 0 else {
            close(fd)
            return nil
        }
        return fd
    }

    /// Connects to the app's control socket. Only the CLI calls this.
    public static func connectSocket() -> Int32? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }

        var addr = makeAddress()
        let result = withUnsafePointer(to: &addr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else {
            close(fd)
            return nil
        }
        return fd
    }
}

/// Buffered newline-delimited read/write over a raw socket file descriptor.
public final class LineChannel {
    private let fd: Int32
    private var buffer = Data()

    public init(fd: Int32) {
        self.fd = fd
    }

    @discardableResult
    public func writeLine(_ line: String) -> Bool {
        var data = Data(line.utf8)
        data.append(0x0A)
        return data.withUnsafeBytes { raw -> Bool in
            guard let base = raw.baseAddress else { return false }
            var written = 0
            let total = raw.count
            while written < total {
                let n = write(fd, base + written, total - written)
                if n <= 0 { return false }
                written += n
            }
            return true
        }
    }

    public func readLine() -> String? {
        while true {
            if let newlineIndex = buffer.firstIndex(of: 0x0A) {
                let lineData = buffer.subdata(in: buffer.startIndex..<newlineIndex)
                buffer.removeSubrange(buffer.startIndex...newlineIndex)
                return String(data: lineData, encoding: .utf8)
            }

            var chunk = [UInt8](repeating: 0, count: 512)
            let n = chunk.withUnsafeMutableBytes { read(fd, $0.baseAddress, 512) }
            if n <= 0 { return nil }
            buffer.append(contentsOf: chunk[0..<n])
        }
    }

    public func close() {
        Darwin.close(fd)
    }
}
