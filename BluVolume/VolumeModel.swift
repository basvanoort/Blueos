import Foundation

/// Keeps the app's volume in sync with the player.
///
/// - Knob changes are sent "latest wins": at most one request in flight; when it
///   returns, the newest knob value is sent. This keeps the player responsive
///   without flooding it with a request per pixel of finger movement.
/// - Changes made elsewhere (BluOS app, Spotify, remote) arrive via long-polling.
@MainActor
final class VolumeModel: ObservableObject {
    enum Connection: Equatable {
        case notConfigured
        case connecting
        case connected
        case failed(String)
    }

    /// Fractional while turning the knob; snapped to a whole percent when you let go.
    @Published var volume: Double = 0
    @Published private(set) var muted = false
    @Published private(set) var db: Double?
    @Published private(set) var connection: Connection = .notConfigured
    @Published private(set) var playerName = ""

    /// Safety cap: the knob never goes above this.
    @Published var maxVolume: Double {
        didSet { UserDefaults.standard.set(maxVolume, forKey: Keys.maxVolume) }
    }

    private(set) var host: String
    private(set) var port: Int

    private var client: BluOSClient?
    private var pollTask: Task<Void, Never>?
    private var isInteracting = false
    private var sendInFlight = false
    private var lastSentLevel: Int?
    private var lastLocalChange = Date.distantPast

    private enum Keys {
        static let host = "playerHost"
        static let port = "playerPort"
        static let maxVolume = "maxVolume"
    }

    init() {
        let defaults = UserDefaults.standard
        host = defaults.string(forKey: Keys.host) ?? ""
        let storedPort = defaults.integer(forKey: Keys.port)
        port = storedPort > 0 ? storedPort : 11000
        let storedMax = defaults.double(forKey: Keys.maxVolume)
        maxVolume = storedMax > 0 ? storedMax : 100
    }

    var level: Int { Int(volume.rounded()) }
    var isConfigured: Bool { !host.isEmpty }

    // MARK: - Lifecycle

    func start() {
        guard pollTask == nil else { return }
        guard isConfigured else {
            connection = .notConfigured
            return
        }
        let client = BluOSClient(host: host, port: port)
        self.client = client
        pollTask = Task { [weak self] in await self?.pollLoop(client) }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    func configure(host: String, port: Int) {
        let host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard host != self.host || port != self.port || pollTask == nil else { return }
        self.host = host
        self.port = port
        UserDefaults.standard.set(host, forKey: Keys.host)
        UserDefaults.standard.set(port, forKey: Keys.port)
        stop()
        client = nil
        playerName = ""
        lastSentLevel = nil
        start()
    }

    // MARK: - User input

    func setInteracting(_ interacting: Bool) {
        isInteracting = interacting
        if !interacting {
            volume = volume.rounded()
            requestSend()
        }
    }

    func userChangedVolume(to newValue: Double) {
        volume = min(max(newValue, 0), maxVolume)
        lastLocalChange = Date()
        requestSend()
    }

    func step(by delta: Int) {
        userChangedVolume(to: Double(level + delta))
    }

    func toggleMute() {
        guard let client else { return }
        let target = !muted
        muted = target
        Task {
            do {
                let state = try await client.setMuted(target)
                muted = state.muted
            } catch {
                muted = !target
                connection = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: - Sending

    private func requestSend() {
        guard let client, !sendInFlight else { return }
        let target = min(level, Int(maxVolume))
        guard target != lastSentLevel else { return }

        sendInFlight = true
        lastSentLevel = target
        Task {
            do {
                let state = try await client.setVolume(target)
                muted = state.muted
                db = state.db
                connection = .connected
            } catch {
                lastSentLevel = nil
                connection = .failed(error.localizedDescription)
            }
            sendInFlight = false
            lastLocalChange = Date()
            // The knob may have moved while we were waiting: send the newest value.
            requestSend()
        }
    }

    // MARK: - Receiving

    private func pollLoop(_ client: BluOSClient) async {
        connection = .connecting
        var etag: String?

        if let name = try? await client.playerName() {
            playerName = name
        }

        while !Task.isCancelled {
            let startedAt = Date()
            do {
                let state: VolumeState
                if let etag {
                    state = try await client.waitForVolumeChange(etag: etag)
                } else {
                    state = try await client.getVolume()
                }
                guard !Task.isCancelled else { return }
                connection = .connected

                // Safety net: if the player answers instantly with the same etag,
                // it isn't long-polling; don't spin in a tight loop.
                if state.etag == etag, Date().timeIntervalSince(startedAt) < 0.5 {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
                etag = state.etag
                applyRemote(state)
            } catch {
                guard !Task.isCancelled else { return }
                connection = .failed(error.localizedDescription)
                etag = nil
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    private func applyRemote(_ state: VolumeState) {
        muted = state.muted
        db = state.db
        // Don't yank the knob out from under the user's finger.
        let userIsBusy = isInteracting || sendInFlight || Date().timeIntervalSince(lastLocalChange) < 1
        guard !userIsBusy else { return }
        volume = Double(state.level)
        lastSentLevel = state.level
    }
}
