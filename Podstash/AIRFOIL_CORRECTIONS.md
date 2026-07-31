# Airfoil Integration - Corrections Applied

## What Was Fixed

### 1. Bundle Identifier
**Changed from:** `com.geoffoliver.Podstash`  
**Changed to:** `me.geoffoliver.Podstash`

All references updated in:
- ✅ `AirfoilScripts/TrackMetadata.scpt`
- ✅ `AirfoilScripts/RemoteControl.scpt`
- ✅ `AirfoilScripts/install.sh`
- ✅ `AIRFOIL_INTEGRATION.md`
- ✅ `AIRFOIL_QUICKSTART.md`
- ✅ `AIRFOIL_CHECKLIST.md`

### 2. Next/Previous Button Behavior
**Old behavior:**
- Next → Play next episode in queue
- Previous → Skip backward 15 seconds

**New behavior (CORRECT):**
- Next → Skip forward in current episode (configurable interval, default 30 seconds)
- Previous → Skip backward in current episode (configurable interval, default 15 seconds)

#### Code changes:
- ✅ `AppleScriptCommands.swift` - NextCommand now calls `skipForward()` instead of `playNextInQueue()`
- ✅ `AppleScriptCommands.swift` - Added clarifying comments
- ✅ `Podstash.sdef` - Updated command descriptions
- ✅ `AudioPlayerManager.swift` - Reverted `playNextInQueue()` back to `private` (no longer needed publicly)
- ✅ `AirfoilScripts/RemoteControl.scpt` - Added clarifying comments

#### Documentation updates:
- ✅ `AIRFOIL_INTEGRATION.md` - Updated behavior descriptions
- ✅ `AIRFOIL_QUICKSTART.md` - Updated "What Each Button Does"
- ✅ `AIRFOIL_HOW_IT_WORKS.md` - Updated component descriptions

## Summary

The Airfoil integration now correctly:

1. **Uses the right bundle identifier** (`me.geoffoliver.Podstash`)
2. **Skip buttons work as expected for podcasts:**
   - ⏭️ Next = Skip forward by configured interval
   - ⏮️ Previous = Skip backward by configured interval
   
This makes more sense for podcast playback, where users typically want to skip ahead/back in the same episode rather than jumping to different episodes.

## Files You Need to Add to Xcode

These three files should be added to your Xcode project:

1. **Podstash.sdef** - AppleScript definition (corrected)
2. **AppleScriptCommands.swift** - Command handlers (corrected)
3. **NSApplication+Scripting.swift** - Property accessors (unchanged)

## Installation Script

The `install.sh` script now uses the correct bundle identifier and will install scripts to:
- `~/Library/Application Support/Airfoil/TrackTitles/me.geoffoliver.Podstash.scpt`
- `~/Library/Application Support/Airfoil/RemoteControl/dacp.me.geoffoliver.Podstash.scpt`

## What to Send to Rogue Amoeba

When you email Rogue Amoeba, send them:
- `me.geoffoliver.Podstash.scpt` (from TrackTitles folder)
- `dacp.me.geoffoliver.Podstash.scpt` (from RemoteControl folder)

With a note like:

> Hi! I've added AppleScript support to my podcast app, Podstash. Attached are the scripts for track metadata and remote control. The Next/Previous buttons skip forward/backward in the current episode (using configurable intervals). Would love to have these included in a future Airfoil update!

---

**All corrections have been applied. The integration is now ready to use with the correct bundle ID and proper skip behavior!** 🎉
