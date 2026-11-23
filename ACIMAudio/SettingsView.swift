import SwiftUI

/// Voice and speed. Three voices, nothing else to decide.
struct SettingsView: View {
    @ObservedObject var audio: AudioReader
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    private var theme: RamsTheme { RamsTheme.current(scheme) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Voice")
                    .font(.ramsMedium(17))
                    .foregroundStyle(theme.inkC)
                Spacer()
                Button { dismiss() } label: {
                    Text("Done").panelLabel(theme).frame(height: Grid.x(5))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Grid.margin)
            .frame(height: Grid.x(7))
            .hairline(theme)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Voice.allCases) { voice in
                        Button {
                            audio.voice = voice
                            audio.preview(voice)
                        } label: {
                            voiceRow(voice)
                        }
                        .buttonStyle(.plain)
                    }

                    Text("Speed")
                        .panelLabel(theme)
                        .padding(.horizontal, Grid.margin)
                        .padding(.top, Grid.x(4))
                        .padding(.bottom, Grid.x(1))

                    HStack(spacing: Grid.x(2)) {
                        Slider(value: $audio.rate, in: 0.7...1.4)
                            .tint(theme.inkC)
                        Text(String(format: "%.2f", audio.rate))
                            .font(.ramsMedium(15))
                            .foregroundStyle(theme.inkC)
                            .monospacedDigit()
                            .frame(width: Grid.x(6), alignment: .trailing)
                    }
                    .padding(.horizontal, Grid.margin)
                    .padding(.bottom, Grid.x(3))
                    .hairline(theme)

                    if let error = audio.engineError {
                        Text(error)
                            .font(.rams(13))
                            .foregroundStyle(theme.accentC)
                            .padding(.horizontal, Grid.margin)
                            .padding(.top, Grid.x(3))
                    }

                    Text("Kokoro‑82M · Apache‑2.0 · runs on this device")
                        .panelLabel(theme)
                        .padding(.horizontal, Grid.margin)
                        .padding(.top, Grid.x(4))
                }
            }
        }
        .background(theme.paperC.ignoresSafeArea())
    }

    private func voiceRow(_ voice: Voice) -> some View {
        let selected = audio.voice == voice
        return HStack(alignment: .firstTextBaseline, spacing: Grid.x(2)) {
            VStack(alignment: .leading, spacing: Grid.x(0.5)) {
                Text(voice.title)
                    .font(.ramsMedium(17))
                    .foregroundStyle(selected ? theme.accentC : theme.inkC)
                Text(voice.describedAs)
                    .font(.rams(14))
                    .foregroundStyle(theme.inkMutedC)
                Text(voice.modelName)
                    .panelLabel(theme)
            }
            Spacer(minLength: 0)
            Rectangle()
                .fill(selected ? theme.accentC : .clear)
                .frame(width: 7, height: 7)
                .offset(y: 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Grid.margin)
        .padding(.vertical, Grid.x(2))
        .contentShape(Rectangle())
        .hairline(theme)
    }
}
