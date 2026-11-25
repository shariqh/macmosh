// windowtool: reads the MacMosh window through the accessibility API, in one quick pass. CI only
// (.github/workflows/menu-pictures.yml, through scripts/ci/drive-window.sh). It reads and never
// presses anything: the driver clicks with posted pointer events (menutool). Never run it on your own Mac.
//
//   windowtool <pid> windows            how many windows titled MacMosh the app has: "windows 1"
//   windowtool <pid> front              whether the app is active, and its focused window's title
//   windowtool <pid> frame              the window's position and size: "frame x y w h"
//   windowtool <pid> find <identifier>  the centre of the element with that accessibility identifier:
//                                       "found x y role", or "notfound"
//   windowtool <pid> value <identifier> that element's text: "value <text>", or "notfound"
//   windowtool <pid> text <prefix>      the first static text that starts with <prefix>: "text <text>"
//   windowtool <pid> close              the centre of the window's close button: "close x y"
//   windowtool <pid> button <title>     the centre of the first button with that title: "found x y role"
//   windowtool <pid> enabled <identifier>   whether that element can be used: "enabled true" or "enabled false"
//   windowtool <pid> selected <identifier>  the text selected in that field: "selected <text>" (issue 144)
//   windowtool <pid> radio <identifier> <title>  the centre of the radio button with that title in the element with
//                                       that identifier (a radio-group Picker): "found x y AXRadioButton" (issue 157)
//   windowtool <pid> chosen <identifier>    the title of the chosen radio button in it: "chosen <title>", or
//                                       "chosen none" (issue 157)
//   windowtool <pid> checked <identifier>   whether that checkbox is ticked: "checked 1" or "checked 0" (issue 163)
//
// find, value, text, button, enabled and selected look in the MacMosh window first (its sheets are inside it), then in
// the app's other windows, where a dialog may be.
//   windowtool <pid> dump               every element: depth, role, identifier, text and centre
//
// The first run read the window with System Events from AppleScript, one Apple event per property, and
// got nothing back for any element while the sample's checks redrew the page every second. One pass
// here takes milliseconds. Built by the workflow with swiftc, as a single file.
import AppKit
import ApplicationServices

let args = CommandLine.arguments
guard args.count >= 3, let pid = pid_t(args[1]) else {
    print("usage: windowtool <pid> windows|front|frame|find|value|text|close|button|enabled|selected|radio|chosen|checked|dump [argument]")
    exit(2)
}
let command = args[2]
let argument = args.count > 3 ? args[3] : ""
let second = args.count > 4 ? args[4] : ""

func attribute(_ e: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(e, name as CFString, &value) == .success else { return nil }
    return value
}

func text(_ e: AXUIElement, _ name: String) -> String? {
    attribute(e, name) as? String
}

func axValue(_ e: AXUIElement, _ name: String) -> AXValue? {
    guard let raw = attribute(e, name), CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
    return (raw as! AXValue)   // the type id was checked just above
}

func frame(_ e: AXUIElement) -> CGRect? {
    var origin = CGPoint.zero, size = CGSize.zero
    guard let p = axValue(e, kAXPositionAttribute), AXValueGetValue(p, .cgPoint, &origin),
          let s = axValue(e, kAXSizeAttribute), AXValueGetValue(s, .cgSize, &size) else { return nil }
    return CGRect(origin: origin, size: size)
}

func centre(_ e: AXUIElement) -> String {
    guard let f = frame(e) else { return "? ?" }
    return "\(Int(f.midX)) \(Int(f.midY))"
}

func children(_ e: AXUIElement) -> [AXUIElement] {
    (attribute(e, kAXChildrenAttribute) as? [AXUIElement]) ?? []
}

/// Its value when that is text, otherwise its title, otherwise its description.
func label(_ e: AXUIElement) -> String {
    for name in [kAXValueAttribute, kAXTitleAttribute, kAXDescriptionAttribute] {
        if let t = text(e, name), !t.isEmpty { return t }
    }
    return ""
}

/// Every element under `root`, depth first, with its depth.
func walk(_ root: AXUIElement) -> [(element: AXUIElement, depth: Int)] {
    var found: [(AXUIElement, Int)] = []
    func visit(_ e: AXUIElement, _ depth: Int) {
        found.append((e, depth))
        if depth < 40 { for child in children(e) { visit(child, depth + 1) } }
    }
    visit(root, 0)
    return found
}

let app = AXUIElementCreateApplication(pid)
let windows = ((attribute(app, kAXWindowsAttribute) as? [AXUIElement]) ?? []).filter { text($0, kAXTitleAttribute) == "MacMosh" }

if command == "windows" {
    print("windows \(windows.count)")
    exit(0)
}
if command == "front" {
    // Whether the app is the active one, and the title of its focused window.
    let active = NSRunningApplication(processIdentifier: pid)?.isActive ?? false
    var focused = "none"
    if let raw = attribute(app, kAXFocusedWindowAttribute), CFGetTypeID(raw) == AXUIElementGetTypeID() {
        focused = text(raw as! AXUIElement, kAXTitleAttribute) ?? "?"   // the type id was checked just above
    }
    print("front active=\(active) focused=\(focused)")
    exit(0)
}
guard let window = windows.first else {
    print("nowindow")
    exit(0)
}

/// The MacMosh window's elements, then those of the app's other windows.
func everything() -> [(element: AXUIElement, depth: Int)] {
    let all = (attribute(app, kAXWindowsAttribute) as? [AXUIElement]) ?? []
    let others = all.filter { text($0, kAXTitleAttribute) != "MacMosh" }
    return ([window] + others).flatMap { walk($0) }
}

switch command {
case "button":
    let hit = everything().first {
        text($0.element, kAXRoleAttribute) == kAXButtonRole
            && (text($0.element, kAXTitleAttribute) == argument || text($0.element, kAXDescriptionAttribute) == argument)
    }
    print(hit.map { "found \(centre($0.element)) \(text($0.element, kAXRoleAttribute) ?? "?")" } ?? "notfound")
case "enabled":
    let hit = everything().first { text($0.element, "AXIdentifier") == argument }
    if let hit {
        print("enabled \((attribute(hit.element, kAXEnabledAttribute) as? Bool) ?? true)")
    } else {
        print("notfound")
    }
case "checked":
    // A checkbox's AXValue is a number, which `label` does not read.
    let hit = everything().first { text($0.element, "AXIdentifier") == argument }
    if let hit {
        print("checked \((attribute(hit.element, kAXValueAttribute) as? NSNumber)?.intValue ?? -1)")
    } else {
        print("notfound")
    }
case "selected":
    let hit = everything().first { text($0.element, "AXIdentifier") == argument }
    if let hit {
        print("selected \(text(hit.element, kAXSelectedTextAttribute) ?? "")")
    } else {
        print("notfound")
    }
case "radio", "chosen":
    // The identifier may sit on the radio group or on each of its buttons, so every element with it is searched,
    // itself and everything under it.
    let groups = everything().filter { text($0.element, "AXIdentifier") == argument }
    let radios = groups.flatMap { walk($0.element) }.map(\.element)
        .filter { text($0, kAXRoleAttribute) == kAXRadioButtonRole }
    if groups.isEmpty {
        print("notfound")
    } else if command == "radio" {
        let hit = radios.first { text($0, kAXTitleAttribute) == second || label($0) == second }
        print(hit.map { "found \(centre($0)) \(text($0, kAXRoleAttribute) ?? "?")" } ?? "notfound")
    } else {
        let on = radios.first { (attribute($0, kAXValueAttribute) as? NSNumber)?.intValue == 1 }
        print("chosen \(on.map { text($0, kAXTitleAttribute) ?? label($0) } ?? "none")")
    }
case "frame":
    guard let f = frame(window) else { print("noframe"); break }
    print("frame \(Int(f.minX)) \(Int(f.minY)) \(Int(f.width)) \(Int(f.height))")
case "close":
    if let raw = attribute(window, kAXCloseButtonAttribute), CFGetTypeID(raw) == AXUIElementGetTypeID() {
        // The type id was checked just above.
        print("close \(centre(raw as! AXUIElement))")
    } else {
        print("notfound")
    }
case "find", "value":
    let hit = everything().first { text($0.element, "AXIdentifier") == argument }
    if let hit {
        let role = text(hit.element, kAXRoleAttribute) ?? "?"
        print(command == "find" ? "found \(centre(hit.element)) \(role)" : "value \(label(hit.element))")
    } else {
        print("notfound")
    }
case "text":
    let hit = everything().first {
        text($0.element, kAXRoleAttribute) == kAXStaticTextRole && label($0.element).hasPrefix(argument)
    }
    print(hit.map { "text \(label($0.element))" } ?? "notfound")
case "dump":
    for (e, depth) in walk(window) {
        let role = text(e, kAXRoleAttribute) ?? "?"
        let id = text(e, "AXIdentifier").map { " id=\($0)" } ?? ""
        print("\(String(repeating: "  ", count: depth))\(role)\(id) [\(label(e))] at \(centre(e))")
    }
default:
    print("unknown command \(command)")
    exit(2)
}
