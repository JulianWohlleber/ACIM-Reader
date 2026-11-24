import Foundation
import AVFoundation
import Combine

/// Reads the book aloud with Kokoro-82M running on the phone.
///
/// One sentence is one synthesised clip, so the sentence index *is* the audio
/// position: tapping, resuming and follow-the-audio cannot drift.
///
/// Keeping that true without making you wait is the whole job of this class:
///
///  - Several sentences are synthesised **ahead** of the one you hear, not one,
///    so a short sentence followed by a long one cannot outrun the engine.
///  - A sentence already being synthesised is never started a second time.
///    Waiting on the request in flight instead of issuing a new one is what
///    removes the stall at a sentence boundary: the engine is serial, so a
///    duplicate request used to queue behind the original and then repeat all
///    of its work.
///  - Clips are handed to the player *before* the one ahead of them ends, so
///    there is no stop-and-start to hear.
///  - A tap cancels look-ahead work outside its reach, so the sentence you
///    asked for gets the engine instead of queueing behind text you left.
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
        didSet {
            UserDefaults.standard.set(rate, forKey: Keys.rate)
            guard rate != oldValue else { return }
            // Clips are keyed by speed, so nothing stale is reused. Work in
            // flight carries the old speed: drop it and synthesise again.
            cancelAllPending()
            pump()
        }
    }

    @Published var voice: Voice {
        didSet {
            UserDefaults.standard.set(voice.rawValue, forKey: Keys.voice)
            guard voice != oldValue else { return }
            cancelAllPending()
            if isBusy { start(at: currentSentenceID) }
        }
    }

    private enum Keys {
        static let rate = "acim.audioRate"
        static let voice = "acim.audioVoice"
        static let position = "acim.lastPosition"
    }

    /// How many sentences are kept synthesised beyond the ones already handed
    /// to the player. Three carries a run of short sentences; more would tie
    /// the engine up on text a tap is about to make irrelevant.
    private static let lookAhead = 3
    /// How many clips sit in the player at once. Two is all it takes to bridge
    /// a sentence boundary.
    private static let queueDepth = 2

    /// Voice and speed belong in the key: a clip made at the old setting must
    /// not be replayed after you change it.
    private struct ClipKey: Hashable {
        let sentenceID: Int
        let voice: Voice
        /// Hundredths, so float rounding cannot miss a cache hit.
        let speed: Int
    }

    private let synthesizer = KokoroSynthesizer()
    private let player = SpeechPlayer()
    private var book: ACIMBook?

    private var clips: [ClipKey: KokoroSynthesizer.Clip] = [:]
    private var inFlight: [ClipKey: Task<KokoroSynthesizer.Clip, Error>] = [:]
    private var timings: [Int: [WordTiming]] = [:]
    /// The next sentence to hand to the player.
    private var nextToEnqueue = 0
    private var ticker: AnyCancellable?

    override init() {
        let storedRate = UserDefaults.standard.object(forKey: Keys.rate) as? Double
        rate = storedRate ?? 1.0
        voice = Voice(rawValue: UserDefaults.standard.string(forKey: Keys.voice) ?? "") ?? .softWoman
        super.init()

        currentSentenceID = UserDefaults.standard.integer(forKey: Keys.position)
        prepareAudioSession()

        player.onClipStarted = { [weak self] id in self?.clipStarted(id) }
        player.onDrained = { [weak self] in self?.drained() }
    }

    func attach(book: ACIMBook) {
        self.book = book
        currentSentenceID = min(max(0, currentSentenceID), max(0, book.sentenceCount - 1))
        nextToEnqueue = currentSentenceID
        if let missing = Self.missingVoiceFiles, !missing.isEmpty {
            engineError = "Voice model missing: \(missing.joined(separator: ", ")). Run Tools/fetch-voices.sh and rebuild."
            return
        }
        // Build the engine and the first clip now, so the first tap on Play
        // does not have to wait for 114 MB of weights to load.
        synthesize(currentSentenceID)
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
        start(at: currentSentenceID)
    }

    func pause() {
        guard isPlaying else { return }
        player.pause()
        ticker = nil
        isPaused = true
        isPlaying = false
    }

    func stop() {
        cancelAllPending()
        player.reset()
        ticker = nil
        isPlaying = false
        isPaused = false
        isPreparing = false
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

        // Whatever was being prepared for the place you left is in the way now.
        cancelPending(outsideReachOf: target)

        if wasActive {
            start(at: target)
        } else {
            player.reset()
            currentSentenceID = target
            currentWordRange = nil
            nextToEnqueue = target
            isPlaying = false
            isPaused = false
            persistPosition()
            // Warm the sentence you tapped, so pressing Play is immediate.
            synthesize(target)
        }
    }

    func stepSentence(forward: Bool) {
        seek(to: currentSentenceID + (forward ? 1 : -1))
    }

    /// Begin speaking at `id`, from silence.
    private func start(at id: Int) {
        player.reset()
        nextToEnqueue = id
        currentSentenceID = id
        currentWordRange = nil
        persistPosition()
        isPaused = false
        isPlaying = true
        isPreparing = clips[key(for: id)] == nil
        startTicking()
        pump()
    }

    // MARK: - Keeping the player fed

    private func key(for sentenceID: Int) -> ClipKey {
        ClipKey(sentenceID: sentenceID, voice: voice, speed: Int((rate * 100).rounded()))
    }

    /// The one place playback moves forward.
    ///
    /// Called when playback starts, when a sentence ends, and whenever a
    /// synthesis finishes. Clips are only ever handed over in order.
    private func pump() {
        guard let book, isPlaying || isPreparing else { return }

        while player.queuedCount < Self.queueDepth, nextToEnqueue < book.sentenceCount {
            guard let clip = clips[key(for: nextToEnqueue)] else {
                synthesize(nextToEnqueue)       // not ready yet; pump() runs again when it is
                break
            }
            do {
                try player.enqueue(samples: clip.samples,
                                   sampleRate: clip.sampleRate,
                                   sentenceID: nextToEnqueue)
                nextToEnqueue += 1
            } catch {
                engineError = error.localizedDescription
                break
            }
        }

        // Keep the run after that warm.
        if nextToEnqueue < book.sentenceCount {
            for id in nextToEnqueue ..< min(nextToEnqueue + Self.lookAhead, book.sentenceCount) {
                synthesize(id)
            }
        }
        evictDistantClips()
    }

    /// Start synthesising one sentence, unless it is already made or already
    /// being made. The second half of that sentence is the important one.
    private func synthesize(_ sentenceID: Int) {
        guard let book, let sentence = book.sentence(withID: sentenceID) else { return }
        let clipKey = key(for: sentenceID)
        guard clips[clipKey] == nil, inFlight[clipKey] == nil else { return }

        let text = sentence.text
        let chosen = clipKey.voice
        let speed = Float(rate)
        let engine = synthesizer

        let work = Task { try await engine.speak(text, voice: chosen, speed: speed) }
        inFlight[clipKey] = work

        Task { [weak self] in
            let outcome = await work.result
            guard let self else { return }
            if self.inFlight[clipKey] == work { self.inFlight[clipKey] = nil }
            switch outcome {
            case .success(let clip):
                self.clips[clipKey] = clip
                self.timings[sentenceID] = WordTiming.plan(for: text, duration: clip.duration)
                self.pump()
            case .failure(let error):
                // A cancelled look-ahead is routine, not a fault to report.
                if !(error is CancellationError) {
                    self.engineError = error.localizedDescription
                    // Nothing will arrive for the sentence being waited on, so
                    // the transport must not sit there claiming to play.
                    if self.player.queuedCount == 0, sentenceID == self.nextToEnqueue {
                        self.stop()
                    }
                }
            }
        }
    }

    private func clipStarted(_ sentenceID: Int) {
        // The voice audition rides the same player under id -1; it must not
        // be mistaken for a reading position.
        guard sentenceID >= 0 else { return }
        isPreparing = false
        engineError = nil
        currentSentenceID = sentenceID
        currentWordRange = nil
        persistPosition()
        pump()
    }

    private func drained() {
        guard let book, isPlaying || isPreparing else { return }
        if nextToEnqueue >= book.sentenceCount {
            stop()                      // the book, or this run, is finished
            return
        }
        // Synthesis could not keep up. Put the clock back and carry on as soon
        // as the clip lands; the look-ahead makes this rare.
        isPreparing = true
        player.reset()
        pump()
    }

    // MARK: - Housekeeping of the buffer

    private func cancelAllPending() {
        for (_, task) in inFlight { task.cancel() }
        inFlight.removeAll()
    }

    private func cancelPending(outsideReachOf sentenceID: Int) {
        let reach = (sentenceID - 1) ... (sentenceID + Self.lookAhead + Self.queueDepth)
        for (key, task) in inFlight where !reach.contains(key.sentenceID) {
            task.cancel()
            inFlight[key] = nil
        }
    }

    /// Clips are large. Keep the ones around the reading position, at the
    /// current voice and speed, and drop the rest.
    private func evictDistantClips() {
        let here = key(for: currentSentenceID)
        let reach = (currentSentenceID - 1) ... (currentSentenceID + Self.lookAhead + Self.queueDepth)
        clips = clips.filter {
            reach.contains($0.key.sentenceID) && $0.key.voice == here.voice && $0.key.speed == here.speed
        }
        timings = timings.filter { reach.contains($0.key) }
    }

    // MARK: - The word marker

    private func startTicking() {
        ticker = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, self.isPlaying else { return }
                let plan = self.timings[self.currentSentenceID] ?? []
                let word = WordTiming.word(at: self.player.elapsed, in: plan)
                // Publishing only on a change keeps the page from being
                // re-laid-out thirty times a second for the same word.
                if word != self.currentWordRange { self.currentWordRange = word }
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
        guard !isBusy else { return }
        Task { [weak self] in
            guard let self else { return }
            guard let clip = try? await self.synthesizer.speak(Voice.sample,
                                                               voice: voice,
                                                               speed: Float(self.rate))
            else { return }
            guard !self.isBusy else { return }
            self.player.reset()
            try? self.player.enqueue(samples: clip.samples,
                                     sampleRate: clip.sampleRate,
                                     sentenceID: -1)
        }
    }
}
