# Working on ACIM Reader

Traps that cost real time here, and the invariants that keep the app honest.
Each one is written as what you will see, what is actually wrong, and the rule
that follows. If you are about to "just widen a filter" or "just add a tap
handler", read the matching section first.

## Build and run

- **`project.yml` is the source of truth.** `ACIMAudio.xcodeproj` is generated.
  Never edit the project file; edit `project.yml` and run `xcodegen generate`.
  Adding a Swift file means running xcodegen, or the file is simply not in the
  build and you will chase a phantom "undefined symbol".
- **Build and install with `./Tools/build-install.sh`.** It builds unsigned and
  signs afterwards on purpose: Xcode refuses an Xcode-managed profile under
  manual signing, while automatic signing wants an Apple ID configured in
  Xcode.
- **The voice model is not in the repository** (~141 MB). `./Tools/fetch-voices.sh`
  pulls it into `ACIMAudio/Resources/Voices/`.
- **Short of disk space?** `.build/` and `ACIMAudio/Resources/Voices/` are the
  two safe things to delete; both are regenerated. Nothing else is.

## Signing: the failure that looks like a crash

**Symptom:** the app installs without complaint and dies the instant you tap
it. Console says:

    Library not loaded: @rpath/ACIM.debug.dylib
    Reason: missing code signature

**Cause:** Xcode 16 splits a Debug build into a thin launcher plus
`ACIM.debug.dylib`, and that dylib sits at the **bundle root**, not in
`Frameworks/`. A signing loop that only walks `Frameworks/` leaves it unsigned,
and dyld then refuses the whole app. `__preview.dylib` is there for the same
reason.

**Rule:** sign every piece of nested code wherever it sits, longest path first
so a container is signed after its contents. `build-install.sh` already does
this — do not narrow it back to a glob.

## Installing on the phone

- The iPhone is paired **over Wi-Fi**, not cable. It drops to `unavailable`
  when it sleeps.
- `devicectl` needs a **power assertion**, which iOS refuses while the screen
  is locked. `CurrentlyAssertableStates = ()` in the error means exactly that:
  unlock the phone. This is a security boundary, not a broken setup.
- **Do not rebuild inside a wait-for-device loop.** A build takes minutes and
  the phone falls asleep while it runs; the loop then catches a device that is
  gone again by the time it tries to install. Build once, then retry only
  `xcrun devicectl device install app` on a short interval.
- Remote launch fails on a locked phone too (`FBSOpenApplicationServiceErrorDomain
  error 1`, reason `Locked`). Installing is enough; the person taps the app.

## Seeing what the app does

A physical iPhone gives you **neither a screenshot nor a console**, so a visual
question about the reading view cannot be answered on it. Build for the
Simulator and look:

    xcodebuild -project ACIMAudio.xcodeproj -scheme ACIMAudio -configuration Debug \
      -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/dd-sim \
      CODE_SIGNING_ALLOWED=NO build

The voice model runs in the Simulator, so playback and the marker can be
watched there in full. For anything the screenshot cannot settle, an `NSLog`
and

    xcrun simctl spawn <udid> log show --last 20s \
      --predicate 'eventMessage CONTAINS "YOURTAG"' --style compact

turns a guess into a reading. The marker was chased for three rounds on
reasoning alone; one screenshot and one log line ended it. Do that first.

Note that a screenshot between two sentences shows **no marker**, because the
word range is cleared when a clip starts. One empty screenshot proves nothing.

## Audio: the invariants

**One sentence is one synthesised clip.** The sentence index *is* the audio
position. Tapping, resuming and follow-the-audio cannot drift as long as this
holds. Do not split a sentence across clips, and do not batch several
sentences into one, without replacing the position model entirely.

**Never start a synthesis for a sentence already being synthesised.** This was
the cause of the stutter at sentence boundaries: a look-ahead was running, the
cache was therefore still empty, and the sentence coming up was requested a
second time. The engine is a serial actor, so the duplicate queued behind the
original and then repeated all of its work — the wait doubled exactly where it
was already audible. `AudioReader.inFlight` exists for this; join the request
in flight instead of issuing a new one.

**Hand clips to the player before the one ahead of them ends.** Stopping the
node and starting it again at a sentence boundary leaves a hole you can hear,
even when the next clip is ready. `SpeechPlayer` keeps a queue and tracks
`consumedFrames` so the node's own sample clock still gives the position inside
the clip being heard.

**A tap must cancel look-ahead work outside its reach**, or the sentence asked
for queues behind text the reader has left. `KokoroSynthesizer.speak` checks
cancellation *on the actor*, which is what lets a pointless request drop out
before it takes the engine.

**Clips are keyed by sentence, voice and speed.** A clip made before a settings
change must never be replayed after it.

## What the model itself gets wrong

The bundled model is `kokoro-int8-multi-lang-v1_0`. Quantising to int8 is what
makes it 114 MB instead of ~330 MB, and it leaves measurable damage:

- **A steady tone at exactly `sampleRate / 5` (4800 Hz) and its second harmonic
  (9600 Hz)**, up to 33 dB above its surroundings — audible as a whine behind
  the voice, present in the pauses too.
- **A DC offset of 2–3 %**, which also caused clicks at clip edges.

`ClipCleanup` removes both with two notches and a DC blocker. The notch
frequencies are **derived from the sample rate**, not hard-coded, so they
follow the model.

**Three facts identify an artefact as the model rather than the speech:** the
frequency is an exact fraction of the sample rate, it is identical across
voices of different pitch, and it does not move with speed. Check all three
before filtering anything.

**Measure before you touch a filter.** You can run the very same model on the
Mac — `pip install sherpa-onnx` in a throwaway venv, point it at
`ACIMAudio/Resources/Voices/`, synthesise, and look at the spectrum. That is
how the whine was localised to the model instead of the playback path. Widening
a filter without a measurement trades the voice for a guess.

**Quotation marks must be stripped before synthesis.** The phonemiser works
from a lexicon, and a quoted word is not in it, so `"harder"` was being dropped
mid-sentence. `KokoroSynthesizer.speakable` handles this; keep apostrophes,
they are needed for contractions.

**Clips are padded with silence** — about 60 ms at the front and 60–100 ms at
the back. Spreading the words across the whole clip hands roughly 8 % of a
short sentence to silence and the marker runs that far ahead of the voice from
the first word on. `Clip` measures its own speech window and `WordTiming.plan`
lays the words across that, not across the duration.

**Words outside the lexicon are dropped from the audio, silently.** sherpa
>= 2.0 phonemises Kokoro from a lexicon alone — espeak-ng is no longer
consulted — so a word it does not know is not guessed at: it is simply not
said. The page and the voice then disagree, and every word position after the
gap shifts.

The shipped lexicon has 178,401 entries and still misses ordinary inflections:
it holds `exist` and `existing` but neither `exists` nor `existed`. Measured
against this corpus that was **2.19 % of all words** — 6310 occurrences of 723
distinct words, including `god's` (434x), `created` (320x) and `illusions`
(239x).

`Tools/build_lexicon_supplement.py` derives the missing pronunciations from
the base forms the lexicon does have, by the ordinary rules of English
inflection, and the lexicon's own entries fix each rule (`tests` = `test` + s,
`wishes` = `wish` + ᵻz, `needed` = `need` + ᵻd). 685 of 700 are covered; the
rest are compounds and URLs. sherpa takes **several lexicons, comma-separated**,
so the supplement is passed alongside the original rather than patched into it.

Two things to keep in mind if you touch that generator. It must **parse** the
corpus, not scan the file: a raw scan reads an escaped newline plus `but` as a
word "nbut". And every sound it invents must exist in `tokens.txt` — `ᵻ`
(U+1D7B) and `ᵬ` (U+1D6C) look identical on screen and only one of them is a
phoneme the model knows. The generator checks this and refuses to write a file
that would fail quietly.

**The word position is derived, not reported.** sherpa-onnx returns samples
only, so `WordTiming` shares the clip's exact duration out across the words by
syllable. Roughly 100–200 ms accurate. The *sentence* boundary is exact. An
exact word position is possible — the model exposes per-token durations — but
needs the tokenisation done directly rather than through sherpa.

## Reading view

- **Never change font metrics while reading.** Giving the spoken word a heavier
  cut makes it wider, which re-breaks the line and makes the paragraph twitch
  word by word as the marker travels. Colour and background only.
- **The marker is a band over 2–3 words**, not a recoloured word. One word
  flickers between short words and reads as a blinking box; a band reads as one
  stroke travelling along the line. The word being spoken is always the first
  one under it, so the marker leads rather than lags.
- **The marker is a wash, not a block.** The accent at a quarter strength, with
  the words keeping their own ink. Solid accent forces the text to be knocked
  out white, and the page then reads as if something were selected rather than
  being read aloud.
- **Keep the lead-in tone clearly apart from both neighbours.** At `#5C5952` it
  was so close to ink that the sentence coming next looked like the one being
  read, which defeats the point of having it.
- **Pages are measured, not guessed.** `ChapterPaginator` lays text into
  page-sized containers against the real viewport. Colour is applied in
  `PageView`, never during pagination, because the reading position changes
  many times a second while page breaks do not.
- **Anything that affects what is drawn belongs in the render key** in
  `PageTextView.updateUIView` — sentence, word range, font size, theme. A page
  holding only the *next* sentence must repaint too, or the lead-in tone never
  appears when it falls across a page break.

## A nested ObservableObject publishes to nobody

`ReaderViewModel` owns an `AudioReader`. SwiftUI does **not** see through that:
a view observing the view model learns nothing when the reader changes. The
view model therefore republishes the signals it cares about by hand —
`isPlaying`, `isPaused`, `isPreparing`, `currentSentenceID`.

`currentWordRange` was deliberately left out, and a comment said the page view
"observes `audio` directly for it". It did not. It read the word range through
the view model without observing anything, so the marker reached the screen
only when some *other* republished value happened to change: on a sentence
change, where the word range had just been cleared to nil, and on pause, where
it still held its last value. Hence a marker that appeared, correctly placed,
the moment you pressed pause and was missing while the voice ran.

`MarkedPage` now holds `@ObservedObject var audio` and is the only thing
redrawn when the marker moves. **If you add a signal from the reader to the
view, say where it is observed, and check that something actually observes
it.** A comment claiming an observation is not an observation.

## Controls

**A plain `Button` around a bare `Text` owns only its glyphs.** A tap a few
points above, below or past the last letter falls through and nothing happens —
this is why the chapter browser "did not always open". Give a control
`.contentShape(Rectangle())` and padding, and say what it is: a label, and a
mark if it opens something.
