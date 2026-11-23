-- CI only: reads and presses SubmenuTrial's menu through System Events (accessibility).
-- GitHub's macOS runners give osascript the Accessibility permission; on your own Mac, don't run this.
--
--   osascript ax.applescript open                 press the menu-bar item (returns when the menu closes)
--   osascript ax.applescript barpos               position and size of the menu-bar item
--   osascript ax.applescript dump <place>         every item of a menu: place is "top" or a submenu row's name
--   osascript ax.applescript selected <place>     the highlighted (AXSelected) item of that menu
--   osascript ax.applescript press <place> <n>    AXPress item n of that menu (prints its name first)
--   osascript ax.applescript pressname <place> <name>
--   osascript ax.applescript find <place> <name>  index, centre x and y of the item with that name
--   osascript ax.applescript findprefix <place> <prefix>
--   osascript ax.applescript posat <place> <n>     centre x and y of item n
--   osascript ax.applescript key <code>           key code through System Events

on run argv
	set cmd to item 1 of argv
	with timeout of 15 seconds
		if cmd is "open" then
			tell application "System Events" to tell process "SubmenuTrial"
				click menu bar item 1 of menu bar (count of menu bars)
			end tell
			return "open returned"
		else if cmd is "barpos" then
			tell application "System Events" to tell process "SubmenuTrial"
				set b to menu bar item 1 of menu bar (count of menu bars)
				return "bar menus=" & (count of menu bars) & " pos=" & my pair(position of b) & " size=" & my pair(size of b)
			end tell
		else if cmd is "key" then
			tell application "System Events" to key code ((item 2 of argv) as integer)
			return "key " & (item 2 of argv) & " sent"
		else if cmd is "dump" then
			return my dumpMenu(my menuAt(item 2 of argv), item 2 of argv)
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
		else if cmd is "press" then
			set m to my menuAt(item 2 of argv)
			tell application "System Events"
				set mi to menu item ((item 3 of argv) as integer) of m
				set label to my nm(mi)
				log "pressing [" & (item 2 of argv) & "] " & (item 3 of argv) & " " & label
				perform action "AXPress" of mi
			end tell
			return "pressed [" & (item 2 of argv) & "] " & (item 3 of argv) & " " & label
		else if cmd is "pressname" then
			set m to my menuAt(item 2 of argv)
			tell application "System Events"
				set mi to menu item (item 3 of argv) of m
				log "pressing [" & (item 2 of argv) & "] " & (item 3 of argv)
				perform action "AXPress" of mi
			end tell
			return "pressed [" & (item 2 of argv) & "] " & (item 3 of argv)
		else if cmd is "posat" then
			set m to my menuAt(item 2 of argv)
			tell application "System Events"
				set i to (item 3 of argv) as integer
				set mi to menu item i of m
				set p to position of mi
				set s to size of mi
				set cx to ((item 1 of p) + (item 1 of s) / 2) as integer
				set cy to ((item 2 of p) + (item 2 of s) / 2) as integer
				return "found " & i & " " & cx & " " & cy & " " & my nm(mi)
			end tell
		else if cmd is "find" or cmd is "findprefix" then
			set m to my menuAt(item 2 of argv)
			set wanted to item 3 of argv
			tell application "System Events"
				set n to count of menu items of m
				repeat with i from 1 to n
					set mi to menu item i of m
					set label to my nm(mi)
					if (cmd is "find" and label is wanted) or (cmd is "findprefix" and label starts with wanted) then
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
	tell application "System Events" to tell process "SubmenuTrial"
		set top to menu 1 of menu bar item 1 of menu bar (count of menu bars)
		if place is "top" then return top
		return menu 1 of menu item place of top
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

on dumpMenu(m, place)
	set out to ""
	tell application "System Events"
		try
			set out to "menu [" & place & "] pos=" & my pair(position of m) & " size=" & my pair(size of m)
		on error e
			set out to "menu [" & place & "] pos/size unreadable: " & e
		end try
		set n to count of menu items of m
		set out to out & " items=" & n & linefeed
		repeat with i from 1 to n
			set mi to menu item i of m
			set line_ to "  item " & i & " name=\"" & my nm(mi) & "\""
			try
				set line_ to line_ & " enabled=" & (enabled of mi)
			end try
			try
				set line_ to line_ & " selected=" & (value of attribute "AXSelected" of mi)
			end try
			try
				set line_ to line_ & " role=" & (role of mi)
			end try
			try
				set line_ to line_ & " pos=" & my pair(position of mi) & " size=" & my pair(size of mi)
			end try
			try
				set line_ to line_ & " submenus=" & (count of menus of mi)
			end try
			try
				set line_ to line_ & " actions=" & my joinList(name of actions of mi)
			end try
			set out to out & line_ & linefeed
		end repeat
	end tell
	return out
end dumpMenu

on joinList(l)
	set AppleScript's text item delimiters to ","
	set t to l as text
	set AppleScript's text item delimiters to ""
	return t
end joinList
