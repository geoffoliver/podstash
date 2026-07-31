# 🎧 Airfoil Integration - Quick Start Guide

## What I Created for You

I've set up complete Airfoil integration for Podstash! Here's what was added:

### ✅ Core Files Created

1. **`Podstash.sdef`** - AppleScript definition file
   - Defines all the properties and commands Airfoil needs
   - Add this to your Xcode project target

2. **`AppleScriptCommands.swift`** - Command handlers
   - Implements play/pause, next, and previous commands
   - Already references your MenuCoordinator

3. **`NSApplication+Scripting.swift`** - Property accessors
   - Provides track title, artist, album, duration, and artwork
   - Returns proper "missing value" when nothing is playing

### ✅ Code Changes Made

4. **`AudioPlayerManager.swift`** - Modified
   - Changed `playNextInQueue()` from `private` to `func` (public)
   - Now accessible for the "next" AppleScript command

### ✅ Scripts for Airfoil

5. **`AirfoilScripts/TrackMetadata.scpt`** - Track metadata script
   - Returns episode/podcast info to Airfoil
   - Install to: `~/Library/Application Support/Airfoil/TrackTitles/`

6. **`AirfoilScripts/RemoteControl.scpt`** - Remote control script
   - Handles playback controls from Airfoil Speakers
   - Install to: `~/Library/Application Support/Airfoil/RemoteControl/`

### ✅ Helper Files

7. **`AirfoilScripts/install.sh`** - Installation script
   - Automatically compiles and installs the AppleScript files
   - Run this after building your app

8. **`AirfoilScripts/TestScript.applescript`** - Test script
   - Comprehensive test of all AppleScript features
   - Run in Script Editor to verify everything works

9. **`AIRFOIL_INTEGRATION.md`** - Complete documentation
   - Detailed setup instructions
   - Testing procedures
   - Troubleshooting guide

10. **`AirfoilScripts/InfoPlistChanges.md`** - Info.plist reference
    - Shows exactly what to add to enable AppleScript

## 🚀 Next Steps (In Order)

### Step 1: Add Files to Xcode
1. Drag these files into Xcode (make sure they're in your target):
   - `Podstash.sdef`
   - `AppleScriptCommands.swift`
   - `NSApplication+Scripting.swift`

### Step 2: Update Info.plist
Add these two keys (see `InfoPlistChanges.md` for details):
- `NSAppleScriptEnabled` = YES
- `OSAScriptingDefinition` = "Podstash.sdef"

### Step 3: Build
- Clean Build Folder (⌘⇧K)
- Build (⌘B)

### Step 4: Test with Script Editor
1. Run Podstash
2. Play an episode
3. Open Script Editor
4. Open and run `AirfoilScripts/TestScript.applescript`
5. You should see all tests pass! ✓

### Step 5: Install Airfoil Scripts
```bash
cd AirfoilScripts
chmod +x install.sh
./install.sh
```

### Step 6: Test with Airfoil
1. Open Airfoil
2. Select Podstash as the audio source
3. Select an output device (like Airfoil Speakers)
4. Play an episode
5. You should see:
   - Episode title
   - Podcast name
   - Artwork
   - Working play/pause/next/previous buttons

## 📝 Important Notes

### Bundle Identifier
The scripts are configured for bundle identifier `me.geoffoliver.Podstash`.

### What Each Button Does
- **Play/Pause**: Toggles playback
- **Next**: Skips forward in current episode (default 30 seconds, configurable in settings)
- **Previous**: Skips backward in current episode (default 15 seconds, configurable in settings)

### Artwork Loading
- Artwork is fetched synchronously when requested
- Airfoil caches it, so it's only fetched once per podcast
- If artwork seems slow, it's because it's downloading from the URL

## 🐛 Troubleshooting

**"Podstash isn't scriptable"**
→ Make sure you added the Info.plist keys and included Podstash.sdef in your target

**No metadata in Airfoil**
→ Make sure the script is named exactly `com.your.bundleid.scpt` (check bundle ID!)

**Controls don't work**
→ Make sure the remote control script is named `dacp.com.your.bundleid.scpt` (note the "dacp." prefix!)

**Artwork doesn't show**
→ Make sure the podcast actually has artwork set in Podstash

## 📧 Sending to Rogue Amoeba

Once it's all working, email these files to `hello@rogueamoeba.com`:
- `~/Library/Application Support/Airfoil/TrackTitles/me.geoffoliver.Podstash.scpt`
- `~/Library/Application Support/Airfoil/RemoteControl/dacp.me.geoffoliver.Podstash.scpt`

They'll include them in future Airfoil updates!

## ✨ That's It!

You now have full Airfoil integration with:
- ✅ Episode metadata display
- ✅ Podcast artwork transmission
- ✅ Remote playback controls
- ✅ All properly formatted for Airfoil Speakers

Enjoy streaming your podcasts around your house! 🎉
