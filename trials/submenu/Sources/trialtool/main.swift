// trialtool: the trial's pointer, keyboard and window-list helper. CI only.
//
//   trialtool preflight             what this process may do (post events, capture the screen)
//   trialtool windows <label>       the SubmenuTrial windows on screen: layer and bounds
//   trialtool move <x> <y>          moves the pointer there in small steps (CGEvent mouseMoved)
//   trialtool click <x> <y>         moves there, then left button down and up
//   trialtool where                 where the pointer is now
//   trialtool clickafter <log> <ms> <x> <y>   moves there, waits for the next "model change" line
//                                   in the log, waits <ms> more, then clicks (all within 8 s)
//   trialtool keys <code> <count> <gap ms>   posts that key <count> times (CGEvent key down/up)
//   trialtool watch <seconds> <label>   samples the menu windows every 50 ms, prints each change
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
    out("usage: trialtool preflight|windows|move|click|where")
    exit(2)
}

let source = CGEventSource(stateID: .hidSystemState)

func pointer() -> CGPoint { CGEvent(source: nil)?.location ?? .zero }

func moveTo(_ target: CGPoint) {
    let start = pointer()
    let steps = 8
    for step in 1...steps {
        let f = CGFloat(step) / CGFloat(steps)
        let p = CGPoint(x: start.x + (target.x - start.x) * f, y: start.y + (target.y - start.y) * f)
        CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)?
            .post(tap: .cghidEventTap)
        usleep(25_000)
    }
}

func click(_ target: CGPoint) {
    let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: target, mouseButton: .left)
    let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: target, mouseButton: .left)
    down?.setIntegerValueField(.mouseEventClickState, value: 1)
    up?.setIntegerValueField(.mouseEventClickState, value: 1)
    down?.post(tap: .cghidEventTap)
    usleep(60_000)
    up?.post(tap: .cghidEventTap)
}

/// The SubmenuTrial menu windows on screen (layer 101), as "x,y,w,h" strings.
func menuWindows() -> [String] {
    let list = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]) ?? []
    return list.compactMap { info in
        guard info[kCGWindowOwnerName as String] as? String == "SubmenuTrial",
              info[kCGWindowLayer as String] as? Int == 101,
              let b = info[kCGWindowBounds as String] as? [String: Any] else { return nil }
        return "\(b["X"] ?? "?"),\(b["Y"] ?? "?"),\(b["Width"] ?? "?"),\(b["Height"] ?? "?")"
    }.sorted()
}

func point(_ index: Int) -> CGPoint {
    CGPoint(x: Double(args[index]) ?? 0, y: Double(args[index + 1]) ?? 0)
}

switch args[1] {
case "preflight":
    out("preflight postEvent=\(CGPreflightPostEventAccess()) listenEvent=\(CGPreflightListenEventAccess()) screenCapture=\(CGPreflightScreenCaptureAccess()) axTrusted=\(AXIsProcessTrusted())")
    out("display main bounds=\(CGDisplayBounds(CGMainDisplayID())) displays=\(NSScreen.screens.map { "\($0.frame) visible=\($0.visibleFrame)" })")
case "where":
    out("pointer at \(pointer())")
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
case "clickafter":
    let path = args[2]
    let delay = UInt32(args[3]) ?? 0
    let target = point(4)
    moveTo(target)
    guard let handle = FileHandle(forReadingAtPath: path) else {
        out("clickafter: cannot read the log")
        exit(1)
    }
    handle.seekToEndOfFile()
    let deadline = Date().addingTimeInterval(8)
    var seen: String?
    while seen == nil && Date() < deadline {
        let data = handle.availableData
        if let text = String(data: data, encoding: .utf8),
           let line = text.split(separator: "\n").first(where: { $0.contains("model change") }) {
            seen = String(line.prefix(60))
        } else {
            usleep(10_000)
        }
    }
    guard let seen else {
        out("clickafter: no model change within 8 s, no click")
        exit(1)
    }
    let seenAt = stamp()
    usleep(delay * 1000)
    let before = menuWindows()
    click(target)
    out("clickafter: saw [\(seen)] at \(seenAt), clicked \(target) \(delay) ms later; menu windows just before the click: \(before)")
case "subclick":
    // subclick <log> <px> <py> <sx> <sy>: after the next model change, rest on the parent row,
    // move into the submenu and click (sx, sy), all inside one 2-second tick.
    let path = args[2]
    let parent = point(3)
    let target = point(5)
    guard let handle = FileHandle(forReadingAtPath: path) else {
        out("subclick: cannot read the log")
        exit(1)
    }
    handle.seekToEndOfFile()
    let deadline = Date().addingTimeInterval(8)
    var seen = false
    while !seen && Date() < deadline {
        if let text = String(data: handle.availableData, encoding: .utf8), text.contains("model change") {
            seen = true
        } else {
            usleep(10_000)
        }
    }
    guard seen else {
        out("subclick: no model change within 8 s")
        exit(1)
    }
    out("subclick: change seen")
    usleep(200_000)
    moveTo(parent)
    usleep(500_000)
    out("subclick: resting on the parent row, menu windows \(menuWindows())")
    moveTo(CGPoint(x: target.x, y: parent.y))
    moveTo(target)
    usleep(150_000)
    out("subclick: on the target, menu windows \(menuWindows())")
    click(target)
    out("subclick: clicked \(target)")
case "keys":
    let code = CGKeyCode(args[2]) ?? 0
    let count = Int(args[3]) ?? 1
    let gap = UInt32(args[4]) ?? 150
    for _ in 0..<count {
        CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true)?.post(tap: .cghidEventTap)
        usleep(30_000)
        CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)?.post(tap: .cghidEventTap)
        usleep(gap * 1000)
    }
    out("keys: posted key \(code) \(count) times")
case "watch":
    let seconds = Double(args[2]) ?? 5
    let label = args.count > 3 ? args[3] : ""
    let end = Date().addingTimeInterval(seconds)
    var last: [String]? = nil
    var samples = 0
    while Date() < end {
        let now = menuWindows()
        samples += 1
        if now != last {
            out("watch [\(label)] menu windows=\(now.count) \(now)")
            last = now
        }
        usleep(50_000)
    }
    out("watch [\(label)] done after \(samples) samples")
case "windows":
    let label = args.count > 2 ? args[2] : ""
    let list = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]) ?? []
    var menus = 0
    var lines: [String] = []
    for info in list {
        let owner = info[kCGWindowOwnerName as String] as? String ?? "?"
        let layer = info[kCGWindowLayer as String] as? Int ?? -1
        guard owner == "SubmenuTrial" || (layer >= 101 && layer < 1000 && owner != "Window Server") else { continue }
        let bounds = info[kCGWindowBounds as String] as? [String: Any] ?? [:]
        let b = "x=\(bounds["X"] ?? "?") y=\(bounds["Y"] ?? "?") w=\(bounds["Width"] ?? "?") h=\(bounds["Height"] ?? "?")"
        if layer == 101 && owner == "SubmenuTrial" { menus += 1 }
        lines.append("window [\(label)] owner=\(owner) layer=\(layer) \(b)")
    }
    out("windows [\(label)] menuWindows=\(menus) total=\(lines.count)")
    lines.forEach(out)
default:
    out("unknown command \(args[1])")
    exit(2)
}
