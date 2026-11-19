import SwiftUI

/// Voice selection, speed, and book source management.
struct SettingsView: View {
    @ObservedObject var audio: AudioReader
    @Environment(\.dismiss) private var dismiss

    @State private var voices: [AudioReader.VoiceInfo] = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Label("Reading speed", systemImage: "speedometer")
                        Spacer()
                        Text("\(String(format: "%.2fx", normalizedRate))")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: Binding(
                        get: { Double(audio.rate) },
                        set: { newValue in audio.rate = newValue }),
                           in: 0.4...0.65, step: 0.01)
                    Text("Tap a sentence in the book to hear a preview of the voice.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Playback")
                }

                Section("Voice") {
                    if voices.isEmpty {
                        Text("No English voices installed. Install a Siri voice in Settings → Accessibility → Spoken Content → Voices.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(voices) { voice in
                        Button {
                            audio.voiceIdentifier = voice.id
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(voice.name)
                                        .foregroundStyle(.primary)
                                    Text("\(voice.language) · \(voice.qualityName) quality")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if audio.voiceIdentifier == voice.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                voices = AudioReader.englishVoices
            }
            .onReceive(audio.$voiceIdentifier) { _ in
                voices = AudioReader.englishVoices
            }
        }
    }

    /// AVSpeechUtterance rate 0.5 == "1.0x" normal speech.
    private var normalizedRate: Double {
        Double(audio.rate) / 0.5
    }
}
