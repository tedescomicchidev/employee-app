import Core
import SwiftUI

/// Announcements tab (FR-ANN-003): feed with unread dots and language chips, plus the Publisher's compose entry.
struct FeedView: View {
    let model: AppModel
    let environment: AppEnvironment
    let title: LocalizedStringResource
    @State private var feed: FeedModel?
    @State private var path: [String] = []

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let feed {
                    FeedContent(feed: feed)
                } else {
                    DSSkeleton().padding(DSSpacing.gutter)
                }
            }
            .background(DSColor.bg)
            .navigationTitle(Text(title))
            .navigationDestination(for: String.self) { id in
                if let feed { AnnouncementDetailView(feed: feed, id: id) }
            }
            .composeEntry(model: model, environment: environment)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { Task { await feed?.refresh() } } label: {
                        Label { Text(L10n.homeRefresh) } icon: { Image(systemName: "arrow.clockwise") }
                    }
                    .accessibilityIdentifier("home.refresh")
                }
            }
        }
        .task(id: model.session?.oid) {
            guard let session = model.session else { return }
            if feed == nil { feed = makeFeed(session) }
            await feed?.begin()
            #if DEBUG
            if let id = environment.openAnnouncementOnLaunch, path.isEmpty { path = [id] }
            #endif
        }
        .accessibilityIdentifier("announcements.feed")
    }

    @MainActor private func makeFeed(_ session: Session) -> FeedModel {
        let auth = environment.auth
        let events = environment.events, context = environment.taskContext
        return FeedModel(
            service: environment.announcements,
            accessToken: { try await auth.accessToken() },
            onReauthNeeded: { [model] in model.needsReauth = true },
            cache: environment.feedCache, userKey: session.oid,
            makeFlow: {
                TaskFlow(taskId: "T-ANN-READ", feature: "ann", mode: .classic, context: context, sink: events)
            })
    }
}

private struct FeedContent: View {
    let feed: FeedModel

    var body: some View {
        ScrollView {
            VStack(spacing: DSSpacing.m) {
                if let asOf = feed.offlineAsOf {
                    DSBanner(.offline, message: Text(L10n.annFeedOffline(asOf.formatted(date: .abbreviated, time: .shortened))))
                        .accessibilityIdentifier("feed.offline")
                }
                switch feed.state {
                case .loading:
                    DSSkeleton()
                case .empty:
                    DSEmptyState(symbol: "megaphone", title: L10n.annFeedEmptyTitle, message: L10n.annFeedEmptyMessage)
                        .accessibilityIdentifier("feed.empty")
                case let .error(code, correlationId):
                    DSErrorState(
                        title: L10n.annFeedErrorTitle, message: L10n.annFeedErrorMessage, retryTitle: L10n.annRetry,
                        correlationId: correlationId, code: code) { Task { await feed.refresh() } }
                        .accessibilityIdentifier("feed.error")
                case let .content(items):
                    if feed.unreadCount > 0 {
                        DSStatusChip(.info, label: Text(L10n.annFeedNew(feed.unreadCount)), symbol: "circle.fill")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("feed.unread")
                    }
                    DSGroupedSection {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            NavigationLink(value: item.id) { FeedRow(item: item) }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("feed.row.\(item.id)")
                            if index < items.count - 1 { DSRowDivider() }
                        }
                    }
                }
            }
            .padding(DSSpacing.gutter)
        }
        .refreshable { await feed.refresh() }
    }
}

struct FeedRow: View {
    let item: AnnouncementItem

    var body: some View {
        HStack(alignment: .top, spacing: DSSpacing.s) {
            Circle().fill(item.read ? Color.clear : DSColor.tint)
                .frame(width: DSSize.unreadDot, height: DSSize.unreadDot)
                .padding(.top, DSSpacing.xs)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                Text(verbatim: item.title).font(DSFont.cardTitle).foregroundStyle(DSColor.ink)
                    .multilineTextAlignment(.leading)
                Text(verbatim: item.body.split(whereSeparator: \.isNewline).joined(separator: " "))
                    .font(DSFont.secondary).foregroundStyle(DSColor.ink2).lineLimit(2)
                    .multilineTextAlignment(.leading)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: DSSpacing.xs) { meta }
                    VStack(alignment: .leading, spacing: DSSpacing.xxs) { meta }
                }
            }
            Spacer(minLength: DSSpacing.xxs)
            Image(systemName: "chevron.right").font(DSFont.caption.weight(.semibold))
                .foregroundStyle(DSColor.placeholder).padding(.top, DSSpacing.xs).accessibilityHidden(true)
        }
        .padding(.horizontal, DSSpacing.m)
        .padding(.vertical, DSSpacing.s)
        .frame(minHeight: DSSize.rowMin)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder private var meta: some View {
        Text(verbatim: "\(item.author) · \(item.publishedAt.formatted(.relative(presentation: .named)))")
            .font(DSFont.caption).foregroundStyle(DSColor.ink2)
        DSStatusChip(item.read ? .neutral : .info, label: Text(verbatim: item.language.rawValue.uppercased()),
                     symbol: "globe")
            .fixedSize(horizontal: true, vertical: false)
    }

    private var label: Text {
        let state = String(localized: item.read ? L10n.annRead : L10n.annUnread)
        let date = item.publishedAt.formatted(date: .abbreviated, time: .shortened)
        let language = String(localized: L10n.annLanguage(item.language))
        return Text(verbatim: [state, item.title, item.author, date, language].joined(separator: ", "))
    }
}

/// Plain text only (FR-ANN-005.2): `Text(verbatim:)` ignores markdown and never auto-links, nothing is
/// fetched, and links found in the text are listed separately and opened only when tapped.
struct AnnouncementDetailView: View {
    let feed: FeedModel
    let id: String
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            if let item = feed.item(id: id), !feed.unavailable.contains(id) {
                VStack(alignment: .leading, spacing: DSSpacing.m) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: DSSpacing.xs) { chips(item) }
                        VStack(alignment: .leading, spacing: DSSpacing.xs) { chips(item) }
                    }
                    Text(verbatim: item.title).font(DSFont.title).accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("detail.title")
                    HStack(spacing: DSSpacing.s) {
                        Text(verbatim: MoreView.initials(item.author)).font(DSFont.secondary.weight(.semibold))
                            .foregroundStyle(DSColor.tint)
                            .frame(width: DSSize.avatar, height: DSSize.avatar)
                            .background(DSColor.tintSoft, in: Circle()).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: item.author).font(DSFont.body.weight(.semibold))
                            Text(verbatim: Self.dateLine(item))
                                .font(DSFont.caption).foregroundStyle(DSColor.ink2)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    Divider()
                    Text(verbatim: item.body).font(DSFont.body).frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("detail.body")
                    links(InertText.links(in: item.body))
                }
                .padding(DSSpacing.gutter)
            } else if feed.unavailable.contains(id) {
                DSEmptyState(symbol: "lock", title: L10n.annDetailUnavailableTitle,
                             message: L10n.annDetailUnavailableMessage)
                    .accessibilityIdentifier("detail.unavailable")
            } else {
                DSSkeleton().padding(DSSpacing.gutter)
            }
        }
        .background(DSColor.bg)
        .navigationBarTitleDisplayModeInline()
        .task { await feed.open(id: id) }
    }

    private static func dateLine(_ item: AnnouncementItem) -> String {
        let date = item.publishedAt.formatted(date: .abbreviated, time: .shortened)
        return item.read ? "\(date) · \(String(localized: L10n.annRead))" : date
    }

    @ViewBuilder private func chips(_ item: AnnouncementItem) -> some View {
        DSStatusChip(.neutral, label: Text(L10n.annLanguage(item.language)), symbol: "globe")
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityLabel(Text(L10n.annLanguageA11y(item.language)))
            .accessibilityIdentifier("detail.language")
        DSStatusChip(.info, label: Text(verbatim: L10n.annAudienceSummary(item.audience)), symbol: "person.2")
    }

    @ViewBuilder private func links(_ urls: [URL]) -> some View {
        if !urls.isEmpty {
            DSGroupedSection(header: L10n.annDetailLinks) {
                ForEach(Array(urls.enumerated()), id: \.element) { index, url in
                    Button { openURL(url) } label: {
                        DSListRow(title: Text(verbatim: url.absoluteString), leading: .icon(systemName: "link", tint: DSColor.tint))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(L10n.annDetailOpenLink(url.absoluteString)))
                    .accessibilityHint(Text(L10n.annDetailLinkHint))
                    .accessibilityIdentifier("detail.link.\(index)")
                    if index < urls.count - 1 { DSRowDivider() }
                }
            }
        }
    }
}

private extension View {
    @ViewBuilder func navigationBarTitleDisplayModeInline() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}
