import MacMoshKit
import SwiftUI

/// The top of a workhorse's page (look design 6.3): the name and its state pill as one headline, "Checking…" in a
/// place of its own so Check now never moves, the time and Check now; under them the hint, the summary, and the
/// result slot, which is always two lines high so the list under it never moves.
struct WorkhorseHeader: View {
    let page: WorkhorsePage
    let notice: String?
    let run: (BoardButton) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                // One element for VoiceOver and CI, read as the menu's headline ("Attic · Ready"); the name and the
                // pill inside it are not read as pieces. Apple, accessibilityElement(children:) (macOS 10.15,
                // https://developer.apple.com/documentation/swiftui/view/accessibilityelement(children:)).
                HStack(alignment: .center, spacing: 10) {
                    Text(verbatim: page.name)
                        .font(.system(size: LookSize.titleFont, weight: .semibold))
                        .foregroundStyle(LookColor.text(.primary, on: .ground))
                        .lineLimit(1)
                        .help(Text(verbatim: page.name))
                    StatePillView(pill: page.pill)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: page.headline))
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier(WindowMarks.headline)
                .layoutPriority(1)
                Spacer(minLength: 8)
                // Always laid out; seen and read only while a check runs.
                Text(verbatim: page.checking ?? WindowWords.checking)
                    .foregroundStyle(LookColor.text(.tertiary, on: .ground))
                    .lineLimit(1).fixedSize()
                    .opacity(page.checking == nil ? 0 : 1)
                    .accessibilityHidden(page.checking == nil)
                if let checked = page.checked {
                    Text(verbatim: checked)
                        .foregroundStyle(LookColor.text(.tertiary, on: .ground))
                        .lineLimit(1).fixedSize()
                }
                Button { run(page.checkNow) } label: { Text(verbatim: page.checkNow.title) }
                    .buttonStyle(LookButtonStyle(kind: ButtonKind.of(page.checkNow.action)))
                    .accessibilityIdentifier(WindowMarks.button(page.checkNow))
            }
            .font(.system(size: LookSize.bodyFont))
            if let hint = page.hint {
                Text(verbatim: hint)
                    .foregroundStyle(LookColor.text(.primary, on: .ground))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let summary = page.summary {
                Text(verbatim: summary)
                    .foregroundStyle(LookColor.text(.secondary, on: .ground))
                    .fixedSize(horizontal: false, vertical: true)
            }
            ResultSlotView(slot: page.resultSlot(notice: notice))
                .padding(.top, 4)
        }
        .font(.system(size: LookSize.bodyFont))
    }
}

/// The state's word in a capsule, after a dot in its colour (look design 6.3). The word is always there, so colour
/// is never alone.
struct StatePillView: View {
    let pill: StatePill

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(LookColor.mark(pill.tone.textRole.token))
                .frame(width: 6, height: 6)
            Text(verbatim: pill.word)
                .font(.system(size: LookSize.secondFont, weight: .medium))
                .foregroundStyle(LookColor.text(pill.tone.textRole, on: .surface))
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .fixedSize()
        .lookTile(radius: 10)
    }
}

/// The result slot (look design 6.3): two lines, always reserved. The last action's sentence after a tick on a small
/// green tile when it worked, a red warning mark when it failed, or a neutral mark when it is not known; the menu's
/// notice under it in one line when it says something else; or the notice alone. The whole sentence is the help tag
/// and, through `page.result`, the element's value; the marks are hidden from VoiceOver.
struct ResultSlotView: View {
    let slot: ResultSlot?

    var body: some View {
        // Two lines of body text, laid out and never shown, give the slot its height whatever it holds.
        Text(verbatim: "A\nA")
            .lineLimit(LookSize.resultLines)
            .hidden()
            .accessibilityHidden(true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .topLeading) {
                if let slot { content(slot) }
            }
    }

    private func content(_ slot: ResultSlot) -> some View {
        HStack(alignment: .top, spacing: 6) {
            if slot.isResult, let kind = slot.kind {
                ResultMark(kind: kind)
            }
            VStack(alignment: .leading, spacing: 0) {
                sentence(slot)
                if let notice = slot.notice {
                    Text(verbatim: notice)
                        .foregroundStyle(LookColor.text(.secondary, on: .ground))
                        .lineLimit(1).truncationMode(.tail)
                        .help(Text(verbatim: notice))
                }
            }
        }
    }

    @ViewBuilder private func sentence(_ slot: ResultSlot) -> some View {
        let text = Text(verbatim: slot.sentence)
            .foregroundStyle(LookColor.text(slot.kind?.textRole ?? .secondary, on: .ground))
            .lineLimit(slot.sentenceLines).truncationMode(.tail)
            .help(Text(verbatim: slot.sentence))
        if slot.isResult {
            text.accessibilityIdentifier(WindowMarks.result)
        } else {
            text
        }
    }
}

/// The mark before a result: a tick on a small green tile, a red warning triangle, or a neutral question mark.
private struct ResultMark: View {
    let kind: ResultKind

    var body: some View {
        Group {
            switch kind {
            case .done:
                // The tick in the surface colour: white on green in light, the dark tile's colour on green in dark.
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(LookColor.background(.surface))
                    .frame(width: 15, height: 15)
                    .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(LookColor.mark(.green)))
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(LookColor.mark(.red))
                    .frame(width: 15, height: 15)
            case .unknown:
                Image(systemName: "questionmark.circle")
                    .foregroundStyle(LookColor.mark(.ink3))
                    .frame(width: 15, height: 15)
            }
        }
        .font(.system(size: 12))
        .padding(.top, 1)
        .accessibilityHidden(true)
    }
}
