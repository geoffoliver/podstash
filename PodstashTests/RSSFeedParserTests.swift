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
