tell application id "me.geoffoliver.Podstash"
	if it is running then
		set my_info to {track title, artist, album, duration, logo}
		return my_info
	end if
end tell
