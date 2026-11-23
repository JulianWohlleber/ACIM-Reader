import Foundation

/// The three voices the reader offers.
///
/// They come from Kokoro-82M v1.0 (Apache-2.0), which runs entirely on the
/// phone — no Apple system voice, no network, no account. The speaker ids are
/// read from the model's own `speaker2id` metadata, not guessed.
enum Voice: String, CaseIterable, Identifiable {
    case softWoman
    case elderMan
    case youngMan

    var id: String { rawValue }

    /// Kokoro speaker id.
    var speakerID: Int32 {
        switch self {
        case .softWoman: return 3    // af_heart
        case .elderMan:  return 16   // am_michael
        case .youngMan:  return 14   // am_fenrir
        }
    }

    /// The model's own name for the voice, shown as the technical subtitle.
    var modelName: String {
        switch self {
        case .softWoman: return "af_heart"
        case .elderMan:  return "am_michael"
        case .youngMan:  return "am_fenrir"
        }
    }

    var title: String {
        switch self {
        case .softWoman: return "Clara"
        case .elderMan:  return "Arthur"
        case .youngMan:  return "Ellis"
        }
    }

    var describedAs: String {
        switch self {
        case .softWoman: return "A woman, soft and even"
        case .elderMan:  return "An older man, strong but gentle"
        case .youngMan:  return "A young man, curious and quiet"
        }
    }

    /// A short line each voice can read so you can hear it before choosing.
    static let sample = "This is a course in miracles. Please take notes."

    /// Each voice reads at its own natural pace; nudge them towards one another
    /// so switching voice does not also change the speed of the book.
    var paceCorrection: Float {
        switch self {
        case .softWoman: return 1.00   // 198 wpm
        case .elderMan:  return 1.05   // 185 wpm
        case .youngMan:  return 0.95   // 204 wpm
        }
    }
}
