# TODO

- [ ] Bug - resorting queue by drag/drop is weird. Sometimes item is placed above when it should be placed below.
- [ ] Bug - app downloads episodes even when "auto download" setting is disabled (i.e., the default setting)
- [ ] Bug - inconsistent row slide controls (mark as played/remove) on iOS and macOS queue views. Make iOS match macOS, both buttons on right, only icons.
- [ ] Bug - iOS transport controls only include play/pause - no way to scrub. probably related to missing "now playing" view
- [ ] UI bug - episode detail dialog dropdown button, shortcut for all items appear to be return/enter -- get rid of shortcuts for this menu
- [ ] UI bug - "More" button on podcast description on desktop breaks whole view - window and sidebar contents disappear!
- [ ] UI bug - User can close main window and there is no way to get it back
  - [ ] ui bug/enhancement - iOS "now playing" view -- where is it?
  - [ ] ui bug/enhancement - iOS, show artwork with bottom controls
- [ ] ui enhancement - text is *very* small on macOS and iOS.
- [ ] ui enhancement - "sidebar icon" option should just be "icon option" on iOS, and icon sizes should be larger - use "medium" macOS size for "small" on iOS, "large" macOS size for "medium" on iOS, and then pick a proportional size for "large" on iOS.
- [ ] ui enhancement - remove number from start of queue items
- [ ] ui enhancement - hide iCloud stuff until it can be implemented
- [ ] ui enhancement - episode detail dialog needs bottom padding - audio file URL bumps right against edge
- [ ] sync - enroll in paid Apple Developer Program, enable CloudKit capability, flip `cloudKitEntitlementsConfigured` in PodstashApp.swift to sync data between devices

# Maybe

- [ ] search feature - search episodes in subscribed feeds
- [ ] can this play videos?
- [ ] "downloads" window/view/whatever
- [ ] "window" menu flashes different content when app is playing - shows extra options for maximizing/fullscreening window
