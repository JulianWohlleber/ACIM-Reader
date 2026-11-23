import Foundation
import AVFoundation
import Combine

/// Reads the book aloud with Kokoro-82M running on the phone.
///
/// One sentence is one synthesised clip, so the sentence index *is* the audio
/// position: tapping, resuming and follow-the-audio cannot drift. While a clip
/// plays, the next one is already being synthesised, so sentences run on
/// without a gap.
@MainActor
final class AudioReader: NSObject, ObservableObject {

    @Published private(set) var isPlaying = false
    @Published private(set) var isPaused = false
    /// True while a sentence is being synthesised and there is nothing to hear yet.
    @Published private(set) var isPreparing = false
    @Published private(set) var currentSentenceID = 0
    @Published private(set) var currentWordRange: NSRange?
    @Published private(set) var engineError: String?

    @Published var rate: Double {
        didSet { UserDefaults.standard.set(rate, forKey: Keys.rate) }
    }

    @Published var voice: Voice {
        didSet {
            UserDefaults.standard.set(voice.rawValue, forKey: Keys.voice)
            guard voice != oldValue else { return }
            clips.removeAll()
            if isBusy { restartCurrentSentence() }
        }
    }

    private enum Keys {
        static let rate = "acim.audioRate"
        static let voice = "acim.audioVoice"
        static let position = "acim.lastPosition"
    }

    private let synthesizer = KokoroSynthesizer()
    private let player = SpeechPlayer()
    private var book: ACIMBook?
    private var timings: [WordTiming] = []
    private var clips: [Int: KokoroSynthesizer.Clip] = [:]
    private var ticker: AnyCancellable?
    private var speakTask: Task<Void, Never>?
    private var prefetchTask: Task<Void, Never>?

    override init() {
        let storedRate = UserDefaults.standard.object(forKey: Keys.rate) as? Double
        rate = storedRate ?? 1.0
        voice = Voice(rawValue: UserDefaults.standard.string(forKey: Keys.voice) ?? "") ?? .softWoman
        super.init()

        currentSentenceID = UserDefaults.standard.integer(forKey: Keys.position)
        prepareAudioSession()
        player.onFinished = { [weak self] in self?.advance() }
    }

    func attach(book: ACIMBook) {
        self.book = book
        currentSentenceID = min(max(0, currentSentenceID), max(0, book.sentenceCount - 1))
        if let missing = Self.missingVoiceFiles, !missing.isEmpty {
            engineError = "Voice model missing: \(missing.joined(separator: ", ")). Run Tools/fetch-voices.sh and rebuild."
        }
    }

    static var missingVoiceFiles: [String]? { KokoroSynthesizer.missingResources() }

    var isBusy: Bool { isPlaying || isPaused }

    // MARK: - Transport

    func play() {
        guard book != nil else { return }
        if isPaused {
            player.resume()
            isPaused = false
            isPlaying = true
            startTicking()
            return
        }
        guard !isPlaying else { return }
        speak(currentSentenceID)
    }

    func pause() {
        guard isPlaying else { return }
        player.pause()
        ticker = nil
        isPaused = true
        isPlaying = false
    }

    func stop() {
        speakTask?.cancel()
        prefetchTask?.cancel()
        player.stop()
        ticker = nil
        isPlaying = false
        isPaused = false
        currentWordRange = nil
    }

    func togglePlayPause() {
        if isPlaying { pause() } else { play() }
    }

    /// Move the audio position. If it was playing or paused, it continues there.
    func seek(to sentenceID: Int) {
        guard let book else { return }
        let target = min(max(0, sentenceID), max(0, book.sentenceCount - 1))
        let wasActive = isBusy
        stop()
        currentSentenceID = target
        persistPosition()
        if wasActive { speak(target) }
    }

    func stepSentence(forward: Bool) {
        seek(to: currentSentenceID + (forward ? 1 : -1))
    }

    private func restartCurrentSentence() {
        let wasActive = isBusy
        let id = currentSentenceID
        stop()
        if wasActive { speak(id) }
    }

    // MARK: - Speaking

    private func speak(_ sentenceID: Int) {
        guard let book, let sentence = book.sentence(withID: sentenceID) else { return }
        speakTask?.cancel()
        currentSentenceID = sentenceID
        currentWordRange = nil
        persistPosition()

        speakTask = Task { [weak self] in
            guard let self else { return }
            self.isPreparing = self.clips[sentenceID] == nil
            // A cancelled task must not leave the spinner spinning for ever.
            defer { self.isPreparing = false }
            do {
                let clip = try await self.clip(for: sentenceID, text: sentence.text)
                guard !Task.isCancelled else { return }
                self.timings = WordTiming.plan(for: sentence.text, duration: clip.duration)
                try self.player.play(samples: clip.samples, sampleRate: clip.sampleRate)
                self.isPlaying = true
                self.isPaused = false
                self.engineError = nil
                self.startTicking()
                self.prefetch(sentenceID + 1)
            } catch {
                guard !Task.isCancelled else { return }
                self.isPlaying = false
                self.engineError = error.localizedDescription
            }
        }
    }

    private func clip(for sentenceID: Int, text: String) async throws -> KokoroSynthesizer.Clip {
        if let cached = clips[sentenceID] { return cached }
        let voice = self.voice
        let speed = Float(rate)
        let made = try await synthesizer.speak(text, voice: voice, speed: speed)
        clips[sentenceID] = made
        trimCache(around: sentenceID)
        return made
    }

    /// Synthesise the next sentence while this one is still being spoken.
    private func prefetch(_ sentenceID: Int) {
        guard let book, let sentence = book.sentence(withID: sentenceID),
              clips[sentenceID] == nil else { return }
        prefetchTask?.cancel()
        let voice = self.voice
        let speed = Float(rate)
        prefetchTask = Task { [weak self] in
            guard let self else { return }
            if let made = try? await self.synthesizer.speak(sentence.text, voice: voice, speed: speed) {
                guard !Task.isCancelled else { return }
                self.clips[sentenceID] = made
                self.trimCache(around: sentenceID)
            }
        }
    }

    /// Clips are large; keep only what is about to be heard.
    private func trimCache(around sentenceID: Int) {
        let keep = Set([sentenceID - 1, sentenceID, sentenceID + 1, currentSentenceID, currentSentenceID + 1])
        clips = clips.filter { keep.contains($0.key) }
    }

    private func advance() {
        guard let book else { return }
        let next = currentSentenceID + 1
        guard next < book.sentenceCount else {
            stop()
            return
        }
        speak(next)
    }

    // MARK: - The word marker

    private func startTicking() {
        ticker = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, self.isPlaying else { return }
                self.currentWordRange = WordTiming.word(at: self.player.elapsed, in: self.timings)
            }
    }

    // MARK: - Housekeeping

    private func persistPosition() {
        UserDefaults.standard.set(currentSentenceID, forKey: Keys.position)
    }

    private func prepareAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true, options: [])
        } catch {
            // Non-fatal: playback still works in most conditions.
        }
    }

    /// Speak a short line in a voice so it can be auditioned before choosing.
    func preview(_ voice: Voice) {
        Task { [weak self] in
            guard let self else { return }
            guard let clip = try? await self.synthesizer.speak(Voice.sample, voice: voice, speed: Float(self.rate))
            else { return }
            guard !self.isPlaying else { return }
            try? self.player.play(samples: clip.samples, sampleRate: clip.sampleRate)
        }
    }
}
