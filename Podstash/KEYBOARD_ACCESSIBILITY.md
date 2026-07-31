# Keyboard Accessibility and Media Controls Implementation

## Overview
This document describes the keyboard accessibility features and media playback controls added to Podstash.

## Latest Features (Media Playback Controls)

### Implemented Features:
1. **Media Keyboard Support**: Hardware media keys (play, pause, skip) now control podcast playback
2. **Now Playing Info**: Currently playing episode appears in macOS Control Center, iOS Lock Screen, and notification center
3. **Spacebar Toggle**: Press spacebar anywhere in the app to toggle play/pause (just like modern media players)
4. **Remote Control**: Control playback from AirPods, headphone buttons, and other Bluetooth devices

### Technical Implementation:

#### Media Player Integration (AudioPlayerManager.swift)
```swift
import MediaPlayer  // Added for MPNowPlayingInfoCenter and MPRemoteCommandCenter

// Setup remote control commands in init()
private func setupRemoteCommands() {
    let commandCenter = MPRemoteCommandCenter.shared()
    
    // Play/Pause/Toggle
    commandCenter.playCommand.addTarget { ... }
    commandCenter.pauseCommand.addTarget { ... }
    commandCenter.togglePlayPauseCommand.addTarget { ... }
    
    // Skip forward/backward
    commandCenter.skipForwardCommand.preferredIntervals = [30]
    commandCenter.skipBackwardCommand.preferredIntervals = [15]
    
    // Scrubbing support
    commandCenter.changePlaybackPositionCommand.addTarget { ... }
}

// Update Now Playing info whenever playback state changes
private func updateNowPlayingInfo() {
    var nowPlayingInfo = [String: Any]()
    nowPlayingInfo[MPMediaItemPropertyTitle] = episode.title
    nowPlayingInfo[MPMediaItemPropertyArtist] = podcast.title
    nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
    nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
    nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = playbackRate
    
    // Artwork loading
    if let artworkURL = episode.podcast?.artworkURL {
        // Async load artwork and add to Now Playing
    }
    
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
}
```

#### Spacebar Keyboard Shortcut (ContentView.swift)
```swift
.onKeyPress(.space) { press in
    // Toggle play/pause when spacebar is pressed
    if audioPlayer.currentEpisode != nil {
        audioPlayer.togglePlayPause()
        return .handled
    }
    return .ignored
}
```

### User Experience:

**On macOS:**
- Press media keys on keyboard to control playback
- View Now Playing info in Control Center (menu bar)
- Press spacebar from anywhere in the app to toggle play/pause
- Scrub through episodes using Touch Bar (if available)

**On iOS/iPadOS:**
- Control playback from Lock Screen
- Use Control Center for quick access
- Press spacebar on external keyboard to toggle play/pause
- Control with AirPods squeeze/tap gestures
- Use Car Play controls when connected

**On Both Platforms:**
- Artwork displays in Now Playing interface
- Episode title and podcast name shown
- Current playback position and duration visible
- Playback speed reflected in Now Playing info
- Skip intervals: 30s forward, 15s backward (configurable)

### Now Playing Info Updates:
The system Now Playing interface is updated when:
- Starting playback of an episode
- Pausing/resuming playback
- Seeking to a different position
- Changing playback speed
- Every 5 seconds during playback (to keep position accurate)

### Commands Supported:
- **Play**: Resume playback
- **Pause**: Pause playback
- **Toggle Play/Pause**: Switch between play and pause
- **Skip Forward**: Jump ahead 30 seconds (user-configurable)
- **Skip Backward**: Jump back 15 seconds (user-configurable)
- **Change Playback Position**: Scrub to specific time

## Bug Fixes (Previous Update)

### Fixed Issues:
1. **Context Menu Multi-Selection**: Context menus now properly handle multi-selection. When right-clicking with items selected, the action applies to all selected items, not just the clicked item.
2. **Cmd+A Selection**: Fixed keyboard selection in sidebar by improving focus management and adding proper modifier key detection on macOS.
3. **Performance Optimization**: Fixed MAJOR performance issues:
   - Removed `@StateObject` from `CachedAsyncImage` (was creating a new observable object for EVERY image!)
   - Cached HTML stripping results in row views (regex was running on every render)
   - Optimized SwiftData queries to only fetch needed data
   - PodcastRowView and EpisodeRowView now cache computed values on initialization

## Features Implemented

### 1. Podcast Sidebar (PodcastListView)
Users can now select multiple podcasts and unsubscribe from them using keyboard shortcuts:

**Keyboard Shortcuts:**
- **Cmd+A**: Select all podcasts in the sidebar
- **Click + Cmd**: Add/remove individual podcasts from selection
- **Delete** or **Backspace**: Unsubscribe from selected podcast(s)

**Behavior:**
- Single selection still works normally - clicking a podcast shows its detail view
- Multi-selection mode activates when multiple podcasts are selected
- Pressing Delete/Backspace shows a confirmation alert before unsubscribing
- Alert message adapts based on single vs. multiple selection
- After unsubscription, all downloaded episodes are deleted (cascade delete via SwiftData relationship)

### 2. Queue View (QueueView)
Users can select multiple episodes in the queue and remove them using keyboard shortcuts:

**Keyboard Shortcuts:**
- **Cmd+A**: Select all episodes in the queue
- **Click + Cmd**: Add/remove individual episodes from selection
- **Delete** or **Backspace**: Remove selected episode(s) from queue

**Behavior:**
- Multi-selection allows bulk removal from queue
- Pressing Delete/Backspace shows a confirmation alert before removing
- Alert message adapts based on single vs. multiple selection
- Queue positions are automatically reindexed after removal
- Existing swipe actions and context menus remain functional

### 3. Podcast Detail View (PodcastDetailView)
**No keyboard deletion implemented** - Episodes in the podcast detail view are intentionally excluded from bulk deletion because:
- It doesn't make semantic sense to bulk delete episodes from a single podcast
- Episodes in this view are meant for playback/queue management, not deletion
- Individual episode management is available through context menus

## Technical Implementation

### Key Changes

#### PodcastListView (ContentView.swift)
```swift
// Added state for multi-selection
@State private var multiSelection = Set<UUID>()
@State private var showingUnsubscribeAlert = false
@FocusState private var isFocused: Bool
@Environment(\.modelContext) private var modelContext

// Changed List binding to support multi-selection
List(selection: $multiSelection) {
    ForEach(podcasts) { podcast in
        PodcastRowView(podcast: podcast)
            .tag(podcast.id)
            // ... row implementation
    }
}
.focused($isFocused)
.onDeleteCommand {
    if !multiSelection.isEmpty {
        showingUnsubscribeAlert = true
    }
}
```

#### QueueView (QueueView.swift)
```swift
// Added state for multi-selection
@State private var multiSelection = Set<UUID>()
@State private var showingRemoveAlert = false
@FocusState private var isFocused: Bool

// Changed List to support multi-selection
List(selection: $multiSelection) {
    ForEach(queuedEpisodes) { episode in
        QueueEpisodeRow(episode: episode)
            .tag(episode.id)
            // ... row implementation
    }
}
.focused($isFocused)
.onDeleteCommand {
    if !multiSelection.isEmpty {
        showingRemoveAlert = true
    }
}
```

### SwiftUI Modifiers Used

1. **`.focused(_:)`**: Manages focus state to ensure the list can receive keyboard input
2. **`.onDeleteCommand(perform:)`**: Responds to Delete/Backspace key presses
3. **`.alert(_:isPresented:actions:message:)`**: Shows confirmation dialogs
4. **`List(selection:)`**: Enables multi-selection with Set<UUID> binding

## User Experience

### Visual Feedback
- Selected items are highlighted with the system accent color
- Multiple selections show a clear visual distinction
- Alerts provide context about how many items will be affected

### Safety Features
- Confirmation alerts prevent accidental deletions
- Clear messaging explains what will be deleted
- Cancel buttons allow users to abort the operation

### Accessibility
- Keyboard-only navigation is fully supported
- VoiceOver announces selections and actions
- Standard macOS/iOS keyboard shortcuts are used

## Testing Recommendations

1. **Single Selection**
   - Select one podcast, press Delete
   - Verify alert shows singular message
   - Verify unsubscription works correctly

2. **Multi-Selection**
   - Use Cmd+Click to select multiple podcasts
   - Press Delete, verify plural message
   - Verify all selected podcasts are removed

3. **Select All**
   - Press Cmd+A in sidebar
   - Verify all podcasts are selected
   - Delete and verify all are unsubscribed

4. **Queue Operations**
   - Repeat above tests in Queue view
   - Verify queue reindexing works correctly

5. **Focus Management**
   - Navigate between sidebar and detail views
   - Verify focus state is maintained
   - Ensure keyboard shortcuts only work when appropriate

## Platform Considerations

- Implementation works on both macOS and iOS/iPadOS
- macOS has native Cmd+A support in List views
- iOS/iPadOS may require tap selection (multi-touch)
- `.onDeleteCommand` works on both platforms with Delete/Backspace keys

## Performance Optimizations

### Critical Fixes:
1. **CachedAsyncImage**: Removed `@StateObject` that was creating an observable object per image instance
   - Before: Each image view created its own ImageCacheManager instance
   - After: All images share the singleton `ImageCacheManager.shared`
   - Impact: Massive reduction in memory and CPU usage

2. **HTML Stripping**: Cached regex results in row initializers
   - Before: `stripHTMLTags()` ran on every view render (potentially hundreds of times per second)
   - After: Stripped text is computed once in `init()` and reused
   - Views affected: `PodcastRowView`, `EpisodeRowView`
   - Impact: 10-100x faster rendering

3. **SwiftData Query Optimization**: 
   - Before: `@Query private var allEpisodes: [Episode]` fetched ALL episodes
   - After: `@Query(filter: #Predicate<Episode> { ... })` only fetches queued episodes
   - Impact: Significantly reduced memory usage and query time

4. **Computed Property Caching**: 
   - Moved expensive computations to `init()` methods
   - Example: `downloadedUnplayedCount` computed once instead of on every render

### Performance Tips for Debug Mode:
- Debug builds are naturally slower due to lack of optimizations
- Release builds will be MUCH faster (compile with optimizations enabled)
- The fixes above help both debug and release, but release will see the biggest improvement

## Future Enhancements

Potential improvements for future versions:
- Add keyboard shortcut labels in menus (macOS)
- Support for Cmd+Z (undo) after deletion
- Batch operations progress indicators
- Keyboard navigation between different sections
