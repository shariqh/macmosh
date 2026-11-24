// menutool: posts pointer and key events and reads MacMosh's menu windows. CI only
// (.github/workflows/menu-pictures.yml, through scripts/ci/drive-menu.sh). It moves the pointer and
// presses keys, so never run it on your own Mac. Cut down from the trial's trialtool
// (branch trial-submenus, trials/submenu/Sources/trialtool).
//
//   menutool preflight             what this process may do (post events, capture the screen)
//   menutool move <x> <y>          moves the pointer there in small steps (CGEvent mouseMoved)
//   menutool click <x> <y>         moves there, rests 150 ms, then left button down and up
//   menutool rushclick <x> <y>     one move straight there, and the button down about 20 ms after it: a click
//                                  that lands before a row's submenu can open (it opens about 0.25 s
//                                  after the pointer reaches the row, on the trial's runners)
//   menutool keys <code> <count> <gap ms>   posts that key <count> times (CGEvent key down and up)
//   menutool count                 how many MacMosh menu windows are on screen (the menu and its submenus)
//   menutool windows <label>       those windows' bounds
//   menutool watch <seconds> <label>   samples the menu windows every 50 ms, prints each change and,
//                                  at the end, the fewest and most seen
//
// Built by the workflow with swiftc, as a single file. Each line it prints starts with a Unix time.
import AppKit
import ApplicationServices
import CoreGraphics

func stamp() -> String { String(format: "%.3f", Date().timeIntervalSince1970) }
func out(_ text: String) {
    print(stamp() + " tool " + text)
    fflush(stdout)
}

let args = CommandLine.arguments
guard args.count >= 2 else {
    out("usage: menutool preflight|move|click|rushclick|keys|count|windows|watch")
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
    usleep(20_000)
    let before = menuWindows()
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
    out("watch [\(label)] done after \(samples) samples fewest=\(fewest) most=\(most)")
default:
    out("unknown command \(args[1])")
    exit(2)
}
