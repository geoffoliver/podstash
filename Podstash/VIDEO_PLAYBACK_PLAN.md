# Video Playback — Implementation Plan

Status: Phases 1-5 complete. Built with TDD per `CLAUDE.md` — every
phase below starts with tests.

## Goal

Support video podcast episodes. macOS: video opens in its own window with
standard QuickTime/iTunes-style transport controls. iOS: video plays inline
in the Now Playing view, with a fullscreen in/out toggle. Audio-only feeds
are unaffected.

## Current state (why this is additive, not a rewrite)

- `Episode` (Models.swift) stores only `audioURL`. It is **not**
  CloudKit-mirrored — every device re-derives it from RSS independently, so
  new fields here don't need sync design.
- `RSSFeedParser.swift` enclosure handling already filters to
  `type.contains("audio")` (line ~148-151) — video enclosures are currently
  parsed and silently discarded.
- `AudioPlayerManager` wraps a single `AVPlayer` with no visual output
  (headless by design — MediaPlayer/remote-command/lock-screen integration
  is solid and stays as-is).
- `NowPlayingView.swift` / `CompactPlayerBar` are audio-shaped: artwork
  square, no video surface.
- macOS already has a pattern for a standalone player window:
  `MiniPlayerWindowController` (MiniPlayerWindow.swift) — an
  `NSWindowController` hosting a SwiftUI view via `NSHostingView`. The video
  window follows the same shape, swapping in AppKit's `AVPlayerView`
  instead of hand-rolled controls.
- Episode artwork is currently rendered ad hoc via `CachedAsyncImage` in
  five separate places: `PodcastDetailView.swift`, `QueueView.swift`,
  `NowPlayingView.swift`, `MiniPlayerWindow.swift`, `ContentView.swift`.
  No shared thumbnail component exists yet.

## Governing rule (applies to every phase below)

**Which enclosure is loaded — audio or video — only ever changes on an
explicit user action.** Foreground/background transitions, window
open/close, and app lifecycle events never switch media kind on their own.
The one thing they're allowed to do (iOS backgrounding) is toggle whether
the *video track of the currently-loaded video item* is decoding — see
Phase 5. This distinction matters enough that it shaped the design below,
so it's called out here rather than buried in one phase.

## Phase 1 — Data model & feed parsing

- `Episode`: add `var videoURL: String?` and `var mediaKind: MediaKind`
  (enum: `.audio`, `.video`), defaulting `.audio` for migration safety.
- `RSSFeedParser.swift`: stop discarding non-audio enclosures — capture
  `type="video/*"` enclosures into `videoURL`/`mediaKind`, same for
  `<media:content medium="video">`. When a feed item has both an audio and
  a video enclosure, store both; `mediaKind` reflects the default (audio
  wins by default — see Phase 4).
- `RSSFeedParserTests.swift`: add fixtures/tests for video-only enclosures,
  audio-only (existing/unchanged behavior), and mixed audio+video items.
- No CloudKit or `PlaybackRecord` changes needed — `PlaybackRecord` stays
  flat (position/played/queue); media availability is a property of
  `Episode`, which every device resolves from the feed itself.

## Phase 2 — Playback core

- `AudioPlayerManager.play(episode:)`: loads the *default* enclosure for
  the episode (audio, if present; video otherwise — see Phase 4). Same
  local-download-first resolution `localFileURL(for:)` already does,
  applied per-URL.
- New `AudioPlayerManager.switchMediaKind(to:)`: tears down the current
  `AVPlayerItem` and loads the other enclosure's URL, re-seeking to the
  current `progress.currentTime` (seconds carried over as-is, not
  proportionally — video and audio cuts of the same episode are not
  expected to be the same length) and preserving play/pause state and
  playback rate. This is the *only* thing allowed to change which
  enclosure is loaded, and it is only ever called from a user action (the
  iOS Audio/Video toggle, or the macOS flow in Phase 3).
- Expose the underlying `AVPlayer` read-only (or a small
  `AVPlayerLayer`-vending accessor) for video-surface views to attach to,
  without breaking the "headless, no re-render on tick" design — progress
  ticking, remote commands, and Now Playing info stay exactly as they are.
- Track-enable API: a method to enable/disable the video
  `AVPlayerItemTrack` on the current item without reloading it (used by
  Phase 5's background handling — cheaper than a full item swap or track
  reload).
- Consider whether `MPNowPlayingInfoPropertyMediaType` should be set for
  video items (helps Control Center present the right chrome).

## Phase 3 — Shared episode thumbnail component

- New `EpisodeThumbnail` view wrapping the existing `CachedAsyncImage`
  pattern, taking an `Episode` and a size. Renders the artwork, and when
  `episode.mediaKind == .video`, overlays the SF Symbol `"video"` at the
  bottom-right corner.
- Replace the five ad hoc `CachedAsyncImage` call sites (`PodcastDetailView`,
  `QueueView`, `NowPlayingView`, `MiniPlayerWindow`, `ContentView`) with
  `EpisodeThumbnail`. Pure refactor for the audio-only case (visual output
  unchanged), and the one place the video badge needs to land.
- Doing this as its own phase (rather than folding it into Phase 1 or 4)
  because it's a good, small, TDD-able unit — mostly view-layer, testable
  via the existing snapshot/preview conventions if any, otherwise a quick
  manual check across all five sites — and it unblocks the badge before
  the bigger UI phases land.

## Phase 4 — macOS: video window

- New `VideoPlayerWindowController` (mirrors `MiniPlayerWindowController`'s
  shape): standard resizable/titled `NSWindow` hosting an `AVPlayerView`
  (AppKit) bound to `AudioPlayerManager`'s player. `AVPlayerView` supplies
  the QuickTime-style transport bar, volume, scrubbing, and fullscreen for
  free — no custom controls to build here.
  - `AVPlayerView.controlsStyle = .floating` (or `.inline`), plus
    `AVPlayerView.actionPopUpButtonMenu` if per-episode actions
    (playback speed, AirPlay) are wanted, matching what `NowPlayingView`
    already exposes for audio.
- New button in the (macOS) playback controls: "Open Video" — visible
  whenever the current episode has a video enclosure and the window isn't
  already open. Calls `switchMediaKind(.video)` and opens the window. The
  main window is *not* hidden when the video window opens (unlike the mini
  player) — this is closer to a QuickTime/iTunes video window than a
  companion mini player.
- **Default on play**: pressing Play on an episode with both enclosures
  defaults to audio (no window). Pressing Play on a video-only episode
  (no audio enclosure) opens the video window immediately, since there's
  nothing to fall back to.
- **Closing the video window stops playback entirely** — both video and
  audio pause. This is a deliberate divergence from "keep playing in the
  background" (that's an iOS-only behavior — see Phase 5): on macOS,
  closing the window is a clear, visible user action to stop watching, not
  an ambient backgrounding event.
- **Resuming after a close**: pressing Play again on that episode —
  - If an audio enclosure exists, resumes as audio (`switchMediaKind(.audio)`
    implicitly, since mediaKind was left at `.video` when the window
    closed) from the carried-over position. The user has to click "Open
    Video" again to bring the window back.
  - If no audio enclosure exists (video-only), resumes by reopening the
    video window directly, since audio isn't an option.
  - Implementation-wise, "close window" = pause + (if audio available)
    `switchMediaKind(.audio)`; "no audio available" = plain pause, media
    kind stays `.video`, so the next Play naturally reopens the window.

## Phase 5 — iOS: inline + fullscreen + background behavior

- `NowPlayingView.swift`: branch on `episode.mediaKind`. For video, replace
  the 250×250 artwork square with a video surface — either SwiftUI's
  `VideoPlayer(player:)` (simplest, but has its own chrome you'd need to
  suppress since transport controls already exist below it) or a thin
  `UIViewRepresentable` around `AVPlayerLayer` (more control, matches the
  existing custom scrubber/controls stack). Leaning toward the
  `AVPlayerLayer` wrapper given the existing custom controls.
- **Audio/Video toggle**: a segmented control labeled "Audio" / "Video",
  styled like the existing Filter buttons on the podcast detail view.
  Visible whenever the episode has a video enclosure at all — including a
  video-only episode with no separate audio enclosure. What selecting a
  segment *does* depends on whether there's actually something to switch
  to (see `VideoDisplayPolicy`):
  - Mixed episode (both enclosures exist): a real source switch, same as
    always — calls `switchMediaKind(to:)` (Phase 2), position carries over.
  - Video-only episode: "Audio" has nothing to switch to, so it just hides
    the video frame (falling back to episode artwork) while the same video
    item keeps playing — no `switchMediaKind()` call, no seek. Matches
    Apple Podcasts' behavior and gives users an "audio-only" affordance
    even though, mechanically, they could get the same result by just not
    looking at the screen. Also disables the video `AVPlayerItemTrack`
    (same mechanism as the background-behavior bullet below) since there's
    no reason to keep decoding frames nobody's displaying.
- **Fullscreen toggle**: present `AVPlayerViewController` modally
  (`UIViewControllerRepresentable` + `.fullScreenCover`, or push via
  `UIHostingController`), or drive fullscreen via
  `AVPlayerViewController.entersFullScreenWhenPlaybackBegins`-style APIs.
  Exiting returns to the inline `NowPlayingView` surface.
- **Background behavior**: when the app backgrounds, or the user swipes
  away/dismisses the Now Playing view, playback continues uninterrupted —
  the audio track of the currently-loaded video item keeps playing. This
  is *not* a media-kind switch (no `switchMediaKind()` call, no seek, no
  change to what's loaded) — it's disabling the video `AVPlayerItemTrack`
  via the Phase 2 track-enable API while backgrounded, and re-enabling it
  when the app foregrounds / Now Playing reopens. Chosen over "just leave
  video decoding invisibly" to save battery.
- `CompactPlayerBar`: thumbnail switches to `EpisodeThumbnail` (Phase 3);
  otherwise no change, since it already just shows an image.

## Phase 6 — Downloads: Wi-Fi-only for video

- `AppSettings`: add `downloadVideoOnWiFiOnly: Bool` (default `true`),
  following the exact existing pattern of `refreshOnlyOnWiFi`.
- `DownloadManager`: gate video-enclosure downloads on this setting the
  same way feed refresh is gated on `refreshOnlyOnWiFi` (needs a look at
  `DownloadManager`'s current network-reachability check to confirm the
  exact hook point before writing tests).
- Settings UI: toggle placed near the existing Wi-Fi-only setting.

## Suggested sequencing

1. Phase 1 (data + parsing) — small, testable in isolation, unlocks
   everything else.
2. Phase 2 (playback core) — `switchMediaKind()` and the track-enable API
   are the two pieces of new logic every later phase depends on.
3. Phase 3 (shared thumbnail) — small, mostly mechanical, good early win.
4. Phase 4 (macOS window) — cheapest UI phase, `AVPlayerView` does the
   heavy lifting; the close/reopen state machine is the only real logic.
5. Phase 5 (iOS inline/fullscreen/background) — the real design/UX time
   sink, and depends on Phase 2's track-enable API.
6. Phase 6 (Wi-Fi-only downloads) — independent of the rest, can slot in
   whenever.

## Out of scope for v1

- CarPlay video (CarPlay is audio/now-playing-template only; separate
  TODO item, unaffected by this work).
- Picture-in-picture.
- Video-specific download quality/resolution selection (single enclosure
  URL per episode, same as audio today).
