import Foundation

enum InnerTubeError: LocalizedError {
    case http(Int)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .http(let code): return "YouTube Music returned HTTP \(code)."
        case .invalidResponse: return "YouTube Music returned a response the app couldn't read."
        }
    }
}

/// Minimal client for YouTube Music's private "InnerTube" API (the same JSON API the web
/// player uses, and the one `ytmusicapi` wraps). Unofficial: request shapes can change at any time.
final class InnerTubeClient: Sendable {
    static let shared = InnerTubeClient()

    private let session: URLSession
    private let baseURL = URL(string: "https://music.youtube.com/youtubei/v1/")!

    /// Search filter token for "Songs" (same value ytmusicapi uses).
    private static let songsFilter = "EgWKAQIIAWoMEA4QChADEAQQCRAF"

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: Endpoints

    func searchSongs(_ query: String) async throws -> [Track] {
        let filtered = try await post("search", body: ["query": query, "params": Self.songsFilter])
        let tracks = InnerTubeParser.tracks(fromSearch: filtered)
        if !tracks.isEmpty { return tracks }

        // The filter token is undocumented; if it stops matching, fall back to an unfiltered search.
        let unfiltered = try await post("search", body: ["query": query])
        return InnerTubeParser.tracks(fromSearch: unfiltered)
    }

    /// "Radio" for a track: similar songs YouTube Music would queue after it.
    func radio(for videoId: String) async throws -> [Track] {
        let body: [String: Any] = [
            "videoId": videoId,
            "playlistId": "RDAMVM\(videoId)",
            "isAudioOnly": true,
            "enablePersistentPlaylistPanel": true,
            "tunerSettingValue": "AUTOMIX_SETTING_NORMAL",
            "watchEndpointMusicSupportedConfigs": [
                "watchEndpointMusicConfig": [
                    "hasPersistentPlaylistPanel": true,
                    "musicVideoType": "MUSIC_VIDEO_TYPE_ATV"
                ]
            ]
        ]
        let json = try await post("next", body: body)
        return InnerTubeParser.tracks(fromWatchNext: json)
    }

    // MARK: Transport

    private func post(_ endpoint: String, body: [String: Any]) async throws -> Any {
        var components = URLComponents(url: baseURL.appendingPathComponent(endpoint), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "alt", value: "json"),
            URLQueryItem(name: "prettyPrint", value: "false")
        ]

        var payload = body
        payload["context"] = [
            "client": [
                "clientName": "WEB_REMIX",
                "clientVersion": Self.webRemixVersion(),
                "hl": "en",
                "gl": "US"
            ],
            "user": [String: Any]()
        ]

        var request = URLRequest(url: components.url!, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://music.youtube.com", forHTTPHeaderField: "Origin")
        request.setValue("SOCS=CAI", forHTTPHeaderField: "Cookie")   // skips the EU consent interstitial
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw InnerTubeError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw InnerTubeError.http(http.statusCode) }
        return try JSONSerialization.jsonObject(with: data)
    }

    /// The web client reports a date-based version, e.g. `1.20260929.01.00`.
    private static func webRemixVersion(now: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd"
        return "1.\(formatter.string(from: now)).01.00"
    }
}
