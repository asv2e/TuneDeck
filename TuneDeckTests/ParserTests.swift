import XCTest
@testable import TuneDeck

final class ParserTests: XCTestCase {

    // MARK: Fixtures (trimmed to the parts the parser reads)

    private let searchFixture = #"""
    {
      "contents": { "tabbedSearchResultsRenderer": { "tabs": [ { "tabRenderer": { "content": {
        "sectionListRenderer": { "contents": [ { "musicShelfRenderer": { "contents": [
          { "musicResponsiveListItemRenderer": {
              "playlistItemData": { "videoId": "A1b2C3d4E5f" },
              "thumbnail": { "musicThumbnailRenderer": { "thumbnail": { "thumbnails": [
                { "url": "https://lh3.googleusercontent.com/abc=w60-h60-l90-rj", "width": 60, "height": 60 },
                { "url": "https://lh3.googleusercontent.com/abc=w120-h120-l90-rj", "width": 120, "height": 120 }
              ] } } },
              "flexColumns": [
                { "musicResponsiveListItemFlexColumnRenderer": { "text": { "runs": [ { "text": "One More Time" } ] } } },
                { "musicResponsiveListItemFlexColumnRenderer": { "text": { "runs": [
                  { "text": "Daft Punk", "navigationEndpoint": { "browseEndpoint": { "browseEndpointContextSupportedConfigs": { "browseEndpointContextMusicConfig": { "pageType": "MUSIC_PAGE_TYPE_ARTIST" } } } } },
                  { "text": " • " },
                  { "text": "Discovery", "navigationEndpoint": { "browseEndpoint": { "browseEndpointContextSupportedConfigs": { "browseEndpointContextMusicConfig": { "pageType": "MUSIC_PAGE_TYPE_ALBUM" } } } } },
                  { "text": " • " },
                  { "text": "5:20" }
                ] } } }
              ] } },
          { "musicResponsiveListItemRenderer": {
              "flexColumns": [
                { "musicResponsiveListItemFlexColumnRenderer": { "text": { "runs": [ { "text": "Discovery" } ] } } },
                { "musicResponsiveListItemFlexColumnRenderer": { "text": { "runs": [ { "text": "Album" }, { "text": " • " }, { "text": "Daft Punk" } ] } } }
              ] } },
          { "musicResponsiveListItemRenderer": {
              "overlay": { "musicItemThumbnailOverlayRenderer": { "content": { "musicPlayButtonRenderer": { "playNavigationEndpoint": { "watchEndpoint": { "videoId": "Z9y8X7w6V5u" } } } } } },
              "flexColumns": [
                { "musicResponsiveListItemFlexColumnRenderer": { "text": { "runs": [ { "text": "Around the World" } ] } } },
                { "musicResponsiveListItemFlexColumnRenderer": { "text": { "runs": [ { "text": "Song" }, { "text": " • " }, { "text": "Daft Punk" }, { "text": " • " }, { "text": "1:02:03" } ] } } }
              ] } }
        ] } } ] }
      } } } ] } }
    }
    """#

    private let watchNextFixture = #"""
    { "contents": { "singleColumnMusicWatchNextResultsRenderer": { "tabbedRenderer": { "watchNextTabbedResultsRenderer": {
      "tabs": [ { "tabRenderer": { "content": { "musicQueueRenderer": { "content": { "playlistPanelRenderer": { "contents": [
        { "playlistPanelVideoWrapperRenderer": {
            "primaryRenderer": { "playlistPanelVideoRenderer": {
              "videoId": "AAAAAAAAAAA",
              "title": { "runs": [ { "text": "Song A" } ] },
              "longBylineText": { "runs": [
                { "text": "Artist A", "navigationEndpoint": { "browseEndpoint": { "browseEndpointContextSupportedConfigs": { "browseEndpointContextMusicConfig": { "pageType": "MUSIC_PAGE_TYPE_ARTIST" } } } } },
                { "text": " • " },
                { "text": "Album A", "navigationEndpoint": { "browseEndpoint": { "browseEndpointContextSupportedConfigs": { "browseEndpointContextMusicConfig": { "pageType": "MUSIC_PAGE_TYPE_ALBUM" } } } } },
                { "text": " • " },
                { "text": "2001" }
              ] },
              "lengthText": { "runs": [ { "text": "3:45" } ] },
              "thumbnail": { "thumbnails": [ { "url": "https://i.ytimg.com/vi/AAAAAAAAAAA/sddefault.jpg", "width": 640, "height": 480 } ] }
            } },
            "counterpart": [ { "counterpartRenderer": { "playlistPanelVideoRenderer": {
              "videoId": "BBBBBBBBBBB",
              "title": { "runs": [ { "text": "Song A (Music Video)" } ] }
            } } } ]
        } },
        { "playlistPanelVideoRenderer": {
            "videoId": "CCCCCCCCCCC",
            "title": { "runs": [ { "text": "Song C" } ] },
            "longBylineText": { "runs": [ { "text": "Artist C" } ] },
            "lengthText": { "runs": [ { "text": "2:10" } ] }
        } }
      ] } } } } } } ] } } } } }
    """#

    private func json(_ text: String) throws -> Any {
        try JSONSerialization.jsonObject(with: Data(text.utf8))
    }

    // MARK: Search

    func testSearchKeepsOnlyPlayableRows() throws {
        let tracks = InnerTubeParser.tracks(fromSearch: try json(searchFixture))
        // The album row has no videoId and must be dropped.
        XCTAssertEqual(tracks.map(\.id), ["A1b2C3d4E5f", "Z9y8X7w6V5u"])
    }

    func testSearchParsesMetadataByPageType() throws {
        let track = try XCTUnwrap(InnerTubeParser.tracks(fromSearch: try json(searchFixture)).first)
        XCTAssertEqual(track.title, "One More Time")
        XCTAssertEqual(track.artists, ["Daft Punk"])
        XCTAssertEqual(track.album, "Discovery")
        XCTAssertEqual(track.duration, 320)
    }

    func testSearchFallsBackToOverlayVideoIdAndIgnoresTypeLabel() throws {
        let track = try XCTUnwrap(InnerTubeParser.tracks(fromSearch: try json(searchFixture)).last)
        XCTAssertEqual(track.id, "Z9y8X7w6V5u")
        XCTAssertEqual(track.artists, ["Daft Punk"])      // "Song" label is not an artist
        XCTAssertEqual(track.duration, 3723)              // 1:02:03
    }

    func testArtworkURLIsUpscaled() throws {
        let track = try XCTUnwrap(InnerTubeParser.tracks(fromSearch: try json(searchFixture)).first)
        XCTAssertEqual(track.artworkURL(size: 544)?.absoluteString,
                       "https://lh3.googleusercontent.com/abc=w544-h544-l90-rj")
    }

    // MARK: Up next

    func testWatchNextSkipsCounterparts() throws {
        let tracks = InnerTubeParser.tracks(fromWatchNext: try json(watchNextFixture))
        XCTAssertEqual(tracks.map(\.id), ["AAAAAAAAAAA", "CCCCCCCCCCC"])
        XCTAssertEqual(tracks.first?.album, "Album A")
        XCTAssertEqual(tracks.first?.duration, 225)
        XCTAssertEqual(tracks.last?.artists, ["Artist C"])   // plain-text fallback
    }

    // MARK: Durations

    func testDurationParsing() {
        XCTAssertEqual(Format.parseDuration("3:45"), 225)
        XCTAssertEqual(Format.parseDuration("1:02:05"), 3725)
        XCTAssertNil(Format.parseDuration("Song"))
        XCTAssertNil(Format.parseDuration("2001"))
        XCTAssertNil(Format.parseDuration("1:xx"))
    }

    func testTimeFormatting() {
        XCTAssertEqual(Format.time(225), "3:45")
        XCTAssertEqual(Format.time(3725), "1:02:05")
        XCTAssertEqual(Format.time(.nan), "0:00")
    }

    // MARK: Player response

    private func playerJSON(status: String = "OK") throws -> Any {
        try json(#"""
        {
          "playabilityStatus": { "status": "\#(status)", "reason": "Sign in to confirm you're not a bot" },
          "streamingData": {
            "expiresInSeconds": "21540",
            "formats": [
              { "itag": 18, "mimeType": "video/mp4; codecs=\"avc1.42001E, mp4a.40.2\"", "bitrate": 500000, "url": "https://example.invalid/muxed" }
            ],
            "adaptiveFormats": [
              { "itag": 251, "mimeType": "audio/webm; codecs=\"opus\"", "bitrate": 160000, "url": "https://example.invalid/opus" },
              { "itag": 139, "mimeType": "audio/mp4; codecs=\"mp4a.40.5\"", "bitrate": 48000, "url": "https://example.invalid/aac48" },
              { "itag": 140, "mimeType": "audio/mp4; codecs=\"mp4a.40.2\"", "bitrate": 130000, "url": "https://example.invalid/aac128" }
            ]
          }
        }
        """#)
    }

    func testPlayerResponsePrefersHighestBitrateAAC() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let stream = try PlayerResponseParser.parse(try playerJSON(), userAgent: "UA", now: now)
        XCTAssertEqual(stream.url.absoluteString, "https://example.invalid/aac128")   // never the Opus stream
        XCTAssertEqual(stream.headers["User-Agent"], "UA")
        XCTAssertEqual(stream.expiresAt, now.addingTimeInterval(21_540))
    }

    func testPlayerResponseThrowsWhenUnplayable() throws {
        XCTAssertThrowsError(try PlayerResponseParser.parse(try playerJSON(status: "LOGIN_REQUIRED"), userAgent: "UA")) { error in
            guard case StreamError.unplayable(let reason) = error else { return XCTFail("wrong error: \(error)") }
            XCTAssertTrue(reason.contains("not a bot"))
        }
    }

    func testPlayerResponseFallsBackToMuxedWhenNoAAC() throws {
        let onlyOpus = try json(#"""
        { "playabilityStatus": { "status": "OK" },
          "streamingData": {
            "formats": [ { "mimeType": "video/mp4", "bitrate": 1, "url": "https://example.invalid/muxed" } ],
            "adaptiveFormats": [ { "mimeType": "audio/webm; codecs=\"opus\"", "bitrate": 1, "url": "https://example.invalid/opus" } ]
          } }
        """#)
        let stream = try PlayerResponseParser.parse(onlyOpus, userAgent: "UA")
        XCTAssertEqual(stream.url.absoluteString, "https://example.invalid/muxed")
    }
}
