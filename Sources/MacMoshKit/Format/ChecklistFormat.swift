import Foundation

/// The words and the JSON `macmosh prepare` prints.
public enum ChecklistFormat {
    /// One block per check, under a heading for each side: "✓ title" for a pass, "✗ title: detail"
    /// with a "   Fix: …" line for a failure, and "• title: detail" for information. Steps are numbered.
    public static func text(_ outcomes: [CheckOutcome]) -> String {
        var lines: [String] = []
        var side: CheckSide?
        for o in outcomes {
            if o.side != side {
                if side != nil { lines.append("") }
                lines.append(o.side == .dailyMac ? "On this Mac:" : "On the workhorse:")
                side = o.side
            }
            switch o.passed {
            case true?: lines.append("✓ \(o.title)")
            case false?: lines.append("✗ \(o.title): \(o.detail)")
            case nil: lines.append("• \(o.title): \(o.detail)")
            }
            if o.passed != true, let action = o.action { lines += fixLines(action, kind: o.fix) }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func fixLines(_ action: FixAction, kind: FixKind) -> [String] {
        switch action {
        case .automatic:
            return ["   Fix: macmosh prepare --fix does this."]
        case .tab(let arguments):
            return ["   Fix: run macmosh " + ShellQuote.join(arguments)]
        case .steps(let steps):
            let heading = kind == .atWorkhorse ? "   Fix, at the workhorse:" : "   Fix:"
            return [heading] + steps.enumerated().map { "     \($0.offset + 1). \($0.element)" }
        }
    }

    /// An array of outcomes, keys sorted, for programs.
    public static func json(_ outcomes: [CheckOutcome]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(outcomes), as: UTF8.self)
    }
}
