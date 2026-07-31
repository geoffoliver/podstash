# How Airfoil Integration Works

This diagram shows the flow of data between Podstash, Airfoil, and Airfoil Speakers.

```
┌─────────────────────────────────────────────────────────────────────┐
│                          YOUR MAC                                    │
│                                                                       │
│  ┌──────────────┐                    ┌──────────────┐               │
│  │   Podstash   │                    │   Airfoil    │               │
│  │              │                    │              │               │
│  │  Playing:    │◄───AppleScript────┤  Source:     │               │
│  │  Episode XYZ │    Queries         │  Podstash    │               │
│  │              │                    │              │               │
│  │  Properties: │───AppleScript────►│  Receives:   │               │
│  │  • Title     │    Returns         │  • Title     │               │
│  │  • Artist    │                    │  • Artist    │               │
│  │  • Album     │                    │  • Album     │               │
│  │  • Duration  │                    │  • Duration  │               │
│  │  • Artwork   │                    │  • Artwork   │               │
│  │              │                    │              │               │
│  │  Commands:   │◄───AppleScript────┤  Controls:   │               │
│  │  • playpause │    Executes        │  Sends       │               │
│  │  • next      │                    │  commands    │               │
│  │  • previous  │                    │              │               │
│  │              │                    │              │               │
│  │  🔊 Audio    │────Raw Audio──────►│  Captures &  │               │
│  │   Output     │                    │  Transmits   │               │
│  └──────────────┘                    └──────┬───────┘               │
│                                              │                        │
└──────────────────────────────────────────────┼────────────────────────┘
                                               │
                                               │ Network Stream
                                               │ (Audio + Metadata)
                                               │
                    ┌──────────────────────────┼────────────────┐
                    │                          │                 │
                    ▼                          ▼                 ▼
            ┌───────────────┐        ┌───────────────┐  ┌───────────────┐
            │ Airfoil       │        │ Airfoil       │  │  Apple TV     │
            │ Speakers      │        │ Speakers      │  │               │
            │ (Living Room) │        │ (Bedroom)     │  │ (Kitchen)     │
            │               │        │               │  │               │
            │ Displays:     │        │ Displays:     │  │ Displays:     │
            │ • Episode     │        │ • Episode     │  │ • Episode     │
            │ • Podcast     │        │ • Podcast     │  │ • Podcast     │
            │ • Artwork     │        │ • Artwork     │  │ • Artwork     │
            │               │        │               │  │               │
            │ Controls:     │        │ Controls:     │  │ Controls:     │
            │ ⏯ ⏮ ⏭       │        │ ⏯ ⏮ ⏭       │  │ ⏯ ⏮ ⏭       │
            │               │        │               │  │               │
            │ 🔊            │        │ 🔊            │  │ 🔊            │
            └───────────────┘        └───────────────┘  └───────────────┘
```

## The Flow Explained

### 1. Metadata Flow (What You See)
```
Podstash Episode Info 
    → AppleScript Property Accessors (NSApplication+Scripting.swift)
    → TrackMetadata.scpt
    → Airfoil reads metadata
    → Airfoil transmits to all Speakers
    → Speakers display episode info + artwork
```

### 2. Control Flow (What You Click)
```
User clicks Play button in Airfoil Speakers
    → Airfoil Speakers sends command to Airfoil
    → Airfoil runs RemoteControl.scpt
    → AppleScript calls "playpause" command
    → PlayPauseCommand.swift executes
    → MenuCoordinator.shared.audioPlayer?.togglePlayPause()
    → Podstash playback toggles
```

### 3. Audio Flow (What You Hear)
```
Podstash plays audio via AVPlayer
    → macOS routes audio to Podstash's audio output
    → Airfoil captures the audio stream
    → Airfoil encodes and transmits to network devices
    → Speakers decode and play synchronized audio
```

## Key Components

### In Podstash:

**Podstash.sdef**
- Defines the AppleScript "API" that Airfoil uses
- Lists all properties (track title, artist, etc.)
- Lists all commands (playpause, next, previous)

**NSApplication+Scripting.swift**
- Implements property getters
- Reads from MenuCoordinator → AudioPlayerManager → currentEpisode
- Returns values or "missing value" if nothing playing

**AppleScriptCommands.swift**
- Implements command handlers
- Receives AppleScript commands
- Calls methods on AudioPlayerManager

**AudioPlayerManager.swift**
- Already has all the logic for playback
- Provides skipForward() and skipBackward() methods
- Coordinator accesses it via MenuCoordinator.shared.audioPlayer

### In Airfoil Support Folder:

**TrackMetadata.scpt**
- Called by Airfoil when it needs current track info
- Queries Podstash for all 5 properties
- Returns them in the correct order

**RemoteControl.scpt**
- Called by Airfoil when user clicks control buttons
- Translates Airfoil's commands to Podstash commands
- `remote_play()` → `playpause`
- `remote_pause()` → `playpause`
- `remote_next_item()` → `next` (skip forward)
- `remote_previous_item()` → `previous` (skip backward)

## What Happens When You Play an Episode

```
1. User plays episode in Podstash
   └─► AudioPlayerManager.currentEpisode is set
   └─► Episode metadata is in memory

2. Airfoil calls TrackMetadata.scpt periodically
   └─► Script queries Podstash for track title, artist, etc.
   └─► NSApplication+Scripting returns current episode info
   └─► Airfoil receives metadata

3. Airfoil transmits metadata with audio stream
   └─► All connected Speakers receive both
   └─► Speakers display episode info + artwork

4. User clicks "Pause" in Airfoil Speakers
   └─► Speakers send command to Airfoil
   └─► Airfoil runs: tell Podstash to playpause
   └─► PlayPauseCommand executes
   └─► AudioPlayerManager.togglePlayPause() is called
   └─► Audio pauses

5. Metadata updates in Airfoil
   └─► Playback state changes to "paused"
   └─► All Speakers show paused state
```

## Why This Design?

**AppleScript Interface:**
- Standard way for apps to communicate on macOS
- Airfoil already supports this for many apps
- No need for custom networking or IPC

**Property-Based Metadata:**
- Airfoil can query at any time
- No need for Podstash to "push" updates
- Works even if Airfoil starts after Podstash

**Command-Based Controls:**
- Decoupled from UI framework
- Works from anywhere (Airfoil, Terminal, Script Editor)
- Easy to test independently

**MenuCoordinator Pattern:**
- Already exists in your app for menu validation
- Provides global access point without singleton
- MainActor-safe for UI updates

## Testing the Flow

### Test 1: Metadata Query
```applescript
tell application "Podstash"
    track title  -- Should return "Episode Name" or missing value
end tell
```

### Test 2: Command Execution
```applescript
tell application "Podstash"
    playpause  -- Should toggle playback
end tell
```

### Test 3: Full Airfoil Integration
1. Start Podstash, play episode
2. Open Airfoil, select Podstash
3. Connect to speaker
4. Check speaker for metadata
5. Click controls in speaker
6. Verify Podstash responds

## Troubleshooting the Flow

**Metadata not showing:**
- Check: Can you query properties in Script Editor?
- Check: Is TrackMetadata.scpt in the right folder?
- Check: Does filename match bundle identifier?

**Controls not working:**
- Check: Can you run commands in Script Editor?
- Check: Is RemoteControl.scpt in the right folder?
- Check: Does filename have "dacp." prefix?

**Artwork not appearing:**
- Check: Does podcast have artworkURL set?
- Check: Can you access the URL in a browser?
- Check: Is network connection working?

---

This integration makes Podstash a first-class Airfoil citizen! 🎉
