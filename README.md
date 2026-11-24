# ACIM Reader (iOS)

An iPhone app that reads **A Course in Miracles** aloud, page by page, and marks
the position being read: the sentence coming next leans in, the sentence being
read is full ink, and an orange marker rides the two or three words being
spoken.

## Interaction model

| Gesture | Audio | View |
|---|---|---|
| Swipe left / right | untouched — playback continues where it is | browse to the previous / next page |
| Tap a sentence | the audio position jumps there and continues | follows the tapped sentence |
| Play ▶ | resumes / starts | first snaps back to the page the audio is on |
| "Back to page N" | untouched | returns to the audio page |

While you browse away from the audio, the header turns orange and says where the
voice still is. The last position survives relaunch.

## Design

Dieter Rams, applied literally: a warm off-white housing (`#F4F3F0`), near-black
text, Helvetica Neue throughout, an 8pt grid, 0.5pt hairlines instead of cards
or shadows, and **exactly one** signal colour — the Braun orange that marks the
word being spoken and nothing else. Dark mode is the ET66 calculator: matte
near-black with the same orange. All tokens live in `ACIMAudio/Design.swift`;
nothing hardcodes a colour anywhere else.

## Content

The app **ships the work with it** — `ACIMAudio/Resources/acim.json`, about
2.5 MB — so it opens instantly and works offline.

The text is the **1975 first edition**, taken from the English Wikisource
transcription, which carries it as `{{PD-US-no-notice}}`: the work was
distributed without a copyright notice before publication, and the 1975
registration was held invalid in *Penguin Books USA v. New Christian Church of
Full Endeavor*, 288 F. Supp. 2d 544 (S.D.N.Y. 2003). The later Foundation for
Inner Peace 2nd and 3rd editions are still claimed and are **not** used.

`Tools/build_corpus.py` rebuilds the corpus from Wikisource: it pulls all 461
pages through the API, strips the wikitext, and emits chapters with plain-text
paragraphs. Current contents: 456 chapters (Text 32, Workbook 386, Manual 38),
5,857 paragraphs, ~2.47 M characters. Sentences are split on device with
`NLTokenizer`, so the sentence — the unit the audio speaks and the tap selects —
is segmented by Apple's tokenizer rather than by a regex.

You can still import any `.txt` edition through the Files app; the app will
rebuild the book from it.

## Building and installing

```
./Tools/build-install.sh
```

Builds for a connected iPhone, signs the bundle, and installs it. Xcode refuses
to use an Xcode-managed provisioning profile under manual signing, and automatic
signing needs an Apple ID configured in Xcode — so the script builds unsigned and
signs the bundle itself with the team's wildcard profile and the Apple
Development certificate from the keychain. It finds both on its own and fails
with a clear message if the phone is not attached and unlocked.

The Xcode project is generated:

```
xcodegen generate
```

Edit `project.yml`, never `ACIMAudio.xcodeproj`.

## Architecture

- `Models.swift` — sentences (global index = audio position), paragraphs, chapters.
- `CorpusBuilder.swift` — the shipped structured corpus → the flat model.
- `ACIMParser.swift` — sentence segmentation, plus a fallback parser for imported `.txt`.
- `BookLibrary.swift` — prefers the bundled corpus, caches the parsed model.
- `AudioReader.swift` — `AVSpeechSynthesizer` speaking **one utterance per sentence**: seek, pause/resume, word-range callbacks, voice ranking (Premium → Enhanced → Default), position persistence.
- `ReaderViewModel.swift` — keeps the *audio* position and the *view* position apart and owns the follow/browse state machine.
- `PageView.swift` — a paragraph is one wrapped `UITextView`; a per-glyph attribute carries the sentence id, so running text wraps like a book and still resolves a tap to exactly one sentence.
- `CarouselPager.swift` — one paging scroll view over a lazy row of all pages.
- `ReaderScreen.swift`, `TOCView.swift`, `SettingsView.swift`, `RootView.swift` — the panels.

Because the sentence index *is* the audio position, tapping, resuming and
follow-the-audio cannot drift out of sync.
