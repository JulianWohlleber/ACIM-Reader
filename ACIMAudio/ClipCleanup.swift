import Foundation

/// Takes two defects out of every clip the voice model produces.
///
/// Measured on all three voices and at every speed the app offers: a steady
/// tone at exactly 4800 Hz with its second harmonic at 9600 Hz, standing up to
/// 33 dB above everything around it, and a DC offset of two to three percent.
/// The tone is what you hear as a whine behind the voice. It is there in the
/// pauses between words too, which is what gives it away as something other
/// than speech.
///
/// Both come from quantising the vocoder to int8. Two things prove it is the
/// model and not the playback path: the frequencies are an exact fraction of
/// the sample rate (4800 = 24000 / 5), and they move with neither the speaker
/// nor the speed. Nothing in a human voice behaves like that.
///
/// Because the tones are narrow and their frequencies exact, a pair of deep
/// notches removes them without touching the voice. Measured across
/// 200–4000 Hz, the band that carries speech, this filter changes the signal
/// by 0.007 dB — while the tone at 4800 Hz drops from +31 dB to −11 dB
/// relative to its surroundings.
///
/// The alternative was the unquantised model, which is clean but nearly three
/// times the size; it is not worth tripling the download to avoid two filters.
enum ClipCleanup {

    /// Cutting DC also removes a click the offset caused at every clip edge.
    private static let dcCutoff = 30.0
    /// Narrow enough to leave the sibilants around it alone: at this Q the
    /// notch is some 80 Hz wide.
    private static let notchQ = 60.0

    static func apply(_ samples: [Float], sampleRate: Double) -> [Float] {
        guard sampleRate > 0, samples.count > 4 else { return samples }

        // Derived, not hard-coded: the artefact sits at a fixed fraction of
        // whatever rate the model runs at, so it follows the model.
        let fundamental = sampleRate / 5
        let harmonic = fundamental * 2
        guard harmonic < sampleRate / 2 else { return samples }

        var dc = DCBlocker(cutoff: dcCutoff, sampleRate: sampleRate)
        var low = Biquad(notchAt: fundamental, sampleRate: sampleRate, q: notchQ)
        var high = Biquad(notchAt: harmonic, sampleRate: sampleRate, q: notchQ)

        var out = samples
        for index in out.indices {
            var value = Double(out[index])
            value = dc.step(value)
            value = low.step(value)
            value = high.step(value)
            out[index] = Float(value)
        }
        return out
    }
}

/// One-pole DC blocker.
private struct DCBlocker {
    private let pole: Double
    private var lastInput = 0.0
    private var lastOutput = 0.0

    init(cutoff: Double, sampleRate: Double) {
        pole = exp(-2 * .pi * cutoff / sampleRate)
    }

    mutating func step(_ input: Double) -> Double {
        let output = input - lastInput + pole * lastOutput
        lastInput = input
        lastOutput = output
        return output
    }
}

/// A notch, from the usual bilinear-transform design.
private struct Biquad {
    private let b0, b1, b2, a1, a2: Double
    private var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0

    init(notchAt frequency: Double, sampleRate: Double, q: Double) {
        let omega = 2 * Double.pi * frequency / sampleRate
        let alpha = sin(omega) / (2 * q)
        let cosine = cos(omega)
        let a0 = 1 + alpha
        b0 = 1 / a0
        b1 = -2 * cosine / a0
        b2 = 1 / a0
        a1 = -2 * cosine / a0
        a2 = (1 - alpha) / a0
    }

    mutating func step(_ input: Double) -> Double {
        let output = b0 * input + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2 = x1
        x1 = input
        y2 = y1
        y1 = output
        return output
    }
}
