import SwiftUI

struct DictionarySettingsView: View {
    @State private var selectedSection: DictionarySection = .replacements
    @State private var activePanel: DictionaryPanel?
    @State private var isAutoLearnReviewPresented = false
    @AppStorage(AutoLearnSettings.hasFailureKey) private var hasAutoLearnFailure = false
    private let dictionaryInfoMessage: LocalizedStringKey =
        "Word Replacements run after transcription. Vocabulary helps supported transcription models and AI enhancement recognize names, technical terms, and unique spellings."

    enum DictionarySection: String, CaseIterable, Hashable {
        case replacements = "Word Replacements"
        case spellings = "Vocabulary"

        var description: String {
            switch self {
            case .spellings:
                return String(
                    localized:
                        "Vocabulary helps supported transcription models and AI enhancement preserve important names, technical terms, and unique spellings."
                )
            case .replacements:
                return String(
                    localized:
                        "Word Replacements run after transcription to replace misheard words, phrases, abbreviations, or boilerplate text."
                )
            }
        }

        var systemImage: String {
            switch self {
            case .spellings:
                return "character.book.closed"
            case .replacements:
                return "arrow.left.arrow.right"
            }
        }
    }

    private enum DictionaryPanel: Equatable {
        case settings
        case autoLearnFailure
    }

    var body: some View {
        ScrollView(.vertical) {
            selectedSectionForm
                .padding(.horizontal, 24)
                .padding(.top, 18)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar {
            ToolbarItem(placement: .principal) {
                sectionPicker
            }

            ToolbarItemGroup(placement: .primaryAction) {
                if hasAutoLearnFailure {
                    Button {
                        activePanel = .autoLearnFailure
                    } label: {
                        Label("Dictionary Auto Learn failed", systemImage: "exclamationmark.triangle.fill")
                    }
                    .foregroundStyle(AppTheme.Status.warningStrong)
                    .help("Dictionary Auto Learn failed")
                }

                ScreenInfoButton(
                    title: "Info",
                    message: dictionaryInfoMessage,
                    learnMoreURL: "https://tryvoiceink.com/docs/auto-learn-dictionary"
                )

                Button {
                    activePanel = activePanel == .settings ? nil : .settings
                } label: {
                    Label("Dictionary Settings", systemImage: "gearshape")
                }
                .help("Dictionary Settings")
            }
        }
        .sidePanel(
            isPresented: Binding(
                get: { activePanel != nil },
                set: { if !$0 { activePanel = nil } }
            )
        ) {
            switch activePanel {
            case .settings:
                DictionarySettingsPanel {
                    activePanel = nil
                } onReviewNow: {
                    activePanel = nil
                    isAutoLearnReviewPresented = true
                }
            case .autoLearnFailure:
                AutoLearnFailurePanel {
                    activePanel = nil
                }
            case nil:
                EmptyView()
            }
        }
        .sidePanel(isPresented: $isAutoLearnReviewPresented) {
            AutoLearnReviewPanel {
                isAutoLearnReviewPresented = false
            }
        }
    }

    private var sectionPicker: some View {
        Picker("Dictionary", selection: $selectedSection.animation(.smooth(duration: 0.2))) {
            ForEach(DictionarySection.allCases, id: \.self) { section in
                Text(LocalizedStringKey(section.rawValue))
                    .tag(section)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .help(selectedSection.description)
    }

    private var selectedSectionForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            DictionaryGroupedSection {
                selectedSectionContent
            }

            // Explains the selected list the way a form section footer would.
            Text(selectedSection.description)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var selectedSectionContent: some View {
        switch selectedSection {
        case .spellings:
            VocabularyView()
        case .replacements:
            WordReplacementView()
        }
    }
}

private struct DictionaryGroupedSection<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(AppCardBackground())
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
