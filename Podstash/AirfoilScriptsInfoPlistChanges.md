# Info.plist Changes for Airfoil Integration

Add these two keys to your Info.plist file to enable AppleScript support:

## Option 1: Edit in Xcode (Recommended)

1. Select your project in the Xcode navigator
2. Select the "Podstash" target
3. Click on the "Info" tab
4. Click the "+" button under "Custom macOS Application Target Properties"
5. Add these keys:

**Key 1:**
- Key: `Scriptable` (or type `NSAppleScriptEnabled`)
- Type: Boolean
- Value: YES

**Key 2:**
- Key: `Scripting definition file name` (or type `OSAScriptingDefinition`)
- Type: String
- Value: `Podstash.sdef`

## Option 2: Edit Info.plist as Source Code

If you prefer to edit the raw plist file, add these lines inside the `<dict>` tag:

```xml
<key>NSAppleScriptEnabled</key>
<true/>
<key>OSAScriptingDefinition</key>
<string>Podstash.sdef</string>
```

## Verification

After adding these keys:
1. Clean your build folder (⌘⇧K)
2. Build your project (⌘B)
3. The Podstash.sdef file should be copied into your app bundle
4. Your app will now be AppleScript-enabled

You can verify by running this in Terminal after building:

```bash
# Replace with your actual build path
plutil -p ~/Library/Developer/Xcode/DerivedData/Podstash-*/Build/Products/Debug/Podstash.app/Contents/Info.plist | grep -i script
```

You should see:
```
"NSAppleScriptEnabled" => 1
"OSAScriptingDefinition" => "Podstash.sdef"
```
