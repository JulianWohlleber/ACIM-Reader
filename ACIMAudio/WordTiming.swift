import Foundation

/// Where each word of a sentence falls inside the synthesised clip.
///
/// Apple's synthesiser hands you a word callback; a neural model does not.
/// sherpa-onnx returns only samples, so the word marker is derived: the clip's
/// exact duration is known, and it is shared out across the words by how long
/// each one takes to say — syllables, not letters — with an extra share for the
/// pause a comma or a full stop creates.
///
/// The sentence marker stays exact regardless, because one sentence is one clip.
struct WordTiming {
    let range: NSRange
    let start: TimeInterval
    let end: TimeInterval

    static func plan(for text: String, duration: TimeInterval) -> [WordTiming] {
        guard duration > 0 else { return [] }
        let ns = text as NSString
        var spans: [(NSRange, Double)] = []

        var index = 0
        while index < ns.length {
            // skip anything that is not a word character
            while index < ns.length, !isWordCharacter(ns.character(at: index)) { index += 1 }
            guard index < ns.length else { break }
            let start = index
            while index < ns.length, isWordCharacter(ns.character(at: index)) { index += 1 }
            let range = NSRange(location: start, length: index - start)

            var weight = Double(syllables(in: ns.substring(with: range)))
            // the pause after punctuation belongs to the word before it
            var look = index
            while look < ns.length, ns.character(at: look) == 32 { look += 1 }
            if look < ns.length {
                switch ns.character(at: look) {
                case 46, 33, 63, 58, 59:      // . ! ? : ;
                    weight += 1.6
                case 44:                       // ,
                    weight += 0.7
                default:
                    break
                }
            }
            spans.append((range, weight))
        }

        let total = spans.reduce(0) { $0 + $1.1 }
        guard total > 0 else { return [] }

        var cursor: TimeInterval = 0
        return spans.map { range, weight in
            let length = duration * (weight / total)
            let timing = WordTiming(range: range, start: cursor, end: cursor + length)
            cursor += length
            return timing
        }
    }

    /// The word being spoken at `time`, or nil before the first / after the last.
    static func word(at time: TimeInterval, in plan: [WordTiming]) -> NSRange? {
        guard let index = index(at: time, in: plan) else { return nil }
        return plan[index].range
    }

    /// The stretch to lay the marker over: the word being spoken and the one
    /// or two that follow it.
    ///
    /// A band over a single word flickers from one short word to the next and
    /// reads as a box blinking, not as a marker. Two words, three when they
    /// are short, make a swipe wide enough to look like one stroke being
    /// drawn along the line — and the word actually being spoken is always
    /// the first one under it, so the marker leads rather than lags.
    static func markerSpan(at time: TimeInterval, in plan: [WordTiming]) -> NSRange? {
        guard let start = index(at: time, in: plan) else { return nil }
        let from = plan[start].range.location

        var last = start
        while last + 1 < plan.count,
              last - start < 2,                                        // three words at most
              NSMaxRange(plan[last].range) - from < 14 {               // already wide enough?
            last += 1
        }
        return NSRange(location: from, length: NSMaxRange(plan[last].range) - from)
    }

    private static func index(at time: TimeInterval, in plan: [WordTiming]) -> Int? {
        guard !plan.isEmpty else { return nil }
        var low = 0, high = plan.count - 1
        while low <= high {
            let mid = (low + high) / 2
            if time < plan[mid].start { high = mid - 1 }
            else if time >= plan[mid].end { low = mid + 1 }
            else { return mid }
        }
        return time >= plan[plan.count - 1].end ? plan.count - 1 : max(0, min(low, plan.count - 1))
    }

    private static func isWordCharacter(_ unit: unichar) -> Bool {
        guard let scalar = Unicode.Scalar(unit) else { return false }
        return CharacterSet.alphanumerics.contains(scalar)
            || scalar == "'" || scalar == "\u{2019}" || scalar == "-"
    }

    /// Vowel groups, which track speaking time far better than letter count.
    private static func syllables(in word: String) -> Int {
        let vowels = Set("aeiouyAEIOUY")
        var count = 0
        var previousWasVowel = false
        for character in word {
            let isVowel = vowels.contains(character)
            if isVowel && !previousWasVowel { count += 1 }
            previousWasVowel = isVowel
        }
        if word.count > 2, word.lowercased().hasSuffix("e"), count > 1 { count -= 1 }
        return max(1, count)
    }
}
