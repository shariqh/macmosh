import AppKit
import MacMoshKit
import SwiftUI

/// The About panel at the end of Settings (look design 6.9, look step 5b), drawn from `AboutSection`, which holds every
/// word: the app's icon, its name and version, the licence, and the two credit lines. It has no control at all, and
/// there is no About window and no About item in the menu.
///
/// The icon is the app's own, the one Finder and the Dock show. Apple, NSApplication.applicationIconImage
/// (https://developer.apple.com/documentation/appkit/nsapplication/applicationiconimage): "The image used for the
/// app’s icon." Apple, Image.init(nsImage:) (macOS 10.15,
/// https://developer.apple.com/documentation/swiftui/image/init(nsimage:)): "Creates a SwiftUI image from an AppKit
/// image instance." It is decoration, hidden from VoiceOver: Apple, accessibilityHidden(_:) (macOS 11.0,
/// https://developer.apple.com/documentation/swiftui/view/accessibilityhidden(_:)): "Specifies whether to hide this
/// view from system accessibility features." Each credit line may wrap at a narrow window, though no picture shows it yet: Apple,
/// fixedSize(horizontal:vertical:) (macOS 10.15,
/// https://developer.apple.com/documentation/swiftui/view/fixedsize(horizontal:vertical:)): "Fixes this view at its
/// ideal size in the specified dimensions."
struct AboutPanel: View {
    let about: AboutSection

    var body: some View {
        SettingsPanel(heading: about.heading, mark: SettingsMarks.aboutHeading) {
            HStack(alignment: .center, spacing: 12) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 48, height: 48)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: about.name)
                        .font(.system(size: LookSize.bodyFont, weight: .semibold))
                        .foregroundStyle(LookColor.text(.primary, on: .surface))
                        .accessibilityIdentifier(SettingsMarks.aboutName)
                    Text(verbatim: about.version)
                        .font(.system(size: LookSize.secondFont))
                        .foregroundStyle(LookColor.text(.secondary, on: .surface))
                        .accessibilityIdentifier(SettingsMarks.aboutVersion)
                    Text(verbatim: about.licence)
                        .font(.system(size: LookSize.secondFont))
                        .foregroundStyle(LookColor.text(.secondary, on: .surface))
                        .accessibilityIdentifier(SettingsMarks.aboutLicence)
                }
            }
            ForEach(Array(about.credits.enumerated()), id: \.offset) { index, line in
                Text(verbatim: line)
                    .font(.system(size: LookSize.tagFont))
                    .foregroundStyle(LookColor.text(.tertiary, on: .surface))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(SettingsMarks.aboutCredit(index))
            }
        }
    }
}
