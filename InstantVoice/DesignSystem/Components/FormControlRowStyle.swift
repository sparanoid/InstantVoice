import SwiftUI

/// Centers a row's control vertically against its label in a grouped form.
///
/// Grouped forms align `LabeledContent`'s control to the label's text baseline and measure the row's top
/// inset from the label, so controls taller than a line of text (bordered buttons, shortcut recorders) sit
/// closer to the row's top edge than its bottom. Apply this to sections rather than a whole form: pickers in a
/// grouped form render through `LabeledContent` too, and would pick it up.
struct FormControlRowStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer()
            configuration.content
                .foregroundStyle(.secondary)
        }
    }
}
