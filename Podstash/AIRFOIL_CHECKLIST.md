# Airfoil Integration Files Checklist

## ✅ Files Created

### In Your Project Root:
- [ ] `Podstash.sdef` → AppleScript definition (ADD TO XCODE TARGET!)
- [ ] `AppleScriptCommands.swift` → Command handlers (ADD TO XCODE TARGET!)
- [ ] `NSApplication+Scripting.swift` → Property accessors (ADD TO XCODE TARGET!)
- [x] `AudioPlayerManager.swift` → Modified (playNextInQueue is now public)
- [ ] `AIRFOIL_INTEGRATION.md` → Full documentation
- [ ] `AIRFOIL_QUICKSTART.md` → Quick start guide

### In AirfoilScripts/ folder:
- [ ] `TrackMetadata.scpt` → Track info for Airfoil
- [ ] `RemoteControl.scpt` → Playback controls for Airfoil
- [ ] `install.sh` → Auto-installer script
- [ ] `TestScript.applescript` → Testing script for Script Editor
- [ ] `InfoPlistChanges.md` → Info.plist reference

## ✅ Xcode Setup Checklist

### 1. Add Files to Project
- [ ] Drag `Podstash.sdef` into Xcode
- [ ] Make sure it's in your app target (check Target Membership)
- [ ] Drag `AppleScriptCommands.swift` into Xcode (if not already there)
- [ ] Drag `NSApplication+Scripting.swift` into Xcode (if not already there)

### 2. Update Info.plist
- [ ] Open your project settings → Target → Info tab
- [ ] Add `Scriptable` (NSAppleScriptEnabled) → YES
- [ ] Add `Scripting definition file name` (OSAScriptingDefinition) → "Podstash.sdef"

### 3. Verify Build Settings
- [ ] Go to Build Phases → Copy Bundle Resources
- [ ] Confirm `Podstash.sdef` is listed
- [ ] If not, click "+" and add it

## ✅ Testing Checklist

### Before Installing Airfoil Scripts:
- [ ] Clean Build Folder (⌘⇧K)
- [ ] Build project (⌘B)
- [ ] Run Podstash
- [ ] Play an episode
- [ ] Open Script Editor (/Applications/Utilities/Script Editor.app)
- [ ] Open `AirfoilScripts/TestScript.applescript`
- [ ] Click Run
- [ ] All tests should pass with ✓

### Install Airfoil Scripts:
- [ ] Open Terminal
- [ ] `cd` to your project directory
- [ ] `cd AirfoilScripts`
- [ ] `chmod +x install.sh`
- [ ] `./install.sh`
- [ ] Should see green ✓ marks

### Test with Airfoil:
- [ ] Make sure Podstash is running
- [ ] Play an episode
- [ ] Open Airfoil
- [ ] Select Podstash as the source
- [ ] You should see the audio waveform
- [ ] Connect to an Airfoil Speaker or device
- [ ] In Airfoil Speakers you should see:
  - [ ] Episode title
  - [ ] Podcast name
  - [ ] Podcast artwork
  - [ ] Play/pause button (working)
  - [ ] Next button (working)
  - [ ] Previous button (working)

## ✅ Final Steps

### If Everything Works:
- [ ] Email the compiled scripts to hello@rogueamoeba.com
  - Located at: `~/Library/Application Support/Airfoil/TrackTitles/me.geoffoliver.Podstash.scpt`
  - And: `~/Library/Application Support/Airfoil/RemoteControl/dacp.me.geoffoliver.Podstash.scpt`
- [ ] Include a note saying you'd like them included in Airfoil
- [ ] Party! 🎉

### Common Issues:

**"Podstash isn't scriptable" error:**
→ Info.plist keys not added correctly. Double-check both keys are present.

**Script Editor can't find properties:**
→ Podstash.sdef not in Copy Bundle Resources. Rebuild after adding it.

**Airfoil doesn't show metadata:**
→ Script filename doesn't match bundle identifier. Check bundle ID in Xcode.

**Remote controls don't appear:**
→ Remote script needs "dacp." prefix: `dacp.me.geoffoliver.Podstash.scpt`

**Artwork doesn't display:**
→ Normal if podcast has no artwork, or network is slow (it's fetched live)

## 📁 Final File Structure

```
YourProject/
├── Podstash.sdef                           ← Add to Xcode
├── AppleScriptCommands.swift               ← Add to Xcode
├── NSApplication+Scripting.swift           ← Add to Xcode
├── AudioPlayerManager.swift                ← Already modified
├── PodstashApp.swift                       ← No changes needed
├── AIRFOIL_INTEGRATION.md                  ← Reference docs
├── AIRFOIL_QUICKSTART.md                   ← Quick guide
└── AirfoilScripts/
    ├── TrackMetadata.scpt                  ← For Airfoil
    ├── RemoteControl.scpt                  ← For Airfoil
    ├── install.sh                          ← Run this to install
    ├── TestScript.applescript              ← Test in Script Editor
    └── InfoPlistChanges.md                 ← Info.plist reference
```

---

**Questions? Check:**
1. `AIRFOIL_QUICKSTART.md` for the fast path
2. `AIRFOIL_INTEGRATION.md` for detailed explanations
3. `InfoPlistChanges.md` for Info.plist help
