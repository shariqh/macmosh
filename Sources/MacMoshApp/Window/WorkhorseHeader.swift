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
            // The name and its pill, then the checks at the right. When the page is too narrow for both on one line
            // (the smallest window), the checks go to a line of their own under the name, still at the right, so the
            // name is never cut for them. Apple, ViewThatFits (macOS 13.0,
            // https://developer.apple.com/documentation/swiftui/viewthatfits): "A view that adapts to the available
            // space by providing the first child view that fits."
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 10) {
                    headline.fixedSize()
                    Spacer(minLength: 12)
                    checks
                }
                VStack(alignment: .leading, spacing: 6) {
                    headline
                    HStack(spacing: 10) {
                        Spacer(minLength: 0)
                        checks
                    }
                }
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

    /// One element for VoiceOver and CI, read as the menu's headline ("Attic · Ready"); the name and the pill inside
    /// it are not read as pieces. Apple, accessibilityElement(children:) (macOS 10.15,
    /// https://developer.apple.com/documentation/swiftui/view/accessibilityelement(children:)).
    private var headline: some View {
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
    }

    /// "Checking…", always laid out and seen and read only while a check runs, so Check now never moves; the time;
    /// Check now.
    private var checks: some View {
        HStack(alignment: .center, spacing: 10) {
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
/// notice under it in one line when it says something else; or the notice alone. A result sits in a small tile, as
/// look-b-details.png draws it (look step 3), hugging its words up to the slot's width; a notice alone stays on the
/// ground. The whole sentence is the help tag and, through `page.result`, the element's value; the marks are hidden
/// from VoiceOver.
struct ResultSlotView: View {
    let slot: ResultSlot?

    var body: some View {
        // Two lines of body text, laid out and never shown, give the slot its height whatever it holds, with the tile's
        // 4 points above and below, so a two-line sentence in its tile never moves the list either.
        Text(verbatim: "A\nA")
            .lineLimit(LookSize.resultLines)
            .hidden()
            .accessibilityHidden(true)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .topLeading) {
                if let slot {
                    if slot.isResult {
                        content(slot, on: .surface)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .lookTile(radius: LookSize.smallTileRadius)
                    } else {
                        content(slot, on: .ground)
                            .padding(.vertical, 4)
                    }
                }
            }
    }

    private func content(_ slot: ResultSlot, on background: BackgroundRole) -> some View {
        HStack(alignment: .top, spacing: 6) {
            if slot.isResult, let kind = slot.kind {
                ResultMark(kind: kind)
            }
            VStack(alignment: .leading, spacing: 0) {
                sentence(slot, on: background)
                if let notice = slot.notice {
                    Text(verbatim: notice)
                        .foregroundStyle(LookColor.text(.secondary, on: background))
                        .lineLimit(1).truncationMode(.tail)
                        .help(Text(verbatim: notice))
                }
            }
        }
    }

    @ViewBuilder private func sentence(_ slot: ResultSlot, on background: BackgroundRole) -> some View {
        let text = Text(verbatim: slot.sentence)
            .foregroundStyle(LookColor.text(slot.kind?.textRole ?? .secondary, on: background))
            .lineLimit(slot.sentenceLines).truncationMode(.tail)
            .help(Text(verbatim: slot.sentence))
        if slot.isResult {
            text.accessibilityIdentifier(WindowMarks.result)
        } else {
            text
        }
    }
}

/// The mark before a result: a round green tick, as the state cell draws it, a red warning triangle, or a neutral
/// question mark, each on the result's tile (`Look.tileMarks`).
private struct ResultMark: View {
    let kind: ResultKind

    var body: some View {
        Group {
            switch kind {
            case .done:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(LookColor.mark(.green))
                    .frame(width: 15, height: 15)
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
