import Core
import SwiftUI

/// Compose, Review and Success for FR-ANN-001 (CLASSIC). Switches on the model's phase.
struct ComposeFlowView: View {
    let model: PublishModel
    let dismiss: () -> Void

    private var isPublished: Bool {
        if case .published = model.phase { true } else { false }
    }

    var body: some View {
        NavigationStack {
            Group {
                switch model.phase {
                case .editing, .checking:
                    ComposeView(model: model)
                case .reviewing, .publishing:
                    ReviewView(model: model)
                case let .published(result):
                    PublishedView(count: result.recipientCount, done: dismiss)
                }
            }
            .background(DSColor.bg)
            .toolbar {
                if !isPublished {
                    ToolbarItem(placement: .cancellationAction) {
                        Button { dismiss() } label: { Text(L10n.cancel) }
                            .accessibilityIdentifier("compose.cancel")
                            .disabled(model.isBusy)
                    }
                }
            }
        }
        .task { await model.begin() }
        .onDisappear { model.leave() }
    }
}

struct ComposeView: View {
    let model: PublishModel

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.m) {
                stateBanner
                field(L10n.annComposeFieldTitle, count: model.draft.title.count,
                      limit: AnnouncementLimits.title, error: model.fieldError == .title ? L10n.annErrorTitle : nil) {
                    TextField(
                        "", text: Binding(get: { model.draft.title }, set: model.editedTitle(_:)),
                        axis: .vertical)
                        .font(DSFont.body)
                        .accessibilityLabel(Text(L10n.annComposeFieldTitle))
                        .accessibilityIdentifier("compose.title")
                }
                field(L10n.annComposeFieldBody, count: model.draft.body.count,
                      limit: AnnouncementLimits.body, error: model.fieldError == .body ? L10n.annErrorBody : nil) {
                    TextEditor(text: Binding(get: { model.draft.body }, set: model.editedBody(_:)))
                        .font(DSFont.body)
                        .frame(minHeight: 160)
                        .scrollContentBackground(.hidden)
                        .accessibilityLabel(Text(L10n.annComposeFieldBody))
                        .accessibilityIdentifier("compose.body")
                }
                languageRow
                audienceRow
                if let other = model.fieldError, other != .title, other != .body {
                    DSBanner(.error, message: Text(L10n.annErrorOther))
                }
                DSButton(L10n.annComposeReview, isBusy: model.isBusy) { Task { await model.review() } }
                    .accessibilityIdentifier("compose.review")
            }
            .padding(DSSpacing.gutter)
        }
        .navigationTitle(Text(L10n.annComposeTitle))
        .inlineNavigationTitle()
    }

    @ViewBuilder private var stateBanner: some View {
        switch model.failure {
        case .offline:
            DSBanner(.offline, message: Text(L10n.annOfflineMessage),
                     actionTitle: L10n.annRetry) { Task { await model.review() } }
        case .forbidden:
            DSBanner(.error, message: Text(L10n.annForbiddenMessage))
        case let .failed(code, _):
            DSBanner(.error, message: Text(L10n.annFailedMessage))
                .accessibilityIdentifier(code ?? "failed")
        default:
            EmptyView()
        }
    }

    private func field<Content: View>(
        _ title: LocalizedStringResource, count: Int, limit: Int, error: LocalizedStringResource?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.xxs) {
            Text(title).font(DSFont.sectionHeader).foregroundStyle(DSColor.ink2)
            content()
                .padding(DSSpacing.s)
                .frame(minHeight: DSSize.touch, alignment: .topLeading)
                .background(DSColor.card, in: RoundedRectangle(cornerRadius: DSRadius.chip + 4))
                .overlay(RoundedRectangle(cornerRadius: DSRadius.chip + 4)
                    .stroke(error == nil ? Color.clear : DSColor.red, lineWidth: 2))
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top) { errorLabel(error); Spacer(minLength: DSSpacing.xs); counter(count, limit) }
                VStack(alignment: .leading, spacing: DSSpacing.xxs) { errorLabel(error); counter(count, limit) }
            }
        }
    }

    @ViewBuilder private func errorLabel(_ error: LocalizedStringResource?) -> some View {
        if let error {
            Label { Text(error) } icon: { Image(systemName: "exclamationmark.circle.fill") }
                .font(DSFont.caption).foregroundStyle(DSColor.red)
        }
    }

    private func counter(_ count: Int, _ limit: Int) -> some View {
        Text(L10n.annCounter(count, limit)).font(DSFont.caption).foregroundStyle(DSColor.ink2)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var languageRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                Text(L10n.annComposeLanguage).font(DSFont.body)
                Spacer(minLength: DSSpacing.xs)
                languagePicker
            }
            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                Text(L10n.annComposeLanguage).font(DSFont.body)
                languagePicker
            }
        }
        .padding(.horizontal, DSSpacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DSColor.card, in: RoundedRectangle(cornerRadius: DSRadius.chip + 4))
    }

    private var languagePicker: some View {
        Picker(selection: Binding(get: { model.draft.language }, set: model.selectLanguage(_:))) {
            ForEach(ContentLanguage.allCases, id: \.self) { Text(L10n.annLanguage($0)).tag($0) }
        } label: { Text(L10n.annComposeLanguage) }
            .pickerStyle(.menu)
            .fixedSize(horizontal: true, vertical: false)
            .frame(minHeight: DSSize.touch)
            .accessibilityIdentifier("compose.language")
    }

    private var audienceRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                Text(L10n.annComposeAudience).font(DSFont.body)
                Spacer(minLength: DSSpacing.xs)
                Text(L10n.annAudienceAll).font(DSFont.body).foregroundStyle(DSColor.ink2)
            }
            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                Text(L10n.annComposeAudience).font(DSFont.body)
                Text(L10n.annAudienceAll).font(DSFont.body).foregroundStyle(DSColor.ink2)
            }
        }
        .padding(DSSpacing.s)
        .frame(minHeight: DSSize.touch, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DSColor.card, in: RoundedRectangle(cornerRadius: DSRadius.chip + 4))
        .accessibilityElement(children: .combine)
    }
}

struct ReviewView: View {
    let model: PublishModel

    private var proposal: AnnouncementProposal? {
        switch model.phase {
        case let .reviewing(p), let .publishing(p): p
        default: nil
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.m) {
                failureBanner
                if let proposal {
                    VStack(alignment: .leading, spacing: DSSpacing.s) {
                        Text(verbatim: proposal.draft.title).font(DSFont.title)
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier("review.title")
                        Text(verbatim: proposal.draft.body).font(DSFont.body)
                            .accessibilityIdentifier("review.body")
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: DSSpacing.xs) { chips(proposal, wrapping: false) }
                            VStack(alignment: .leading, spacing: DSSpacing.xs) { chips(proposal, wrapping: true) }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(DSSpacing.m)
                    .background(DSColor.card, in: RoundedRectangle(cornerRadius: DSRadius.card))
                    Text(L10n.annReviewHint).font(DSFont.caption).foregroundStyle(DSColor.ink2)
                    publishButton
                    DSButton(L10n.annReviewEdit, kind: .soft) { model.backToEditing() }
                        .disabled(model.isBusy)
                        .accessibilityIdentifier("review.edit")
                }
            }
            .padding(DSSpacing.gutter)
        }
        .navigationTitle(Text(L10n.annReviewTitle))
        .inlineNavigationTitle()
    }

    @ViewBuilder private func chips(_ proposal: AnnouncementProposal, wrapping: Bool) -> some View {
        chip(DSStatusChip(.neutral, label: Text(L10n.annLanguage(proposal.draft.language)), symbol: "globe"),
             wrapping)
        chip(DSStatusChip(.info, label: Text(L10n.annAudienceAll), symbol: "person.3"), wrapping)
        chip(DSStatusChip(.neutral, label: Text(L10n.annRecipients(proposal.recipientCount)), symbol: "number"),
             wrapping)
            .accessibilityIdentifier("review.recipients")
    }

    /// Side by side the chips keep their natural width; stacked they may wrap instead of widening the screen.
    @ViewBuilder private func chip(_ chip: DSStatusChip, _ wrapping: Bool) -> some View {
        if wrapping { chip } else { chip.fixedSize(horizontal: true, vertical: false) }
    }

    @ViewBuilder private var publishButton: some View {
        // Offline: writes are disabled, the draft stays (NFR-007).
        let offline = model.failure == .offline
        DSButton(L10n.annReviewPublish, isBusy: model.isBusy) {
            Task { await model.publish() }
        }
        .disabled(offline || model.failure == .forbidden)
        .accessibilityIdentifier("review.publish")
    }

    @ViewBuilder private var failureBanner: some View {
        switch model.failure {
        case .offline:
            DSBanner(.offline, message: Text(L10n.annOfflineMessage),
                     actionTitle: L10n.annRetry) { Task { await model.retry() } }
        case .forbidden:
            DSBanner(.error, message: Text(L10n.annForbiddenMessage))
        case .invalidConfirmation:
            DSBanner(.error, message: Text(L10n.annExpired))
        case let .failed(code, correlationId):
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                DSBanner(.error, message: Text(L10n.annFailedMessage), actionTitle: L10n.annRetry) {
                    Task { await model.retry() }
                }
                if code != nil || correlationId != nil {
                    DisclosureGroup { Text(verbatim: [code, correlationId].compactMap { $0 }.joined(separator: " · "))
                        .font(DSFont.code).foregroundStyle(DSColor.ink2).textSelection(.enabled)
                    } label: { Text(L10n.annDetails).font(DSFont.secondary) }
                }
            }
            .accessibilityIdentifier("review.failed")
        case nil:
            EmptyView()
        }
    }
}

struct PublishedView: View {
    let count: Int
    let done: () -> Void
    @AccessibilityFocusState private var focused: Bool

    var body: some View {
        VStack(spacing: DSSpacing.l) {
            DSEmptyState(symbol: "checkmark.circle.fill", title: L10n.annSuccessTitle(count))
                .accessibilityFocused($focused)
                .accessibilityIdentifier("published.title")
            DSButton(L10n.annSuccessDone) { done() }
                .padding(.horizontal, DSSpacing.gutter)
                .accessibilityIdentifier("published.done")
        }
        .frame(maxHeight: .infinity)
        .onAppear {
            focused = true
            AccessibilityNotification.Announcement(String(localized: L10n.annSuccessTitle(count))).post()
        }
        .navigationBarBackButtonHidden()
    }
}

private extension View {
    @ViewBuilder func inlineNavigationTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}
