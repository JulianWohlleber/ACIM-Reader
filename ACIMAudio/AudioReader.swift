import Foundation
import AVFoundation

/// The audio engine: speaks the book sentence by sentence with the best
/// available system voice, publishes the current sentence + word range for the
/// karaoke highlighting, and supports seeking, pausing and voice selection.
///
/// Sentence-granular playback has two big benefits: the current sentence is
/// always exactly known (no fragile time offsets) and `willSpeakRange...`
/// gives word-level highlighting for free.
@MainActor
final class AudioReader: NSObject, ObservableObject {

    // MARK: Published state

    /// The voice is speaking (not necessarily on the *same sentence* as the view).
    @Published private(set) var isPlaying = false
    /// Playback was started but is currently paused.
    @Published private(set) var isPaused = false
    /// Global sentence id of the audio position.
    @Published private(set) var currentSentenceID = 0
    /// Character range within the current sentence being spoken (word karaoke).
    @Published private(set) var currentWordRange: NSRange?
    /// Utterance rate (0.4 ... 0.65 feels natural for book narration).
    @Published var rate: Double {
        didSet { UserDefaults.standard.set(rate, forKey: Keys.rate) }
    }
    /// Identifier of the selected voice (`AVSpeechSynthesisVoice(identifier:)`).
    @Published var voiceIdentifier: String? {
        didSet { UserDefaults.standard.set(voiceIdentifier, forKey: Keys.voice) }
    }

    private struct Keys {
        static let rate = "acim.audioRate"
        static let voice = "acim.audioVoice"
        static let position = "acim.lastPosition"
    }

    // MARK: Private

    private let synthesizer = AVSpeechSynthesizer()
    private var book: ACIMBook?
    /// True while we cancelled on purpose (seek/stop) — ignore stale callbacks.
    private var intentionalCancel = false

    // MARK: Init

    override init() {
        let storedRate = UserDefaults.standard.object(forKey: Keys.rate) as? Double
        rate = storedRate ?? 0.5
        voiceIdentifier = UserDefaults.standard.string(forKey: Keys.voice)
        storedPosition = UserDefaults.standard.integer(forKey: Keys.position)
        super.init()
        synthesizer.delegate = self
    }

    private var storedPosition: Int = 0

    // MARK: Configuration

    func attach(book: ACIMBook) {
        self.book = book
        // restore last position if valid
        if book.sentences.indices.contains(storedPosition) {
            currentSentenceID = storedPosition
        } else {
            currentSentenceID = 0
            storedPosition = currentSentenceID
        }
        // default to best voice if none chosen
        if voiceIdentifier == nil || AVSpeechSynthesisVoice(identifier: voiceIdentifier ?? "") == nil {
            voiceIdentifier = Self.bestVoice()?.identifier
        }
    }

    // MARK: Voices

    struct VoiceInfo: Identifiable {
        let id: String          // AVSpeechSynthesisVoice identifier
        let name: String
        let language: String
        let quality: Int        // AVSpeechSynthesisVoiceQuality raw value
        let qualityName: String
    }

    /// English voices, best quality first — premium Siri voices read books
    /// beautifully; enhanced voices are the second choice.
    static var englishVoices: [VoiceInfo] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
            .map { v in
                VoiceInfo(id: v.identifier,
                          name: v.name,
                          language: v.language,
                          quality: v.quality.rawValue,
                          qualityName: qualityName(v.quality))
            }
            .sorted { l, r in
                // premium first, then US/GB English, then alphabetically
                if l.quality != r.quality { return l.quality > r.quality }
                let lPreferred = l.language == "en-US" || l.language == "en-GB"
                let rPreferred = r.language == "en-US" || r.language == "en-GB"
                if lPreferred != rPreferred { return lPreferred }
                return l.name < r.name
            }
    }

        static func qualityName(_ quality: AVSpeechSynthesisVoiceQuality) -> String {
        switch quality {
        case .premium: return "Premium"
        case .enhanced: return "Enhanced"
        case .default: return "Default"
        default: return "Default"
        }
    }

    static func bestVoice() -> AVSpeechSynthesisVoice? {
        englishVoices.first.flatMap { AVSpeechSynthesisVoice(identifier: $0.id) }
    }

    var activeVoice: AVSpeechSynthesisVoice? {
        AVSpeechSynthesisVoice(identifier: voiceIdentifier ?? "") ?? Self.bestVoice()
    }

    // MARK: Transport

    var isBusy: Bool { isPlaying || isPaused }

    /// Start playback at the current position (or resume after pause).
    func play() {
        guard let book, book.sentenceCount > 0 else { return }
        prepareAudioSession()
        if isPaused, synthesizer.isPaused {
            synthesizer.continueSpeaking()
            isPaused = false
            isPlaying = true
            return
        }
        speakCurrentSentence()
    }

    func pause() {
        guard isPlaying else { return }
        synthesizer.pauseSpeaking(atBoundary: .immediate)
        isPaused = true
        isPlaying = false
    }

    func stop() {
        intentionalCancel = true
        synthesizer.stopSpeaking(atBoundary: .immediate)
        isPlaying = false
        isPaused = false
    }

    /// Standard play/pause toggle.
    func togglePlayPause() {
        if isPlaying { pause() } else { play() }
    }

    /// Jump the audio position to a sentence.
    /// If playback was running (or paused), it continues from the new spot.
    func seek(to sentenceID: Int) {
        let wasActive = isPlaying || isPaused
        if sentenceID != currentSentenceID {
            intentionalCancel = true
            synthesizer.stopSpeaking(atBoundary: .immediate)
            isPlaying = false
            isPaused = false
            currentSentenceID = min(max(0, sentenceID), max(0, (book?.sentenceCount ?? 1) - 1))
            currentWordRange = nil
            persistPosition()
        }
        if wasActive {
            play()
        }
    }

    /// Jump to the next / previous sentence without changing play state.
    func stepSentence(forward: Bool) {
        guard let book else { return }
        let target = currentSentenceID + (forward ? 1 : -1)
        if book.sentences.indices.contains(target) {
            seek(to: target)
        }
    }

    // MARK: Internals

    private func speakCurrentSentence() {
        guard let book, let sentence = book.sentence(withID: currentSentenceID) else {
            stop()
            return
        }
        let utterance = AVSpeechUtterance(string: sentence.text)
        utterance.voice = activeVoice
        utterance.rate = Float(rate)
        utterance.pitchMultiplier = 1.0
        utterance.postUtteranceDelay = 0.15
        intentionalCancel = false
        synthesizer.speak(utterance)
        isPlaying = true
        isPaused = false
        persistPosition()
    }

    private func advance() {
        guard let book else { return }
        let next = currentSentenceID + 1
        guard next < book.sentenceCount else {
            // End of book.
            stop()
            return
        }
        currentSentenceID = next
        currentWordRange = nil
        speakCurrentSentence()
    }

    private func persistPosition() {
        storedPosition = currentSentenceID
        UserDefaults.standard.set(currentSentenceID, forKey: Keys.position)
    }

    private func prepareAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers, .interruptPlayback])
            try session.setActive(true, options: [])
        } catch {
            // Non-fatal: speech still works in most conditions.
        }
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension AudioReader: AVSpeechSynthesizerDelegate {

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard self.isPlaying else { return }
            self.advance()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       willSpeakRangeOfSpeechString characterRange: NSRange,
                                       utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.currentWordRange = characterRange
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard !self.intentionalCancel, self.isPlaying else { return }
            // Unexpected cancel (e.g. route change): keep position, allow replay.
            self.isPlaying = false
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didPause utterance: AVSpeechUtterance) {
        Task { @MainActor in
            // state already handled by `pause()`
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didContinue utterance: AVSpeechUtterance) {
        Task { @MainActor in
            // state already handled by `play()`
        }
    }
}
