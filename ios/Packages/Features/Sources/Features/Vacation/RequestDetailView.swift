import Core
import SwiftUI

/// Request detail: the owner's overview with "Cancel request" (FR-VAC-003), or the approver's
/// decision screen with Approve / Reject (FR-VAC-004).
struct RequestDetailView: View {
    @Bindable var model: RequestDetailModel
    @Environment(\.dynamicTypeSize) private var typeSize

    /// Side by side normally; stacked at accessibility sizes so no column is squeezed.
    private func adaptive(_ alignment: HorizontalAlignment) -> AnyLayout {
        typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: alignment, spacing: DSSpacing.s))
            : AnyLayout(HStackLayout(spacing: DSSpacing.s))
    }

    private var leadingLayout: AnyLayout { adaptive(.leading) }
    private var centeredLayout: AnyLayout { adaptive(.center) }

    var body: some View {
        ScrollView {
            VStack(spacing: DSSpacing.m) {
                if model.isOffline {
                    DSBanner(.offline, message: Text(L10n.vacDetailOfflineActions))
                        .accessibilityIdentifier("detail.offline")
                }
                notice
                switch model.state {
                case .loading:
                    DSSkeleton(rows: 5).accessibilityIdentifier("detail.loading")
                case let .content(request):
                    if model.role == .approver {
                        decisionContent(request)
                    } else {
                        overview(request)
                        if request.status == .pending { cancelButton }
                    }
                case .notFound:
                    DSEmptyState(symbol: "questionmark.folder", title: L10n.vacDetailNotFoundTitle,
                                 message: L10n.vacDetailNotFoundMessage)
                        .accessibilityIdentifier("detail.notfound")
                case let .error(code, correlationId):
                    DSErrorState(
                        title: L10n.vacErrorTitle, message: L10n.vacErrorMessage, retryTitle: L10n.vacRetry,
                        correlationId: correlationId, code: code) { Task { await model.load() } }
                        .accessibilityIdentifier("detail.error")
                }
            }
            .padding(DSSpacing.gutter)
        }
        .background(DSColor.bg)
        .navigationTitle(Text(L10n.vacDetailTitle))
        .vacInlineTitle()
        .vacHideTabBar(model.role == .approver)  // room for Approve / Reject
        .safeAreaInset(edge: .bottom) { decisionBar }
        .task { await model.load() }
        .refreshable { await model.load() }
        .alert(
            Text(L10n.vacCancelTitle), isPresented: $model.isConfirmingCancel, presenting: model.request
        ) { _ in
            Button(role: .destructive) { Task { await model.confirmCancel() } } label: {
                Text(L10n.vacCancelButton)
            }
            Button(role: .cancel) {} label: { Text(L10n.vacCancelKeep) }
        } message: { request in
            Text(L10n.vacCancelMessage(days: request.countedDays, approver: request.approver))
        }
        .alert(
            Text(L10n.vacDecisionApproveTitle), isPresented: $model.isConfirmingApprove, presenting: model.request
        ) { _ in
            Button { Task { await model.confirmApprove() } } label: { Text(L10n.vacDecisionApprove) }
            Button(role: .cancel) { model.dismissApprove() } label: { Text(L10n.vacDecisionCancel) }
        } message: { request in
            Text(L10n.vacDecisionApproveMessage(name: request.ownerName, days: request.countedDays))
        }
        .sheet(isPresented: $model.isRejecting, onDismiss: { model.dismissReject() }) {
            RejectSheet(model: model)
        }
    }

    // MARK: Notices

    @ViewBuilder private var notice: some View {
        switch model.notice {
        case .cancelFailed:
            DSBanner(.error, message: Text(L10n.vacCancelFailed)).accessibilityIdentifier("detail.cancel_failed")
        case .alreadyDecided:
            DSBanner(.info, message: Text(alreadyDecidedText)).accessibilityIdentifier("detail.invalid_state")
        case .offline:
            DSBanner(.offline, message: Text(L10n.vacRequestOffline)).accessibilityIdentifier("detail.cancel_offline")
        case .decisionFailed:
            DSBanner(.error, message: Text(L10n.vacDecisionFailed)).accessibilityIdentifier("detail.decision_failed")
        case .forbidden:
            DSBanner(.error, message: Text(L10n.vacDecisionForbidden)).accessibilityIdentifier("detail.forbidden")
        case let .blocked(violation):
            DSBanner(.error, message: Text(L10n.vacDecisionBlocked(L10n.vacRule(violation).trimmingCharacters(in: CharacterSet(charactersIn: ".")))))
                .accessibilityIdentifier("detail.blocked.\(violation.code)")
        case let .decided(status):
            DSBanner(.success, message: Text(L10n.vacDecisionDone(status, name: model.request?.ownerName ?? "")))
                .accessibilityIdentifier("detail.decided")
        case nil:
            EmptyView()
        }
    }

    private var alreadyDecidedText: LocalizedStringResource {
        guard let request = model.request, let decided = request.decidedAt,
              request.status == .approved || request.status == .rejected
        else { return L10n.vacDetailInvalidState }
        return L10n.vacDecisionAlready(request.status, on: VacationFormat.asOf(decided))
    }

    // MARK: Owner overview (FR-VAC-003)

    private func overview(_ request: VacationRequestSummary) -> some View {
        DSGroupedSection(header: L10n.vacDetailOverview) {
            field(L10n.vacDetailPeriod, VacationFormat.range(request.start, request.end, long: true), id: "period")
            DSRowDivider()
            field(L10n.vacDetailCounted, String(localized: L10n.vacWorkdays(request.countedDays)), id: "days")
            DSRowDivider()
            statusRow(request)
            DSRowDivider()
            field(L10n.vacDetailApprover, request.approver, id: "approver")
            if let decided = request.decidedAt {
                DSRowDivider()
                field(L10n.vacDetailDecided, VacationFormat.plain(CalendarDay(date: decided)), id: "decided")
            }
            if let reason = request.reason, !reason.isEmpty {
                DSRowDivider()
                field(L10n.vacDetailReason, reason, id: "reason")
            }
            if let submitted = request.submittedAt {
                DSRowDivider()
                field(L10n.vacDetailSubmitted, VacationFormat.long(CalendarDay(date: submitted)), id: "submitted")
            }
        }
    }

    private func statusRow(_ request: VacationRequestSummary) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                Text(L10n.vacDetailStatus).font(DSFont.secondary).foregroundStyle(DSColor.ink2)
                DSStatusChip(request.status.chipKind, label: Text(L10n.vacStatus(request.status)))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DSSpacing.m).padding(.vertical, DSSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("detail.status")
    }

    private func field(_ label: LocalizedStringResource, _ value: String, id: String) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.xxs) {
            Text(label).font(DSFont.secondary).foregroundStyle(DSColor.ink2)
            Text(verbatim: value).font(DSFont.body)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DSSpacing.m).padding(.vertical, DSSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("detail.\(id)")
    }

    private var cancelButton: some View {
        VStack(spacing: DSSpacing.xs) {
            DSButton(L10n.vacCancelButton, kind: .destructive, isBusy: model.isCancelling) { model.askToCancel() }
                .disabled(!model.canCancel)
                .accessibilityIdentifier("detail.cancel")
        }
    }

    // MARK: Approver decision (FR-VAC-004)

    @ViewBuilder private func decisionContent(_ request: VacationRequestSummary) -> some View {
        DSGroupedSection {
            leadingLayout {
                DSAvatar(initials: VacationFormat.initials(request.ownerName))
                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                    Text(verbatim: request.ownerName).font(DSFont.cardTitle)
                    Text(verbatim: "\(VacationFormat.range(request.start, request.end, long: true)) · \(String(localized: L10n.vacWorkdays(request.countedDays)))")
                        .font(DSFont.secondary).foregroundStyle(DSColor.ink2)
                }
                if !typeSize.isAccessibilitySize { Spacer(minLength: DSSpacing.xs) }
                if request.status != .pending {
                    DSStatusChip(request.status.chipKind, label: Text(L10n.vacStatus(request.status)))
                }
            }
            .padding(DSSpacing.m)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("detail.header")
        }
        if let balance = request.ownerBalance {
            DSGroupedSection(header: L10n.vacDecisionBalanceHeader(VacationFormat.firstName(request.ownerName))) {
                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                    Text(L10n.vacRemaining(balance.year)).font(DSFont.secondary).foregroundStyle(DSColor.ink2)
                    (Text(L10n.vacDays(balance.remaining)).font(DSFont.cardTitle)
                        + Text(verbatim: " ")
                        + Text(L10n.vacDecisionBalanceNote).font(DSFont.secondary).foregroundStyle(DSColor.ink2))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DSSpacing.m)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("detail.owner_balance")
            }
        }
        if let reason = request.reason, !reason.isEmpty {
            DSGroupedSection {
                field(L10n.vacDetailReason, reason, id: "reason")
            }
        }
    }

    private var rejectButton: some View {
        DSButton(L10n.vacDecisionReject, kind: .destructive) { model.askToReject() }
            .accessibilityIdentifier("detail.reject")
    }

    private var approveButton: some View {
        DSButton(L10n.vacDecisionApprove, isBusy: model.isDeciding) { model.askToApprove() }
            .accessibilityIdentifier("detail.approve")
    }

    @ViewBuilder private var decisionBar: some View {
        if model.role == .approver, model.request != nil, model.request?.status == .pending || model.notice == .alreadyDecided {
            centeredLayout {
                if typeSize.isAccessibilitySize {
                    approveButton
                    rejectButton
                } else {
                    rejectButton
                    approveButton
                }
            }
            .disabled(!model.canDecide)
            .padding(.horizontal, DSSpacing.gutter)
            .padding(.vertical, DSSpacing.s)
            .background(DSColor.bg)
        }
    }
}

/// Reject with an optional reason of at most 500 characters.
private struct RejectSheet: View {
    @Bindable var model: RequestDetailModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.m) {
            Text(L10n.vacDecisionRejectTitle).font(DSFont.title).accessibilityAddTraits(.isHeader)
            if let request = model.request {
                Text(L10n.vacDecisionRejectMessage(name: request.ownerName, days: request.countedDays))
                    .font(DSFont.body).foregroundStyle(DSColor.ink2)
            }
            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                Text(L10n.vacDecisionReasonLabel).font(DSFont.secondary).foregroundStyle(DSColor.ink2)
                TextEditor(text: $model.reason)
                    .font(DSFont.body)
                    .frame(minHeight: DSSize.touch * 2)
                    .scrollContentBackground(.hidden)
                    .focused($focused)
                    .accessibilityLabel(Text(L10n.vacDecisionReasonLabel))
                    .accessibilityIdentifier("reject.reason")
                Text(verbatim: "\(model.reason.count) / \(RequestDetailModel.maxReason)")
                    .font(DSFont.secondary)
                    .foregroundStyle(model.reasonTooLong ? DSColor.red : DSColor.ink2)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .accessibilityIdentifier("reject.count")
            }
            .padding(DSSpacing.s)
            .background(DSColor.bg, in: RoundedRectangle(cornerRadius: DSRadius.card))
            DSButton(L10n.vacDecisionReject, kind: .destructive) { Task { await model.confirmReject() } }
                .disabled(model.reasonTooLong)
                .accessibilityIdentifier("reject.confirm")
            DSButton(L10n.vacDecisionCancel, kind: .neutral) { model.dismissReject() }
                .accessibilityIdentifier("reject.cancel")
        }
        .padding(DSSpacing.gutter)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(DSColor.card)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

/// Keeps one model per pushed screen; the navigation destination closure runs on every parent update.
struct RequestDetailHost: View {
    @State private var model: RequestDetailModel
    private let autopilot: DetailAutopilot?

    /// The autopilot opens a dialog or sheet once loaded; only the screenshot runs set it.
    init(autopilot: DetailAutopilot? = nil, make: () -> RequestDetailModel) {
        self.autopilot = autopilot
        _model = State(initialValue: make())
    }

    var body: some View {
        RequestDetailView(model: model)
            .task {
                guard let autopilot else { return }
                await model.load()
                switch autopilot {
                case .cancel: model.askToCancel()
                case .reject: model.askToReject()
                case .approve:
                    model.askToApprove()
                    await model.confirmApprove()
                }
            }
    }
}

/// Which dialog the screenshot autopilot opens on the detail screen (DEBUG launches only).
enum DetailAutopilot { case cancel, reject, approve }
