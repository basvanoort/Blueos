import SwiftUI

struct ContentView: View {
    @StateObject private var model = VolumeModel()
    @AppStorage("rotationsForFullScale") private var rotationsForFullScale = 4.0
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSettings = false

    /// 4 rotations for 0–100 % → 14.4° per percent.
    private var degreesPerStep: Double { rotationsForFullScale * 360 / 100 }

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                statusLine

                Spacer(minLength: 0)

                volumeReadout

                VolumeKnob(
                    value: Binding(get: { model.volume }, set: { model.userChangedVolume(to: $0) }),
                    range: 0...model.maxVolume,
                    degreesPerStep: degreesPerStep,
                    onEditingChanged: { model.setInteracting($0) }
                )
                .padding(.horizontal, 24)
                .opacity(model.muted ? 0.5 : 1)

                controls

                Spacer(minLength: 0)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(white: 0.05).ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Instellingen")
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(model: model, rotationsForFullScale: $rotationsForFullScale)
            }
        }
        .onAppear {
            if model.isConfigured { model.start() } else { showSettings = true }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: model.start()
            case .background: model.stop()
            default: break
            }
        }
    }

    private var statusLine: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(statusText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var volumeReadout: some View {
        VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(verbatim: "\(model.level)")
                    .font(.system(size: 88, weight: .thin, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("%")
                    .font(.system(size: 28, weight: .light, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Group {
                if model.muted {
                    Text("Gedempt")
                } else if let db = model.db {
                    Text(String(format: "%.1f dB", db))
                } else {
                    Text(" ")
                }
            }
            .font(.footnote.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    private var controls: some View {
        HStack(spacing: 36) {
            roundButton(systemName: "minus", label: "Zachter") { model.step(by: -1) }
            roundButton(systemName: model.muted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                        label: model.muted ? "Dempen opheffen" : "Dempen") { model.toggleMute() }
            roundButton(systemName: "plus", label: "Harder") { model.step(by: 1) }
        }
    }

    private func roundButton(systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.title3)
                .frame(width: 56, height: 56)
                .background(Circle().fill(Color.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var statusText: String {
        switch model.connection {
        case .notConfigured: return "Geen speler ingesteld"
        case .connecting: return "Verbinden met \(model.host)…"
        case .connected: return model.playerName.isEmpty ? model.host : model.playerName
        case .failed(let message): return message
        }
    }

    private var statusColor: Color {
        switch model.connection {
        case .connected: return .green
        case .connecting: return .yellow
        case .failed: return .red
        case .notConfigured: return .gray
        }
    }
}

#Preview {
    ContentView()
        .preferredColorScheme(.dark)
}
