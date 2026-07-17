import Foundation

/// Simple lock-protected box for values shared between the audio render
/// threads and the main thread (gain setting, meter reading, etc.).
final class AtomicValue<T> {
    private var value: T
    private let lock = NSLock()

    init(_ value: T) {
        self.value = value
    }

    var current: T {
        get { lock.lock(); defer { lock.unlock() }; return value }
        set { lock.lock(); defer { lock.unlock() }; value = newValue }
    }
}
