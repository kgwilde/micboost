import AVFoundation
import CoreAudio

/// Captures the selected microphone, applies gain and a soft limiter, and
/// streams the result to BlackHole so other apps can pick it up as an input.
///
/// This needs two separate AVAudioEngine instances rather than one. On macOS
/// an AVAudioEngine's inputNode and outputNode share a single underlying
/// audio unit, so pointing the input at the mic and the output at BlackHole
/// on the same engine just overwrites one device with the other. Two engines
/// means two independent audio units, one per device.
final class MicBoostEngine {
    private var inputEngine: AVAudioEngine?
    private var outputEngine: AVAudioEngine?

    private let ring = RingBuffer(capacity: 48_000 * 2) // ~2s at 48kHz
    let gain = AtomicValue<Float>(1.0)
    let peakLevel = AtomicValue<Float>(0)

    private(set) var isRunning = false
    var onStatusChange: ((String) -> Void)?

    func availableInputDevices() -> [(id: AudioDeviceID, name: String)] {
        AudioDevice.allIDs()
            .filter { AudioDevice.inputChannelCount(of: $0) > 0 && !AudioDevice.name(of: $0).contains("BlackHole") }
            .map { ($0, AudioDevice.name(of: $0)) }
    }

    private func findBlackhole() -> AudioDeviceID? {
        AudioDevice.allIDs().first { AudioDevice.name(of: $0).contains("BlackHole") }
    }

    func start(micID: AudioDeviceID) {
        guard !isRunning else { return }

        guard let blackholeID = findBlackhole() else {
            onStatusChange?("BlackHole not found. Install it with \"brew install blackhole-2ch\", restart coreaudiod, then try again.")
            return
        }

        // A sample rate mismatch between the two devices is a common cause
        // of silence or glitching, so line them up before starting.
        if let micRate = AudioDevice.nominalSampleRate(of: micID),
           let blackholeRate = AudioDevice.nominalSampleRate(of: blackholeID),
           micRate != blackholeRate {
            AudioDevice.setNominalSampleRate(micRate, for: blackholeID)
        }

        guard let inputFormat = configureInput(micID: micID) else { return }
        configureOutput(blackholeID: blackholeID, format: inputFormat)

        do {
            inputEngine?.prepare()
            try inputEngine?.start()
            outputEngine?.prepare()
            try outputEngine?.start()
            isRunning = true
            onStatusChange?("Running — \(AudioDevice.name(of: micID)) → BlackHole 2ch")
        } catch {
            onStatusChange?("Failed to start: \(error.localizedDescription)")
        }
    }

    func stop() {
        guard isRunning else { return }
        inputEngine?.inputNode.removeTap(onBus: 0)
        inputEngine?.stop()
        outputEngine?.stop()
        inputEngine = nil
        outputEngine = nil
        isRunning = false
        peakLevel.current = 0
        onStatusChange?("Stopped")
    }

    // MARK: - Setup

    private func configureInput(micID: AudioDeviceID) -> AVAudioFormat? {
        let engine = AVAudioEngine()

        guard let audioUnit = engine.inputNode.audioUnit,
              AudioDevice.setCurrentDevice(micID, on: audioUnit) else {
            onStatusChange?("Could not set input device \(AudioDevice.name(of: micID)).")
            return nil
        }

        let format = engine.inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            onStatusChange?("Selected microphone reported no format. Try a different input.")
            return nil
        }

        engine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: format, block: processInputBuffer)
        inputEngine = engine
        return format
    }

    private func configureOutput(blackholeID: AudioDeviceID, format inputFormat: AVAudioFormat) {
        let engine = AVAudioEngine()

        guard let audioUnit = engine.outputNode.audioUnit,
              AudioDevice.setCurrentDevice(blackholeID, on: audioUnit) else {
            onStatusChange?("Could not set output device to BlackHole.")
            return
        }

        let outputFormat = AVAudioFormat(standardFormatWithSampleRate: inputFormat.sampleRate, channels: 2)!
        let ring = self.ring
        let source = AVAudioSourceNode(format: outputFormat) { _, _, frameCount, bufferList in
            ring.read(into: bufferList, frameCount: Int(frameCount))
            return noErr
        }

        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: outputFormat)
        outputEngine = engine
    }

    // MARK: - Render thread

    private func processInputBuffer(_ buffer: AVAudioPCMBuffer, _ time: AVAudioTime) {
        guard let channelData = buffer.floatChannelData else { return }
        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frameLength > 0 else { return }

        var mono = [Float](repeating: 0, count: frameLength)
        for channel in 0..<channelCount {
            let samples = channelData[channel]
            for i in 0..<frameLength {
                mono[i] += samples[i] / Float(channelCount)
            }
        }

        let currentGain = gain.current
        var peak: Float = 0
        for i in 0..<frameLength {
            // tanh acts as a soft limiter: it boosts quiet signal roughly
            // linearly, then rounds off the peaks instead of hard clipping
            // once gain pushes the signal towards full scale.
            mono[i] = tanhf(mono[i] * currentGain)
            peak = max(peak, abs(mono[i]))
        }

        // Fast attack, slow decay so the meter reads peaks without flickering to zero.
        peakLevel.current = max(peak, peakLevel.current - 0.05)

        mono.withUnsafeBufferPointer { pointer in
            if let base = pointer.baseAddress {
                ring.write(base, count: frameLength)
            }
        }
    }
}

private extension RingBuffer {
    func read(into bufferList: UnsafeMutablePointer<AudioBufferList>, frameCount: Int) {
        var temp = [Float](repeating: 0, count: frameCount)
        temp.withUnsafeMutableBufferPointer { pointer in
            if let base = pointer.baseAddress {
                read(base, count: frameCount)
            }
        }

        for buffer in UnsafeMutableAudioBufferListPointer(bufferList) {
            guard let raw = buffer.mData else { continue }
            let out = raw.assumingMemoryBound(to: Float.self)
            for i in 0..<frameCount {
                out[i] = temp[i]
            }
        }
    }
}
