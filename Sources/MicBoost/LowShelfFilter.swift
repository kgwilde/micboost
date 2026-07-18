import Foundation

/// A biquad low-shelf filter: boosts (or cuts) frequencies below a corner
/// point while leaving everything above it alone. Used to add back warmth
/// to a mic signal that sounds thin after gain boost, since gain alone is
/// frequency-neutral and can't do that.
final class LowShelfFilter {
    private var b0: Float = 1, b1: Float = 0, b2: Float = 0
    private var a1: Float = 0, a2: Float = 0
    private var x1: Float = 0, x2: Float = 0
    private var y1: Float = 0, y2: Float = 0

    private var configuredSampleRate: Double = 0
    private var configuredGainDB: Float = .nan

    func reset() {
        x1 = 0; x2 = 0; y1 = 0; y2 = 0
    }

    // Coefficient formulas from the RBJ Audio EQ Cookbook's low-shelf design.
    // Only recomputed when sample rate or gain actually change, since sin/cos/pow
    // are too costly to redo every sample.
    func updateIfNeeded(sampleRate: Double, gainDB: Float, frequency: Float = 200, shelfSlope: Float = 1.0) {
        guard sampleRate != configuredSampleRate || gainDB != configuredGainDB else { return }
        configuredSampleRate = sampleRate
        configuredGainDB = gainDB

        let a = powf(10, gainDB / 40)
        let w0 = 2 * Float.pi * frequency / Float(sampleRate)
        let cosw0 = cosf(w0)
        let sinw0 = sinf(w0)
        let alpha = sinw0 / 2 * sqrtf((a + 1 / a) * (1 / shelfSlope - 1) + 2)
        let twoSqrtAAlpha = 2 * sqrtf(a) * alpha

        let b0v = a * ((a + 1) - (a - 1) * cosw0 + twoSqrtAAlpha)
        let b1v = 2 * a * ((a - 1) - (a + 1) * cosw0)
        let b2v = a * ((a + 1) - (a - 1) * cosw0 - twoSqrtAAlpha)
        let a0v = (a + 1) + (a - 1) * cosw0 + twoSqrtAAlpha
        let a1v = -2 * ((a - 1) + (a + 1) * cosw0)
        let a2v = (a + 1) + (a - 1) * cosw0 - twoSqrtAAlpha

        b0 = b0v / a0v
        b1 = b1v / a0v
        b2 = b2v / a0v
        a1 = a1v / a0v
        a2 = a2v / a0v
    }

    func process(_ input: Float) -> Float {
        let output = b0 * input + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2 = x1
        x1 = input
        y2 = y1
        y1 = output
        return output
    }
}
