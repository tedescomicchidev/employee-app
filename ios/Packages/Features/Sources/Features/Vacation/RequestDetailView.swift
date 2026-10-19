import Core
import SwiftUI

/// Request detail (FR-VAC-003): the overview of one request; for the owner of a pending one,
/// "Cancel request" behind a confirmation dialog.
struct RequestDetailView: View {
    @Bindable var model: RequestDetailModel

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
                    overview(request)
                    if request.status == .pending { cancelButton }
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
    }

    @ViewBuilder private var notice: some View {
        switch model.notice {
        case .cancelFailed:
            DSBanner(.error, message: Text(L10n.vacCancelFailed)).accessibilityIdentifier("detail.cancel_failed")
        case .alreadyDecided:
            DSBanner(.info, message: Text(L10n.vacDetailInvalidState)).accessibilityIdentifier("detail.invalid_state")
        case .offline:
            DSBanner(.offline, message: Text(L10n.vacRequestOffline)).accessibilityIdentifier("detail.cancel_offline")
        case nil:
            EmptyView()
        }
    }

    private func overview(_ request: VacationRequestSummary) -> some View {
        DSGroupedSection(header: L10n.vacDetailOverview) {
            field(L10n.vacDetailPeriod, VacationFormat.range(request.start, request.end, long: true), id: "period")
            DSRowDivider()
            field(L10n.vacDetailCounted, String(localized: L10n.vacWorkdays(request.countedDays)), id: "days")
            DSRowDivider()
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
}

/// Keeps one model per pushed screen; the navigation destination closure runs on every parent update.
struct RequestDetailHost: View {
    @State private var model: RequestDetailModel
    private let askToCancel: Bool

    /// `askToCancel` opens the dialog once loaded; only the screenshot autopilot sets it.
    init(askToCancel: Bool = false, make: () -> RequestDetailModel) {
        self.askToCancel = askToCancel
        _model = State(initialValue: make())
    }

    var body: some View {
        RequestDetailView(model: model)
            .task {
                guard askToCancel else { return }
                await model.load()
                model.askToCancel()
            }
    }
}
