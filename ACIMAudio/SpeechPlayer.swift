import Foundation
import AVFoundation

/// Plays one synthesised clip at a time and reports how far into it we are.
@MainActor
final class SpeechPlayer {

    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private var connectedFormat: AVAudioFormat?
    private var generation = 0

    /// Called on the main actor when a clip finished on its own.
    var onFinished: (() -> Void)?

    init() {
        engine.attach(node)
    }

    private func connect(sampleRate: Double) throws {
        if let connectedFormat, connectedFormat.sampleRate == sampleRate, engine.isRunning { return }
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else { return }
        if connectedFormat != nil { engine.disconnectNodeOutput(node) }
        engine.connect(node, to: engine.mainMixerNode, format: format)
        connectedFormat = format
        if !engine.isRunning { try engine.start() }
    }

    func play(samples: [Float], sampleRate: Double) throws {
        stop()
        try connect(sampleRate: sampleRate)
        guard let format = connectedFormat,
              let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                            frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else { return }

        samples.withUnsafeBufferPointer { source in
            channel.update(from: source.baseAddress!, count: samples.count)
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        Self.fadeEdges(channel, count: samples.count, sampleRate: sampleRate)

        generation += 1
        let token = generation
        node.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in
                guard let self, token == self.generation else { return }  // superseded by a seek
                self.onFinished?()
            }
        }
        node.play()
    }

    /// A clip that starts or stops on a non-zero sample clicks. Ramping a few
    /// milliseconds at each end removes the click between sentences.
    private static func fadeEdges(_ channel: UnsafeMutablePointer<Float>,
                                  count: Int,
                                  sampleRate: Double) {
        let ramp = min(Int(sampleRate * 0.008), count / 2)   // 8 ms
        guard ramp > 1 else { return }
        for i in 0..<ramp {
            let gain = Float(i) / Float(ramp)
            channel[i] *= gain
            channel[count - 1 - i] *= gain
        }
    }

    /// Seconds played of the current clip.
    var elapsed: TimeInterval {
        guard let nodeTime = node.lastRenderTime,
              let playerTime = node.playerTime(forNodeTime: nodeTime),
              playerTime.sampleRate > 0 else { return 0 }
        return Double(playerTime.sampleTime) / playerTime.sampleRate
    }

    var isPlaying: Bool { node.isPlaying }

    func pause() {
        node.pause()
    }

    func resume() {
        if !engine.isRunning { try? engine.start() }
        node.play()
    }

    /// Discards whatever is scheduled; the pending completion is ignored.
    func stop() {
        generation += 1
        node.stop()
    }
}
