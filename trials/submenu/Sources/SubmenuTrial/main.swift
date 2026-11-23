// SubmenuTrial: a MenuBarExtra whose menu holds what the submenu questions need.
//
// Environment:
//   TRIAL_LOG     file the app appends one line per event to
//   TRIAL_STYLE   "plain" (no style modifier, the default) or "menu" (.menuBarExtraStyle(.menu))
//   TRIAL_LIVE    "1" starts a task that changes the model every 2 seconds (TRIAL_TICK seconds if set)
//   TRIAL_LAYOUT  "main" (default) or "eleven" (11 top-level rows, one a 12-row submenu)
import AppKit
import SwiftUI

let env = ProcessInfo.processInfo.environment

// MARK: - Log

final class TrialLog {
    static let shared = TrialLog()
    private let file: UnsafeMutablePointer<FILE>?

    private init() {
        file = fopen(env["TRIAL_LOG"] ?? "/dev/stderr", "a")
    }

    func write(_ text: String) {
        let line = String(format: "%.3f", Date().timeIntervalSince1970) + " app " + text + "\n"
        if let file {
            fputs(line, file)
            fflush(file)
        }
    }
}

func log(_ text: String) { TrialLog.shared.write(text) }

// MARK: - Menu notifications

/// Watches every NSMenu notification and names each menu object it sees: m1, m2, ...
final class MenuWatcher {
    static let shared = MenuWatcher()
    private var menus: [NSMenu] = []
    private var firstTracked: NSMenu?
    private var counts: [String: Int] = [:]

    func start() {
        NotificationCenter.default.addObserver(forName: nil, object: nil, queue: nil) { [weak self] note in
            let name = note.name.rawValue
            guard name.hasPrefix("NSMenu") else { return }
            self?.record(note)
        }
    }

    /// What the open menu shows now: the live rows of the top menu and of the two live submenus.
    func snapshot(_ why: String) {
        guard let top = firstTracked else { return }
        func titles(_ menu: NSMenu) -> String {
            menu.items.filter { !$0.isSeparatorItem }.map { item in
                (item == menu.highlightedItem ? "*" : "") + item.title
            }.filter { $0.contains("row") || $0.contains("renamed") }.joined(separator: "|")
        }
        var text = "shows [\(why)] top=\(titles(top))"
        for item in top.items where item.title.hasPrefix("Live submenu") {
            if let sub = item.submenu { text += " \(item.title.suffix(1))=\(titles(sub))" }
        }
        text += " highlighted=\"\(top.highlightedItem?.title ?? "none")\""
        log(text)
    }

    private func label(_ menu: NSMenu) -> String {
        if let index = menus.firstIndex(where: { $0 === menu }) { return "m\(index + 1)" }
        menus.append(menu)
        return "m\(menus.count)"
    }

    private func record(_ note: Notification) {
        let name = note.name.rawValue
        counts[name, default: 0] += 1
        var text = "note \(name) #\(counts[name]!)"
        if let menu = note.object as? NSMenu {
            let isBegin = note.name == NSMenu.didBeginTrackingNotification
            if isBegin && firstTracked == nil { firstTracked = menu }
            let firstTitles = menu.items.prefix(3).map { $0.isSeparatorItem ? "---" : $0.title }
            text += " object=\(label(menu)) class=\(String(describing: type(of: menu)))"
            text += " title=\"\(menu.title)\" items=\(menu.numberOfItems)"
            text += " supermenu=\(menu.supermenu.map { label($0) } ?? "none")"
            text += " sameAsFirstTracked=\(firstTracked.map { $0 === menu } ?? false)"
            text += " isMainMenu=\(NSApp.mainMenu === menu)"
            text += " firstItems=\(firstTitles)"
        } else {
            text += " object=\(note.object.map { String(describing: type(of: $0)) } ?? "nil")"
        }
        if let item = note.userInfo?["MenuItem"] as? NSMenuItem {
            text += " menuItem=\"\(item.title)\""
        }
        if let index = note.userInfo?["NSMenuItemIndex"] {
            text += " itemIndex=\(index)"
        }
        log(text)
        if name == "NSMenuItemSelectedNotification" { snapshot("at selection") }
    }
}

// MARK: - Model

struct Row: Identifiable, Equatable {
    let id: String
    var title: String
}

@MainActor
final class LiveModel: ObservableObject {
    @Published var rows: [Row] = (1...4).map { Row(id: "r\($0)", title: "row \($0)") }
    @Published var header = "Live tick 0"
    private var counter = 0
    private var nextNumber = 5

    func start() {
        Task { @MainActor in
            while true {
                try? await Task.sleep(for: .seconds(Double(env["TRIAL_TICK"] ?? "2") ?? 2))
                step()
            }
        }
    }

    /// Every tick changes the header, and one of: add a row at the top, rename the second row,
    /// remove the top row.
    func step() {
        counter += 1
        header = "Live tick \(counter)"
        let op: String
        switch counter % 3 {
        case 1:
            let row = Row(id: "r\(nextNumber)", title: "row \(nextNumber)")
            nextNumber += 1
            rows.insert(row, at: 0)
            op = "add \(row.id) at 0"
        case 2:
            if rows.count > 1 {
                rows[1].title = "renamed \(counter)"
                op = "rename \(rows[1].id) to \"renamed \(counter)\""
            } else {
                op = "rename skipped"
            }
        default:
            let gone = rows.removeFirst()
            op = "remove \(gone.id) from 0"
        }
        let list = rows.map { "\($0.id)=\($0.title)" }.joined(separator: ",")
        log("model change #\(counter) op=\(op) header=\"\(header)\" rows=[\(list)] tracking=\(RunLoop.current.currentMode?.rawValue ?? "none")")
        let n = counter
        for delay in [0.05, 0.4] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                MenuWatcher.shared.snapshot("change #\(n) +\(Int(delay * 1000))ms")
            }
        }
    }
}

// MARK: - Views

func button(_ title: String, id: String) -> some View {
    Button(title) { log("button id=\(id) title=\"\(title)\"") }
}

struct MainMenu: View {
    @ObservedObject var model: LiveModel

    var body: some View {
        Text("Plain text line")
        Divider()
        Button("Disabled button") { log("button id=disabled ran (should not)") }
            .disabled(true)
        Section("Section header") {
            button("Button in section", id: "insection")
        }
        button("   Indented button", id: "indented")
        button("Plain button", id: "plain")
        Menu("Plain submenu") {
            Text("Sub text line")
            Divider()
            Button("Sub disabled") { log("button id=subdisabled ran (should not)") }
                .disabled(true)
            Section("Sub section header") {
                button("Sub in section", id: "subinsection")
            }
            button("   Sub indented", id: "subindented")
            button("Sub button", id: "subbutton")
        }
        Menu("Desk workhorse") {
            button("Open desk workhorse", id: "deskopen")
            button("Rename desk", id: "deskrename")
        } primaryAction: {
            log("primary action desk=workhorse")
        }
        Menu("Twelve rows") {
            ForEach(1...12, id: \.self) { n in
                button("Twelve row \(n)", id: "twelve\(n)")
            }
        }
        // The live submenus sit above the changing rows, so their own rows never move.
        Menu("Live submenu P") {
            ForEach(model.rows.indices, id: \.self) { index in
                let shown = model.rows[index]
                Button("SP \(shown.title)") { pressByPosition(index, shown: shown, where: "sub") }
            }
        }
        Menu("Live submenu I") {
            ForEach(model.rows) { row in
                Button("SI \(row.title)") { pressById(row, where: "sub") }
            }
        }
        Divider()
        Text(model.header)
        // Rows keyed by position: the action looks the row up again when it runs.
        ForEach(model.rows.indices, id: \.self) { index in
            let shown = model.rows[index]
            Button("P \(shown.title)") { pressByPosition(index, shown: shown, where: "top") }
        }
        Divider()
        // Rows keyed by a stable id.
        ForEach(model.rows) { row in
            Button("I \(row.title)") { pressById(row, where: "top") }
        }
        Divider()
        Button("Quit SubmenuTrial") {
            log("quit pressed")
            NSApp.terminate(nil)
        }
    }

    private func pressByPosition(_ index: Int, shown: Row, where place: String) {
        let now = index < model.rows.count ? model.rows[index] : nil
        log("press keying=position place=\(place) index=\(index) built=\(shown.id)/\"\(shown.title)\" lookupNow=\(now?.id ?? "none")/\"\(now?.title ?? "none")\" match=\(now == shown)")
    }

    private func pressById(_ row: Row, where place: String) {
        let now = model.rows.first { $0.id == row.id }
        log("press keying=id place=\(place) built=\(row.id)/\"\(row.title)\" lookupNow=\(now?.id ?? "none")/\"\(now?.title ?? "none")\" match=\(now == row)")
    }
}

struct ElevenMenu: View {
    var body: some View {
        ForEach(1...10, id: \.self) { n in
            button("Top row \(n)", id: "top\(n)")
        }
        Menu("Twelve rows") {
            ForEach(1...12, id: \.self) { n in
                button("Twelve row \(n)", id: "twelve\(n)")
            }
        }
    }
}

struct TrialContent: View {
    @ObservedObject var model: LiveModel

    var body: some View {
        if env["TRIAL_LAYOUT"] == "eleven" {
            ElevenMenu()
        } else {
            MainMenu(model: model)
        }
    }
}

// MARK: - Start

@MainActor
func startUp() -> LiveModel {
    let model = LiveModel()
    MenuWatcher.shared.start()
    log("started style=\(env["TRIAL_STYLE"] ?? "plain") live=\(env["TRIAL_LIVE"] ?? "0") layout=\(env["TRIAL_LAYOUT"] ?? "main") os=\(ProcessInfo.processInfo.operatingSystemVersionString)")
    if env["TRIAL_LIVE"] == "1" { model.start() }
    return model
}

nonisolated(unsafe) var sharedModel: LiveModel!

struct PlainStyleApp: App {
    var body: some Scene {
        MenuBarExtra("SubmenuTrial", systemImage: "star") {
            TrialContent(model: sharedModel)
        }
    }
}

struct MenuStyleApp: App {
    var body: some Scene {
        MenuBarExtra("SubmenuTrial", systemImage: "star") {
            TrialContent(model: sharedModel)
        }
        .menuBarExtraStyle(.menu)
    }
}

MainActor.assumeIsolated {
    sharedModel = startUp()
    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
        for screen in NSScreen.screens {
            log("screen frame=\(screen.frame) visible=\(screen.visibleFrame) scale=\(screen.backingScaleFactor)")
        }
    }
    if env["TRIAL_STYLE"] == "menu" {
        MenuStyleApp.main()
    } else {
        PlainStyleApp.main()
    }
}
