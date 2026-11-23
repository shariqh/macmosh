// trialtool: the trial's pointer, keyboard and window-list helper. CI only.
//
//   trialtool preflight             what this process may do (post events, capture the screen)
//   trialtool windows <label>       the SubmenuTrial windows on screen: layer and bounds
//   trialtool move <x> <y>          moves the pointer there in small steps (CGEvent mouseMoved)
//   trialtool click <x> <y>         moves there, then left button down and up
//   trialtool where                 where the pointer is now
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
    let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: target, mouseButton: .left)
    let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: target, mouseButton: .left)
    down?.setIntegerValueField(.mouseEventClickState, value: 1)
    up?.setIntegerValueField(.mouseEventClickState, value: 1)
    down?.post(tap: .cghidEventTap)
    usleep(80_000)
    up?.post(tap: .cghidEventTap)
    usleep(100_000)
    out("click at \(target) pointer now at \(pointer())")
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
