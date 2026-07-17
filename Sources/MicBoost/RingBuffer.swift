import Foundation

/// Fixed-size circular buffer used to hand mono samples from the input
/// tap (mic thread) to the output source node (BlackHole thread).
final class RingBuffer {
    private var storage: [Float]
    private var writeIndex = 0
    private var readIndex = 0
    private var filled = 0
    private let capacity: Int
    private let lock = NSLock()

    init(capacity: Int) {
        self.capacity = capacity
        storage = [Float](repeating: 0, count: capacity)
    }

    func write(_ samples: UnsafePointer<Float>, count: Int) {
        lock.lock(); defer { lock.unlock() }
        for i in 0..<count {
            storage[writeIndex] = samples[i]
            writeIndex = (writeIndex + 1) % capacity
        }
        filled = min(filled + count, capacity)
    }

    func read(_ output: UnsafeMutablePointer<Float>, count: Int) {
        lock.lock(); defer { lock.unlock() }
        for i in 0..<count {
            guard filled > 0 else {
                output[i] = 0
                continue
            }
            output[i] = storage[readIndex]
            readIndex = (readIndex + 1) % capacity
            filled -= 1
        }
    }
}
