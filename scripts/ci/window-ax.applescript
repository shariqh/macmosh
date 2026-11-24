-- CI only: reads the MacMosh window through System Events (accessibility). GitHub's macOS runners let
-- osascript do this; on your own Mac, don't run it. It never presses anything: the driver clicks with
-- posted pointer events (menutool). Used by scripts/ci/drive-window.sh.
--
--   osascript window-ax.applescript windows             how many windows called MacMosh the app has
--   osascript window-ax.applescript frame               the window's position and size: "frame x y w h"
--   osascript window-ax.applescript find <identifier>   the centre of the element with that accessibility
--                                                       identifier: "found x y role", or "notfound"
--   osascript window-ax.applescript value <identifier>  that element's value, or its name: "value <text>"
--   osascript window-ax.applescript text <prefix>       the first text whose value starts with <prefix>
--   osascript window-ax.applescript close               the centre of the window's close button
--   osascript window-ax.applescript dump                every element: role, identifier, text, position

on run argv
	set cmd to item 1 of argv
	with timeout of 40 seconds
		tell application "System Events" to tell process "MacMosh"
			if cmd is "windows" then
				return "windows " & (count of (windows whose name is "MacMosh"))
			end if
			if (count of (windows whose name is "MacMosh")) is 0 then return "nowindow"
			set w to first window whose name is "MacMosh"
			if cmd is "frame" then
				set p to position of w
				set s to size of w
				return "frame " & my int(item 1 of p) & " " & my int(item 2 of p) & " " & my int(item 1 of s) & " " & my int(item 2 of s)
			else if cmd is "close" then
				repeat with b in (buttons of w)
					try
						if (subrole of b) is "AXCloseButton" then return "close " & my centre(b)
					end try
				end repeat
				return "notfound"
			else if cmd is "find" or cmd is "value" then
				set wanted to item 2 of argv
				repeat with e in (entire contents of w)
					try
						if (value of attribute "AXIdentifier" of e) is wanted then
							if cmd is "find" then return "found " & my centre(e) & " " & (role of e)
							return "value " & my label(e)
						end if
					end try
				end repeat
				return "notfound"
			else if cmd is "text" then
				set wanted to item 2 of argv
				repeat with e in (entire contents of w)
					try
						if (role of e) is "AXStaticText" then
							set t to my label(e)
							if t starts with wanted then return "text " & t
						end if
					end try
				end repeat
				return "notfound"
			else if cmd is "dump" then
				set out to ""
				repeat with e in (entire contents of w)
					set line_ to ""
					try
						set line_ to (role of e)
					end try
					try
						set i to value of attribute "AXIdentifier" of e
						if i is not missing value and i is not "" then set line_ to line_ & " id=" & i
					end try
					set line_ to line_ & " [" & my label(e) & "]"
					try
						set line_ to line_ & " at " & my centre(e)
					end try
					set out to out & line_ & linefeed
				end repeat
				return out
			end if
		end tell
	end timeout
	return "unknown command " & cmd
end run

on int(n)
	return (n as integer) as text
end int

on centre(e)
	tell application "System Events"
		set p to position of e
		set s to size of e
	end tell
	return my int((item 1 of p) + (item 1 of s) / 2) & " " & my int((item 2 of p) + (item 2 of s) / 2)
end centre

-- The element's value when it has a text one, otherwise its name, otherwise its description.
on label(e)
	tell application "System Events"
		try
			set v to value of e
			if v is not missing value and class of v is text and v is not "" then return v
		end try
		try
			set n to name of e
			if n is not missing value and n is not "" then return n
		end try
		try
			set d to description of e
			if d is not missing value then return d
		end try
	end tell
	return ""
end label
