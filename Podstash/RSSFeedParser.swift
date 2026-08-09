//
//  RSSFeedParser.swift
//  Podstash
//
//  Created by Geoff Oliver on 7/30/26.
//

import Foundation

struct ParsedPodcast {
    let title: String
    let description: String?
    let artworkURL: String?
    let author: String?
    let websiteURL: String?
    let episodes: [ParsedEpisode]
}

struct ParsedEpisode {
    let title: String
    let description: String?
    let audioURL: String
    let guid: String?
    let duration: TimeInterval?
    let publishDate: Date
    let artworkURL: String?
}

class RSSFeedParser: NSObject, XMLParserDelegate {
    private var parser: XMLParser?
    private var currentElement = ""
    private var currentText = ""
    
    // Podcast metadata
    private var podcastTitle = ""
    private var podcastDescription: String?
    private var podcastArtworkURL: String?
    private var podcastAuthor: String?
    private var podcastWebsiteURL: String?
    
    // Episode data
    private var episodes: [ParsedEpisode] = []
    private var currentEpisodeTitle = ""
    private var currentEpisodeDescription: String?
    private var currentEpisodeAudioURL: String?
    private var currentEpisodeGUID: String?
    private var currentEpisodeDuration: TimeInterval?
    private var currentEpisodePublishDate: Date?
    private var currentEpisodeArtworkURL: String?
    
    private var isInItem = false
    private var isInChannel = false
    
    // Safety valve against pathological/malformed feeds - real feeds won't hit this
    private let maxEpisodesToParse = 5000
    private var didAbortIntentionally = false
    
    // Real-world feeds don't all follow RFC 822 to the letter - some use a named timezone
    // (GMT/EST/PST) instead of a numeric offset, some omit the leading zero on single-digit
    // days, and some (particularly feeds re-exported from Atom) use ISO 8601 in pubDate. Tried
    // in order; the first formatter that parses the string wins.
    private static let rfc822DateFormats = [
        "EEE, dd MMM yyyy HH:mm:ss Z",
        "EEE, dd MMM yyyy HH:mm:ss zzz",
        "EEE, d MMM yyyy HH:mm:ss Z",
        "EEE, d MMM yyyy HH:mm:ss zzz",
        "dd MMM yyyy HH:mm:ss Z",
        "d MMM yyyy HH:mm:ss Z",
    ]

    private let dateFormatters: [DateFormatter] = RSSFeedParser.rfc822DateFormats.map { format in
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        return formatter
    }

    private let isoDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private let isoDateFormatterNoFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// Returns nil, rather than "now", when the string doesn't match any known format - a
    /// silent "now" fallback previously made unparseable-but-old episodes sort as the newest
    /// thing in the feed and get swept up by auto-download.
    private func parsePublishDate(_ text: String) -> Date? {
        for formatter in dateFormatters {
            if let date = formatter.date(from: text) {
                return date
            }
        }
        return isoDateFormatter.date(from: text) ?? isoDateFormatterNoFractionalSeconds.date(from: text)
    }
    
    func parse(data: Data) -> ParsedPodcast? {
        parser = XMLParser(data: data)
        parser?.delegate = self
        didAbortIntentionally = false
        
        let parseSucceeded = parser?.parse() ?? false
        
        // If we aborted intentionally, that's actually a success
        guard parseSucceeded || didAbortIntentionally else {
            return nil
        }
        
        return ParsedPodcast(
            title: podcastTitle.isEmpty ? "Untitled Podcast" : podcastTitle,
            description: podcastDescription,
            artworkURL: podcastArtworkURL,
            author: podcastAuthor,
            websiteURL: podcastWebsiteURL,
            episodes: episodes
        )
    }
    
    // MARK: - XMLParserDelegate
    
    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName
        currentText = ""
        
        switch elementName {
        case "channel":
            isInChannel = true
        case "item":
            isInItem = true
            // Reset episode data
            currentEpisodeTitle = ""
            currentEpisodeDescription = nil
            currentEpisodeAudioURL = nil
            currentEpisodeGUID = nil
            currentEpisodeDuration = nil
            currentEpisodePublishDate = nil
            currentEpisodeArtworkURL = nil
            
        case "enclosure":
            // Audio file URL is in the enclosure tag
            if isInItem, let url = attributeDict["url"], let type = attributeDict["type"],
               type.contains("audio") {
                currentEpisodeAudioURL = url
            }
            
        case "itunes:image":
            // iTunes artwork
            if let href = attributeDict["href"] {
                if isInItem {
                    currentEpisodeArtworkURL = href
                } else if isInChannel {
                    podcastArtworkURL = href
                }
            }
            
        case "media:content":
            // Some feeds use media:content for audio
            if isInItem, let url = attributeDict["url"], let medium = attributeDict["medium"],
               medium == "audio" {
                currentEpisodeAudioURL = url
            }
            
        default:
            break
        }
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }
    
    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        let trimmedText = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if isInItem {
            // Parsing episode data
            switch elementName {
            case "item":
                // Episode complete, save it
                if let audioURL = currentEpisodeAudioURL,
                   !currentEpisodeTitle.isEmpty,
                   let publishDate = currentEpisodePublishDate {
                    let episode = ParsedEpisode(
                        title: currentEpisodeTitle,
                        description: currentEpisodeDescription,
                        audioURL: audioURL,
                        guid: currentEpisodeGUID,
                        duration: currentEpisodeDuration,
                        publishDate: publishDate,
                        artworkURL: currentEpisodeArtworkURL
                    )
                    episodes.append(episode)
                    
                    // Stop parsing if we've hit the limit
                    if episodes.count >= maxEpisodesToParse {
                        didAbortIntentionally = true
                        parser.abortParsing()
                    }
                }
                isInItem = false
                
            case "title":
                currentEpisodeTitle = trimmedText.decodingBasicHTMLEntities()
                
            case "description", "itunes:summary", "content:encoded":
                if currentEpisodeDescription == nil || elementName == "content:encoded" {
                    // Keep raw HTML/text - we'll render it in the UI
                    currentEpisodeDescription = trimmedText
                }
                
            case "guid":
                if !trimmedText.isEmpty {
                    currentEpisodeGUID = trimmedText
                }

            case "pubDate":
                // Fall back to distantPast (not "now") for a date we can't parse, so a
                // genuinely old episode with a malformed date never sorts as the newest thing
                // in the feed and gets picked up by auto-download.
                currentEpisodePublishDate = parsePublishDate(trimmedText) ?? Date.distantPast
                
            case "itunes:duration":
                currentEpisodeDuration = parseDuration(trimmedText)
                
            default:
                break
            }
        } else if isInChannel {
            // Parsing podcast metadata
            switch elementName {
            case "channel":
                isInChannel = false
                
            case "title":
                if podcastTitle.isEmpty {
                    podcastTitle = trimmedText.decodingBasicHTMLEntities()
                }
                
            case "description", "itunes:summary":
                if podcastDescription == nil {
                    // Keep raw HTML/text - we'll render it in the UI
                    podcastDescription = trimmedText
                }
                
            case "itunes:author", "author":
                if podcastAuthor == nil {
                    podcastAuthor = trimmedText
                }
                
            case "link":
                if podcastWebsiteURL == nil {
                    podcastWebsiteURL = trimmedText
                }
                
            default:
                break
            }
        }
        
        currentText = ""
    }
    
    // MARK: - Helper Methods
    
    private func parseDuration(_ durationString: String) -> TimeInterval? {
        let components = durationString.components(separatedBy: ":")
        
        if components.count == 3 {
            // HH:MM:SS
            guard let hours = Double(components[0]),
                  let minutes = Double(components[1]),
                  let seconds = Double(components[2]) else {
                return nil
            }
            return hours * 3600 + minutes * 60 + seconds
        } else if components.count == 2 {
            // MM:SS
            guard let minutes = Double(components[0]),
                  let seconds = Double(components[1]) else {
                return nil
            }
            return minutes * 60 + seconds
        } else if components.count == 1 {
            // Just seconds
            return Double(durationString)
        }
        
        return nil
    }
}

// MARK: - String Extension

extension String {
    /// Decode only the most common HTML entities for titles and plain text
    /// No regex, no complex parsing - just simple string replacement
    func decodingBasicHTMLEntities() -> String {
        // Quick check: if there are no entities, skip all the work
        guard self.contains("&") else {
            return self
        }
        
        var result = self
        
        // Most common entities - do these in order of likelihood
        result = result.replacingOccurrences(of: "&amp;", with: "&")
        result = result.replacingOccurrences(of: "&apos;", with: "'")
        result = result.replacingOccurrences(of: "&#39;", with: "'")
        result = result.replacingOccurrences(of: "&quot;", with: "\"")
        result = result.replacingOccurrences(of: "&lt;", with: "<")
        result = result.replacingOccurrences(of: "&gt;", with: ">")
        result = result.replacingOccurrences(of: "&nbsp;", with: " ")
        result = result.replacingOccurrences(of: "&ndash;", with: "–")
        result = result.replacingOccurrences(of: "&mdash;", with: "—")
        result = result.replacingOccurrences(of: "&rsquo;", with: "'")
        result = result.replacingOccurrences(of: "&lsquo;", with: "'")
        result = result.replacingOccurrences(of: "&rdquo;", with: "\"")
        result = result.replacingOccurrences(of: "&ldquo;", with: "\"")
        
        // That's it! No regex, no complex parsing.
        // If there are weird numeric entities in titles, tough luck.
        // Descriptions will be rendered as HTML anyway.
        
        return result
    }

    /// Escape the characters XML attribute values can't contain literally, for writing out
    /// (the inverse of `decodingBasicHTMLEntities()` above, restricted to what's required for
    /// well-formed XML rather than the full HTML entity set).
    func escapingForXMLAttribute() -> String {
        var result = self
        result = result.replacingOccurrences(of: "&", with: "&amp;")
        result = result.replacingOccurrences(of: "\"", with: "&quot;")
        result = result.replacingOccurrences(of: "'", with: "&apos;")
        result = result.replacingOccurrences(of: "<", with: "&lt;")
        result = result.replacingOccurrences(of: ">", with: "&gt;")
        return result
    }
}
