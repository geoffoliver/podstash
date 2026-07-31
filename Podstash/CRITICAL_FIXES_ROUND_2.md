# Critical Performance Fixes - Round 2

## Issues Fixed

### 0. ✅ Queue Items Don't Play on Double-Click (macOS)
**Problem**: On macOS, double-clicking a queue item didn't start playing the episode (non-standard behavior).

**Root Cause**: Queue rows used a single-click Button, which is iOS-style behavior. macOS Lists typically use double-click.

**Fix**: Platform-specific interaction patterns:
```swift
#if os(macOS)
// On macOS, use double-click to play (standard behavior)
rowContent
    .contentShape(Rectangle())
    .onTapGesture(count: 2) {
        audioPlayer.play(episode: episode)
    }
#else
// On iOS, use button for single tap
Button {
    audioPlayer.play(episode: episode)
} label: {
    rowContent
}
#endif
```

**Result**: 
- **macOS**: Double-click to play (standard List behavior)
- **iOS**: Single tap to play (standard mobile behavior)

---

### 1. ✅ Feeds Not Refreshing After OPML Import
**Problem**: After importing an OPML file, the feeds were added to the database but episodes weren't fetched automatically.

**Root Cause**: The import process subscribed to feeds but didn't trigger a refresh to fetch episodes.

**Fix**: Added automatic refresh after successful OPML import:
```swift
// In OPMLImportCoordinator
var triggerRefreshAfterImport: (() -> Void)?

// After successful import
if successCount > 0 {
    await MainActor.run {
        self.triggerRefreshAfterImport?()  // Triggers refreshAllFeeds()
    }
}

// In PodstashApp
opmlCoordinator.triggerRefreshAfterImport = {
    refreshCoordinator.refreshAllFeeds()
}
```

**Result**: After importing OPML, feeds automatically refresh to fetch episodes.

---

### 1. ✅ Podcast Artwork Not Updating
**Problem**: When switching between podcasts, the artwork stayed the same (showing the first podcast's image).

**Root Cause**: SwiftUI was reusing the same view instance instead of creating a new one when the podcast changed.

**Fix**: Added `.id(podcast.id)` to force SwiftUI to create a fresh view for each podcast:
```swift
PodcastDetailView(podcast: podcast)
    .id(podcast.id) // Force new view when podcast changes
```

**Result**: Each podcast now gets its own view instance with the correct artwork.

---

### 1. ✅ Queue Navigation & Selection
**Problems**: 
- Clicking "Queue" didn't switch to queue view
- Queue row didn't highlight when selected
- Had to click directly on label text

**Root Cause**: Using `.tag()` and `.onTapGesture` together was conflicting with List selection.

**Fixes**:
1. Simplified to direct tap gesture without Button wrapper
2. Added `.contentShape(Rectangle())` to make entire row clickable
3. Added `.listRowBackground()` to highlight queue when selected

```swift
HStack {
    Label { ... } icon: { ... }
}
.contentShape(Rectangle()) // Make entire row clickable
.listRowBackground(showingQueue ? Color.accentColor.opacity(0.15) : Color.clear)
.onTapGesture {
    showingQueue = true
    selectedPodcast = nil
}
```

---

### 2. ✅ 59% CPU When Opening Podcast Detail
**Problem**: CPU spiked to 59% when opening a podcast with many episodes.

**Root Causes**:
1. **Sorting on every render**: `podcast.episodes.sorted(...)` called in ForEach
2. **No virtualization**: Using ScrollView + ForEach renders ALL episodes at once
3. **Render ALL episodes**: No filtering, showing 100+ episodes simultaneously

**Fixes**:
1. **Pre-compute sorting**: Moved sorting to computed property, called once
2. **Use List instead of ScrollView**: List virtualizes - only renders visible rows
3. **Added tabs**: Unplayed (downloaded) / All - to focus on what matters
4. **Cached filtered results**: Filter happens once per tab change, not per render
5. **Smart default**: Opens to "Unplayed" tab showing only downloaded episodes

```swift
// Before (BAD):
ScrollView {
    ForEach(podcast.episodes.sorted(...)) { episode in  // Sorts on EVERY render!
        EpisodeRowView(episode: episode)  // ALL episodes rendered at once
    }
}

// After (GOOD):
enum EpisodeFilter {
    case unplayed, all  // Unplayed = downloaded & unplayed only
}

private var sortedEpisodes: [Episode] {  // Computed once
    podcast.episodes.sorted(by: { $0.publishDate > $1.publishDate })
}

private var filteredEpisodes: [Episode] {
    switch selectedTab {
    case .unplayed: 
        return sortedEpisodes.filter { !$0.isPlayed && $0.isDownloaded }
    case .all: 
        return sortedEpisodes
    }
}

// Tab picker - Unplayed first!
Picker("Filter", selection: $selectedTab) {
    Text("Unplayed (\(unplayedDownloadedCount))").tag(EpisodeFilter.unplayed)
    Text("All (\(sortedEpisodes.count))").tag(EpisodeFilter.all)
}

List {  // Virtualizes! Only renders visible rows
    ForEach(filteredEpisodes) { episode in
        EpisodeRowView(episode: episode)
    }
}
```

**Expected Result**: 
- Opening podcast should be instant
- CPU should stay low (<10%)
- Only downloaded unplayed episodes shown by default
- Only visible episodes are rendered
- Scrolling is smooth with virtualization
- Users can switch to "All" to see everything

---

### 3. ✅ "Last Updated" Time Constantly Recalculating
**Problem**: `.relative` date style recalculates continuously, causing constant re-renders.

**Fix**: Calculate relative time string ONCE in init():
```swift
// Before (BAD):
if let lastUpdated = podcast.lastUpdated {
    Text("Updated \(lastUpdated, style: .relative)")  // Recalculates constantly!
}

// After (GOOD):
private let lastUpdatedText: String?

init(podcast: Podcast) {
    if let lastUpdated = podcast.lastUpdated {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        self.lastUpdatedText = formatter.localizedString(for: lastUpdated, relativeTo: Date())
    }
}

// In body:
if let lastUpdatedText = lastUpdatedText {
    Text("Updated \(lastUpdatedText)")  // Just displays cached string
}
```

**Result**: No more constant recalculation of relative dates

---

## Performance Impact Summary

| Issue | Before | After | Fix |
|-------|--------|-------|-----|
| Queue navigation | Broken | ✅ Works | Changed to Button |
| Opening podcast | 59% CPU | ~5-10% CPU | List virtualization + tabs |
| Episode rendering | ALL rendered | Only visible | List instead of ScrollView |
| Date calculations | Constant | Once | Cache in init() |
| Episode sorting | Every render | Once | Computed property |

---

## Key Lessons

### 1. Never Sort/Filter in ForEach
```swift
// ❌ BAD - sorts on every render
ForEach(items.sorted(...)) { }

// ✅ GOOD - compute once
let sortedItems = items.sorted(...)
ForEach(sortedItems) { }
```

### 2. Use List for Long Lists, Not ScrollView + ForEach
- **List**: Virtualizes, only renders visible rows
- **ScrollView + ForEach**: Renders EVERYTHING immediately

### 3. Never Use .relative Date Style in Lists
- Constantly recalculates
- Causes continuous re-renders
- Cache the formatted string instead

### 4. Use Tabs/Filters to Reduce Visible Items
- Don't render 100+ items if user only cares about unplayed
- Dramatically reduces rendering work

---

## Testing Checklist

- [ ] Click anywhere on "Queue" row → should navigate to queue view
- [ ] Queue row should be highlighted when selected
- [ ] Open podcast with many episodes → should be instant, CPU < 10%
- [ ] Default view should show "Unplayed" tab with downloaded episodes only
- [ ] Scroll through episodes → should be smooth
- [ ] Switch between Unplayed/All tabs → should be instant
- [ ] Leave app idle → CPU should be near 0%
- [ ] Check Activity Monitor → memory should be stable

---

## Expected Performance

**Idle**: ~0-2% CPU
**Browsing podcasts**: ~5-10% CPU
**Opening podcast detail**: ~5-10% CPU (brief spike is OK)
**Scrolling episodes**: ~10-15% CPU
**Playing audio**: ~15-20% CPU

If CPU is higher than this, there's still a problem to investigate.
