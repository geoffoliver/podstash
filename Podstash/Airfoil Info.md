
Developer Note: Integrating with Airfoil for Mac

Posted By Rogue Amoeba Alumni on April 6th, 2011
This post was written by Rogue Amoeba alumnus Jeff Johnson.

Among the many improvements included in Airfoil 4, two of particular interest to third-party developers are track metadata display and source remote control. If you make any kind of media playing application, this post is for you. With just a few minutes work, you can get your application to integrate with Airfoil and Airfoil Speakers, so your users can see what’s playing and control playback as well.

The Basics

Airfoil automatically gathers metadata such as track titles and album artwork from supported applications. That metadata is shown when transmitting to Airfoil Speakers or an Apple TV. Currently, Airfoil has built-in track metadata support for iTunes and QuickTime Player, as well as our own applications Airfoil Video Player and Pulsar.

Metadate in Airfoil Speakers

Meanwhile, remote control allows the playback of a transmitted application to be controlled directly in Airfoil Speakers, from across the network. When a supported application is transmitted by Airfoil, buttons for play, previous track, and next track will be shown in Airfoil Speakers. Remote control support is currently built in for iTunes, QuickTime Player, Pulsar, and VLC.

Playback Controls in Airfoil Speakers

How It Works

Both track metadata and remote control are supported by Airfoil via Applescript. This means that support can be added for additional applications simply by adding more Applescripts. So, if your application is scriptable, it can take advantage of Airfoil’s new features by providing Applescript support for track metadata properties and remote control commands.

Airfoil has a kind of Applescript API, which we’ve been using internally. Now we’re documenting the API publicly for third-party developers.

To integrate with Airfoil, your application should handle five Applescript properties — track title, artist, album, duration, and logo — and three Applescript commands — playpause, next, and previous.

A Sample Implementation

The easiest way to explain this Applescript API is to provide an example, so we’ve got a sample Xcode project called Airfoil Integration Sample.

Download for Airfoil Integration Sample

Click to download

The scripting definition for Airfoil Integration Sample is in the file AppleScriptSuite.sdef. The names of the properties and commands (as well as codes, descriptions, and classes in the sdef file) can be customized as needed for your own application. What’s crucial is the type and functionality of each item. The track title, artist, and album properties should all return a string, the duration property should return an integer representing the length of the track in seconds, and the logo property should return TIFF image data. The playpause command should start and stop the audio of the current track, while the next and previous commands should switch to the next or previous track.

In the file AirfoilIntegrationSampleAppDelegate.m, you can see how the Applescript properties and commands are implemented in Cocoa. The string properties are represented by NSString, the duration property by NSNumber, and the logo property by NSData. Note that any of the property methods can also return nil, which corresponds to missing value in Applescript. This is the way to let Airfoil know that a track does not have a particular property.

Once your application supports the appropriate Applescript properties and commands, they can be tested with actual scripts. Airfoil Integration Sample comes with the scripts dacp.com.rogueamoeba.AirfoilIntegrationSample.scpt for remote control and com.rogueamoeba.AirfoilIntegrationSample.scpt for track metadata. When Airfoil transmits an application, it looks for scripts within the Airfoil bundle1, corresponding to the source application’s bundle identifier. New remote control scripts can be placed in the Application Support folder to be loaded by Airfoil:

~/Library/Application Support/Airfoil/RemoteControl/

~/Library/Application Support/Airfoil/TrackTitles/

For track metadata support, it is essential that your script returns the metadata items in the correct order:

    Track title
    Artist
    Album
    Duration
    Logo

Note that you can substitute missing value for any of the five items.

For remote control, you need to support at least the remote_play, remote_pause, remote_previous_item, and remote_next_item items in the script, which will call your Applescript commands playpause, previous, and next.

Get In Touch

Once your application supports track metadata or remote control, just let us know by emailing our hello@rogueamoeba.com address. We can then include your scripts in an update to Airfoil.

Footnotes:

    You can find existing scripts in Airfoil.app/Contents/Resources/RemoteControl and Airfoil.app/Contents/Frameworks/TrackTitles.framework/Resources/Applescripts   ↩
