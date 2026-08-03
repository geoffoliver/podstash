//
//  Models.swift
//  Podstash
//
//  Created by Geoff Oliver on 7/30/26.
//

import Foundation
import SwiftData

@Model
final class Podcast {
    // CloudKit mirroring requires every non-optional property to carry a default value on
    // the declaration itself (an init parameter default isn't enough), and to-one
    // relationships to be optional - see Episode.podcast below.
    var id: UUID = UUID()
    var title: String = ""
    var feedURL: String = ""
    var websiteURL: String?
    var podcastDescription: String?
    var artworkURL: String?
    var author: String?
    var subscriptionDate: Date = Date()
    var lastUpdated: Date?
    
    // CloudKit mirroring requires relationships to be Optional even when they're to-many, so
    // the actual persisted relationship is `episodesStorage`; `episodes` below is a plain
    // computed convenience wrapper so every existing call site can keep treating it as a
    // non-optional array.
    @Relationship(deleteRule: .cascade, inverse: \Episode.podcast)
    var episodesStorage: [Episode]? = []

    var episodes: [Episode] {
        get { episodesStorage ?? [] }
        set { episodesStorage = newValue }
    }
    
    init(
        id: UUID = UUID(),
        title: String,
        feedURL: String,
        websiteURL: String? = nil,
        podcastDescription: String? = nil,
        artworkURL: String? = nil,
        author: String? = nil,
        subscriptionDate: Date = Date(),
        lastUpdated: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.feedURL = feedURL
        self.websiteURL = websiteURL
        self.podcastDescription = podcastDescription
        self.artworkURL = artworkURL
        self.author = author
        self.subscriptionDate = subscriptionDate
        self.lastUpdated = lastUpdated
    }
}

@Model
final class Episode {
    var id: UUID = UUID()
    var title: String = ""
    var episodeDescription: String?
    var audioURL: String = ""
    // RSS <guid> - the feed's own stable identifier for this item, used (in preference to
    // audioURL) to recognize an episode across refreshes. Nil for episodes stored before this
    // field existed, or for feeds that omit guid; those fall back to matching by audioURL.
    var guid: String?
    var duration: TimeInterval?
    var publishDate: Date = Date()
    var artworkURL: String?
    var isPlayed: Bool = false
    var playbackPosition: TimeInterval = 0
    var lastPlayedDate: Date?  // Track when user last played this episode
    var isDownloaded: Bool = false  // For future offline support
    // Filename only (e.g. "<episode-id>.mp3"), not an absolute path - resolved to this
    // device's local Downloads folder via DownloadManager.localFileURL(forStoredFilename:).
    // Since this field syncs via iCloud, an absolute path from another device's container
    // would be meaningless here; the filename is deterministic (derived from episode.id) so
    // every device resolves it the same way once it has the file.
    var downloadedFilename: String?
    var queuePosition: Int?  // Position in queue, nil if not in queue
    
    var podcast: Podcast?
    
    init(
        id: UUID = UUID(),
        title: String,
        episodeDescription: String? = nil,
        audioURL: String,
        guid: String? = nil,
        duration: TimeInterval? = nil,
        publishDate: Date,
        artworkURL: String? = nil,
        isPlayed: Bool = false,
        playbackPosition: TimeInterval = 0,
        lastPlayedDate: Date? = nil,
        isDownloaded: Bool = false,
        downloadedFilename: String? = nil,
        queuePosition: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.episodeDescription = episodeDescription
        self.audioURL = audioURL
        self.guid = guid
        self.duration = duration
        self.publishDate = publishDate
        self.artworkURL = artworkURL
        self.isPlayed = isPlayed
        self.playbackPosition = playbackPosition
        self.lastPlayedDate = lastPlayedDate
        self.isDownloaded = isDownloaded
        self.downloadedFilename = downloadedFilename
        self.queuePosition = queuePosition
    }
}
