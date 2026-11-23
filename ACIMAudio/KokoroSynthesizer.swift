import Foundation
import SherpaOnnxC

/// Wraps the sherpa-onnx offline TTS C API around Kokoro-82M.
///
/// Loading the model costs real time and ~114 MB of int8 weights, so the handle
/// is created once, off the main actor, and every synthesis call runs here.
/// Callers stay on the main actor and `await`.
actor KokoroSynthesizer {

    enum Failure: LocalizedError {
        case missingModel(String)
        case handleUnavailable
        case emptyResult

        var errorDescription: String? {
            switch self {
            case .missingModel(let name):
                return "The voice model is missing from the app bundle (\(name)). Run Tools/fetch-voices.sh and rebuild."
            case .handleUnavailable:
                return "The voice engine could not be created."
            case .emptyResult:
                return "The voice engine returned no audio."
            }
        }
    }

    struct Clip {
        let samples: [Float]
        let sampleRate: Double
        var duration: TimeInterval { sampleRate > 0 ? Double(samples.count) / sampleRate : 0 }
    }

    private var handle: OpaquePointer?
    private var ownedStrings: [UnsafeMutablePointer<CChar>] = []

    /// Files fetched by `Tools/fetch-voices.sh` and bundled as resources.
    private static let required = ["model.int8.onnx", "voices.bin", "tokens.txt", "lexicon-us-en.txt"]

    static func missingResources() -> [String] {
        required.filter { name in
            let parts = name.split(separator: ".", maxSplits: 1).map(String.init)
            return Bundle.main.url(forResource: parts[0], withExtension: parts.count > 1 ? parts[1] : nil) == nil
        }
    }

    private func path(_ name: String) throws -> String {
        let parts = name.split(separator: ".", maxSplits: 1).map(String.init)
        guard let url = Bundle.main.url(forResource: parts[0],
                                        withExtension: parts.count > 1 ? parts[1] : nil) else {
            throw Failure.missingModel(name)
        }
        return url.path
    }

    private func cString(_ value: String) -> UnsafeMutablePointer<CChar> {
        let copy = strdup(value)!
        ownedStrings.append(copy)
        return copy
    }

    /// Build the engine. Safe to call repeatedly; only the first call works.
    func prepare() throws {
        guard handle == nil else { return }

        var config = SherpaOnnxOfflineTtsConfig()
        config.model.kokoro.model   = UnsafePointer(cString(try path("model.int8.onnx")))
        config.model.kokoro.voices  = UnsafePointer(cString(try path("voices.bin")))
        config.model.kokoro.tokens  = UnsafePointer(cString(try path("tokens.txt")))
        config.model.kokoro.lexicon = UnsafePointer(cString(try path("lexicon-us-en.txt")))
        config.model.kokoro.lang    = UnsafePointer(cString("en-us"))
        config.model.kokoro.length_scale = 1.0
        config.model.num_threads = 2
        config.model.debug = 0
        config.model.provider = UnsafePointer(cString("cpu"))
        config.max_num_sentences = 1
        config.silence_scale = 1.0

        guard let created = SherpaOnnxCreateOfflineTts(&config) else {
            throw Failure.handleUnavailable
        }
        handle = created
    }

    /// Synthesise one sentence. The reader always speaks a single sentence, so
    /// the sentence index stays exactly in step with the audio.
    func speak(_ text: String, voice: Voice, speed: Float) throws -> Clip {
        try prepare()
        guard let handle else { throw Failure.handleUnavailable }

        var generation = SherpaOnnxGenerationConfig()
        generation.sid = voice.speakerID
        generation.speed = max(0.5, min(2.0, speed * voice.paceCorrection))
        generation.silence_scale = 1.0

        let produced: UnsafePointer<SherpaOnnxGeneratedAudio>? = Self.speakable(text).withCString { raw in
            SherpaOnnxOfflineTtsGenerateWithConfig(handle, raw, &generation, nil, nil)
        }
        guard let produced else { throw Failure.emptyResult }
        defer { SherpaOnnxDestroyOfflineTtsGeneratedAudio(produced) }

        let count = Int(produced.pointee.n)
        guard count > 0, let source = produced.pointee.samples else { throw Failure.emptyResult }

        return Clip(samples: Array(UnsafeBufferPointer(start: source, count: count)),
                    sampleRate: Double(produced.pointee.sample_rate))
    }

    /// What the voice is given, which is not quite what the page shows.
    ///
    /// The phonemiser works from a lexicon: a word wearing quotation marks is
    /// not in it, so `"harder"` was being dropped mid-sentence. Stripping the
    /// marks puts the word back. Word count is left untouched, so the word
    /// marker still lines up with the text on screen.
    private static func speakable(_ text: String) -> String {
        var out = text
        for mark in ["\u{201C}", "\u{201D}", "\u{201E}", "\u{00AB}", "\u{00BB}", "\""] {
            out = out.replacingOccurrences(of: mark, with: "")
        }
        // Keep apostrophes: the lexicon needs them for contractions.
        out = out.replacingOccurrences(of: "\u{2018}", with: "'")
        out = out.replacingOccurrences(of: "\u{2019}", with: "'")
        // Dashes are not in the lexicon either; a comma keeps the pause.
        out = out.replacingOccurrences(of: "\u{2014}", with: ",")
        out = out.replacingOccurrences(of: "\u{2013}", with: ",")
        out = out.replacingOccurrences(of: "\n", with: " ")
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    deinit {
        if let handle { SherpaOnnxDestroyOfflineTts(handle) }
        ownedStrings.forEach { free($0) }
    }
}
