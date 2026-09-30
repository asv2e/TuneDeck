import Foundation

// MARK: - Types

struct ResolvedStream: Sendable {
    let url: URL
    /// HTTP headers AVPlayer must send with every request for this URL.
    let headers: [String: String]
    let expiresAt: Date

    var isFresh: Bool { expiresAt.timeIntervalSinceNow > 60 }
}

enum StreamError: LocalizedError {
    case unplayable(String)
    case noAudioFormat
    case http(Int)
    case badResponse
    case allFailed([String])

    var errorDescription: String? {
        switch self {
        case .unplayable(let reason):
            return "YouTube says this track can't be played: \(reason)"
        case .noAudioFormat:
            return "No playable audio format was returned."
        case .http(let code):
            return "Server returned HTTP \(code)."
        case .badResponse:
            return "Unreadable response."
        case .allFailed(let failures):
            let detail = failures.joined(separator: " | ")
            return "Couldn't get an audio stream. Set up a stream resolver in Settings for reliable playback. (\(detail))"
        }
    }
}

protocol StreamResolving: Sendable {
    var name: String { get }
    func resolve(videoId: String) async throws -> ResolvedStream
}

// MARK: - Your own resolver server (recommended)

/// Talks to `server/resolver.py`, which runs yt-dlp. By default it also proxies the audio bytes,
/// because YouTube stream URLs are locked to the IP address that requested them.
struct RemoteStreamResolver: StreamResolving {
    let name = "Resolver server"
    let baseURL: URL
    let token: String?
    let proxy: Bool

    private struct Payload: Decodable {
        let mode: String
        let url: String?
        let headers: [String: String]?
        let ttl: TimeInterval?
    }

    func resolve(videoId: String) async throws -> ResolvedStream {
        var components = URLComponents(url: baseURL.appendingPathComponent("resolve"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "id", value: videoId),
            URLQueryItem(name: "mode", value: proxy ? "proxy" : "direct")
        ]
        var request = URLRequest(url: components.url!, timeoutInterval: 60)
        applyAuth(to: &request)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw StreamError.badResponse }
        guard http.statusCode == 200 else { throw StreamError.http(http.statusCode) }
        let payload = try JSONDecoder().decode(Payload.self, from: data)

        if payload.mode == "direct", let raw = payload.url, let url = URL(string: raw) {
            return ResolvedStream(
                url: url,
                headers: payload.headers ?? [:],
                expiresAt: Date().addingTimeInterval(payload.ttl ?? 3600)
            )
        }

        var streamComponents = URLComponents(url: baseURL.appendingPathComponent("stream"), resolvingAgainstBaseURL: false)!
        streamComponents.queryItems = [URLQueryItem(name: "id", value: videoId)]
        var headers: [String: String] = [:]
        if let token, !token.isEmpty { headers["Authorization"] = "Bearer \(token)" }
        return ResolvedStream(url: streamComponents.url!, headers: headers, expiresAt: Date().addingTimeInterval(1800))
    }

    private func applyAuth(to request: inout URLRequest) {
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }

    /// Used by the Settings screen's "Test connection" button.
    static func check(baseURLText: String, token: String) async -> String {
        guard let url = URL(string: baseURLText.trimmed), url.host != nil,
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            return "Enter a full URL, e.g. https://resolver.example.com"
        }
        var request = URLRequest(url: url.appendingPathComponent("health"), timeoutInterval: 10)
        if !token.isEmpty { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return "No response from server." }
            switch http.statusCode {
            case 200:
                let version = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["yt_dlp"] as? String
                return "Connected. yt-dlp \(version ?? "version unknown")."
            case 401:
                return "The server rejected the access token."
            default:
                return "Server returned HTTP \(http.statusCode)."
            }
        } catch {
            return "Couldn't reach the server: \(error.localizedDescription)"
        }
    }
}

// MARK: - On-device InnerTube player request (best effort)

/// Identity of a first-party YouTube client. YouTube increasingly demands proof-of-origin
/// tokens from these, so treat on-device resolution as an experiment. Current values live in
/// yt-dlp's `INNERTUBE_CLIENTS` table; update them here when they go stale.
struct PlayerClientProfile: Sendable {
    let name: String
    let headerId: Int
    let version: String
    let userAgent: String
    let deviceMake: String?
    let deviceModel: String?
    let osName: String?
    let osVersion: String?
    let androidSdkVersion: Int?

    var clientContext: [String: Any] {
        var context: [String: Any] = [
            "clientName": name,
            "clientVersion": version,
            "hl": "en",
            "gl": "US"
        ]
        if let deviceMake { context["deviceMake"] = deviceMake }
        if let deviceModel { context["deviceModel"] = deviceModel }
        if let osName { context["osName"] = osName }
        if let osVersion { context["osVersion"] = osVersion }
        if let androidSdkVersion { context["androidSdkVersion"] = androidSdkVersion }
        return context
    }

    static let androidVR = PlayerClientProfile(
        name: "ANDROID_VR",
        headerId: 28,
        version: "1.65.10",
        userAgent: "com.google.android.apps.youtube.vr.oculus/1.65.10 (Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip",
        deviceMake: "Oculus",
        deviceModel: "Quest 3",
        osName: "Android",
        osVersion: "12L",
        androidSdkVersion: 32
    )

    static let ios = PlayerClientProfile(
        name: "IOS",
        headerId: 5,
        version: "20.10.4",
        userAgent: "com.google.ios.youtube/20.10.4 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X;)",
        deviceMake: "Apple",
        deviceModel: "iPhone16,2",
        osName: "iPhone",
        osVersion: "18.3.2.22D82",
        androidSdkVersion: nil
    )
}

struct InnerTubeStreamResolver: StreamResolving {
    let profile: PlayerClientProfile
    var name: String { "On-device (\(profile.name))" }

    func resolve(videoId: String) async throws -> ResolvedStream {
        var components = URLComponents(string: "https://www.youtube.com/youtubei/v1/player")!
        components.queryItems = [URLQueryItem(name: "prettyPrint", value: "false")]

        let body: [String: Any] = [
            "context": ["client": profile.clientContext],
            "videoId": videoId,
            "contentCheckOk": true,
            "racyCheckOk": true
        ]

        var request = URLRequest(url: components.url!, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(profile.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(String(profile.headerId), forHTTPHeaderField: "X-YouTube-Client-Name")
        request.setValue(profile.version, forHTTPHeaderField: "X-YouTube-Client-Version")
        request.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw StreamError.badResponse }
        guard http.statusCode == 200 else { throw StreamError.http(http.statusCode) }
        let json = try JSONSerialization.jsonObject(with: data)
        return try PlayerResponseParser.parse(json, userAgent: profile.userAgent)
    }
}

enum PlayerResponseParser {
    /// Picks the best format AVPlayer can decode. AVPlayer handles AAC-in-MP4 but not Opus/WebM,
    /// so prefer the highest-bitrate `audio/mp4` stream, then fall back to a muxed MP4.
    static func parse(_ json: Any, userAgent: String, now: Date = Date()) throws -> ResolvedStream {
        let status = dig(json, "playabilityStatus", "status") as? String
        guard status == "OK" else {
            let reason = (dig(json, "playabilityStatus", "reason") as? String) ?? status ?? "unknown reason"
            throw StreamError.unplayable(reason)
        }

        let adaptive = (dig(json, "streamingData", "adaptiveFormats") as? [[String: Any]]) ?? []
        let muxed = (dig(json, "streamingData", "formats") as? [[String: Any]]) ?? []

        func hasURL(_ format: [String: Any]) -> Bool { format["url"] is String }
        func bitrate(_ format: [String: Any]) -> Int { (format["bitrate"] as? Int) ?? 0 }

        let audioOnly = adaptive.filter { format in
            let mime = (format["mimeType"] as? String) ?? ""
            return mime.hasPrefix("audio/mp4") && hasURL(format)
        }
        let candidates = audioOnly.isEmpty ? muxed.filter(hasURL) : audioOnly
        guard let best = candidates.max(by: { bitrate($0) < bitrate($1) }),
              let text = best["url"] as? String,
              let url = URL(string: text) else {
            throw StreamError.noAudioFormat
        }

        let ttl = ((dig(json, "streamingData", "expiresInSeconds") as? String).flatMap(Double.init)) ?? 3600
        return ResolvedStream(url: url, headers: ["User-Agent": userAgent], expiresAt: now.addingTimeInterval(ttl))
    }
}

// MARK: - Orchestration

/// Resolves and caches stream URLs. Tries your resolver server first (if configured), then
/// on-device clients, and probes every candidate URL so a 403 falls through to the next option
/// instead of surfacing as a mid-playback failure.
actor StreamService {
    private var cache: [String: ResolvedStream] = [:]
    private var inflight: [String: Task<ResolvedStream, Error>] = [:]

    func stream(for videoId: String) async throws -> ResolvedStream {
        if let hit = cache[videoId], hit.isFresh { return hit }
        if let running = inflight[videoId] { return try await running.value }

        let resolvers = Self.currentResolvers()
        let task = Task { try await Self.resolve(videoId, using: resolvers) }
        inflight[videoId] = task
        defer { inflight[videoId] = nil }

        let stream = try await task.value
        cache[videoId] = stream
        return stream
    }

    func invalidate(_ videoId: String) {
        cache[videoId] = nil
    }

    // MARK: Private

    private static func currentResolvers() -> [any StreamResolving] {
        let defaults = UserDefaults.standard
        var resolvers: [any StreamResolving] = []

        let raw = (defaults.string(forKey: SettingsKey.resolverURL) ?? "").trimmed
        if let url = URL(string: raw), url.host != nil,
           ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
            resolvers.append(RemoteStreamResolver(
                baseURL: url,
                token: defaults.string(forKey: SettingsKey.resolverToken),
                proxy: (defaults.object(forKey: SettingsKey.resolverProxy) as? Bool) ?? true
            ))
        }
        resolvers.append(InnerTubeStreamResolver(profile: .androidVR))
        resolvers.append(InnerTubeStreamResolver(profile: .ios))
        return resolvers
    }

    private static func resolve(_ videoId: String, using resolvers: [any StreamResolving]) async throws -> ResolvedStream {
        var failures: [String] = []
        for resolver in resolvers {
            do {
                let stream = try await resolver.resolve(videoId: videoId)
                let status = await probe(stream)
                if status == 200 || status == 206 { return stream }
                failures.append("\(resolver.name): stream rejected (HTTP \(status))")
            } catch {
                failures.append("\(resolver.name): \(error.localizedDescription)")
            }
        }
        throw StreamError.allFailed(failures)
    }

    /// Requests two bytes to confirm the URL is actually playable. Returns 0 on network failure.
    private static func probe(_ stream: ResolvedStream) async -> Int {
        var request = URLRequest(url: stream.url, timeoutInterval: 15)
        request.setValue("bytes=0-1", forHTTPHeaderField: "Range")
        for (field, value) in stream.headers { request.setValue(value, forHTTPHeaderField: field) }
        guard let result = try? await URLSession.shared.data(for: request),
              let http = result.1 as? HTTPURLResponse else { return 0 }
        return http.statusCode
    }
}
