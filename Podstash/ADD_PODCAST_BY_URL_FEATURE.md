# Add Podcast by URL Feature

## Overview
This feature allows users to add a podcast by providing its RSS feed URL directly. It includes validation, user feedback, and automatic episode downloading.

## Implementation Details

### Files Modified
1. **PodstashApp.swift** - Main implementation
2. **RefreshCoordinator.swift** - Added convenience method

### Components Added

#### 1. AddPodcastCoordinator
A new `@MainActor` class that manages the entire "Add Podcast by URL" workflow:

**Properties:**
- `isPresented`: Controls sheet visibility
- `feedURL`: User-entered feed URL
- `isValidating`: Indicates validation in progress
- `validationMessage`: Error/warning messages
- `showSuccessMessage`: Success state flag
- `triggerRefreshAfterAdding`: Callback for feed refresh

**Key Methods:**
- `showDialog()`: Opens the add podcast sheet
- `addPodcast()`: Main workflow that:
  1. Validates URL format
  2. Fetches and parses RSS feed
  3. Verifies feed has episodes
  4. Checks for duplicate subscription
  5. Creates podcast subscription
  6. Adds configured number of episodes
  7. Triggers feed refresh
  8. Shows success message

#### 2. AddPodcastSheet
A SwiftUI view that provides the user interface:

**States:**
- **Input State**: Text field for URL entry with validation
- **Success State**: Confirmation with "Subscribed to Podcast!" message

**Features:**
- URL text field with auto-submission (Enter key)
- Real-time validation error display
- Loading indicator during validation
- Automatic dismissal after success (1.5 seconds)
- Keyboard shortcuts (Cmd+Return to add, Esc to cancel)

#### 3. FeedValidationResult
An enum for validation results:
- `.success(ParsedPodcast)`: Feed is valid with parsed data
- `.failure(String)`: Validation failed with error message

### Menu Integration

The File menu now contains (in order):
1. **Add Podcast by URL…** (⌘N)
2. **Import OPML…** (⌘I) 
3. Divider
4. **Refresh All Feeds** (⌘R)

### Workflow

1. **User Initiates**: 
   - File menu → "Add Podcast by URL…"
   - Or keyboard shortcut: ⌘N

2. **URL Entry**:
   - Sheet appears with text field
   - User enters RSS feed URL
   - Press Enter or click "Add Podcast"

3. **Validation**:
   - URL format check (http/https)
   - Network fetch of RSS feed
   - XML parsing verification
   - Episode existence check
   - Duplicate subscription check

4. **Success Path**:
   - Create podcast subscription
   - Parse and store metadata (title, description, artwork, etc.)
   - Add most recent N episodes (based on settings)
   - Show success message
   - Trigger feed refresh (which downloads episodes if auto-download is enabled)
   - Auto-dismiss after 1.5 seconds

5. **Error Handling**:
   - Display validation errors inline
   - User can correct and retry
   - Task cancellation support

### Integration Points

#### With SubscriptionManager
- Uses existing `subscribe()` method
- Prevents duplicate subscriptions
- Handles database persistence

#### With RefreshCoordinator
- New `refreshFeed(for:)` convenience method
- Triggers single feed refresh after adding
- Leverages existing download infrastructure

#### With AppSettings
- Respects `maxEpisodesToDownload` setting
- Auto-download controlled by settings
- Download quality and WiFi preferences honored

### Key Features

✅ **Full Feed Validation**: Fetches and parses feed before subscribing
✅ **Reuses Parsed Data**: Validation fetch data is used to populate episodes
✅ **Automatic Episode Download**: Configured number of episodes added immediately
✅ **User Feedback**: Success message and loading states
✅ **Keyboard Shortcuts**: ⌘N for add, ⌘I for import
✅ **Error Handling**: Clear validation messages
✅ **Duplicate Prevention**: Checks existing subscriptions
✅ **Cross-Platform**: Works on macOS and iOS/iPadOS

### User Experience Flow

```
User presses ⌘N
    ↓
Sheet appears with URL field
    ↓
User enters feed URL
    ↓
User presses Enter or clicks "Add Podcast"
    ↓
"Validating…" shown with spinner
    ↓
Feed fetched and validated
    ↓
[If valid]
    ↓
"Subscribed to Podcast!" shown
"Downloading episodes…" subtitle
    ↓
Feed refreshes in background
    ↓
Sheet auto-dismisses after 1.5s
```

### Testing Checklist

- [ ] Add valid podcast feed URL
- [ ] Add duplicate podcast (should show error)
- [ ] Add invalid URL (should show error)
- [ ] Add non-RSS URL (should show error)
- [ ] Add feed with no episodes (should show error)
- [ ] Cancel during validation
- [ ] Verify correct number of episodes added
- [ ] Verify auto-download triggers (if enabled)
- [ ] Test keyboard shortcuts (⌘N, ⌘I)
- [ ] Test on macOS
- [ ] Test on iOS/iPadOS

### Future Enhancements

Potential improvements:
- Show podcast preview before subscribing (title, artwork, episode count)
- Support for authentication/password-protected feeds
- Feed URL clipboard detection
- URL validation with common podcast directories
- Batch URL import (multiple URLs at once)

