# Airfoil Integration for Podstash

This document explains how to set up, test, and use Airfoil integration with Podstash.

## What You Get

When properly configured, Podstash will work as a **source** for Airfoil, providing:

- ✅ **Track metadata** displayed in Airfoil Speakers (episode title, podcast name, artwork)
- ✅ **Playback controls** in Airfoil Speakers (play, pause, next, previous)
- ✅ **Album artwork** sent to all Airfoil Satellite clients

## Setup Instructions

### Step 1: Add Files to Your Xcode Project

1. **Add `Podstash.sdef` to your Xcode project:**
   - Drag `Podstash.sdef` into your Xcode project
   - Make sure it's included in your app target
   - **Important:** The file must be copied into your project, not just referenced

2. **Add the Swift files to your project:**
   - `AppleScriptCommands.swift`
   - `NSApplication+Scripting.swift`
   
   These should automatically be included in your app target.

### Step 2: Update Info.plist

Add the following keys to your `Info.plist` file:

```xml
<key>NSAppleScriptEnabled</key>
<true/>
<key>OSAScriptingDefinition</key>
<string>Podstash.sdef</string>
```

You can do this in Xcode by:
1. Select your project in the navigator
2. Select your app target
3. Go to the "Info" tab
4. Click the "+" button to add new keys:
   - Add "Scriptable" (NSAppleScriptEnabled) → YES
   - Add "Scripting definition file name" (OSAScriptingDefinition) → "Podstash.sdef"

### Step 3: Verify Bundle Identifier

The AppleScript files are configured for bundle identifier `me.geoffoliver.Podstash`.

### Step 4: Build and Run

1. Build your project in Xcode (⌘B)
2. Run the app (⌘R)
3. If you get build errors, make sure:
   - `Podstash.sdef` is in the "Copy Bundle Resources" build phase
   - All Swift files are in the "Compile Sources" build phase

## Testing Instructions

### Test 1: Script Editor (Before Installing Scripts)

Before installing the Airfoil scripts, you can test that your AppleScript support is working:

1. **Open Script Editor** (in `/Applications/Utilities/`)

2. **Start playing an episode in Podstash**

3. **Run this test script:**

```applescript
tell application "Podstash"
    -- Get track metadata
    set theTitle to track title
    set theArtist to artist
    set theAlbum to album
    set theDuration to duration
    
    -- Display the results
    return "Title: " & theTitle & return & "Artist: " & theArtist & return & "Album: " & theAlbum & return & "Duration: " & (theDuration as string) & " seconds"
end tell
```

**Expected result:** You should see a dialog with your currently playing episode's information.

4. **Test the playback commands:**

```applescript
tell application "Podstash"
    playpause -- Should pause if playing, play if paused
    delay 2
    playpause -- Should toggle back
end tell
```

**Expected result:** Podstash should pause and then resume playback.

### Test 2: Install and Test with Airfoil

1. **Install the AppleScript files:**

   Open Terminal and run these commands (adjust the bundle identifier if needed):

   ```bash
   # Create the directories if they don't exist
   mkdir -p ~/Library/Application\ Support/Airfoil/TrackTitles
   mkdir -p ~/Library/Application\ Support/Airfoil/RemoteControl
   
   # Compile and copy the track metadata script
   # Replace YOUR_PROJECT_PATH with the actual path to your Podstash project
   osacompile -o ~/Library/Application\ Support/Airfoil/TrackTitles/me.geoffoliver.Podstash.scpt \
       YOUR_PROJECT_PATH/AirfoilScripts/TrackMetadata.scpt
   
   # Compile and copy the remote control script
   osacompile -o ~/Library/Application\ Support/Airfoil/RemoteControl/dacp.me.geoffoliver.Podstash.scpt \
       YOUR_PROJECT_PATH/AirfoilScripts/RemoteControl.scpt
   ```

2. **Launch Airfoil** (if you have it installed)

3. **Select Podstash as the audio source** in Airfoil

4. **Start playing an episode in Podstash**

5. **Check Airfoil Speakers** (or Airfoil on another Mac):
   - You should see the episode title
   - You should see the podcast name as the artist
   - You should see the podcast artwork
   - The play/pause, next, and previous buttons should be enabled

6. **Test remote control:**
   - Click the play/pause button in Airfoil Speakers → Podstash should pause/resume
   - Click the next button → Podstash should skip forward (default 30 seconds, configurable in settings)
   - Click the previous button → Podstash should skip backward (default 15 seconds, configurable in settings)

### Test 3: Verify Artwork Transmission

1. With Airfoil transmitting Podstash to an Airfoil Satellite or Apple TV
2. Look at the Now Playing display on the satellite device
3. You should see the podcast's album artwork

## Troubleshooting

### "Podstash isn't scriptable" error

- Check that `NSAppleScriptEnabled` is set to `YES` in Info.plist
- Check that `OSAScriptingDefinition` points to `Podstash.sdef`
- Rebuild the app completely (Clean Build Folder: ⌘⇧K, then Build: ⌘B)

### No metadata showing in Airfoil Speakers

- Make sure the script is in the correct location with the correct filename
- The filename must match your bundle identifier exactly
- Check the Console app for any AppleScript errors
- Try running the test script in Script Editor first

### Remote control buttons don't appear

- Make sure the remote control script is in `~/Library/Application Support/Airfoil/RemoteControl/`
- The filename must start with `dacp.` and then your bundle identifier
- Restart Airfoil after installing the script

### Artwork doesn't show up

- Make sure the podcast you're playing actually has artwork set
- The artwork is fetched synchronously, so if your network is slow it might take a moment
- Airfoil caches artwork, so it will only be fetched once per podcast

## File Locations Reference

```
~/Library/Application Support/Airfoil/
├── TrackTitles/
│   └── me.geoffoliver.Podstash.scpt          # Track metadata script
└── RemoteControl/
    └── dacp.me.geoffoliver.Podstash.scpt     # Remote control script
```

## What to Send to Rogue Amoeba

Once you've tested everything and it's working, you can email these two compiled script files to `hello@rogueamoeba.com`:

- `me.geoffoliver.Podstash.scpt` (from TrackTitles folder)
- `dacp.me.geoffoliver.Podstash.scpt` (from RemoteControl folder)

Include a brief note like:

> Hi! I've added AppleScript support to my podcast app, Podstash, and would love to have it included in a future Airfoil update. Attached are the track metadata and remote control scripts. The app supports episode title, podcast name (as artist/album), duration, artwork display, and playback controls (play/pause, next, previous).

They may include these in a future version of Airfoil so all users automatically get Podstash support!

## Notes

- The "next" button skips forward in the current episode by the configured interval (default 30 seconds, adjustable in Podstash settings)
- The "previous" button skips backward in the current episode by the configured interval (default 15 seconds, adjustable in Podstash settings)
- If there's no episode playing, all metadata will return "missing value" in AppleScript, which Airfoil handles gracefully
- The artwork is fetched synchronously when requested, so Airfoil may cache it to avoid repeated fetches

Enjoy your Airfoil integration! 🎧
