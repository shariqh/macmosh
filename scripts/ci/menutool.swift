// menutool: posts pointer and key events and reads MacMosh's menu windows. CI only
// (.github/workflows/menu-pictures.yml, through scripts/ci/drive-menu.sh). It moves the pointer and
// presses keys, so never run it on your own Mac. Cut down from the trial's trialtool
// (branch trial-submenus, trials/submenu/Sources/trialtool).
//
//   menutool preflight             what this process may do (post events, capture the screen)
//   menutool move <x> <y>          moves the pointer there in small steps (CGEvent mouseMoved)
//   menutool click <x> <y>         moves there, rests 150 ms, then left button down and up
//   menutool rushclick <x> <y>     one move straight there, and the button down one window list after it: a click
//                                  that lands before a row's submenu can open (it opens about 0.25 s
//                                  after the pointer reaches the row, on the trial's runners)
//   menutool keys <code> <count> <gap ms>   posts that key <count> times (CGEvent key down and up)
//   menutool type <text>           types the text, one key per character, each found in this Mac's keyboard
//                                  layout (UCKeyTranslate), with Shift where the layout needs it
//   menutool chord <character> cmd|shiftcmd   that character's key with Command held (Command-V, Command-A),
//                                  or with Shift and Command (Shift-Command-Z)
//   menutool count                 how many MacMosh menu windows are on screen (the menu and its submenus)
//   menutool windows <label>       those windows' bounds
//   menutool watch <seconds> <label>   samples the menu windows (a 50 ms rest plus one window list
//                                  between samples), prints each change and, at the end, the fewest
//                                  and most seen and the average gap between samples
//
// Built by the workflow with swiftc, as a single file. Each line it prints starts with a Unix time.
import AppKit
import ApplicationServices
import Carbon
import CoreGraphics

func stamp() -> String { String(format: "%.3f", Date().timeIntervalSince1970) }
func out(_ text: String) {
    print(stamp() + " tool " + text)
    fflush(stdout)
}

let args = CommandLine.arguments
guard args.count >= 2 else {
    out("usage: menutool preflight|move|click|rushclick|keys|type|chord|count|windows|watch")
    exit(2)
}

/// The app whose menu windows are counted: the menu bar item's owner.
let owner = ProcessInfo.processInfo.environment["MENUTOOL_OWNER"] ?? "MacMosh"
let source = CGEventSource(stateID: .hidSystemState)

func pointer() -> CGPoint { CGEvent(source: nil)?.location ?? .zero }

func post(_ type: CGEventType, _ at: CGPoint) {
    let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: at, mouseButton: .left)
    if type == .leftMouseDown || type == .leftMouseUp { event?.setIntegerValueField(.mouseEventClickState, value: 1) }
    event?.post(tap: .cghidEventTap)
}

func moveTo(_ target: CGPoint) {
    let start = pointer()
    let steps = 8
    for step in 1...steps {
        let f = CGFloat(step) / CGFloat(steps)
        post(.mouseMoved, CGPoint(x: start.x + (target.x - start.x) * f, y: start.y + (target.y - start.y) * f))
        usleep(25_000)
    }
}

func click(_ target: CGPoint) {
    post(.leftMouseDown, target)
    usleep(60_000)
    post(.leftMouseUp, target)
}

/// The app's menu windows on screen (layer 101, the pop-up menu layer on the trial's runners), as
/// "x,y,w,h" strings.
func menuWindows() -> [String] {
    let list = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]) ?? []
    return list.compactMap { info in
        guard info[kCGWindowOwnerName as String] as? String == owner,
              info[kCGWindowLayer as String] as? Int == 101,
              let b = info[kCGWindowBounds as String] as? [String: Any] else { return nil }
        return "\(b["X"] ?? "?"),\(b["Y"] ?? "?"),\(b["Width"] ?? "?"),\(b["Height"] ?? "?")"
    }.sorted()
}

/// Each character this Mac's keyboard layout types with one key, and whether it needs Shift. Apple,
/// UCKeyTranslate (macOS 10.0, https://developer.apple.com/documentation/coreservices/1390584-uckeytranslate):
/// "Converts a combination of a virtual key code, a modifier key state, and a dead-key state into a string of
/// one or more Unicode characters."
func keyMap() -> [Character: (code: CGKeyCode, shift: Bool)] {
    guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
          let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return [:] }
    let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
    var map: [Character: (code: CGKeyCode, shift: Bool)] = [:]
    data.withUnsafeBytes { buffer in
        guard let base = buffer.baseAddress else { return }
        let layout = base.assumingMemoryBound(to: UCKeyboardLayout.self)
        for shift in [false, true] {
            for code in 0..<128 {
                var dead: UInt32 = 0
                var length = 0
                var chars = [UniChar](repeating: 0, count: 4)
                let modifiers: UInt32 = shift ? UInt32((shiftKey >> 8) & 0xFF) : 0
                let status = UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDown), modifiers,
                                            UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                                            &dead, chars.count, &length, &chars)
                guard status == noErr, length == 1 else { continue }
                let text = String(utf16CodeUnits: chars, count: length)
                if let c = text.first, map[c] == nil { map[c] = (CGKeyCode(code), shift) }
            }
        }
    }
    return map
}

/// One key down and up, with these flags, carrying `text` as its characters too.
func press(_ code: CGKeyCode, flags: CGEventFlags, text: String?) {
    for down in [true, false] {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else { continue }
        event.flags = flags
        if let text {
            let units = Array(text.utf16)
            event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
        }
        event.post(tap: .cghidEventTap)
        usleep(down ? 30_000 : 40_000)
    }
}

func point(_ index: Int) -> CGPoint {
    guard args.count > index + 1, let x = Double(args[index]), let y = Double(args[index + 1]) else {
        out("needs x and y")
        exit(2)
    }
    return CGPoint(x: x, y: y)
}

switch args[1] {
case "preflight":
    out("preflight postEvent=\(CGPreflightPostEventAccess()) screenCapture=\(CGPreflightScreenCaptureAccess()) axTrusted=\(AXIsProcessTrusted())")
    out("display main bounds=\(CGDisplayBounds(CGMainDisplayID())) screens=\(NSScreen.screens.map { "\($0.frame) visible=\($0.visibleFrame) scale=\($0.backingScaleFactor)" })")
case "move":
    let target = point(2)
    moveTo(target)
    usleep(100_000)
    out("move to \(target) pointer now at \(pointer())")
case "click":
    let target = point(2)
    moveTo(target)
    usleep(150_000)
    click(target)
    usleep(100_000)
    out("click at \(target) pointer now at \(pointer())")
case "rushclick":
    let target = point(2)
    let from = pointer()
    _ = menuWindows()   // the first window list of a process is slow; this one is not timed
    let arrived = Date()
    post(.mouseMoved, target)
    let before = menuWindows()   // one window list (about 50 ms on the runners) is the only wait
    let down = Date()
    post(.leftMouseDown, target)
    usleep(60_000)
    post(.leftMouseUp, target)
    let ms = Int(down.timeIntervalSince(arrived) * 1000)
    out("rushclick from \(from) to \(target): button down \(ms) ms after the move; menu windows just before it: \(before.count) \(before)")
case "keys":
    guard args.count >= 5, let code = CGKeyCode(args[2]), let count = Int(args[3]), let gap = UInt32(args[4]) else {
        out("usage: menutool keys <code> <count> <gap ms>")
        exit(2)
    }
    for _ in 0..<count {
        CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true)?.post(tap: .cghidEventTap)
        usleep(30_000)
        CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)?.post(tap: .cghidEventTap)
        usleep(gap * 1000)
    }
    out("keys: posted key \(code) \(count) times")
case "type":
    guard args.count >= 3 else {
        out("usage: menutool type <text>")
        exit(2)
    }
    let map = keyMap()
    var missing = 0
    for c in args[2] {
        if let key = map[c] {
            press(key.code, flags: key.shift ? .maskShift : [], text: String(c))
        } else {
            missing += 1
            press(0, flags: [], text: String(c))
        }
    }
    out("type: \(args[2].count) characters, \(missing) not in the keyboard layout (sent as text only), layout keys=\(map.count)")
case "chord":
    guard args.count >= 4, let c = args[2].first, args[3] == "cmd" || args[3] == "shiftcmd" else {
        out("usage: menutool chord <character> cmd|shiftcmd")
        exit(2)
    }
    let shifted = args[3] == "shiftcmd"
    guard let key = keyMap()[c] else {
        out("chord: no key for \(c) in the keyboard layout")
        exit(1)
    }
    // Apple, CGEventFlags.maskCommand: "Indicates that the Command key is down for a keyboard, mouse, or
    // flag-changed event." (https://developer.apple.com/documentation/coregraphics/cgeventflags/maskcommand)
    // Apple, CGEventFlags.maskShift: "Indicates that the Shift key is down for a keyboard, mouse, or flag-changed
    // event." (https://developer.apple.com/documentation/coregraphics/cgeventflags/maskshift)
    // The modifier keys go down first and come up last, as on a keyboard (kVK_Command and kVK_Shift, Carbon's
    // virtual key codes), each carrying the flags held at that moment.
    let flags: CGEventFlags = shifted ? [.maskCommand, .maskShift] : .maskCommand
    func modifier(_ code: Int, down: Bool, flags: CGEventFlags) {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(code), keyDown: down) else { return }
        event.flags = flags
        event.post(tap: .cghidEventTap)
        usleep(30_000)
    }
    modifier(kVK_Command, down: true, flags: .maskCommand)
    if shifted { modifier(kVK_Shift, down: true, flags: flags) }
    press(key.code, flags: flags, text: shifted ? String(c).uppercased() : String(c))
    if shifted { modifier(kVK_Shift, down: false, flags: .maskCommand) }
    modifier(kVK_Command, down: false, flags: [])
    out("chord: \(shifted ? "Shift-" : "")Command-\(c) (key \(key.code))")
case "count":
    print(menuWindows().count)
case "windows":
    let label = args.count > 2 ? args[2] : ""
    let now = menuWindows()
    out("windows [\(label)] menu windows=\(now.count) \(now)")
case "watch":
    let seconds = args.count > 2 ? Double(args[2]) ?? 5 : 5
    let label = args.count > 3 ? args[3] : ""
    let end = Date().addingTimeInterval(seconds)
    var last: [String]?
    var samples = 0
    var fewest = Int.max
    var most = 0
    while Date() < end {
        let now = menuWindows()
        samples += 1
        fewest = min(fewest, now.count)
        most = max(most, now.count)
        if now != last {
            out("watch [\(label)] menu windows=\(now.count) \(now)")
            last = now
        }
        usleep(50_000)
    }
    out("watch [\(label)] done after \(samples) samples fewest=\(fewest) most=\(most), about \(Int(seconds * 1000) / max(samples, 1)) ms apart")
default:
    out("unknown command \(args[1])")
    exit(2)
}
