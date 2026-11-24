import Foundation
import AVFoundation

/// Plays synthesised clips one after another without a hole between them.
///
/// The old player held a single clip: to speak the next sentence it stopped the
/// node, waited for the clip, and started again. That stop-and-start was
/// audible at every sentence boundary, even when the next clip was ready.
///
/// Here the next sentence is handed to the node *while the one before it is
/// still sounding*, so the engine is never asked to stop at a boundary. The
/// node's own sample clock stays the single source of truth for the reading
/// position: every clip that finishes adds its length to `consumedFrames`, and
/// the difference between the clock and that total is the position inside the
/// clip you are hearing.
@MainActor
final class SpeechPlayer {

    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private var connectedFormat: AVAudioFormat?

    private struct Scheduled {
        let sentenceID: Int
        let frames: AVAudioFrameCount
    }

    /// Clips handed to the node and not finished yet; the first one is sounding.
    private var queue: [Scheduled] = []
    /// Length of everything already played, on the node's own timeline.
    private var consumedFrames: AVAudioFramePosition = 0
    /// Bumped by every reset, so a completion callback that arrives late cannot
    /// be mistaken for one belonging to the current run.
    private var generation = 0

    /// The clip that was sounding ended and the next queued one took over.
    var onClipStarted: ((Int) -> Void)?
    /// Everything scheduled has been played and nothing follows.
    var onDrained: (() -> Void)?

    init() {
        engine.attach(node)
    }

    // MARK: - Scheduling

    var queuedCount: Int { queue.count }
    var isPlaying: Bool { node.isPlaying }

    /// Hand one sentence to the node. Safe to call while another is sounding.
    func enqueue(samples: [Float], sampleRate: Double, sentenceID: Int) throws {
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

        let token = generation
        let isFirst = queue.isEmpty
        queue.append(Scheduled(sentenceID: sentenceID, frames: buffer.frameLength))

        node.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in self?.clipFinished(token: token) }
        }
        node.play()

        // Announced on a later turn of the loop: the caller is still inside
        // this method, and the handler asks the player for its state.
        if isFirst {
            Task { @MainActor [weak self] in
                guard let self, token == self.generation else { return }
                self.onClipStarted?(sentenceID)
            }
        }
    }

    private func clipFinished(token: Int) {
        guard token == generation, !queue.isEmpty else { return }
        consumedFrames += AVAudioFramePosition(queue.removeFirst().frames)
        if let next = queue.first {
            onClipStarted?(next.sentenceID)
        } else {
            onDrained?()
        }
    }

    /// Throw everything scheduled away and put the clock back to zero.
    func reset() {
        generation += 1
        queue.removeAll()
        consumedFrames = 0
        node.stop()
    }

    func pause() {
        node.pause()
    }

    func resume() {
        if !engine.isRunning { try? engine.start() }
        node.play()
    }

    /// Seconds into the clip you are hearing.
    var elapsed: TimeInterval {
        guard let nodeTime = node.lastRenderTime,
              let playerTime = node.playerTime(forNodeTime: nodeTime),
              playerTime.sampleRate > 0 else { return 0 }
        return max(0, Double(playerTime.sampleTime - consumedFrames) / playerTime.sampleRate)
    }

    // MARK: - Engine

    private func connect(sampleRate: Double) throws {
        if let connectedFormat, connectedFormat.sampleRate == sampleRate, engine.isRunning { return }
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else { return }
        if connectedFormat != nil { engine.disconnectNodeOutput(node) }
        engine.connect(node, to: engine.mainMixerNode, format: format)
        connectedFormat = format
        if !engine.isRunning { try engine.start() }
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
}
