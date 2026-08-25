//
//  Models.swift
//  Podstash
//
//  Created by Geoff Oliver on 7/30/26.
//

import Foundation
import SwiftData

// CloudKit-mirrored (see PodstashApp.sharedModelContainer for the configuration split).
@Model
final class Podcast {
    // CloudKit mirroring requires every non-optional property to carry a default value on
    // the declaration itself (an init parameter default isn't enough).
    var id: UUID = UUID()
    var title: String = ""
    var feedURL: String = ""
    var websiteURL: String?
    var podcastDescription: String?
    var artworkURL: String?
    var author: String?
    var subscriptionDate: Date = Date()
    var lastUpdated: Date?

    // The newest `publishDate` this device has ever observed for this feed, advanced on every
    // refresh to max(existing, every parsed item's publishDate) - regardless of whether any
    // item ends up auto-downloaded. Gates FeedFetcher's auto-download/auto-queue eligibility:
    // an item at or before this date never triggers auto-download, even if its local Episode
    // row doesn't exist yet (e.g. retention cleanup deleted it, or this is a fresh install) -
    // that's what makes it safe to never resurrect an already-handled episode as "new" without
    // needing a tombstone table.
    var newestKnownPublishDate: Date?

    // The newest `publishDate` among episodes marked played in this feed, advanced monotonically
    // via UnplayedEligibilityPolicy.advancedMostRecentlyPlayedDate whenever an episode is marked
    // played (marking one unplayed again does not roll this back). Combined with
    // `newestKnownPublishDate`, this is what lets UnplayedEligibilityPolicy decide whether a
    // non-downloaded episode counts as "unplayed" without scanning every PlaybackRecord in the
    // feed: nil means nothing in the feed has ever been played.
    var mostRecentlyPlayedDate: Date?

    init(
        id: UUID = UUID(),
        title: String,
        feedURL: String,
        websiteURL: String? = nil,
        podcastDescription: String? = nil,
        artworkURL: String? = nil,
        author: String? = nil,
        subscriptionDate: Date = Date(),
        lastUpdated: Date? = nil,
        newestKnownPublishDate: Date? = nil,
        mostRecentlyPlayedDate: Date? = nil
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
        self.newestKnownPublishDate = newestKnownPublishDate
        self.mostRecentlyPlayedDate = mostRecentlyPlayedDate
    }
}

// Which enclosure an Episode with both audio and video should play by default. Resolved once at
// parse time (see RSSFeedParser) from whichever medium the feed's actual <enclosure> tag
// declared - not a user preference, and not re-derived later. A user-initiated switch (Phase 4/5
// of VIDEO_PLAYBACK_PLAN.md) changes what's currently playing, never this stored default.
enum MediaKind: String, Codable {
    case audio
    case video
}

// NOT CloudKit-mirrored - purely local metadata cache, independently derived from RSS by every
// device. Cross-device state (played/position/queue) lives in PlaybackRecord instead, joined by
// `episodeKey`. No relationship to Podcast: a synced model and a local-only model can't be
// linked by a SwiftData relationship across different ModelConfigurations, so `podcastID` is a
// plain scalar and callers fetch/filter Episodes by it instead of walking `podcast.episodes`.
@Model
final class Episode {
    var id: UUID = UUID()
    var title: String = ""
    var episodeDescription: String?
    // Optional - a video-only episode (no audio enclosure at all) has none. At least one of
    // audioURL/videoURL is guaranteed non-nil by the parser (see RSSFeedParser); an episode
    // with neither is never created.
    var audioURL: String?
    // The episode's video enclosure, if the feed offers one (plain <enclosure type="video/*">,
    // <media:content medium="video">, or a non-HLS <podcast:alternateEnclosure> - see
    // RSSFeedParser). HLS variants (application/x-mpegURL) are deliberately never captured here:
    // AVPlayer could stream them, but they're not a single downloadable file, and download
    // support is the only reason this app tracks a URL up front rather than resolving one at
    // play time.
    var videoURL: String?
    // Which of audioURL/videoURL plays by default when both are present - see MediaKind. Set to
    // .audio or .video (never left nil) for every episode this app creates - see the init below.
    //
    // Declared Optional, with no inline default, purely so SwiftData's lightweight migration
    // leaves existing on-disk rows (from before this column existed) as nil rather than crashing:
    // a non-optional enum-typed attribute here made SwiftData's migration backfill the wrong
    // (empty) value for old rows, which then failed to decode as MediaKind at all ("Could not
    // cast value of type 'Optional<Any>' to 'MediaKind'"). A reader without a real signal to
    // consult (nil here means "created before this column existed") should treat nil the same
    // as the init's own fallback: audio if audioURL is set, else video.
    var defaultMediaKind: MediaKind?
    // RSS <guid> - the feed's own stable identifier for this item, used (in preference to
    // audioURL/videoURL) to recognize an episode across refreshes. Nil for feeds that omit guid
    // (rare - Apple's podcast requirements mandate it, and it was present on every item across
    // every feed this app was tested against); those fall back to matching by audioURL/videoURL.
    var guid: String?
    // Stable join key to PlaybackRecord: `guid ?? audioURL ?? videoURL` at creation time, fixed
    // forever - never recomputed even if a guid is later backfilled onto a row originally
    // matched by audioURL/videoURL alone, so an episode never "moves" to a different
    // PlaybackRecord mid-life. Stored as a real field (not a computed property) so it can be
    // used directly in #Predicate equality/`.contains` - SwiftData predicates can't evaluate `??`.
    var episodeKey: String = ""
    var duration: TimeInterval?
    var publishDate: Date = Date()
    var artworkURL: String?
    // Per-device only, deliberately not synced: a downloaded file either exists in this
    // device's Downloads folder or it doesn't. Syncing this used to drive
    // DownloadManager.syncFollowMeDownloads, silently re-downloading gigabytes on every device
    // sharing an iCloud account - dropped entirely.
    var isDownloaded: Bool = false
    // Filename only (e.g. "<episode-id>.mp3"), not an absolute path - resolved to this
    // device's local Downloads folder via DownloadManager.localFileURL(forStoredFilename:).
    var downloadedFilename: String?
    // Plain scalar (see type-level doc comment above) - not a relationship.
    var podcastID: UUID = UUID()

    init(
        id: UUID = UUID(),
        title: String,
        episodeDescription: String? = nil,
        audioURL: String? = nil,
        videoURL: String? = nil,
        defaultMediaKind: MediaKind? = nil,
        guid: String? = nil,
        duration: TimeInterval? = nil,
        publishDate: Date,
        artworkURL: String? = nil,
        isDownloaded: Bool = false,
        downloadedFilename: String? = nil,
        podcastID: UUID
    ) {
        self.id = id
        self.title = title
        self.episodeDescription = episodeDescription
        self.audioURL = audioURL
        self.videoURL = videoURL
        self.defaultMediaKind = defaultMediaKind ?? (audioURL != nil ? .audio : .video)
        self.guid = guid
        self.episodeKey = guid ?? audioURL ?? videoURL ?? ""
        self.duration = duration
        self.publishDate = publishDate
        self.artworkURL = artworkURL
        self.isDownloaded = isDownloaded
        self.downloadedFilename = downloadedFilename
        self.podcastID = podcastID
    }
}

// CloudKit-mirrored. Tiny and flat - no relationships to anything, which structurally rules out
// the relationship-resolution retry storm that corrupted local state before this redesign (see
// PodstashApp.sharedModelContainer). Rows are created lazily, only once the user actually plays,
// queues, or marks an episode (see PlaybackRecordStore.recordForMutation) - an episode with no
// PlaybackRecord row is just isPlayed=false/playbackPosition=0/queuePosition=nil, so an untouched
// library syncs ~nothing.
//
// Not `@Attribute(.unique)` on episodeKey - SwiftData doesn't support unique constraints under
// CloudKit mirroring, so two devices each first-touching the same episode before either's row
// syncs can produce two rows for one key. PlaybackRecordStore.deduplicate(in:) is the periodic
// cleanup for that gap.
@Model
final class PlaybackRecord {
    var episodeKey: String = ""
    var isPlayed: Bool = false
    var playbackPosition: TimeInterval = 0
    var lastPlayedDate: Date?
    var queuePosition: Int?

    init(
        episodeKey: String,
        isPlayed: Bool = false,
        playbackPosition: TimeInterval = 0,
        lastPlayedDate: Date? = nil,
        queuePosition: Int? = nil
    ) {
        self.episodeKey = episodeKey
        self.isPlayed = isPlayed
        self.playbackPosition = playbackPosition
        self.lastPlayedDate = lastPlayedDate
        self.queuePosition = queuePosition
    }
}
