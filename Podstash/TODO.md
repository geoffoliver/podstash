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
- [ ] UI bug (desktop) - Sometimes on initial play, progress scrubber is too wide (goes all the way to right edge and probably far outside of it)

- [ ] UI enhancement - text is *very* small on macOS and iOS.
- [ ] UI enhancement - "cancel" button for feed refreshing is very small. make actual button with "cancel" label
- [ ] UI enhancement - "sidebar icon" option should just be "icon option" on iOS, and icon sizes should be larger - use "medium" macOS size for "small" on iOS, "large" macOS size for "medium" on iOS, and then pick a proportional size for "large" on iOS.
- [ ] UI enhancement - settings is kind of a mess. for example, "Download _ most recent episode" setting is at top, but should be with "Auto-download..." setting, and also not be enabled/displayed/whatever when the "Auto-download..." option is not enabled. The whole thing needs a bit of a reorgnization and maybe a bit of functionality tweaks.
- [ ] UI enhancement - remove number from start of queue items
- [ ] UI enhancement - hide iCloud stuff until it can be implemented
- [ ] UI enhancement - add Airplay button to Desktop transport controls
- [ ] UI enhancement - episode detail dialog needs bottom padding - audio file URL bumps right against edge
- [ ] sync - enroll in paid Apple Developer Program, enable CloudKit capability, flip `cloudKitEntitlementsConfigured` in PodstashApp.swift to sync data between devices

# Maybe

- [ ] search feature - search episodes in subscribed feeds
- [ ] can this play videos?
- [ ] "downloads" window/view/whatever - maybe we can just use the queue for this? show progress circle like on podcast detail?
- [ ] "window" menu flashes different content when app is playing - shows extra options for maximizing/fullscreening window
- [ ] macOS queue drag/drop ghost is a plain blue bar with title only - could match the real row look instead (artwork thumbnail, rounded corners, stacked title/podcast text)
