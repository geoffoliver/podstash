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
    var id: UUID
    var title: String
    var feedURL: String
    var websiteURL: String?
    var podcastDescription: String?
    var artworkURL: String?
    var author: String?
    var subscriptionDate: Date
    var lastUpdated: Date?
    
    @Relationship(deleteRule: .cascade, inverse: \Episode.podcast)
    var episodes: [Episode] = []
    
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
    var id: UUID
    var title: String
    var episodeDescription: String?
    var audioURL: String
    var duration: TimeInterval?
    var publishDate: Date
    var artworkURL: String?
    var isPlayed: Bool
    var playbackPosition: TimeInterval
    var lastPlayedDate: Date?  // Track when user last played this episode
    var isDownloaded: Bool  // For future offline support
    var downloadedFileURL: String?  // Local file path if downloaded
    var queuePosition: Int?  // Position in queue, nil if not in queue
    
    var podcast: Podcast?
    
    init(
        id: UUID = UUID(),
        title: String,
        episodeDescription: String? = nil,
        audioURL: String,
        duration: TimeInterval? = nil,
        publishDate: Date,
        artworkURL: String? = nil,
        isPlayed: Bool = false,
        playbackPosition: TimeInterval = 0,
        lastPlayedDate: Date? = nil,
        isDownloaded: Bool = false,
        downloadedFileURL: String? = nil,
        queuePosition: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.episodeDescription = episodeDescription
        self.audioURL = audioURL
        self.duration = duration
        self.publishDate = publishDate
        self.artworkURL = artworkURL
        self.isPlayed = isPlayed
        self.playbackPosition = playbackPosition
        self.lastPlayedDate = lastPlayedDate
        self.isDownloaded = isDownloaded
        self.downloadedFileURL = downloadedFileURL
        self.queuePosition = queuePosition
    }
}
