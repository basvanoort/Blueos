import Foundation

/// Volume state as reported by a BluOS player's `/Volume` endpoint.
///
/// Example response:
/// `<volume db="-38.5" mute="0" offsetDb="0" etag="4f0c...">8</volume>`
struct VolumeState: Equatable {
    var level: Int
    var muted: Bool
    var db: Double?
    var etag: String?
}

enum BluOSError: LocalizedError {
    case invalidResponse
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Onverwacht antwoord van de speler."
        case .httpStatus(let code): return "De speler antwoordde met HTTP \(code)."
        }
    }
}

/// Minimal client for the BluOS HTTP API (http://<player>:11000).
final class BluOSClient {
    let host: String
    let port: Int

    /// Short timeouts for commands, so a slider-like knob never feels stuck.
    private let commandSession: URLSession
    /// Separate session for long-polling, so a pending poll never blocks a volume command.
    private let pollSession: URLSession

    init(host: String, port: Int = 11000) {
        self.host = host
        self.port = port

        let command = URLSessionConfiguration.ephemeral
        command.timeoutIntervalForRequest = 6
        command.requestCachePolicy = .reloadIgnoringLocalCacheData
        commandSession = URLSession(configuration: command)

        let poll = URLSessionConfiguration.ephemeral
        poll.timeoutIntervalForRequest = 90
        poll.requestCachePolicy = .reloadIgnoringLocalCacheData
        pollSession = URLSession(configuration: poll)
    }

    deinit {
        commandSession.invalidateAndCancel()
        pollSession.invalidateAndCancel()
    }

    // MARK: - Volume

    func getVolume() async throws -> VolumeState {
        try await volumeRequest([], session: commandSession)
    }

    func setVolume(_ level: Int) async throws -> VolumeState {
        let clamped = min(max(level, 0), 100)
        return try await volumeRequest([URLQueryItem(name: "level", value: String(clamped))], session: commandSession)
    }

    func setMuted(_ muted: Bool) async throws -> VolumeState {
        try await volumeRequest([URLQueryItem(name: "mute", value: muted ? "1" : "0")], session: commandSession)
    }

    /// Long-poll: the player holds the request until the volume changes
    /// (new etag) or `timeout` seconds have passed.
    func waitForVolumeChange(etag: String, timeout: Int = 60) async throws -> VolumeState {
        try await volumeRequest([
            URLQueryItem(name: "timeout", value: String(timeout)),
            URLQueryItem(name: "etag", value: etag),
        ], session: pollSession)
    }

    // MARK: - Player info

    /// The player's friendly name (e.g. "Woonkamer"), from `/SyncStatus`.
    func playerName() async throws -> String? {
        let xml = try await request(path: "/SyncStatus", query: [], session: commandSession)
        return xml.attributes["name"]
    }

    // MARK: - Plumbing

    private func volumeRequest(_ query: [URLQueryItem], session: URLSession) async throws -> VolumeState {
        let xml = try await request(path: "/Volume", query: query, session: session)
        guard xml.rootName == "volume",
              let level = Int(xml.text.trimmingCharacters(in: .whitespacesAndNewlines))
        else { throw BluOSError.invalidResponse }

        return VolumeState(
            level: level,
            muted: xml.attributes["mute"] == "1",
            db: xml.attributes["db"].flatMap(Double.init),
            etag: xml.attributes["etag"]
        )
    }

    private func request(path: String, query: [URLQueryItem], session: URLSession) async throws -> SimpleXML {
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = port
        components.path = path
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw URLError(.badURL) }

        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw BluOSError.httpStatus(http.statusCode)
        }
        return try SimpleXML.parse(data)
    }
}

/// Tiny XML reader: we only need the root element's name, attributes and text.
private final class SimpleXML: NSObject, XMLParserDelegate {
    private(set) var rootName: String?
    private(set) var attributes: [String: String] = [:]
    private(set) var text = ""
    private var depth = 0

    static func parse(_ data: Data) throws -> SimpleXML {
        let parser = XMLParser(data: data)
        let result = SimpleXML()
        parser.delegate = result
        guard parser.parse(), result.rootName != nil else { throw BluOSError.invalidResponse }
        return result
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        if depth == 0 {
            rootName = elementName
            attributes = attributeDict
        }
        depth += 1
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        depth -= 1
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if depth == 1 { text += string }
    }
}
