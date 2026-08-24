//
//  RSSFeedParserTests.swift
//  PodstashTests
//

import Testing
import Foundation
@testable import Podstash

@Suite("RSSFeedParser")
struct RSSFeedParserTests {

    @Test("Parses a well-formed feed with itunes metadata")
    func parsesWellFormedFeed() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd">
        <channel>
          <title>Test &amp; Podcast</title>
          <description>A show about testing</description>
          <itunes:author>Jane Host</itunes:author>
          <link>https://example.com</link>
          <itunes:image href="https://example.com/art.jpg" />
          <item>
            <title>Episode One</title>
            <guid>ep-1</guid>
            <pubDate>Mon, 03 Aug 2026 10:00:00 GMT</pubDate>
            <itunes:duration>01:02:03</itunes:duration>
            <enclosure url="https://example.com/ep1.mp3" type="audio/mpeg" length="123"/>
          </item>
          <item>
            <title>Episode Two</title>
            <guid>ep-2</guid>
            <pubDate>Tue, 4 Aug 2026 09:30:00 -0700</pubDate>
            <itunes:duration>45:30</itunes:duration>
            <enclosure url="https://example.com/ep2.mp3" type="audio/mpeg" length="456"/>
          </item>
        </channel>
        </rss>
        """
        let parser = RSSFeedParser()
        let podcast = try #require(parser.parse(data: Data(xml.utf8)))

        #expect(podcast.title == "Test & Podcast")
        #expect(podcast.author == "Jane Host")
        #expect(podcast.artworkURL == "https://example.com/art.jpg")
        #expect(podcast.episodes.count == 2)

        let ep1 = try #require(podcast.episodes.first { $0.guid == "ep-1" })
        #expect(ep1.audioURL == "https://example.com/ep1.mp3")
        #expect(ep1.duration == 3723) // 1h 2m 3s

        let ep2 = try #require(podcast.episodes.first { $0.guid == "ep-2" })
        #expect(ep2.duration == 2730) // 45m 30s
    }

    @Test("Episodes without an audio enclosure are skipped")
    func skipsEpisodesWithoutAudio() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0"><channel>
          <title>No Audio Show</title>
          <item>
            <title>Text Only</title>
            <guid>no-audio</guid>
            <pubDate>Mon, 03 Aug 2026 10:00:00 GMT</pubDate>
          </item>
        </channel></rss>
        """
        let parser = RSSFeedParser()
        let podcast = try #require(parser.parse(data: Data(xml.utf8)))
        #expect(podcast.episodes.isEmpty)
    }

    @Test("Malformed XML fails to parse rather than crashing")
    func malformedXMLReturnsNil() {
        let parser = RSSFeedParser()
        let result = parser.parse(data: Data("<rss><channel><title>Oops".utf8))
        #expect(result == nil)
    }

    @Test(
        "Unparseable publish dates fall back to distantPast, not now",
        arguments: ["not a date", ""]
    )
    func unparseableDateFallsBackToDistantPast(dateText: String) throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0"><channel>
          <title>Weird Dates</title>
          <item>
            <title>Mystery Episode</title>
            <guid>mystery</guid>
            <pubDate>\(dateText)</pubDate>
            <enclosure url="https://example.com/ep.mp3" type="audio/mpeg"/>
          </item>
        </channel></rss>
        """
        let parser = RSSFeedParser()
        let podcast = try #require(parser.parse(data: Data(xml.utf8)))
        let episode = try #require(podcast.episodes.first)
        #expect(episode.publishDate == Date.distantPast)
    }

    @Test("A video-only enclosure is captured as videoURL, with no audioURL, and the episode is not skipped")
    func capturesVideoOnlyEnclosure() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0"><channel>
          <title>Video Show</title>
          <item>
            <title>Video Only Episode</title>
            <guid>video-only</guid>
            <pubDate>Mon, 03 Aug 2026 10:00:00 GMT</pubDate>
            <enclosure url="https://example.com/ep.mp4" type="video/mp4" length="789"/>
          </item>
        </channel></rss>
        """
        let parser = RSSFeedParser()
        let podcast = try #require(parser.parse(data: Data(xml.utf8)))
        let episode = try #require(podcast.episodes.first)

        #expect(episode.audioURL == nil)
        #expect(episode.videoURL == "https://example.com/ep.mp4")
    }

    @Test("An item with both audio and video enclosures captures both URLs")
    func capturesMixedAudioAndVideoEnclosures() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0" xmlns:media="http://search.yahoo.com/mrss/"><channel>
          <title>Mixed Show</title>
          <item>
            <title>Mixed Episode</title>
            <guid>mixed</guid>
            <pubDate>Mon, 03 Aug 2026 10:00:00 GMT</pubDate>
            <enclosure url="https://example.com/ep-audio.mp3" type="audio/mpeg"/>
            <media:content url="https://example.com/ep-video.mp4" medium="video"/>
          </item>
        </channel></rss>
        """
        let parser = RSSFeedParser()
        let podcast = try #require(parser.parse(data: Data(xml.utf8)))
        let episode = try #require(podcast.episodes.first)

        #expect(episode.audioURL == "https://example.com/ep-audio.mp3")
        #expect(episode.videoURL == "https://example.com/ep-video.mp4")
        // The plain <enclosure> is audio, media:content is the extra - audio is the default.
        #expect(episode.defaultMediaKind == .audio)
    }

    @Test("When the main enclosure is video and media:content supplies audio, video is the default")
    func mainEnclosureVideoTakesPrecedenceOverMediaContentAudio() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0" xmlns:media="http://search.yahoo.com/mrss/"><channel>
          <title>Video-First Show</title>
          <item>
            <title>Video-First Episode</title>
            <guid>video-first</guid>
            <pubDate>Mon, 03 Aug 2026 10:00:00 GMT</pubDate>
            <enclosure url="https://example.com/ep-video.mp4" type="video/mp4"/>
            <media:content url="https://example.com/ep-audio.mp3" medium="audio"/>
          </item>
        </channel></rss>
        """
        let parser = RSSFeedParser()
        let podcast = try #require(parser.parse(data: Data(xml.utf8)))
        let episode = try #require(podcast.episodes.first)

        #expect(episode.audioURL == "https://example.com/ep-audio.mp3")
        #expect(episode.videoURL == "https://example.com/ep-video.mp4")
        #expect(episode.defaultMediaKind == .video)
    }

    @Test("When the main enclosure is audio and alternateEnclosure supplies video, audio is the default")
    func mainEnclosureAudioTakesPrecedenceOverAlternateVideo() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0" xmlns:podcast="https://podcastindex.org/namespace/1.0"><channel>
          <title>Audio-First Show</title>
          <item>
            <title>Audio-First Episode</title>
            <guid>audio-first</guid>
            <pubDate>Mon, 03 Aug 2026 10:00:00 GMT</pubDate>
            <enclosure url="https://example.com/ep-audio.mp3" type="audio/mpeg"/>
            <podcast:alternateEnclosure type="video/mp4">
              <podcast:source uri="https://example.com/ep-video.mp4"/>
            </podcast:alternateEnclosure>
          </item>
        </channel></rss>
        """
        let parser = RSSFeedParser()
        let podcast = try #require(parser.parse(data: Data(xml.utf8)))
        let episode = try #require(podcast.episodes.first)

        #expect(episode.defaultMediaKind == .audio)
    }

    @Test("When the main enclosure is video and alternateEnclosure supplies audio, video is the default")
    func mainEnclosureVideoTakesPrecedenceOverAlternateAudio() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0" xmlns:podcast="https://podcastindex.org/namespace/1.0"><channel>
          <title>Video-First Show</title>
          <item>
            <title>Video-First Episode</title>
            <guid>video-first-alt</guid>
            <pubDate>Mon, 03 Aug 2026 10:00:00 GMT</pubDate>
            <enclosure url="https://example.com/ep-video.mp4" type="video/mp4"/>
            <podcast:alternateEnclosure type="audio/mpeg">
              <podcast:source uri="https://example.com/ep-audio.mp3"/>
            </podcast:alternateEnclosure>
          </item>
        </channel></rss>
        """
        let parser = RSSFeedParser()
        let podcast = try #require(parser.parse(data: Data(xml.utf8)))
        let episode = try #require(podcast.episodes.first)

        #expect(episode.audioURL == "https://example.com/ep-audio.mp3")
        #expect(episode.videoURL == "https://example.com/ep-video.mp4")
        #expect(episode.defaultMediaKind == .video)
    }

    @Test("A video-only episode defaults to video, with no main enclosure to consult")
    func videoOnlyEpisodeDefaultsToVideo() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0"><channel>
          <title>Video Show</title>
          <item>
            <title>Video Only</title>
            <guid>video-only-default</guid>
            <pubDate>Mon, 03 Aug 2026 10:00:00 GMT</pubDate>
            <enclosure url="https://example.com/ep.mp4" type="video/mp4"/>
          </item>
        </channel></rss>
        """
        let parser = RSSFeedParser()
        let podcast = try #require(parser.parse(data: Data(xml.utf8)))
        let episode = try #require(podcast.episodes.first)

        #expect(episode.defaultMediaKind == .video)
    }

    @Test("A podcast:alternateEnclosure video variant's podcast:source uri is captured as videoURL")
    func capturesVideoFromAlternateEnclosure() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0" xmlns:podcast="https://podcastindex.org/namespace/1.0"><channel>
          <title>Alt Enclosure Show</title>
          <item>
            <title>Episode With Video Alternate</title>
            <guid>alt-video</guid>
            <pubDate>Mon, 03 Aug 2026 10:00:00 GMT</pubDate>
            <enclosure url="https://example.com/ep-audio.mp3" type="audio/mpeg"/>
            <podcast:alternateEnclosure type="video/mp4" length="123456">
              <podcast:source uri="https://example.com/ep-video.mp4"/>
            </podcast:alternateEnclosure>
          </item>
        </channel></rss>
        """
        let parser = RSSFeedParser()
        let podcast = try #require(parser.parse(data: Data(xml.utf8)))
        let episode = try #require(podcast.episodes.first)

        #expect(episode.audioURL == "https://example.com/ep-audio.mp3")
        #expect(episode.videoURL == "https://example.com/ep-video.mp4")
    }

    @Test("An HLS podcast:alternateEnclosure (application/x-mpegURL) is skipped, not captured as videoURL")
    func skipsHLSAlternateEnclosure() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0" xmlns:podcast="https://podcastindex.org/namespace/1.0"><channel>
          <title>HLS Show</title>
          <item>
            <title>Episode With HLS Alternate</title>
            <guid>alt-hls</guid>
            <pubDate>Mon, 03 Aug 2026 10:00:00 GMT</pubDate>
            <enclosure url="https://example.com/ep-audio.mp3" type="audio/mpeg"/>
            <podcast:alternateEnclosure type="application/x-mpegURL" length="0">
              <podcast:source uri="https://example.com/ep.m3u8"/>
            </podcast:alternateEnclosure>
          </item>
        </channel></rss>
        """
        let parser = RSSFeedParser()
        let podcast = try #require(parser.parse(data: Data(xml.utf8)))
        let episode = try #require(podcast.episodes.first)

        #expect(episode.audioURL == "https://example.com/ep-audio.mp3")
        #expect(episode.videoURL == nil)
    }

    @Test("Only the first podcast:source uri within an alternateEnclosure block is used")
    func usesFirstSourceInAlternateEnclosure() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0" xmlns:podcast="https://podcastindex.org/namespace/1.0"><channel>
          <title>Multi Source Show</title>
          <item>
            <title>Episode With Multiple Sources</title>
            <guid>multi-source</guid>
            <pubDate>Mon, 03 Aug 2026 10:00:00 GMT</pubDate>
            <podcast:alternateEnclosure type="video/mp4" length="123456">
              <podcast:source uri="https://example.com/primary.mp4"/>
              <podcast:source uri="ipfs://someRandomVideoFile"/>
            </podcast:alternateEnclosure>
          </item>
        </channel></rss>
        """
        let parser = RSSFeedParser()
        let podcast = try #require(parser.parse(data: Data(xml.utf8)))
        let episode = try #require(podcast.episodes.first)

        #expect(episode.videoURL == "https://example.com/primary.mp4")
    }

    @Test(
        "RFC 822 date formats with named and numeric time zones all parse",
        arguments: [
            "Mon, 03 Aug 2026 10:00:00 GMT",
            "Mon, 03 Aug 2026 10:00:00 +0000",
            "3 Aug 2026 10:00:00 +0000",
        ]
    )
    func parsesVarietyOfDateFormats(dateText: String) throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0"><channel>
          <title>Dates</title>
          <item>
            <title>Episode</title>
            <guid>d1</guid>
            <pubDate>\(dateText)</pubDate>
            <enclosure url="https://example.com/ep.mp3" type="audio/mpeg"/>
          </item>
        </channel></rss>
        """
        let parser = RSSFeedParser()
        let podcast = try #require(parser.parse(data: Data(xml.utf8)))
        let episode = try #require(podcast.episodes.first)
        #expect(episode.publishDate != Date.distantPast)
    }
}

@Suite("HTML entity decoding")
struct HTMLEntityDecodingTests {
    @Test(
        "Decodes common entities",
        arguments: [
            ("Rock &amp; Roll", "Rock & Roll"),
            ("It&apos;s here", "It's here"),
            ("Quote: &quot;hi&quot;", "Quote: \"hi\""),
            ("A &lt;tag&gt; example", "A <tag> example"),
            ("No entities here", "No entities here"),
        ]
    )
    func decodesEntities(input: String, expected: String) {
        #expect(input.decodingBasicHTMLEntities() == expected)
    }
}
