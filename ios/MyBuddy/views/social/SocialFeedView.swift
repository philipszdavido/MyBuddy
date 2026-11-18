//
//  SocialFeedView.swift
//  MyBuddy
//
//  Feed tab on the MyBuddy API backend: following/discover feeds of posts with media, likes, comments,
//  reposts and saves; entry points to search, activity and the composer.
//

import SwiftUI

struct SocialFeedView: View {
    @EnvironmentObject private var router: DeepLinkRouter
    @EnvironmentObject private var auth: AuthViewModel
    @StateObject private var model: SocialFeedViewModel
    @StateObject private var activity: ActivityBadgeModel
    private let repository: SocialRepository

    @State private var composing = false
    @State private var pendingDelete: Post?
    @State private var path: [SocialRoute] = []

    init(repository: SocialRepository) {
        self.repository = repository
        _model = StateObject(wrappedValue: SocialFeedViewModel(repository: repository))
        _activity = StateObject(wrappedValue: ActivityBadgeModel(repository: repository))
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                composerPrompt
                Picker("Feed", selection: $model.tab) {
                    ForEach(SocialFeedViewModel.Tab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, DS.Space.m)
                .padding(.bottom, DS.Space.s)

                if model.isPublishing {
                    Group {
                        if let progress = model.uploadProgress { UploadProgressView(progress: progress, label: "Posting") }
                        else { HStack { ProgressView(); Text("Posting…").font(.subheadline).foregroundStyle(DS.Palette.secondaryText) } }
                    }
                    .padding(.horizontal, DS.Space.m)
                    .padding(.bottom, DS.Space.s)
                }

                Divider()

                if model.posts.isEmpty && model.isLoading {
                    SkeletonPosts()
                } else if model.posts.isEmpty {
                    BrandEmptyState(
                        systemImage: model.tab == .following ? "person.2.fill" : "sparkles",
                        title: "No posts yet",
                        message: model.tab == .following
                            ? "Posts from your contacts and people you follow will show up here."
                            : "Public posts from around MyBuddy will show up here.",
                        actionTitle: "Share an update"
                    ) { composing = true }
                    .padding(.top, 48)
                }
                ForEach(model.posts) { post in
                    PostCardView(
                        post: post,
                        onReact: { model.toggle($0, on: post) },
                        onSave: { model.toggleSaved(post) },
                        onRepost: { model.repost(post) },
                        onDelete: { pendingDelete = post }
                    )
                    .padding(.horizontal, DS.Space.m)
                    .padding(.vertical, DS.Space.m)
                    .onAppear {
                        model.appeared(post)
                        Task { await model.loadMoreIfNeeded(current: post) }
                    }
                    Divider().padding(.leading, DS.Space.m)
                }
                if model.isLoading && !model.posts.isEmpty { ProgressView().padding(DS.Space.l) }
            }
        }
        .refreshable { await model.reload() }
        .navigationTitle("Feed")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                NavigationLink { SearchView(repository: repository) } label: { Image(systemName: "magnifyingglass") }
                    .accessibilityLabel("Search")
                NavigationLink { ActivityView(repository: repository, badge: activity) } label: {
                    Image(systemName: activity.unread > 0 ? "bell.badge" : "bell")
                        .symbolRenderingMode(activity.unread > 0 ? .multicolor : .monochrome)
                }
                .accessibilityLabel(activity.unread > 0 ? "Activity, \(activity.unread) unread" : "Activity")
            }
        }
        .navigationDestination(for: SocialRoute.self) { route in
            switch route {
            case .profile(let id): ProfileView(repository: repository, userID: id)
            case .post(let id): PostDetailView(repository: repository, postID: id)
            case .comments(let id): CommentsView(repository: repository, postID: id)
            }
        }
        .navigationDestination(isPresented: Binding(get: { !path.isEmpty }, set: { if !$0 { path.removeAll() } })) {
            if let route = path.first {
                switch route {
                case .profile(let id): ProfileView(repository: repository, userID: id)
                case .post(let id): PostDetailView(repository: repository, postID: id)
                case .comments(let id): CommentsView(repository: repository, postID: id)
                }
            }
        }
        .sheet(isPresented: $composing) {
            ComposePostView(model: model)
        }
        .confirmationDialog("Delete this post?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let post = pendingDelete { Task { await model.delete(post) } }
            }
        }
        .task(id: model.tab) { await model.reload() }
        .task { await activity.refresh() }
        .onAppear(perform: openPendingLink)
        .onChange(of: router.pending) { openPendingLink() }
        .onDisappear { model.flushImpressions() }
        .errorAlert($model.errorMessage)
    }

    /// Tap target that opens the composer (avatar + placeholder), like most social apps.
    private var composerPrompt: some View {
        Button { composing = true } label: {
            HStack(spacing: DS.Space.s) {
                AvatarView(user: auth.userProfile.map { UserSummary(id: $0.id, username: nil, displayName: $0.displayName,
                                                                     avatarURL: $0.photoURL.flatMap(URL.init(string:)), isVerified: false) }, size: 36)
                Text("Share an update…")
                    .foregroundStyle(DS.Palette.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "photo").foregroundStyle(DS.Palette.accent)
            }
            .padding(.horizontal, DS.Space.s)
            .padding(.vertical, DS.Space.xs)
            .background(DS.Palette.surface, in: RoundedRectangle(cornerRadius: DS.Radius.l, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, DS.Space.m)
        .padding(.vertical, DS.Space.s)
        .accessibilityLabel("New post")
        .disabled(model.isPublishing)
    }

    /// Profile and post links (notifications, shared links) open here.
    private func openPendingLink() {
        switch router.pending {
        case .post(let id)?: _ = router.consume(); path = [.post(id)]
        case .profile(let id)?: _ = router.consume(); path = [.profile(id)]
        default: break
        }
    }
}

/// One post: author row, text, media, quoted post, and a single action row. Double-tap likes.
struct PostCardView: View {
    let post: Post
    @State private var heartBurst = false
    var onReact: (ReactionKind) -> Void
    var onSave: () -> Void
    var onRepost: () -> Void
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            if post.kind == "repost" {
                Label("\(post.author.displayName) reposted", systemImage: "arrow.2.squarepath")
                    .font(.caption.weight(.medium)).foregroundStyle(DS.Palette.secondaryText)
            }
            let shown = post.kind == "repost" ? post.repostOf.map { ($0.author, $0.text, $0.media, $0.publishedAt) } : (post.author, post.text, post.media, post.publishedAt)
            if let shown {
                let (author, text, media, date) = shown
                HStack(spacing: DS.Space.s) {
                    NavigationLink(value: SocialRoute.profile(author.id)) {
                        HStack(spacing: DS.Space.s) {
                            AvatarView(user: author, size: 44)
                            VStack(alignment: .leading, spacing: 1) {
                                UserNameLabel(user: author)
                                HStack(spacing: DS.Space.xxs) {
                                    if let date { Text(date, format: .relative(presentation: .named)) }
                                    Image(systemName: audienceIcon).accessibilityLabel(audienceLabel)
                                }
                                .font(.caption)
                                .foregroundStyle(DS.Palette.secondaryText)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    moreMenu
                }

                VStack(alignment: .leading, spacing: DS.Space.s) {
                    if let text, !text.isEmpty {
                        Text(text).font(.body).foregroundStyle(DS.Palette.primaryText).lineSpacing(2)
                    }
                    if !media.isEmpty { MediaGrid(media: media) }
                    if post.kind == "quote", let original = post.repostOf { QuotedPostView(snapshot: original) }
                }
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { doubleTapLike() }
                .overlay {
                    if heartBurst {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 84))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.25), radius: 12)
                            .transition(.scale(scale: 0.4).combined(with: .opacity))
                            .accessibilityHidden(true)
                    }
                }
            } else {
                Text("This post is unavailable.").foregroundStyle(DS.Palette.secondaryText)
            }
            actions
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actions: some View {
        HStack(spacing: 0) {
            action(post.myReaction == .like ? "heart.fill" : "heart", count: post.counts.likes,
                   tint: post.myReaction == .like ? DS.Brand.pink : DS.Palette.secondaryText, label: "Like", selected: post.myReaction == .like) {
                Haptics.tap()
                onReact(.like)
            }
            NavigationLink(value: SocialRoute.comments(post.id)) {
                actionLabel("bubble.right", count: post.counts.comments, tint: DS.Palette.secondaryText)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Comments, \(post.counts.comments)")
            action("arrow.2.squarepath", count: post.counts.reposts, tint: post.reposted ? DS.Palette.success : DS.Palette.secondaryText,
                   label: post.reposted ? "Reposted" : "Repost", selected: post.reposted, action: onRepost)
                .disabled(post.reposted || post.audience != .public || post.canEdit)
            action(post.myReaction == .dislike ? "hand.thumbsdown.fill" : "hand.thumbsdown", count: post.counts.dislikes,
                   tint: post.myReaction == .dislike ? DS.Palette.primaryText : DS.Palette.secondaryText, label: "Dislike", selected: post.myReaction == .dislike) { onReact(.dislike) }
            Spacer()
            Button(action: onSave) {
                Image(systemName: post.saved ? "bookmark.fill" : "bookmark")
                    .font(.system(size: DS.Icon.action))
                    .foregroundStyle(post.saved ? DS.Palette.accent : DS.Palette.secondaryText)
                    .frame(minWidth: 44, minHeight: 36)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(post.saved ? "Unsave" : "Save")
        }
        .padding(.leading, -DS.Space.xs)
    }

    private func action(_ icon: String, count: Int, tint: Color, label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { actionLabel(icon, count: count, tint: tint) }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
            .accessibilityValue("\(count)")
            .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func doubleTapLike() {
        Haptics.tap()
        if post.myReaction != .like { onReact(.like) }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) { heartBurst = true }
        Task {
            try? await Task.sleep(for: .milliseconds(650))
            withAnimation(.easeOut(duration: 0.25)) { heartBurst = false }
        }
    }

    private func actionLabel(_ icon: String, count: Int, tint: Color) -> some View {
        HStack(spacing: DS.Space.xxs) {
            Image(systemName: icon).font(.system(size: DS.Icon.action, weight: .medium))
                .symbolEffect(.bounce, value: icon)
                .contentTransition(.symbolEffect(.replace))
            if count > 0 { Text("\(count.abbreviated)").font(.subheadline).monospacedDigit() }
        }
        .foregroundStyle(tint)
        .frame(minWidth: 56, minHeight: 36, alignment: .leading)
        .padding(.leading, DS.Space.xs)
        .contentShape(Rectangle())
    }

    private var moreMenu: some View {
        Menu {
            if let url = URL(string: "mybuddy://post/\(post.id)") {
                ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") }
            }
            if post.canEdit {
                Button(role: .destructive, action: onDelete) { Label("Delete", systemImage: "trash") }
            }
        } label: {
            Image(systemName: "ellipsis")
                .foregroundStyle(DS.Palette.secondaryText)
                .frame(width: 36, height: 36)
        }
        .accessibilityLabel("More actions")
    }

    private var audienceIcon: String {
        switch post.audience { case .public: "globe"; case .followers: "person.2.fill"; case .contacts: "person.crop.circle.badge.checkmark" }
    }

    private var audienceLabel: String {
        switch post.audience { case .public: "Public"; case .followers: "Followers"; case .contacts: "Contacts" }
    }
}

struct QuotedPostView: View {
    let snapshot: PostSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                AvatarView(user: snapshot.author, size: 20)
                UserNameLabel(user: snapshot.author).font(.subheadline)
            }
            if let text = snapshot.text { Text(text).font(.subheadline).lineLimit(4) }
            if !snapshot.media.isEmpty { MediaGrid(media: snapshot.media) }
        }
        .padding(DS.Space.s)
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous).stroke(DS.Palette.separator))
    }
}

/// Single post (deep link target), with its comments below.
struct PostDetailView: View {
    let repository: SocialRepository
    let postID: String
    @State private var post: Post?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let post {
                CommentsView(repository: repository, postID: post.id, header: post)
            } else if errorMessage != nil {
                ContentUnavailableView("Post unavailable", systemImage: "eye.slash", description: Text("It may have been deleted, or it isn't shared with you."))
            } else {
                ProgressView()
            }
        }
        .task {
            do { post = try await repository.post(id: postID) }
            catch { errorMessage = AppError.wrap(error).userMessage }
        }
    }
}

/// Unread count for the bell icon.
@MainActor
final class ActivityBadgeModel: ObservableObject {
    @Published var unread = 0
    private let repository: SocialRepository
    init(repository: SocialRepository) { self.repository = repository }

    func refresh() async {
        unread = (try? await repository.unreadActivityCount()) ?? unread
    }
}

#Preview {
    NavigationStack { SocialFeedView(repository: MockSocialRepository()) }
        .environmentObject(DeepLinkRouter())
        .environmentObject(AuthViewModel.shared)
}
