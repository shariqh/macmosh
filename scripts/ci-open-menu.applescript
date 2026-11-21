-- CI only: opens MacMosh's menu the way a person does, by clicking its icon in the menu bar.
-- System Events does the click, so whoever runs this needs the Accessibility permission. GitHub's
-- macOS runners have it; on your own Mac, don't run this.
-- What it finds goes to stderr (`log`), so a failed run says where it stopped.

with timeout of 30 seconds
	tell application "System Events"
		if not (exists process "MacMosh") then error "MacMosh is not running"
		tell process "MacMosh"
			set barCount to count of menu bars
			log "MacMosh has " & barCount & " menu bar(s)"
			if barCount is 0 then error "MacMosh has no menu bar to click"
			-- The menu-bar icon sits in the last menu bar: the only one for an app with no Dock icon.
			set itemCount to count of menu bar items of menu bar barCount
			log "its last menu bar has " & itemCount & " item(s)"
			if itemCount is 0 then error "MacMosh's menu bar has no item to click"
			click menu bar item 1 of menu bar barCount
		end tell
	end tell
end timeout
