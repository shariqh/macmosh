-- CI only: reads MacMosh's menu through System Events (accessibility). GitHub's macOS runners let
-- osascript do this; on your own Mac, don't run it. Cut down from the trial's ax.applescript (branch
-- trial-submenus). It never presses anything: the driver clicks with posted pointer events.
--
--   osascript menu-ax.applescript barpos                   position and size of the menu-bar item
--   osascript menu-ax.applescript dump <place>             every row of a menu, one per line
--   osascript menu-ax.applescript names <place>            only the rows' names, one per line
--   osascript menu-ax.applescript selected <place>         the highlighted (AXSelected) row of a menu
--   osascript menu-ax.applescript find <place> <prefix>    index, centre x and y, and name of the first
--                                                          row whose name starts with <prefix>
--
-- <place> is "top" for the menu itself, or the start of the name of the top-level row whose submenu
-- is meant (desk rows start with three spaces).

on run argv
	set cmd to item 1 of argv
	with timeout of 15 seconds
		if cmd is "barpos" then
			tell application "System Events" to tell process "MacMosh"
				set b to menu bar item 1 of menu bar (count of menu bars)
				return "bar menus=" & (count of menu bars) & " pos=" & my pair(position of b) & " size=" & my pair(size of b)
			end tell
		else if cmd is "dump" then
			return my dumpMenu(my menuAt(item 2 of argv), item 2 of argv, false)
		else if cmd is "names" then
			return my dumpMenu(my menuAt(item 2 of argv), item 2 of argv, true)
		else if cmd is "selected" then
			set m to my menuAt(item 2 of argv)
			tell application "System Events"
				set n to count of menu items of m
				repeat with i from 1 to n
					set mi to menu item i of m
					try
						if (value of attribute "AXSelected" of mi) is true then return "selected [" & (item 2 of argv) & "] " & i & " " & my nm(mi)
					end try
				end repeat
			end tell
			return "selected [" & (item 2 of argv) & "] none"
		else if cmd is "find" then
			set m to my menuAt(item 2 of argv)
			set wanted to item 3 of argv
			tell application "System Events"
				set n to count of menu items of m
				repeat with i from 1 to n
					set mi to menu item i of m
					set label to my nm(mi)
					if label starts with wanted then
						set p to position of mi
						set s to size of mi
						set cx to ((item 1 of p) + (item 1 of s) / 2) as integer
						set cy to ((item 2 of p) + (item 2 of s) / 2) as integer
						return "found " & i & " " & cx & " " & cy & " " & label
					end if
				end repeat
			end tell
			return "notfound"
		end if
	end timeout
	return "unknown command " & cmd
end run

on menuAt(place)
	tell application "System Events" to tell process "MacMosh"
		set top to menu 1 of menu bar item 1 of menu bar (count of menu bars)
		if place is "top" then return top
		set n to count of menu items of top
		repeat with i from 1 to n
			set mi to menu item i of top
			if my nm(mi) starts with place then return menu 1 of mi
		end repeat
		error "no top-level row starts with [" & place & "]"
	end tell
end menuAt

on nm(mi)
	tell application "System Events"
		try
			set t to name of mi
			if t is missing value then return "<no name>"
			return t
		on error
			return "<no name>"
		end try
	end tell
end nm

on pair(p)
	try
		return ((item 1 of p) as integer as text) & "," & ((item 2 of p) as integer as text)
	on error
		return "?"
	end try
end pair

on dumpMenu(m, place, namesOnly)
	set out to ""
	tell application "System Events"
		if not namesOnly then
			try
				set out to "menu [" & place & "] pos=" & my pair(position of m) & " size=" & my pair(size of m) & linefeed
			on error e
				set out to "menu [" & place & "] pos/size unreadable: " & e & linefeed
			end try
		end if
		set n to count of menu items of m
		repeat with i from 1 to n
			set mi to menu item i of m
			if namesOnly then
				set out to out & my nm(mi) & linefeed
			else
				set line_ to "  item " & i & " name=\"" & my nm(mi) & "\""
				try
					set line_ to line_ & " enabled=" & (enabled of mi)
				end try
				try
					set line_ to line_ & " selected=" & (value of attribute "AXSelected" of mi)
				end try
				try
					set line_ to line_ & " pos=" & my pair(position of mi) & " size=" & my pair(size of mi)
				end try
				try
					set line_ to line_ & " submenus=" & (count of menus of mi)
				end try
				set out to out & line_ & linefeed
			end if
		end repeat
	end tell
	return out
end dumpMenu
