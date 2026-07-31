# AIRFOIL INTEGRATION - FILE CLEANUP GUIDE

## The Mess Explained

Due to limitations in how I create files, a bunch of incorrectly named files were created. Here's what you need to do to fix this:

## Files You Need (3 Swift files + 1 sdef + 2 scripts + 1 installer)

### 1. Core Swift/Scripting Files (Add to Xcode)

**Podstash.sdef** - Use the one without "2" in the name
- If it has syntax errors or is missing, here's the correct content:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE dictionary SYSTEM "file://localhost/System/Library/DTDs/sdef.dtd">
<dictionary title="Podstash Terminology">
    <suite name="Podstash Suite" code="Pdst" description="Podstash scripting support for Airfoil integration">
        <class name="application" code="capp" description="Podstash application">
            <cocoa class="NSApplication"/>
            
            <property name="track title" code="pTTl" type="text" access="r" description="The title of the currently playing episode">
                <cocoa key="trackTitle"/>
            </property>
            
            <property name="artist" code="pArt" type="text" access="r" description="The podcast name (artist)">
                <cocoa key="artist"/>
            </property>
            
            <property name="album" code="pAlb" type="text" access="r" description="The podcast name (album)">
                <cocoa key="album"/>
            </property>
            
            <property name="duration" code="pDur" type="integer" access="r" description="The duration of the current episode in seconds">
                <cocoa key="duration"/>
            </property>
            
            <property name="logo" code="pLog" type="TIFF picture" access="r" description="The podcast artwork as TIFF data">
                <cocoa key="logo"/>
            </property>
            
            <command name="playpause" code="PdstPlps" description="Toggle play/pause of the current episode">
                <cocoa class="PlayPauseCommand"/>
            </command>
            
            <command name="next" code="PdstNext" description="Skip forward in the current episode by the configured interval">
                <cocoa class="NextCommand"/>
            </command>
            
            <command name="previous" code="PdstPrev" description="Skip backward in the current episode by the configured interval">
                <cocoa class="PreviousCommand"/>
            </command>
        </class>
    </suite>
</dictionary>
```

**AppleScriptCommands.swift** - Should be fine, verify it has this:

```swift
#if os(macOS)
import Foundation
import AppKit

@objc(PlayPauseCommand)
class PlayPauseCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        Task { @MainActor in
            MenuCoordinator.shared.audioPlayer?.togglePlayPause()
        }
        return nil
    }
}

@objc(NextCommand)
class NextCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        Task { @MainActor in
            MenuCoordinator.shared.audioPlayer?.skipForward()
        }
        return nil
    }
}

@objc(PreviousCommand)
class PreviousCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        Task { @MainActor in
            MenuCoordinator.shared.audioPlayer?.skipBackward()
        }
        return nil
    }
}
#endif
```

**NSApplication+Scripting.swift** - Should be fine as-is

### 2. AppleScript Files (For Airfoil)

Create these TWO files in your project root (same directory as install.sh):

**File: TrackMetadata.scpt**
```applescript
tell application "Podstash"
	try
		set theTitle to track title
		set theArtist to artist
		set theAlbum to album
		set theDuration to duration
		set theLogo to logo
		return {theTitle, theArtist, theAlbum, theDuration, theLogo}
	on error
		return {missing value, missing value, missing value, missing value, missing value}
	end try
end tell
```

**File: RemoteControl.scpt**
```applescript
on remote_play()
	tell application "Podstash" to playpause
end remote_play

on remote_pause()
	tell application "Podstash" to playpause
end remote_pause

on remote_next_item()
	tell application "Podstash" to next
end remote_next_item

on remote_previous_item()
	tell application "Podstash" to previous
end remote_previous_item
```

### 3. Installer Script

**File: install.sh**
(Use the one that's already there - it should be fine)

## How to Clean Up

1. **Delete all files with "2" in the name** (Podstash 2.sdef, RemoteControl 2.scpt, etc.)

2. **Delete all files starting with "AirfoilScripts"** (these were incorrectly named)

3. **Keep these files:**
   - `Podstash.sdef`
   - `AppleScriptCommands.swift`
   - `NSApplication+Scripting.swift`
   - `install.sh`

4. **Manually create these two files** in the same directory as install.sh:
   - `TrackMetadata.scpt` (copy content from above)
   - `RemoteControl.scpt` (copy content from above)

## Installation Steps

1. Add to Xcode (make sure they're in your target):
   - Podstash.sdef
   - AppleScriptCommands.swift
   - NSApplication+Scripting.swift

2. Update Info.plist:
   - Add `NSAppleScriptEnabled` = YES
   - Add `OSAScriptingDefinition` = "Podstash.sdef"

3. Build your app (⌘B)

4. Run from Terminal (in the directory with install.sh):
   ```bash
   chmod +x install.sh
   ./install.sh
   ```

## Testing

After installation, open Script Editor and run:
```applescript
tell application "Podstash"
    track title
end tell
```

It should return your current episode title (or missing value if nothing is playing).

---

I sincerely apologize for the mess. The file naming issues were due to how the file creation system works in this environment. The above guide should get you to a clean, working state.
