import Foundation

/// Turns raw InnerTube JSON into `Track`s. Pure functions, covered by unit tests.
enum InnerTubeParser {
    private static let typeLabels: Set<String> = [
        "Song", "Video", "Single", "Album", "EP", "Playlist", "Episode", "Explicit"
    ]

    // MARK: Search

    static func tracks(fromSearch json: Any) -> [Track] {
        let rows = JSONSearch.collect("musicResponsiveListItemRenderer", in: json)
        return unique(rows.compactMap { track(fromListItem: $0) })
    }

    static func track(fromListItem item: [String: Any]) -> Track? {
        let videoId = (dig(item, "playlistItemData", "videoId") as? String)
            ?? (dig(item, "overlay", "musicItemThumbnailOverlayRenderer", "content",
                    "musicPlayButtonRenderer", "playNavigationEndpoint", "watchEndpoint", "videoId") as? String)
        guard let videoId, !videoId.isEmpty else { return nil }   // albums, artists, playlists have no videoId

        let columns = (item["flexColumns"] as? [Any]) ?? []
        func runs(inColumn index: Int) -> [[String: Any]] {
            guard columns.indices.contains(index) else { return [] }
            return (dig(columns[index], "musicResponsiveListItemFlexColumnRenderer", "text", "runs") as? [[String: Any]]) ?? []
        }

        guard let title = runs(inColumn: 0).first?["text"] as? String else { return nil }
        let info = metadata(from: runs(inColumn: 1))
        return Track(
            id: videoId,
            title: title,
            artists: info.artists,
            album: info.album,
            duration: info.duration,
            thumbnailURL: thumbnailURL(dig(item, "thumbnail", "musicThumbnailRenderer", "thumbnail", "thumbnails"))
        )
    }

    // MARK: Up next / radio

    static func tracks(fromWatchNext json: Any) -> [Track] {
        // Each entry may carry a `counterpart` (the music-video twin of a song); skip those.
        let panels = JSONSearch.collect("playlistPanelVideoRenderer", in: json, skipping: ["counterpart"])
        let tracks = panels.compactMap { (panel: [String: Any]) -> Track? in
            guard let id = panel["videoId"] as? String,
                  let title = dig(panel, "title", "runs", 0, "text") as? String else { return nil }
            let info = metadata(from: (dig(panel, "longBylineText", "runs") as? [[String: Any]]) ?? [])
            let length = (dig(panel, "lengthText", "runs", 0, "text") as? String).flatMap(Format.parseDuration)
            return Track(
                id: id,
                title: title,
                artists: info.artists,
                album: info.album,
                duration: length ?? info.duration,
                thumbnailURL: thumbnailURL(dig(panel, "thumbnail", "thumbnails"))
            )
        }
        return unique(tracks)
    }

    // MARK: Helpers

    private struct Metadata {
        var artists: [String] = []
        var album: String?
        var duration: TimeInterval?
    }

    /// Byline runs look like `Artist • Album • 3:45`. Links carry a page type, which is far
    /// more reliable than position, so classify by that and fall back to plain text.
    private static func metadata(from runs: [[String: Any]]) -> Metadata {
        var result = Metadata()
        var loose: [String] = []
        for run in runs {
            guard let raw = run["text"] as? String else { continue }
            let text = raw.trimmed
            if text.isEmpty || text == "•" { continue }

            let pageType = dig(run, "navigationEndpoint", "browseEndpoint",
                               "browseEndpointContextSupportedConfigs",
                               "browseEndpointContextMusicConfig", "pageType") as? String

            switch pageType ?? "" {
            case "MUSIC_PAGE_TYPE_ARTIST", "MUSIC_PAGE_TYPE_USER_CHANNEL":
                result.artists.append(text)
            case "MUSIC_PAGE_TYPE_ALBUM":
                result.album = text
            default:
                if let seconds = Format.parseDuration(text) {
                    result.duration = seconds
                } else if !typeLabels.contains(text) {
                    loose.append(text)
                }
            }
        }
        if result.artists.isEmpty, let first = loose.first {
            result.artists = [first]
        }
        return result
    }

    private static func thumbnailURL(_ node: Any?) -> URL? {
        guard let thumbnails = node as? [[String: Any]], !thumbnails.isEmpty else { return nil }
        let largest = thumbnails.max { (($0["width"] as? Int) ?? 0) < (($1["width"] as? Int) ?? 0) }
        guard let text = largest?["url"] as? String else { return nil }
        return URL(string: text)
    }

    private static func unique(_ tracks: [Track]) -> [Track] {
        var seen = Set<String>()
        return tracks.filter { seen.insert($0.id).inserted }
    }
}
