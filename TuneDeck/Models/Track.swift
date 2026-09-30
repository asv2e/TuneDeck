import Foundation

/// A playable item (song or video) from YouTube Music.
struct Track: Identifiable, Hashable, Codable, Sendable {
    /// The YouTube `videoId`.
    let id: String
    var title: String
    var artists: [String]
    var album: String?
    var duration: TimeInterval?
    var thumbnailURL: URL?

    var artistLine: String {
        artists.isEmpty ? "Unknown artist" : artists.joined(separator: ", ")
    }

    /// Google-hosted artwork URLs end in `=w60-h60-...`; rewrite that to request a larger size.
    func artworkURL(size: Int) -> URL? {
        guard let url = thumbnailURL else { return nil }
        let text = url.absoluteString
        guard let range = text.range(of: #"=w\d+-h\d+"#, options: .regularExpression) else { return url }
        return URL(string: text.replacingCharacters(in: range, with: "=w\(size)-h\(size)"))
    }
}
