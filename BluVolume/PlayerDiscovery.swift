import Foundation

/// Finds BluOS players on the local network via Bonjour (`_musc._tcp`).
final class PlayerDiscovery: NSObject, ObservableObject {
    struct Player: Identifiable, Hashable {
        var id: String { name }
        let name: String
        let host: String
        let port: Int
    }

    @Published private(set) var players: [Player] = []
    @Published private(set) var isSearching = false

    private var browser: NetServiceBrowser?
    private var pending: [NetService] = []

    func start() {
        stop()
        let browser = NetServiceBrowser()
        browser.delegate = self
        browser.searchForServices(ofType: "_musc._tcp.", inDomain: "local.")
        self.browser = browser
        isSearching = true
    }

    func stop() {
        browser?.stop()
        browser = nil
        pending.forEach { $0.stop() }
        pending.removeAll()
        isSearching = false
    }

    /// Prefer a plain IPv4 address: it is the most reliable thing to hand to URLSession.
    private static func ipv4Address(from addresses: [Data]?) -> String? {
        for data in addresses ?? [] {
            let ip: String? = data.withUnsafeBytes { raw in
                guard raw.count >= MemoryLayout<sockaddr_in>.size,
                      raw[1] == UInt8(AF_INET) else { return nil }
                var sin = raw.loadUnaligned(as: sockaddr_in.self)
                var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                guard inet_ntop(AF_INET, &sin.sin_addr, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil else { return nil }
                return String(cString: buffer)
            }
            if let ip { return ip }
        }
        return nil
    }
}

extension PlayerDiscovery: NetServiceBrowserDelegate, NetServiceDelegate {
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        service.delegate = self
        pending.append(service)
        service.resolve(withTimeout: 5)
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        players.removeAll { $0.name == service.name }
    }

    func netServiceBrowserDidStopSearch(_ browser: NetServiceBrowser) {
        isSearching = false
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        let host = Self.ipv4Address(from: sender.addresses)
            ?? sender.hostName.map { $0.hasSuffix(".") ? String($0.dropLast()) : $0 }
        guard let host else { return }

        let player = Player(name: sender.name, host: host, port: sender.port > 0 ? sender.port : 11000)
        players.removeAll { $0.name == player.name }
        players.append(player)
        players.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        pending.removeAll { $0 === sender }
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        pending.removeAll { $0 === sender }
    }
}
