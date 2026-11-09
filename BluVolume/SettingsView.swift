import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: VolumeModel
    @Binding var rotationsForFullScale: Double

    @StateObject private var discovery = PlayerDiscovery()
    @Environment(\.dismiss) private var dismiss
    @State private var host = ""
    @State private var port = "11000"

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if discovery.players.isEmpty {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Zoeken naar BluOS-spelers…")
                                .foregroundStyle(.secondary)
                        }
                    }
                    ForEach(discovery.players) { player in
                        Button {
                            host = player.host
                            port = String(player.port)
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(player.name).foregroundStyle(.primary)
                                    Text(player.host).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if player.host == host {
                                    Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Gevonden spelers")
                }

                Section {
                    TextField("IP-adres, bijv. 192.168.1.20", text: $host)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Poort", text: $port)
                        .keyboardType(.numberPad)
                } header: {
                    Text("Handmatig")
                } footer: {
                    Text("Het IP-adres vind je in de BluOS-app onder Help › Diagnostiek, of in je router.")
                }

                Section {
                    VStack(alignment: .leading) {
                        Text(String(format: "%.1f omwentelingen voor 0–100 %%", rotationsForFullScale))
                        Slider(value: $rotationsForFullScale, in: 1...10, step: 0.5)
                    }
                    LabeledContent("Per procent", value: String(format: "%.1f°", rotationsForFullScale * 3.6))
                } header: {
                    Text("Draaiknop")
                } footer: {
                    Text("Hoe meer omwentelingen, hoe fijner je kunt instellen.")
                }

                Section {
                    VStack(alignment: .leading) {
                        Text(verbatim: "Maximaal \(Int(model.maxVolume)) %")
                        Slider(value: $model.maxVolume, in: 10...100, step: 5)
                    }
                } header: {
                    Text("Veiligheid")
                } footer: {
                    Text("De knop gaat nooit hoger dan deze waarde.")
                }
            }
            .navigationTitle("Instellingen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Gereed") {
                        model.configure(host: host, port: Int(port) ?? 11000)
                        dismiss()
                    }
                    .disabled(host.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .onAppear {
            host = model.host
            port = String(model.port)
            discovery.start()
        }
        .onDisappear { discovery.stop() }
        .preferredColorScheme(.dark)
    }
}
