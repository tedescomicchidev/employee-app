import Core
import SwiftUI

/// Compose, Review and Success for FR-ANN-001 (CLASSIC). Switches on the model's phase.
struct ComposeFlowView: View {
    enum Route: Hashable { case audience }

    let model: PublishModel
    let dismiss: () -> Void
    /// Owned here so moving on to Review can pop the picker (the root view changes underneath it).
    @State private var path: [Route]

    init(model: PublishModel, startAtAudience: Bool = false, dismiss: @escaping () -> Void) {
        self.model = model
        self.dismiss = dismiss
        _path = State(initialValue: startAtAudience ? [.audience] : [])
    }

    private var isPublished: Bool {
        if case .published = model.phase { true } else { false }
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                switch model.phase {
                case .editing, .checking:
                    ComposeView(model: model) { path.append(.audience) }
                case .reviewing, .publishing:
                    ReviewView(model: model)
                case let .published(result):
                    PublishedView(count: result.recipientCount, done: dismiss)
                }
            }
            .background(DSColor.bg)
            .navigationDestination(for: Route.self) { _ in AudiencePickerView(model: model) }
            .onChange(of: model.phase) { _, phase in
                if case .reviewing = phase { path.removeAll() }
            }
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
    let openAudience: () -> Void

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
        VStack(alignment: .leading, spacing: DSSpacing.xxs) {
            Button { model.openedAudience(); openAudience() } label: {
                ViewThatFits(in: .horizontal) {
                    HStack {
                        Text(L10n.annComposeAudience).font(DSFont.body)
                        Spacer(minLength: DSSpacing.xs)
                        summary
                        chevron
                    }
                    VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                        Text(L10n.annComposeAudience).font(DSFont.body)
                        summary
                    }
                }
                .foregroundStyle(DSColor.ink)
                .padding(DSSpacing.s)
                .frame(minHeight: DSSize.touch, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DSColor.card, in: RoundedRectangle(cornerRadius: DSRadius.chip + 4))
                .overlay(RoundedRectangle(cornerRadius: DSRadius.chip + 4)
                    .stroke(model.fieldError == .audience ? DSColor.red : Color.clear, lineWidth: 2))
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text(L10n.annAudienceChange))
            .accessibilityIdentifier("compose.audience")
            if model.fieldError == .audience {
                Label { Text(L10n.annAudienceEmptyTitle) } icon: { Image(systemName: "exclamationmark.circle.fill") }
                    .font(DSFont.caption).foregroundStyle(DSColor.red)
            }
        }
    }

    private var summary: some View {
        Text(verbatim: model.draft.audience.isEmpty
             ? String(localized: L10n.annAudienceEmptyTitle) : L10n.annAudienceSummary(model.draft.audience))
            .font(DSFont.body).foregroundStyle(DSColor.ink2).multilineTextAlignment(.trailing)
    }

    private var chevron: some View {
        Image(systemName: "chevron.right").font(DSFont.caption.weight(.semibold))
            .foregroundStyle(DSColor.placeholder).accessibilityHidden(true)
    }
}

/// FR-ANN-002: chips per region / store / role, "All" exclusive, live recipient count before review.
struct AudiencePickerView: View {
    let model: PublishModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.m) {
                DSToggleRow(
                    title: Text(L10n.annAudienceAll), subtitle: Text(L10n.annAudienceAllSubtitle),
                    isOn: Binding(get: { model.draft.audience.everyone }, set: model.setEveryone(_:)))
                    .background(DSColor.card, in: RoundedRectangle(cornerRadius: DSRadius.card))
                    .accessibilityIdentifier("audience.all")
                options
                Text(L10n.annAudienceHint).font(DSFont.caption).foregroundStyle(DSColor.ink2)
                countCard
                DSButton(L10n.annAudienceNext, isBusy: model.isBusy) { Task { await model.review() } }
                    .disabled(model.audienceCount == .empty || model.draft.audience.isEmpty)
                    .accessibilityIdentifier("audience.next")
            }
            .padding(DSSpacing.gutter)
        }
        .background(DSColor.bg)
        .navigationTitle(Text(L10n.annAudienceTitle))
        .inlineAudienceTitle()
        .task { await model.loadAudience() }
    }

    @ViewBuilder private var options: some View {
        if let options = model.audienceOptions {
            ForEach(AudienceDimension.allCases, id: \.self) { dimension in
                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    Text(L10n.annAudienceDimension(dimension)).font(DSFont.sectionHeader)
                        .foregroundStyle(DSColor.ink2).accessibilityAddTraits(.isHeader)
                    FlowLayout(spacing: DSSpacing.xs) {
                        ForEach(options.values(dimension), id: \.self) { value in
                            DSPickChip(
                                Text(verbatim: L10n.audienceValue(value, dimension)),
                                isSelected: model.draft.audience.contains(value, in: dimension)
                            ) { model.toggleAudience(value, in: dimension) }
                            .accessibilityIdentifier("audience.\(dimension.rawValue).\(value)")
                        }
                    }
                }
            }
        } else if model.audienceOptionsFailed {
            DSBanner(.error, message: Text(L10n.annAudienceOptionsError), actionTitle: L10n.annRetry) {
                Task { await model.loadAudience() }
            }
        } else {
            DSSkeleton(rows: 2)
        }
    }

    @ViewBuilder private var countCard: some View {
        HStack(spacing: DSSpacing.s) {
            Image(systemName: model.audienceCount == .empty ? "person.crop.circle.badge.exclamationmark" : "person.2")
                .foregroundStyle(model.audienceCount == .empty ? DSColor.red : DSColor.tint)
                .frame(width: DSSize.avatar, height: DSSize.avatar)
                .background(model.audienceCount == .empty ? DSColor.redSoft : DSColor.tintSoft, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                switch model.audienceCount {
                case .loading: Text(L10n.annAudienceCounting).font(DSFont.body)
                case let .recipients(count): Text(L10n.annRecipients(count)).font(DSFont.cardTitle)
                case .empty:
                    Text(L10n.annAudienceEmptyTitle).font(DSFont.cardTitle)
                    Text(L10n.annAudienceEmptyMessage).font(DSFont.secondary).foregroundStyle(DSColor.ink2)
                case .failed: Text(L10n.annFailedMessage).font(DSFont.body)
                }
                if case .recipients = model.audienceCount, !model.draft.audience.everyone {
                    Text(verbatim: L10n.annAudienceSummary(model.draft.audience))
                        .font(DSFont.secondary).foregroundStyle(DSColor.ink2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(DSSpacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DSColor.card, in: RoundedRectangle(cornerRadius: DSRadius.card))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("audience.count")
    }
}

/// Wraps chips onto several lines at any Dynamic Type size.
struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(width: bounds.width, subviews: subviews)
        for (index, origin) in result.origins.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.init(width: width, height: nil))
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return (CGSize(width: min(maxX, width), height: y + rowHeight), origins)
    }
}

private extension View {
    @ViewBuilder func inlineAudienceTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
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
        chip(DSStatusChip(.info, label: Text(verbatim: L10n.annAudienceSummary(proposal.draft.audience)), symbol: "person.3"),
             wrapping)
            .accessibilityIdentifier("review.audience")
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
