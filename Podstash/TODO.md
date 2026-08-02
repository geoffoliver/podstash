# TODO

- [x] Bug - app downloads episodes even when "auto download" setting is disabled (i.e., the default setting)
- [x] Bug - iOS transport controls only include play/pause - no way to scrub. probably related to missing "now playing" view
  - [x] Bug - iOS "now playing" view -- where is it?
  - [x] Enhancement - iOS, show artwork with bottom controls
- [x] Bug - resorting queue by drag/drop is weird. Sometimes item is placed above when it should be placed below.
- [ ] Bug - right clicking in queue and "mark as played" doesn't work if user right clicks to select item and trigger menu immediately.
- [ ] Bug - inconsistent row slide controls (mark as played/remove) on iOS and macOS queue views. Make iOS match macOS, both buttons on right, only icons.


- [ ] UI bug - User can close main window and there is no way to get it back
- [ ] UI bug - episode detail dialog dropdown button, shortcut for all items appear to be return/enter -- get rid of shortcuts for this menu
- [ ] UI bug - "Queue" item in sidebar is weird. Click directly on it results in two background colors, one spans full width of sidebar and is not as vibrant/bright, other is correct (not full width, rounded corners) and is very bright blue.
- [ ] UI bug - on iOS, "now playing" view, tapping anywhere opens audio file in browser, and that is very weird.
- [x] UI bug - "More" button on podcast description on desktop breaks whole view - window and sidebar contents disappear!


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
- [ ] "downloads" window/view/whatever
- [ ] "window" menu flashes different content when app is playing - shows extra options for maximizing/fullscreening window
- [ ] macOS queue drag/drop ghost is a plain blue bar with title only - could match the real row look instead (artwork thumbnail, rounded corners, stacked title/podcast text)
