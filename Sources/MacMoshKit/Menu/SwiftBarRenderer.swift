import Foundation

/// Prints a `Menu` in SwiftBar's text format (README, 2026-11-19): a header line, `---`, then one
/// line per item, `<title> | key=value …`.
public enum SwiftBarRenderer {
    public static func render(_ menu: Menu, macmoshPath: String) -> String {
        var lines = [" | sfimage=\(menu.symbol)", "---"]
        for item in menu.items {
            if item.isSeparator {
                lines.append("---")
                continue
            }
            let title = String(repeating: "   ", count: max(0, item.indent)) + clean(item.title)
            lines.append(title + suffix(for: item.action, macmoshPath: macmoshPath))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// A small menu for when the real one can't be made: the warning icon and one plain line.
    public static func errorMenu(_ message: String) -> String {
        render(Menu(symbol: "exclamationmark.triangle", items: [.line(message, indent: 0)]), macmoshPath: "")
    }

    /// The absolute path of the running `macmosh`, from the path the system gave or the first
    /// command-line word, which is taken from `folder` when it is not absolute.
    public static func absolutePath(of raw: String, in folder: String) -> String {
        URL(fileURLWithPath: raw, relativeTo: URL(fileURLWithPath: folder, isDirectory: true))
            .standardizedFileURL.path
    }

    // MARK: Pieces

    /// A title can't break its line: `|` becomes `/` and a line break becomes a space. A title that
    /// starts with `-` would read as a separator or a submenu in SwiftBar, so it gets a no-break space first.
    private static func clean(_ title: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in title.unicodeScalars {
            if scalar == "|" {
                scalars.append("/")
            } else if CharacterSet.newlines.contains(scalar) {
                scalars.append(" ")
            } else {
                scalars.append(scalar)
            }
        }
        let text = String(scalars)
        return text.hasPrefix("-") ? "\u{00A0}" + text : text
    }

    /// The part after the bar. An action whose words aren't plain would need quoting that SwiftBar
    /// has no syntax for, so such a line gets no action rather than a wrong one.
    private static func suffix(for action: MenuAction, macmoshPath: String) -> String {
        switch action {
        case .none:
            return ""
        case .refresh:
            return " | refresh=true"
        case .tab(let args):
            guard let params = params(["open"] + args, macmoshPath) else { return "" }
            return " | bash=\(macmoshPath) \(params) terminal=false"
        case .run(let args):
            guard let params = params(args, macmoshPath) else { return "" }
            return " | bash=\(macmoshPath) \(params) terminal=false refresh=true"
        }
    }

    private static func params(_ words: [String], _ macmoshPath: String) -> String? {
        guard PlainWords.isPlain(macmoshPath), words.allSatisfy(PlainWords.isPlain) else { return nil }
        return words.enumerated().map { "param\($0.offset)=\($0.element)" }.joined(separator: " ")
    }
}
