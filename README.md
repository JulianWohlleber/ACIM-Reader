# ACIM Reader (iOS)

An iPhone/iPad app that reads **A Course in Miracles** (Urtext edition) aloud
with a high-quality system voice, page-by-page, with live karaoke highlighting
of the sentence — and the exact word — being spoken.

## Interaction model

| Gesture | Effect on audio | Effect on view |
|---|---|---|
| Swipe left / right | none — playback continues where it is | browse to the previous / next page |
| Tap a sentence | audio position jumps there and continues | follows the tapped sentence |
| Play (▶︎) | resumes / starts playback | first snaps back to the page the audio is on |
| Browsing pill (“Back to audio”) | none | jumps back to the audio page |

- The current sentence is highlighted with a soft accent background; the word
  currently being spoken is tinted.
- Last position is remembered across launches.
- Speed and voice are configurable; the app prefers Premium / Enhanced
  English Siri voices automatically.

## Content / copyright

The app bundles **no text**. On first launch it downloads the freely
available *Urtext* plain text (~4 MB, OCR) from the Internet Archive
(item `ACourseInMircalesUrtextEdition` — see
https://archive.org/details/ACourseInMircalesUrtextEdition), caches it in
Application Support and parses it into chapters / sentences (NaturalLanguage
sentence tokenizer). You can also import any `.txt` version via the Files app
(e.g. a cleaner scan) — the app will rebuild the book from it.

Note: the widely sold *Foundation for Inner Peace* edition is copyrighted and
is *not* used or downloaded.

## Building

1. Open `ACIMAudio.xcodeproj` in Xcode 16 or later.
2. Select your team in *Signing & Capabilities* (the bundle id is
   `com.julianwohlleber.acimreader`).
3. Run on a device or the simulator (iOS 17+).

## Architecture

- `Models.swift` — book model: sentences (global index = audio position),
  paragraphs, chapters; pages derived on demand.
- `ACIMParser.swift` — defensive OCR-text parser (chapter/lesson detection,
  NLTokenizer sentence splitting, single-chapter fallback).
- `BookLibrary.swift` — download, cache, JSON persistence of the parsed book.
- `AudioReader.swift` — `AVSpeechSynthesizer` engine speaking **per
  sentence**: pause/resume, seek-to-sentence, word-range callbacks, voice
  ranking (Premium → Enhanced → Default, en-US/en-GB first), position
  persistence.
- `ReaderViewModel.swift` — separates *audio position* from *view position*
  and owns the follow/browse state machine.
- `ReaderScreen.swift`, `CarouselPager.swift`, `PageView.swift`,
  `FlowLayout.swift` — UI: three-slot swipeable page carousel, paragraph flow
  with tappable sentence chips.
- `SettingsView.swift`, `TOCView.swift` — voice/speed settings and contents.

The per-sentence playback design keeps everything exact: the sentence index
*is* the audio position, so tapping, resuming and follow-the-audio never drift
out of sync.
