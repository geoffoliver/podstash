# TODO

- [x] Bug - app downloads episodes even when "auto download" setting is disabled (i.e., the default setting)
- [x] Bug - iOS transport controls only include play/pause - no way to scrub. probably related to missing "now playing" view
  - [x] Bug - iOS "now playing" view -- where is it?
  - [x] Enhancement - iOS, show artwork with bottom controls
- [x] Bug - resorting queue by drag/drop is weird. Sometimes item is placed above when it should be placed below.
- [x] Bug - right clicking in queue and "mark as played" doesn't work if user right clicks to select item and trigger menu immediately.
- [x] Bug - inconsistent row slide controls (mark as played/remove) on iOS and macOS queue views. Make all platforms match - put "mark played" on left, and "delete" on right. Sliding the row far enough should perform the appropriate action ("mark played" or "delete) depending on the direction.
- [x] "Add All Unplayed" in queue adds *ALL* the unplayed items, not just the downloaded unplayed items, which is what it should do


- [x] UI bug (desktop) - User can close main window and there is no way to get it back
- [x] UI bug (desktop) - Right click works, but control+click does not (it should show context menus. it's basic macOS functionality!)
- [x] UI bug - episode detail dialog dropdown button, shortcut for all items appear to be return/enter -- get rid of shortcuts for this menu
- [x] UI bug (desktop) - "Queue" item in sidebar is weird. Click directly on it results in two background colors, one spans full width of sidebar and is not as vibrant/bright, other is correct (not full width, rounded corners) and is very bright blue.
- [x] UI bug (iOS) - "episode detail" sheet, tapping anywhere opens audio file in browser, and that is very weird.
- [x] UI bug (desktop) - "More" button on podcast description  breaks whole view - window and sidebar contents disappear!
- [x] UI bug (desktop) - "Queue" sidebar item is included with "select all" (cmd+a) action, and it should not be.

- [x] Bug - Downloading/re-downloading an episode should mark it as unplayed. Or at the very least give users the ability to mark an episode as unplayed.
- [x] UI bug (desktop) - Sometimes on initial play, progress scrubber is too wide (goes all the way to right edge and probably far outside of it)

- [x] UI enhancement - text is *very* small on macOS and iOS.
- [x] UI enhancement - figure out what "compact list mode" does
- [x] UI enhancement - delay between double clicking and episode actually starting to play. Verify that we are playing local files rather than streaming when local files are available.
- [x] UI enhancement - "cancel" button for feed refreshing is very small. make actual button with "cancel" label
- [x] UI enhancement - "sidebar icon" option should just be "icon option" on iOS, and icon sizes should be larger - use "medium" macOS size for "small" on iOS, "large" macOS size for "medium" on iOS, and then pick a proportional size for "large" on iOS.
- [x] UI enhancement - settings is kind of a mess. for example, "Download _ most recent episode" setting is at top, but should be with "Auto-download..." setting, and also not be enabled/displayed/whatever when the "Auto-download..." option is not enabled. The whole thing needs a bit of a reorgnization and maybe a bit of functionality tweaks.
- [x] UI enhancement - remove number from start of queue items
- [x] UI enhancement - hide iCloud stuff until it can be implemented
- [x] UI enhancement - add Airplay button to Desktop transport controls
- [x] UI enhancement - episode detail dialog needs bottom padding - audio file URL bumps right against edge
- [x] search feature (standard placement (top/right on desktop, bottom on ios))
  - [x] episodes in podcast detail view (always searches "all" tab)
  - [x] queue
- [x] sync - enroll in paid Apple Developer Program, enable CloudKit capability, flip `cloudKitEntitlementsConfigured` in PodstashApp.swift to sync data between devices
- [x] UI enhancement - Change music note icon on "nothing is playing" view. Not sure what, but music note makes no sense because podcasts aren't music
- [x] Enhancement - Export OPML of subscribed feeds
- [x] UI bug/enhancement - Setting for "Keep episodes" and "Auto-delete played episodes" are confusing. What happens if "Keep episodes" is set to "all episodes", what does "Auto-delete played episodes" do? Shouldn't it do nothing and disappear or be disabled? This is confusing.
- [x] Default settings change - Auto-delete played episodes: true; Auto-download new episodes: true; Download [1] most recent episode per refresh;
- [x] Bug - Storage reporting 0 episodes/0MB download, but I do have files downloaded
- [x] Github release
- [x] Github Actions CI - `.github/workflows/release.yml` builds, Developer ID-signs, notarizes, and publishes a macOS release automatically on `git push origin vX.Y.Z`. iOS is not built in CI (dev-signed only, not publicly installable).
- [x] Bug - Search not visible on iOS (phone) when an item is playing/paused.
- [x] Github "pages" page - one page, screenshots for desktop and mobile, light and dark mode, download badges (point to github releases for now - point to AppStore once that is working).
- [x] Podcast detail header on iOS is cramped (episode count, last updated date, "web" link)
- [x] Change "home" view for iOS -- it should be sidebar, not queue
- [x] Github release for x86 Macs
- [x] Readme
- [x] Docs
- [x] Sparkle for auto-updates on macOS (iOS still needs TestFlight/App Store). CI signs and publishes `docs/appcast.xml` on every tagged release; toggle is in Settings → Updates.
- [x] Sparkle is STILL BROKEN!! - fix was missing `com.apple.security.temporary-exception.mach-lookup.global-name` entitlement (`-spks`/`-spki`), required for a sandboxed app to talk to Sparkle's Installer.xpc. Bumped to 0.0.9; needs a real device test of "Check for Updates" from an older build before tagging.
- [x] Launch screen
- [ ] Tests?
- [ ] TestFlight distribution
- [ ] AppStore submission
- [x] Bug (iOS) - Queue scrolling is incorrect when the Now Playing view is visible. Scrolling the queue all the way up leaves the last item partially hidden under the Now Playing view.
- [x] Add video playback support - macOS: video opens in a separate QuickTime-style window (AVPlayerView); iOS: video plays inline in Now Playing with fullscreen toggle. Design finalized, see VIDEO_PLAYBACK_PLAN.md.
  - [x] Phase 1 - Feed parsing: detect video enclosures (plain `<enclosure>`, `<media:content>`, `podcast:alternateEnclosure`/`source`, HLS skipped), store `videoURL`/`defaultMediaKind` on `Episode`
  - [x] Phase 2 - Playback core: `switchMediaKind(to:)`, player/layer exposure, video-track enable/disable API
  - [x] Phase 3 - Shared `EpisodeThumbnail` view (replaces 5 ad hoc `CachedAsyncImage` sites) with video badge overlay
  - [x] Phase 4 - macOS `VideoPlayerWindowController` (mirrors `MiniPlayerWindowController`) + close/reopen state machine (closing window stops playback entirely; next Play defaults to audio if available, else reopens video)
  - [x] Phase 5 - iOS: video surface + Audio/Video segmented toggle in `NowPlayingView`, fullscreen presentation/toggle, background = keep playing via video track disabled (not a media-kind switch)
  - [x] Phase 6 - Settings: "Wi-Fi only for video downloads" toggle (mirrors `refreshOnlyOnWiFi`)
  - [x] Phase 6 follow-up - "Auto-download video episodes" toggle, defaults OFF (video can eat storage unattended); manual per-episode download always available regardless of the setting
- [x] UI weirdness - Add "Done" button to settings UI on iOS. Currently the only way to get rid of it is to swipe it away, which works, but isn't immediately obvious.
- [x] UI weirdness - "Unplayed" view in podcast detail view and "Queue" view list downloaded and unplayed episodes, which is by design. Unfortunately it causes confusion if someone does not have auto-download enabled, as new episodes only appear in the "All" tab of a podcast detail view, and users must manually go through each podcast and hunt for new episodes and download them to get them into the queue. The "Unplayed" and the "Queue" views logic need updating (along with the logic that adds the unplayed count badge to the sidebar items) so that they can include episodes that match any of the following criteria:
  - [x] Downloaded and unplayed files
  - [x] Any episode in a feed that is unplayed and newer than the most recently played episode in the same feed
  - [x] If adding a feed for the first time, the most recent episode of a show
- [ ] Add ability to unsubscribe from "Search Podcasts" dialog in case someone subscribes to something on accident
- [ ] UI enhancement - Click/tap current time to change to time remaining and vise versa
- [ ] CarPlay UI
- [ ] Bug - When in use in the car, playback does not get paused when Maps gives directions or when Siri speaks
- [ ] Reorganize transport controls on compact player bar on mobile
  - [ ] Move Play/Pause where Airplay button is
  - [ ] Add fast foward and rewind controls around play/pause button
- [ ] New feature: Download Missing Episodes - This should be an option in the queue that would let users download any episodes that are in the queue, but have not been downloaded
- [ ] New feature: "downloads" manager - Maybe we can just use the queue for this? Show a progress circle like on podcast detail with option to cancel?

# Maybe

- [ ] Activity window - show sync status
- [ ] "window" menu flashes different content when app is playing - shows extra options for maximizing/fullscreening window
- [ ] macOS queue drag/drop ghost is a plain blue bar with title only - could match the real row look instead (artwork thumbnail, rounded corners, stacked title/podcast text)
- [ ] macOS "Search Episodes" field (podcast detail) has a lighter background than "Search Queue" (queue view) - same `.searchable()` usage but they render with different bezel colors. Ruled out: toolbar item presence, explicit vs automatic placement, focus state. Suspect it's tied to podcast detail using a real SwiftUI `List` vs queue's NSTableView wrapper - try swapping the episode List to ScrollView/LazyVStack to test.
- [x] UI enhancement (iOS) - podcast detail view's search field is always visible right below the title, unlike Queue's "drag down to reveal" search. The header (artwork/description) and Unplayed/All picker sit in a fixed VStack above a separate List, rather than inside the same scrollable container as the episode list, so the nav bar can't track scroll position to drive the reveal behavior. Fixing this means folding the header + picker into the episode List itself (e.g. as a Section), which would also let them scroll off-screen - worth doing anyway since the header eats a lot of vertical space on iPhone.
