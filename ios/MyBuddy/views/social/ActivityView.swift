//
//  ActivityView.swift
//  MyBuddy
//
//  In-app notification inbox: follows, requests, likes, comments, replies, mentions, reposts.
//  Tapping an item marks it read and opens the related post or profile.
//

import SwiftUI

@MainActor
final class ActivityViewModel: ObservableObject {
    @Published private(set) var items: [ActivityItem] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    private var cursor: String?
    private var reachedEnd = false
    private let repository: SocialRepository

    init(repository: SocialRepository) { self.repository = repository }

    func reload() async {
        cursor = nil
        reachedEnd = false
        items = []
        await loadMore()
    }

    func loadMore() async {
        guard !isLoading, !reachedEnd else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await repository.activity(cursor: cursor)
            items += page.items
            cursor = page.nextCursor
            reachedEnd = page.nextCursor == nil
        } catch {
            let e = AppError.wrap(error)
            if case .cancelled = e { return }
            errorMessage = e.userMessage
        }
    }

    func markRead(_ item: ActivityItem) async {
        guard !item.read else { return }
        if let i = items.firstIndex(where: { $0.id == item.id }) { items[i].read = true }
        try? await repository.markActivityRead(id: item.id)
    }

    func markAllRead() async {
        for i in items.indices { items[i].read = true }
        try? await repository.markActivityRead(id: nil)
    }
}

struct ActivityView: View {
    @StateObject private var model: ActivityViewModel
    @ObservedObject var badge: ActivityBadgeModel

    init(repository: SocialRepository, badge: ActivityBadgeModel) {
        _model = StateObject(wrappedValue: ActivityViewModel(repository: repository))
        self.badge = badge
    }

    var body: some View {
        List {
            if model.items.isEmpty && !model.isLoading {
                BrandEmptyState(systemImage: "bell.fill", title: "No activity yet", message: "Likes, comments, follows and mentions will show up here.")
                    .listRowSeparator(.hidden)
                    .padding(.top, 60)
            }
            ForEach(model.items) { item in
                NavigationLink(value: route(for: item)) {
                    HStack(spacing: 12) {
                        AvatarView(user: item.actor, size: 46)
                            .overlay(alignment: .bottomTrailing) { badge(for: item.type).offset(x: 4, y: 4) }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(description(of: item)).font(.subheadline)
                            Text(item.createdAt, style: .relative).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if !item.read { Circle().fill(DS.Palette.accent).frame(width: 8, height: 8).accessibilityLabel("Unread") }
                    }
                }
                .simultaneousGesture(TapGesture().onEnded { Task { await model.markRead(item) } })
                .onAppear { if item.id == model.items.last?.id { Task { await model.loadMore() } } }
            }
            if model.isLoading { ProgressView() }
        }
        .listStyle(.plain)
        .navigationTitle("Activity")
        .toolbar {
            Button("Mark all read") { Task { await model.markAllRead(); await badge.refresh() } }
                .disabled(model.items.allSatisfy(\.read))
        }
        .refreshable { await model.reload() }
        .task { await model.reload() }
        .onDisappear { Task { await badge.refresh() } }
        .errorAlert($model.errorMessage)
    }

    private func badge(for type: ActivityType) -> some View {
        let (icon, color): (String, Color) = switch type {
        case .postReaction, .commentReaction: ("heart.fill", DS.Brand.pink)
        case .comment, .commentReply: ("bubble.right.fill", DS.Brand.sky)
        case .follow, .followAccepted: ("person.fill.checkmark", DS.Palette.success)
        case .followRequest: ("person.fill.badge.plus", .orange)
        case .mention: ("at", DS.Brand.violet)
        case .repost: ("arrow.2.squarepath", DS.Palette.success)
        case .message, .messageRequest: ("bubble.left.fill", DS.Brand.violet)
        }
        return Image(systemName: icon)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(color, in: Circle())
            .overlay(Circle().stroke(DS.Palette.background, lineWidth: 2))
            .accessibilityHidden(true)
    }

    private func route(for item: ActivityItem) -> SocialRoute {
        if let post = item.postID { return .post(post) }
        return .profile(item.actor?.id ?? "")
    }

    private func description(of item: ActivityItem) -> AttributedString {
        var name = AttributedString(item.actor?.displayName ?? "Someone")
        name.font = .subheadline.bold()
        let rest: String
        switch item.type {
        case .follow: rest = " started following you"
        case .followRequest: rest = " wants to follow you"
        case .followAccepted: rest = " accepted your follow request"
        case .postReaction: rest = " liked your post"
        case .comment: rest = " commented on your post"
        case .commentReply: rest = " replied to your comment"
        case .commentReaction: rest = " liked your comment"
        case .mention: rest = " mentioned you"
        case .repost: rest = " reposted your post"
        case .message: rest = " sent you a message"
        case .messageRequest: rest = " wants to send you a message"
        }
        return name + AttributedString(rest)
    }
}

#Preview {
    let repo = MockSocialRepository()
    return NavigationStack { ActivityView(repository: repo, badge: ActivityBadgeModel(repository: repo)) }
}
